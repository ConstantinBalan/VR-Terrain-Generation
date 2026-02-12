class_name TerrainChunk
extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D



var parameters: TerrainParameters
var height_data: PackedFloat32Array
var grid_position: Vector2i = Vector2i.ZERO
var is_locked: bool = false
var generation_time: float = 0.0

var noise: FastNoiseLite

var mesh_cache: ArrayMesh
var collision_cache: HeightMapShape3D

signal generation_complete(chunk: TerrainChunk)
signal generation_failed(chunk: TerrainChunk, error: String)


func _ready():
	name = "TerrainChunk_" + str(grid_position.x) + "_" + str(grid_position.y)
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
	
func set_parameters(params: Dictionary):
	pass
	
func generate_terrain(params: TerrainParameters, grid_pos: Vector2i) -> bool:
	parameters = params.duplicate()
	grid_position = grid_pos
	
	print("TerrainChunk: Starting generation for chunk at ", grid_position)
	var start_time = Time.get_time_dict_from_system()
	
	print("TerrainChunk: Setting up noise generator...")
	if not setup_noise_generator():
		print("TerrainChunk: Failed to setup noise generator")
		generation_failed.emit(self, "Failed to setup noise generator")
		return false
	
	print("TerrainChunk: Generating height data...")
	if not generate_height_data():
		print("TerrainChunk: Failed to generate height data")
		generation_failed.emit(self, "Failed to generate height data")
		return false
	
	print("TerrainChunk: Creating mesh from heights...")	
	if not create_mesh_from_heights():
		print("TerrainChunk: Failed to create mesh")
		generation_failed.emit(self, "Failed to create mesh from height")
		return false
	
	print("TerrainChunk: Setting up collisions...")	
	if not setup_collisions():
		print("TerrainChunk: Failed to setup collisions")
		generation_failed.emit(self, "Failed to set up collisions")
		return false
	
	var end_time = Time.get_time_dict_from_system()
	generation_time = calculate_time_difference(start_time, end_time)
	
	print("Generated terrain chunk at ", grid_position, " in ", generation_time, "ms")
	print("TerrainChunk: Emitting generation_complete signal for chunk at ", grid_position)
	generation_complete.emit(self)
	return true
	
func setup_noise_generator():
	noise = FastNoiseLite.new()
	noise.seed = parameters.seed_value
	noise.frequency = parameters.frequency
	
	match parameters.terrain_type:
		TerrainParameters.TerrainType.HILLS:
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		TerrainParameters.TerrainType.MOUNTAINS:
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		TerrainParameters.TerrainType.VALLEYS:
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			#invert amplitude for valleys
		TerrainParameters.TerrainType.FLAT:
			pass
			
	noise.fractal_octaves = parameters.octaves
	noise.fractal_lacunarity = parameters.lacunarity
	noise.fractal_gain = parameters.persistance
	
	return noise != null
	
func generate_height_data() -> bool:
	var resolution = parameters.resolution
	var chunk_size = parameters.chunk_size_meters
	var cell_size = chunk_size / float(resolution - 1) # -1 for edge sharing
	
	var world_offset = GridManager.grid_to_world(grid_position)
	
	height_data = PackedFloat32Array()
	height_data.resize(resolution * resolution)
	
	for z in range(resolution):
		for x in range(resolution):
			var world_x = world_offset.x - (chunk_size * 0.5) + (x * cell_size)
			var world_z = world_offset.z - (chunk_size * 0.5) + (z * cell_size)
			
			var height = sample_height_at_world_position(world_x, world_z)
			height_data[z * resolution + x] = height
			
	return height_data.size() > 0

func sample_height_at_world_position(world_x: float, world_z: float):
	var base_height = noise.get_noise_2d(world_x, world_z) * parameters.amplitude
	
	match parameters.terrain_type:
		TerrainParameters.TerrainType.VALLEYS:
			base_height = -abs(base_height)
		TerrainParameters.TerrainType.PLATEAU:
			base_height = apply_plateau_effect(base_height)
		TerrainParameters.TerrainType.FLAT:
			base_height *= 0.1
		
	if parameters.erosion_strength > 0.0:
		base_height = apply_erosion_effect(world_x, world_z, base_height)
		
	return base_height
	
func apply_plateau_effect(height: float) -> float:
	var plateau_threshold = parameters.plateau_level
	if height > plateau_threshold:
		var t = (height - plateau_threshold) / (parameters.amplitude - plateau_threshold)
		t = clamp(t, 0.0, 1.0)
		var smoothed = t * t * (3.0 - 2.0 * t)
		return plateau_threshold + smoothed * (parameters.amplitude - plateau_threshold)
	return height

func apply_erosion_effect(world_x: float, world_z: float, base_height: float) -> float:
	var erosion_noise = FastNoiseLite.new()
	erosion_noise.seed = parameters.seed_value + 1000
	erosion_noise.frequency = parameters.frequency * 4.0
	
	var erosion_factor = erosion_noise.get_noise_2d(world_x, world_z)
	erosion_factor = (erosion_factor + 1.0) * 0.5
	
	var erosion_amount = parameters.erosion_strength * erosion_factor
	return base_height * (1.0 - erosion_amount)

func calculate_time_difference(start_time: Dictionary, end_time: Dictionary):
	var start_ms = start_time.hour * 3600000 + start_time.minute * 60000 + start_time.second * 1000
	var end_ms = end_time.hour * 3600000 + end_time.minute * 60000 + end_time.second * 1000
	return end_ms - start_ms

