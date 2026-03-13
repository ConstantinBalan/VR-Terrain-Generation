class_name DualContouringChunk
extends Node3D

## 3D terrain chunk using dual contouring for caves, overhangs, and complex geometry.
## Implements density field sampling, QEF vertex placement, and quad-based mesh building.

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D

var parameters: TerrainParameters
var grid_position: Vector2i = Vector2i.ZERO
var is_locked: bool = false
var generation_time: float = 0.0

var noise: FastNoiseLite
var density_grid: Dictionary = {}  # {Vector3i: float}
var cell_vertices: Dictionary = {} # {Vector3i: Vector3}

var mesh_cache: ArrayMesh

signal generation_complete(chunk: DualContouringChunk)
signal generation_failed(chunk: DualContouringChunk, error: String)


func _ready():
	name = "DCChunk_" + str(grid_position.x) + "_" + str(grid_position.y)
	setup_default_components()

func setup_default_components():
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)

	if not has_node("StaticBody3D"):
		var static_body = StaticBody3D.new()
		collision_shape = CollisionShape3D.new()
		static_body.add_child(collision_shape)
		add_child(static_body)


func generate_terrain(params: TerrainParameters, grid_pos: Vector2i) -> bool:
	parameters = params.duplicate()
	grid_position = grid_pos

	print("DualContouringChunk: Starting generation at ", grid_position)
	var start_time = Time.get_time_dict_from_system()

	if not setup_noise_generator():
		generation_failed.emit(self, "Failed to setup noise generator")
		return false

	# Phase 1: Sample density at all grid corners
	sample_density_grid()

	# Phase 2: Compute dual contouring vertices via QEF
	cell_vertices = compute_cell_vertices()

	if cell_vertices.is_empty():
		print("DualContouringChunk: No surface cells found — density field has no sign changes")
		generation_failed.emit(self, "No surface found in density field")
		return false

	# Phase 3: Build triangle mesh from cell vertices
	var mesh = build_mesh()
	if not mesh:
		generation_failed.emit(self, "Failed to build mesh")
		return false

	mesh_cache = mesh
	mesh_instance.mesh = mesh_cache
	setup_terrain_material()

	# Phase 4: Collision from trimesh
	if not setup_collisions():
		generation_failed.emit(self, "Failed to setup collisions")
		return false

	var end_time = Time.get_time_dict_from_system()
	generation_time = calculate_time_difference(start_time, end_time)

	print("DualContouringChunk: Generated at ", grid_position, " in ", generation_time, "ms",
		" | cells with surface: ", cell_vertices.size())
	generation_complete.emit(self)
	return true


func setup_noise_generator() -> bool:
	noise = FastNoiseLite.new()
	noise.seed = parameters.seed_value
	noise.frequency = parameters.frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = parameters.octaves
	noise.fractal_lacunarity = parameters.lacunarity
	noise.fractal_gain = parameters.persistance
	return noise != null


# --- Density Field ---

func density(pos: Vector3) -> float:
	var grid_size := parameters.grid_size_3d
	# Vertical gradient: positive underground, negative in air
	var gradient = -(pos.y - float(grid_size) * parameters.ground_level) / float(grid_size)
	var terrain = noise.get_noise_3d(pos.x, pos.y, pos.z)
	var base_density = gradient + terrain * parameters.terrain_strength

	# Cave carving (only underground)
	if not parameters.cave_enabled:
		return base_density

	if base_density <= parameters.min_depth:
		return base_density

	var cs = parameters.cave_scale
	var cx = pos.x * cs
	var cy = pos.y * cs
	var cz = pos.z * cs
	var cave1 = abs(noise.get_noise_3d(cx + 100.0, cy + 100.0, cz + 100.0))
	var cave2 = abs(noise.get_noise_3d(cx + 200.0, cy + 200.0, cz + 200.0))
	var cave_value = cave1 + cave2

	var depth_factor = clampf((base_density - parameters.min_depth) * 2.0, 0.0, 1.0)

	if cave_value < parameters.cave_threshold:
		var carve = (parameters.cave_threshold - cave_value) / parameters.cave_threshold
		base_density -= carve * depth_factor * 2.0

	return base_density

