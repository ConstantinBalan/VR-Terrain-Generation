@tool
class_name TerrainPreviewTool
extends Node3D

enum TerrainType {
	FLAT,
	HILLS,
	MOUNTAINS,
	VALLEYS,
	PLATEAU
}

@export var terrain_type: TerrainType = TerrainType.HILLS:
	set(value):
		terrain_type = value
		_regenerate()

@export_range(0, 10000) var seed_value: int = 0:
	set(value):
		seed_value = value
		_regenerate()

@export_range(0.01, 0.5, 0.01) var frequency: float = 0.1:
	set(value):
		frequency = value
		_regenerate()

@export_range(0.1, 40.0, 0.1) var amplitude: float = 5.0:
	set(value):
		amplitude = value
		_regenerate()

@export_range(1, 5) var octaves: int = 3:
	set(value):
		octaves = value
		_regenerate()

@export_range(1.5, 2.5, 0.1) var lacunarity: float = 2.0:
	set(value):
		lacunarity = value
		_regenerate()

@export_range(0.1, 0.6, 0.05) var persistence: float = 0.5:
	set(value):
		persistence = value
		_regenerate()

@export_range(0.0, 1.0, 0.05) var erosion: float = 0.0:
	set(value):
		erosion = value
		_regenerate()

@export_range(0.0, 3.0, 0.1) var plateau_level: float = 0.0:
	set(value):
		plateau_level = value
		_regenerate()

@export_range(8, 128, 8) var resolution: int = 32:
	set(value):
		resolution = value
		_regenerate()

@export_range(4.0, 32.0, 1.0) var chunk_size_meters: float = 8.0:
	set(value):
		chunk_size_meters = value
		_regenerate()

var _mesh_instance: MeshInstance3D
var _noise: FastNoiseLite
var _height_data: PackedFloat32Array
var _is_ready: bool = false


func _ready():
	_ensure_mesh_instance()
	_is_ready = true
	_regenerate()


func _ensure_mesh_instance():
	# Look for existing MeshInstance3D child
	for child in get_children():
		if child is MeshInstance3D:
			_mesh_instance = child
			return

	# Create one if missing
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "MeshInstance3D"
	add_child(_mesh_instance)
	if Engine.is_editor_hint():
		_mesh_instance.owner = get_tree().edited_scene_root


func _regenerate():
	if not _is_ready:
		return
	_ensure_mesh_instance()
	_setup_noise()
	_generate_heights()
	_build_mesh()


func _setup_noise():
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.frequency = frequency

	var effective_octaves = octaves

	match terrain_type:
		TerrainType.FLAT:
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
			effective_octaves = 1
		TerrainType.HILLS:
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		TerrainType.MOUNTAINS:
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		TerrainType.VALLEYS:
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		TerrainType.PLATEAU:
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			_noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	_noise.fractal_octaves = effective_octaves
	_noise.fractal_lacunarity = lacunarity
	_noise.fractal_gain = persistence


func _generate_heights():
	var cell_size = chunk_size_meters / float(resolution - 1)

	_height_data = PackedFloat32Array()
	_height_data.resize(resolution * resolution)

	for z in range(resolution):
		for x in range(resolution):
			var local_x = -chunk_size_meters * 0.5 + x * cell_size
			var local_z = -chunk_size_meters * 0.5 + z * cell_size

			var height = _sample_height(local_x, local_z)
			_height_data[z * resolution + x] = height


func _sample_height(local_x: float, local_z: float) -> float:
	var base_height = _noise.get_noise_2d(local_x, local_z) * amplitude

	match terrain_type:
		TerrainType.VALLEYS:
			base_height = -abs(base_height)
		TerrainType.PLATEAU:
			if base_height > plateau_level:
				base_height = plateau_level
		TerrainType.FLAT:
			base_height *= 0.02

	if erosion > 0.0:
		var erosion_noise = FastNoiseLite.new()
		erosion_noise.seed = seed_value + 1000
		erosion_noise.frequency = frequency * 4.0
		var erosion_factor = erosion_noise.get_noise_2d(local_x, local_z)
		erosion_factor = (erosion_factor + 1.0) * 0.5
		base_height *= (1.0 - erosion * erosion_factor)

	return base_height


func _build_mesh():
	if _height_data.is_empty():
		return

	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Vertices
	var cell_size = chunk_size_meters / float(resolution - 1)
	for z in range(resolution):
		for x in range(resolution):
			var local_x = -chunk_size_meters * 0.5 + x * cell_size
			var local_z = -chunk_size_meters * 0.5 + z * cell_size
			var height = _height_data[z * resolution + x]

			var u = float(x) / float(resolution - 1)
			var v = float(z) / float(resolution - 1)
			surface_tool.set_uv(Vector2(u, v))

			var height_ratio = (height + amplitude) / (2.0 * amplitude)
			height_ratio = clamp(height_ratio, 0.0, 1.0)
			surface_tool.set_color(Color(height_ratio, 1.0 - height_ratio, 0.5))

			surface_tool.add_vertex(Vector3(local_x, height, local_z))

	# Triangles
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

	surface_tool.generate_normals(false)
	surface_tool.generate_tangents()

	_mesh_instance.mesh = surface_tool.commit()

	# Material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.7, 0.2)
	material.roughness = 0.8
	material.metallic = 0.0
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	_mesh_instance.material_override = material