func get_height_at_local_position(local_x: float, local_z: float) -> float:
	if height_data.is_empty():
		return 0.0
		
	var resolution = parameters.resolution
	var chunk_size = parameters.chunk_size_meters
	
	var x_coord = ((local_x + chunk_size * 0.5) / chunk_size) * (resolution - 1)
	var z_coord = ((local_z + chunk_size * 0.5) / chunk_size) * (resolution - 1)
	
	return bilinear_interpolate_height(x_coord, z_coord)
	
func bilinear_interpolate_height(x: float, z: float) -> float:
	var resolution = parameters.resolution
	
	var x0 = int(floor(x))
	var x1 = x0 + 1
	var z0 = int(floor(z))
	var z1 = z0 + 1
	
	var fx = x - x0
	var fz = z - z0
	
	x0 = clamp(x0, 0, resolution - 1)
	x1 = clamp(x1, 0, resolution - 1)
	z0 = clamp(z0, 0, resolution - 1)
	z1 = clamp(z1, 0, resolution - 1)
	
	var h00 = height_data[z0 * resolution + x0]
	var h10 = height_data[z0 * resolution + x1]
	var h01 = height_data[z1 * resolution + x0]
	var h11 = height_data[z1 * resolution + x1]
	
	var h0 = lerp(h00, h10, fx)
	var h1 = lerp(h01, h11, fx)
	return lerp(h0, h1, fz)

func get_edge_heights(edge_direction: Vector2i) -> PackedFloat32Array:
	var resolution = parameters.resolution
	var edge_heights = PackedFloat32Array()
	
	if edge_direction.x == 1: #right edge
		for z in range(resolution):
			edge_heights.append(height_data[z * resolution + (resolution - 1)])
	elif edge_direction.x == -1: #left edge
		for z in range(resolution):
			edge_heights.append(height_data[z * resolution + 0])
	elif edge_direction.y == 1: #bottom edge, positive z
		for x in range(resolution):
			edge_heights.append(height_data[(resolution -1) * resolution + x])
	elif edge_direction.y == -1: #top edge, negative z
		for x in range(resolution):
			edge_heights.append(height_data[0 * resolution + x])
			
	return edge_heights
	
func create_mesh_from_heights():
	if height_data.is_empty():
		push_error("No height data available for mesh generation")
		return false
	
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	if not generate_vertices(surface_tool):
		return false
	
	if not generate_triangles(surface_tool):
		return false
	
	surface_tool.generate_normals(false)
	surface_tool.generate_tangents()
	
	mesh_cache = surface_tool.commit()
	mesh_instance.mesh = mesh_cache
	
	setup_terrain_material()
	
	return mesh_cache != null
	
func generate_vertices(surface_tool: SurfaceTool):
	var resolution = parameters.resolution
	var chunk_size = parameters.chunk_size_meters
	var cell_size = chunk_size /float(resolution - 1)
	
	for z in range(resolution):
		for x in range(resolution):
			var local_x = -chunk_size * 0.5 + x * cell_size
			var local_z = -chunk_size * 0.5 + z * cell_size
			var height = height_data[z * resolution + x]
			
			var u = float(x) / float(resolution - 1)
			var v = float(z) / float(resolution - 1)
			surface_tool.set_uv(Vector2(u, v))
			
			var height_ratio = (height + parameters.amplitude) / (2.0 * parameters.amplitude)
			height_ratio = clamp(height_ratio, 0.0, 1.0)
			surface_tool.set_color(Color(height_ratio, 1.0 - height_ratio, 0.5))
			
			var vertex = Vector3(local_x, height, local_z)
			surface_tool.add_vertex(vertex)
	return true
	
func generate_triangles(surface_tool: SurfaceTool) -> bool:
	var resolution = parameters.resolution
		
	for z in range(resolution - 1):
		for x in range(resolution - 1):
			var top_left = z * resolution + x
			var top_right = z * resolution + (x + 1)
			var bottom_left = (z + 1) * resolution + x
			var bottom_right = (z + 1) * resolution + (x + 1)
				
			surface_tool.add_index(top_left)
			surface_tool.add_index(top_right)
			surface_tool.add_index(bottom_left)
				
			surface_tool.add_index(top_right)
			surface_tool.add_index(bottom_right)
			surface_tool.add_index(bottom_left)
				
	return true
	
func setup_terrain_material():
	var material = StandardMaterial3D.new()
	
	material.albedo_color = Color(0.4, 0.7, 0.2)
	material.roughness = 0.8
	material.metallic = 0.0
	
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	
	#Add texture tiling for details later on at some point
	
	mesh_instance.material_override = material
	

func setup_collisions() -> bool:
	if not collision_shape:
		push_error("No collision shape found")
		return false
	
	var heightmap_shape = HeightMapShape3D.new()
	
	var collision_heights = PackedFloat32Array()
	var resolution = parameters.resolution
	
	for z in range(resolution):
		for x in range(resolution):
			collision_heights.append(height_data[z * resolution + x])
	heightmap_shape.map_data = collision_heights
	heightmap_shape.map_width = resolution
	heightmap_shape.map_depth = resolution
	
	collision_shape.shape = heightmap_shape
	collision_cache = heightmap_shape
	
	return true

func get_tri_count() -> int:
	var resolution = parameters.resolution
	return (resolution - 1) * (resolution - 1) * 2

func get_vertex_count() -> int:
	var resolution = parameters.resolution
	return resolution * resolution

func get_estimated_mem_usage() -> Dictionary:
	var vertex_count = get_vertex_count()
	var triangle_count = get_tri_count()
	
	return {
		"vertices": vertex_count,
		"triangles": triangle_count,
		"height_data_bytes": height_data.size() * 4,
		"estimated_vram_kb": (vertex_count * 32 + triangle_count * 12) / 1024
	}

	