func density_gradient(pos: Vector3) -> Vector3:
	var eps := 0.01
	var dx = density(Vector3(pos.x + eps, pos.y, pos.z)) - density(Vector3(pos.x - eps, pos.y, pos.z))
	var dy = density(Vector3(pos.x, pos.y + eps, pos.z)) - density(Vector3(pos.x, pos.y - eps, pos.z))
	var dz = density(Vector3(pos.x, pos.y, pos.z + eps)) - density(Vector3(pos.x, pos.y, pos.z - eps))
	var grad = Vector3(dx, dy, dz)
	if grad.length_squared() < 0.00001:
		return Vector3.UP
	return grad.normalized()


# --- Grid Sampling ---

func sample_density_grid():
	density_grid.clear()
	var grid_size := parameters.grid_size_3d
	var chunk_size := parameters.chunk_size_meters
	var cell_size := chunk_size / float(grid_size)

	# World offset: density field is centered on the chunk's world position
	# but sampled in local space (mesh is local to this node)
	for x in range(grid_size + 1):
		for y in range(grid_size + 1):
			for z in range(grid_size + 1):
				# Map grid coords to local space centered on chunk
				var local_pos = Vector3(
					-chunk_size * 0.5 + x * cell_size,
					-chunk_size * 0.5 + y * cell_size,
					-chunk_size * 0.5 + z * cell_size
				)
				# Convert to world space for noise sampling
				var world_pos = local_pos + global_position
				density_grid[Vector3i(x, y, z)] = density(world_pos)


# --- QEF Solver ---

func solve_qef(crossings: Array, normals: Array, cell_min: Vector3, cell_max: Vector3) -> Vector3:
	# Solve the 3x3 Quadratic Error Function: find point minimizing squared
	# distance to all tangent planes defined by (crossing, normal) pairs.
	var ata_00 := 0.0; var ata_01 := 0.0; var ata_02 := 0.0
	var ata_11 := 0.0; var ata_12 := 0.0; var ata_22 := 0.0
	var atb := Vector3.ZERO

	for i in range(crossings.size()):
		var n: Vector3 = normals[i]
		var p: Vector3 = crossings[i]
		var d = n.dot(p)
		ata_00 += n.x * n.x
		ata_01 += n.x * n.y
		ata_02 += n.x * n.z
		ata_11 += n.y * n.y
		ata_12 += n.y * n.z
		ata_22 += n.z * n.z
		atb.x += n.x * d
		atb.y += n.y * d
		atb.z += n.z * d

	var det = (ata_00 * (ata_11 * ata_22 - ata_12 * ata_12)
			 - ata_01 * (ata_01 * ata_22 - ata_12 * ata_02)
			 + ata_02 * (ata_01 * ata_12 - ata_11 * ata_02))

	# Degenerate case: fall back to average of crossings
	if abs(det) < 0.0001:
		var avg := Vector3.ZERO
		for c in crossings:
			avg += c
		return avg / crossings.size()

	var inv = 1.0 / det
	var result := Vector3.ZERO
	result.x = ((ata_11 * ata_22 - ata_12 * ata_12) * atb.x + (ata_02 * ata_12 - ata_01 * ata_22) * atb.y + (ata_01 * ata_12 - ata_02 * ata_11) * atb.z) * inv
	result.y = ((ata_02 * ata_12 - ata_01 * ata_22) * atb.x + (ata_00 * ata_22 - ata_02 * ata_02) * atb.y + (ata_01 * ata_02 - ata_00 * ata_12) * atb.z) * inv
	result.z = ((ata_01 * ata_12 - ata_02 * ata_11) * atb.x + (ata_01 * ata_02 - ata_00 * ata_12) * atb.y + (ata_00 * ata_11 - ata_01 * ata_01) * atb.z) * inv

	# Clamp to cell bounds
	result.x = clampf(result.x, cell_min.x, cell_max.x)
	result.y = clampf(result.y, cell_min.y, cell_max.y)
	result.z = clampf(result.z, cell_min.z, cell_max.z)
	return result


