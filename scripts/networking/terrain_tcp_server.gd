@tool
extends Node3D

# Message type constants (mirrored from NetworkProtocol)
const MSG_HANDSHAKE := 0
const MSG_HANDSHAKE_ACK := 1
const MSG_TERRAIN_CHUNK := 2
const MSG_CHUNK_ACK := 3
const MSG_DISCONNECT := 4

@export var port: int = 4242
@export var auto_listen: bool = false

var server: TCPServer = TCPServer.new()
var peer: StreamPeerTCP = null
var is_listening: bool = false

signal client_connected
signal client_disconnected
signal terrain_received(grid_pos: Vector2i)
signal terrain_generated(grid_pos: Vector2i, chunk_node: Node3D)

func _ready() -> void:
	print("TerrainTCPServer: _ready() called, auto_listen=", auto_listen, ", is_editor=", Engine.is_editor_hint())
	if auto_listen:
		start_listening()

func start_listening() -> void:
	if is_listening:
		push_warning("TerrainTCPServer: Already listening")
		return

	var err = server.listen(port)
	if err != OK:
		push_error("TerrainTCPServer: Failed to listen on port ", port, " - error: ", err)
		return

	is_listening = true
	print("TerrainTCPServer: Listening on port ", port)

func stop_listening() -> void:
	if peer:
		peer.disconnect_from_host()
		peer = null
	server.stop()
	is_listening = false
	print("TerrainTCPServer: Stopped listening")

func _process(_delta: float) -> void:
	if not is_listening:
		return

	if server.is_connection_available():
		var new_peer = server.take_connection()
		if new_peer:
			if peer:
				peer.disconnect_from_host()
			peer = new_peer
			print("TerrainTCPServer: Client connected")
			client_connected.emit()

	if peer:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			print("TerrainTCPServer: Client disconnected")
			peer = null
			client_disconnected.emit()
			return

		while peer.get_available_bytes() > 0:
			var data = peer.get_var()
			if data is Dictionary:
				_handle_message(data)

func _handle_message(data: Dictionary) -> void:
	var msg_type = data.get("type", -1)

	match msg_type:
		MSG_HANDSHAKE:
			var version = data.get("version", "")
			print("TerrainTCPServer: Handshake from client v", version)
			_send_message({"type": MSG_HANDSHAKE_ACK, "version": "1.0"})

		MSG_TERRAIN_CHUNK:
			var pos_data = data.get("grid_position", {"x": 0, "y": 0})
			var grid_pos = Vector2i(pos_data.x, pos_data.y)
			var params_dict = data.get("parameters", {})
			print("TerrainTCPServer: Received terrain chunk at ", grid_pos)
			terrain_received.emit(grid_pos)
			_rebuild_terrain(grid_pos, params_dict)
			_send_message({"type": MSG_CHUNK_ACK, "grid_position": {"x": grid_pos.x, "y": grid_pos.y}})

		MSG_DISCONNECT:
			print("TerrainTCPServer: Client sent disconnect")
			if peer:
				peer.disconnect_from_host()
				peer = null
			client_disconnected.emit()

func _rebuild_terrain(grid_pos: Vector2i, params_dict: Dictionary) -> void:
	print("TerrainTCPServer: Rebuilding terrain at ", grid_pos)

	# Extract parameters from dictionary
	var seed_value: int = params_dict.get("seed", 0)
	var frequency: float = params_dict.get("frequency", 0.1)
	var amplitude: float = params_dict.get("amplitude", 5.0)
	var octaves: int = params_dict.get("octaves", 3)
	var lacunarity: float = params_dict.get("lacunarity", 2.0)
	var persistance: float = params_dict.get("persistance", 0.5)
	var terrain_type: int = params_dict.get("terrain_type", 1)  # HILLS
	var erosion_strength: float = params_dict.get("erosion", 0.0)
	var plateau_level: float = params_dict.get("plateau", 0.0)
	var resolution: int = params_dict.get("resolution", 64)
	var chunk_size: float = params_dict.get("size_meters", 8.0)

	# Setup noise (same logic as terrain_chunk.gd)
	var noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency

	match terrain_type:
		0:  # FLAT
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.fractal_type = FastNoiseLite.FRACTAL_NONE
			octaves = 1
		1:  # HILLS
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		2:  # MOUNTAINS
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		3:  # VALLEYS
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		4:  # PLATEAU
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = lacunarity
	noise.fractal_gain = persistance

	# Inline grid_to_world (GridManager is not @tool, can't call methods on it)
	# Formula: world = grid_pos * grid_size + grid_size * 0.5 + grid_offset
	var grid_size := 4.0
	var world_offset = Vector3(
		float(grid_pos.x) * grid_size + grid_size * 0.5,
		0.0,
		float(grid_pos.y) * grid_size + grid_size * 0.5
	)
	var cell_size_step = chunk_size / float(resolution - 1)
	var height_data = PackedFloat32Array()
	height_data.resize(resolution * resolution)

	for z in range(resolution):
		for x in range(resolution):
			var world_x = world_offset.x - (chunk_size * 0.5) + (x * cell_size_step)
			var world_z = world_offset.z - (chunk_size * 0.5) + (z * cell_size_step)

			var base_height = noise.get_noise_2d(world_x, world_z) * amplitude

			match terrain_type:
				3:  # VALLEYS
					base_height = -abs(base_height)
				4:  # PLATEAU
					if base_height > plateau_level:
						base_height = plateau_level
				0:  # FLAT
					base_height *= 0.02

			if erosion_strength > 0.0:
				var erosion_noise = FastNoiseLite.new()
				erosion_noise.seed = seed_value + 1000
				erosion_noise.frequency = frequency * 4.0
				var erosion_factor = erosion_noise.get_noise_2d(world_x, world_z)
				erosion_factor = (erosion_factor + 1.0) * 0.5
				base_height = base_height * (1.0 - erosion_strength * erosion_factor)

			height_data[z * resolution + x] = base_height

	# Build mesh (same logic as terrain_chunk.gd)
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in range(resolution):
		for x in range(resolution):
			var local_x = -chunk_size * 0.5 + x * cell_size_step
			var local_z = -chunk_size * 0.5 + z * cell_size_step
			var height = height_data[z * resolution + x]

			var u = float(x) / float(resolution - 1)
			var v = float(z) / float(resolution - 1)
			surface_tool.set_uv(Vector2(u, v))

			var height_ratio = (height + amplitude) / (2.0 * amplitude)
			height_ratio = clamp(height_ratio, 0.0, 1.0)
			surface_tool.set_color(Color(height_ratio, 1.0 - height_ratio, 0.5))

			surface_tool.add_vertex(Vector3(local_x, height, local_z))

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
	var mesh = surface_tool.commit()

	# Create the chunk node with mesh
	var chunk = Node3D.new()
	chunk.name = "TerrainChunk_%d_%d" % [grid_pos.x, grid_pos.y]
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	chunk.add_child(mesh_instance)

	# Material (same as terrain_chunk.gd)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.7, 0.2)
	material.roughness = 0.8
	material.metallic = 0.0
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	mesh_instance.material_override = material

	# Position and add to scene
	chunk.position = world_offset
	add_child(chunk)

	if Engine.is_editor_hint():
		chunk.owner = get_tree().edited_scene_root
		mesh_instance.owner = get_tree().edited_scene_root

	print("TerrainTCPServer: Generated terrain at ", grid_pos, " -> world ", world_offset)
	terrain_generated.emit(grid_pos, chunk)

func _send_message(message: Dictionary) -> void:
	if peer and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_var(message)

func _exit_tree() -> void:
	stop_listening()