# --- Cell Vertex Computation ---

func compute_cell_vertices() -> Dictionary:
	var verts := {}
	var grid_size := parameters.grid_size_3d
	var chunk_size := parameters.chunk_size_meters
	var cell_size := chunk_size / float(grid_size)

	for cx in range(grid_size):
		for cy in range(grid_size):
			for cz in range(grid_size):
				# Check if this cell has a sign change (surface crossing)
				var has_pos := false
				var has_neg := false
				for dx in range(2):
					for dy in range(2):
						for dz in range(2):
							var d = density_grid[Vector3i(cx + dx, cy + dy, cz + dz)]
							if d >= 0.0: has_pos = true
							else: has_neg = true

				if not (has_pos and has_neg):
					continue

				# This cell contains the surface — find edge crossings
				var edges := [
					[Vector3i(cx,cy,cz), Vector3i(cx+1,cy,cz)],
					[Vector3i(cx,cy+1,cz), Vector3i(cx+1,cy+1,cz)],
					[Vector3i(cx,cy,cz+1), Vector3i(cx+1,cy,cz+1)],
					[Vector3i(cx,cy+1,cz+1), Vector3i(cx+1,cy+1,cz+1)],
					[Vector3i(cx,cy,cz), Vector3i(cx,cy+1,cz)],
					[Vector3i(cx+1,cy,cz), Vector3i(cx+1,cy+1,cz)],
					[Vector3i(cx,cy,cz+1), Vector3i(cx,cy+1,cz+1)],
					[Vector3i(cx+1,cy,cz+1), Vector3i(cx+1,cy+1,cz+1)],
					[Vector3i(cx,cy,cz), Vector3i(cx,cy,cz+1)],
					[Vector3i(cx+1,cy,cz), Vector3i(cx+1,cy,cz+1)],
					[Vector3i(cx,cy+1,cz), Vector3i(cx,cy+1,cz+1)],
					[Vector3i(cx+1,cy+1,cz), Vector3i(cx+1,cy+1,cz+1)],
				]

				var cross_list := []
				var normal_list := []

				for edge in edges:
					var d0 = density_grid[edge[0]]
					var d1 = density_grid[edge[1]]
					if (d0 > 0.0) != (d1 > 0.0):
						var t = d0 / (d0 - d1)
						var p0 = _grid_to_local(edge[0], cell_size)
						var p1 = _grid_to_local(edge[1], cell_size)
						var cross = p0 + t * (p1 - p0)
						cross_list.append(cross)
						# Gradient at world position for normal
						normal_list.append(density_gradient(cross + global_position))

				var cell_min = _grid_to_local(Vector3i(cx, cy, cz), cell_size)
				var cell_max = _grid_to_local(Vector3i(cx + 1, cy + 1, cz + 1), cell_size)
				verts[Vector3i(cx, cy, cz)] = solve_qef(cross_list, normal_list, cell_min, cell_max)

	return verts

func _grid_to_local(grid_coord: Vector3i, cell_size: float) -> Vector3:
	var chunk_size := parameters.chunk_size_meters
	return Vector3(
		-chunk_size * 0.5 + grid_coord.x * cell_size,
		-chunk_size * 0.5 + grid_coord.y * cell_size,
		-chunk_size * 0.5 + grid_coord.z * cell_size
	)


# --- Mesh Building ---

func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var grid_size := parameters.grid_size_3d

	for x in range(grid_size + 1):
		for y in range(grid_size + 1):
			for z in range(grid_size + 1):
				var d0 = density_grid[Vector3i(x, y, z)]

				# X-aligned edge: shared by 4 cells around it
				if x < grid_size and y > 0 and y < grid_size and z > 0 and z < grid_size:
					var d1 = density_grid[Vector3i(x + 1, y, z)]
					if (d0 > 0.0) != (d1 > 0.0):
						var c0 = Vector3i(x, y - 1, z - 1)
						var c1 = Vector3i(x, y, z - 1)
						var c2 = Vector3i(x, y, z)
						var c3 = Vector3i(x, y - 1, z)
						if cell_vertices.has(c0) and cell_vertices.has(c1) and cell_vertices.has(c2) and cell_vertices.has(c3):
							_emit_quad(verts, norms, cell_vertices[c0], cell_vertices[c1], cell_vertices[c2], cell_vertices[c3])

				# Y-aligned edge
				if y < grid_size and x > 0 and x < grid_size and z > 0 and z < grid_size:
					var d1 = density_grid[Vector3i(x, y + 1, z)]
					if (d0 > 0.0) != (d1 > 0.0):
						var c0 = Vector3i(x - 1, y, z - 1)
						var c1 = Vector3i(x, y, z - 1)
						var c2 = Vector3i(x, y, z)
						var c3 = Vector3i(x - 1, y, z)
						if cell_vertices.has(c0) and cell_vertices.has(c1) and cell_vertices.has(c2) and cell_vertices.has(c3):
							_emit_quad(verts, norms, cell_vertices[c0], cell_vertices[c1], cell_vertices[c2], cell_vertices[c3])

				# Z-aligned edge
				if z < grid_size and x > 0 and x < grid_size and y > 0 and y < grid_size:
					var d1 = density_grid[Vector3i(x, y, z + 1)]
					if (d0 > 0.0) != (d1 > 0.0):
						var c0 = Vector3i(x - 1, y - 1, z)
						var c1 = Vector3i(x, y - 1, z)
						var c2 = Vector3i(x, y, z)
						var c3 = Vector3i(x - 1, y, z)
						if cell_vertices.has(c0) and cell_vertices.has(c1) and cell_vertices.has(c2) and cell_vertices.has(c3):
							_emit_quad(verts, norms, cell_vertices[c0], cell_vertices[c1], cell_vertices[c2], cell_vertices[c3])

	if verts.size() == 0:
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _emit_tri(verts: PackedVector3Array, norms: PackedVector3Array, v0: Vector3, v1: Vector3, v2: Vector3):
	var n0 = -density_gradient(v0 + global_position)
	var n1 = -density_gradient(v1 + global_position)
	var n2 = -density_gradient(v2 + global_position)

	# Per-triangle winding correction
	var geo_normal = (v1 - v0).cross(v2 - v0)
	var avg_normal = n0 + n1 + n2

	if geo_normal.dot(avg_normal) < 0.0:
		verts.append(v0); verts.append(v2); verts.append(v1)
		norms.append(n0); norms.append(n2); norms.append(n1)
	else:
		verts.append(v0); verts.append(v1); verts.append(v2)
		norms.append(n0); norms.append(n1); norms.append(n2)

func _emit_quad(verts: PackedVector3Array, norms: PackedVector3Array, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3):
	_emit_tri(verts, norms, v0, v1, v2)
	_emit_tri(verts, norms, v0, v2, v3)


# --- Material ---

func setup_terrain_material():
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.6, 0.3)
	material.roughness = 0.8
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material


# --- Collision ---

func setup_collisions() -> bool:
	if not collision_shape:
		push_error("No collision shape found")
		return false

	if not mesh_cache:
		return false

	# Use trimesh collision for complex 3D geometry (caves, overhangs)
	var trimesh_shape = mesh_cache.create_trimesh_shape()
	if not trimesh_shape:
		push_error("Failed to create trimesh collision shape")
		return false

	collision_shape.shape = trimesh_shape
	return true


# --- Utility ---

func calculate_time_difference(start_time: Dictionary, end_time: Dictionary) -> float:
	var start_ms = start_time.hour * 3600000 + start_time.minute * 60000 + start_time.second * 1000
	var end_ms = end_time.hour * 3600000 + end_time.minute * 60000 + end_time.second * 1000
	return end_ms - start_ms

func get_vertex_count() -> int:
	if mesh_cache:
		return mesh_cache.get_surface_count()
	return 0

func get_tri_count() -> int:
	if mesh_cache and mesh_cache.get_surface_count() > 0:
		var arrays = mesh_cache.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_VERTEX]:
			return arrays[Mesh.ARRAY_VERTEX].size() / 3
	return 0
