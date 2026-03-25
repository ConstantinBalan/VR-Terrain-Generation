extends Node

enum InteractionMode {
	SIZE_SELECTION,
	PLACEMENT,
	VOICE_MODE,
	VOICE_RECORDING,
	VOICE_PROCESSING,
	LOCKED,
	EDITING
}

@export var current_mode: InteractionMode = InteractionMode.SIZE_SELECTION
@export var selected_chunk_size: GridManager.ChunkSize = GridManager.ChunkSize.SMALL_8x8
@export var generation_mode: TerrainParameters.GenerationMode = TerrainParameters.GenerationMode.HEIGHTMAP_2D

var left_controller: VRController
var right_controller: VRController
var primary_controller: VRController

var preview_chunk: MeshInstance3D
var preview_position: Vector2i

# Voice terrain control integration
var voice_controller: VoiceTerrainController

# TCP export
var tcp_client: TerrainTCPClient

signal mode_changed(old_mode: InteractionMode, new_mode: InteractionMode)
signal chunk_size_changed(new_size: GridManager.ChunkSize)
signal placement_confirmed(grid_pos: Vector2i, size: GridManager.ChunkSize)
signal voice_recording_started()
signal voice_recording_stopped()
signal export_started()
signal export_finished(total_sent: int)

func _ready():
	setup_controller_connections()
	create_preview_chunk()
	setup_voice_controller()
	setup_tcp_client()
	
func setup_controller_connections():
	# Find VR controllers from the main scene structure
	var main_scene = get_tree().current_scene
	if main_scene:
		var vr_user = main_scene.get_node_or_null("VR_User")
		if vr_user:
			var xr_origin = vr_user.get_node_or_null("XROrigin3D")
			if xr_origin:
				left_controller = xr_origin.get_node_or_null("LeftHand")
				right_controller = xr_origin.get_node_or_null("RightHand")
				
				# Default to right hand as primary
				primary_controller = right_controller
				
				# Connect signals
				if left_controller:
					left_controller.trigger_activated.connect(_on_controller_trigger)
					left_controller.primary_button_activated.connect(_on_controller_primary_button)
					left_controller.secondary_button_activated.connect(_on_controller_secondary_button)
					left_controller.thumbstick_size_up.connect(_on_thumbstick_size_up)
					left_controller.thumbstick_size_down.connect(_on_thumbstick_size_down)
					left_controller.thumbstick_mode_toggle.connect(_on_thumbstick_mode_toggle)
					
				if right_controller:
					right_controller.trigger_activated.connect(_on_controller_trigger)
					right_controller.primary_button_activated.connect(_on_controller_primary_button)
					right_controller.secondary_button_activated.connect(_on_controller_secondary_button)
					right_controller.thumbstick_size_up.connect(_on_thumbstick_size_up)
					right_controller.thumbstick_size_down.connect(_on_thumbstick_size_down)
					right_controller.thumbstick_mode_toggle.connect(_on_thumbstick_mode_toggle)

func create_preview_chunk():
	preview_chunk = MeshInstance3D.new()
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 1.0, 0.5, 0.5)  # Transparent green
	material.flags_transparent = true
	material.flags_unshaded = true
	
	get_tree().current_scene.add_child(preview_chunk)
	preview_chunk.visible = false

func setup_voice_controller():
	# Create voice terrain controller
	voice_controller = VoiceTerrainController.new()
	add_child(voice_controller)
	
	# Connect voice system signals
	voice_controller.voice_recording_started.connect(_on_voice_recording_started)
	voice_controller.voice_recording_stopped.connect(_on_voice_recording_stopped)
	voice_controller.voice_processing_started.connect(_on_voice_processing_started)
	voice_controller.voice_processing_completed.connect(_on_voice_processing_completed)
	voice_controller.voice_processing_failed.connect(_on_voice_processing_failed)
	voice_controller.terrain_generation_completed.connect(_on_voice_terrain_completed)
	
	print("InteractionManager: Voice terrain controller setup complete")

func setup_tcp_client():
	tcp_client = TerrainTCPClient.new()
	add_child(tcp_client)
	tcp_client.connected_to_editor.connect(_on_tcp_connected)
	tcp_client.disconnected_from_editor.connect(_on_tcp_disconnected)
	tcp_client.chunk_acknowledged.connect(_on_chunk_acknowledged)
	tcp_client.export_completed.connect(_on_export_completed)
	tcp_client.connection_failed.connect(_on_tcp_connection_failed)
	print("InteractionManager: TCP client setup complete")

func _on_tcp_connected():
	print("InteractionManager: Connected to editor - exporting all chunks")
	tcp_client.export_all_chunks()
	export_started.emit()

func _on_tcp_disconnected():
	print("InteractionManager: Disconnected from editor")

func _on_chunk_acknowledged(grid_pos: Vector2i):
	print("InteractionManager: Editor acknowledged chunk at ", grid_pos)

func _on_export_completed(total_sent: int):
	print("InteractionManager: Export complete - ", total_sent, " chunks sent to editor")
	export_finished.emit(total_sent)

func _on_tcp_connection_failed(reason: String):
	print("InteractionManager: TCP connection failed - ", reason)

func trigger_export():
	if GridManager.chunk_parameters.is_empty():
		print("InteractionManager: No chunks to export")
		return
	if tcp_client.state == TerrainTCPClient.ConnectionState.CONNECTED:
		tcp_client.export_all_chunks()
		export_started.emit()
	else:
		print("InteractionManager: Connecting to editor at 127.0.0.1:", NetworkProtocol.DEFAULT_PORT)
		tcp_client.connect_to_editor()

# Voice system callbacks
func _on_voice_recording_started():
	print("InteractionManager: Voice recording started")
	voice_recording_started.emit()

func _on_voice_recording_stopped(duration: float):
	print("InteractionManager: Voice recording stopped (", duration, "s)")
	set_mode(InteractionMode.VOICE_PROCESSING)
	voice_recording_stopped.emit()

func _on_voice_processing_started(audio_file_path: String):
	print("InteractionManager: Voice processing started for file: ", audio_file_path)

func _on_voice_processing_completed(terrain_params: Dictionary):
	print("InteractionManager: Voice processing completed with params: ", terrain_params)

func _on_voice_processing_failed(error_message: String):
	print("InteractionManager ERROR: Voice processing failed: ", error_message)
	set_mode(InteractionMode.PLACEMENT)  # Return to placement mode

func _on_voice_terrain_completed(chunk: Node3D):
	print("InteractionManager: Voice-generated terrain completed")
	set_mode(InteractionMode.LOCKED)  # Lock after successful voice generation

func _on_controller_trigger(world_pos: Vector3, grid_pos: Vector2i):
	# Enforced flow: SIZE_SELECTION -> VOICE_MODE -> VOICE_RECORDING -> VOICE_PROCESSING -> LOCKED
	match current_mode:
		InteractionMode.SIZE_SELECTION:
			# Confirm size, move to aiming for position
			set_mode(InteractionMode.VOICE_MODE)

		InteractionMode.VOICE_MODE:
			# Confirm position, move to recording
			if voice_controller and voice_controller.can_start_recording():
				voice_controller.target_grid_position = grid_pos
				voice_controller.target_chunk_size = selected_chunk_size
				set_mode(InteractionMode.VOICE_RECORDING)
				print("InteractionManager: Voice target set at ", grid_pos, " - Hold LEFT GRIP and speak")
			else:
				print("InteractionManager: Cannot set target - voice controller not ready")

		InteractionMode.VOICE_RECORDING, InteractionMode.VOICE_PROCESSING:
			# Pipeline is running - ignore trigger
			print("InteractionManager: Voice system active - trigger ignored")

		InteractionMode.LOCKED:
			# Generation complete - trigger resets to start
			set_mode(InteractionMode.SIZE_SELECTION)

func _on_controller_primary_button():
	# Primary button only used to go back one step or cancel
	match current_mode:
		InteractionMode.VOICE_MODE:
			# Go back to size selection
			set_mode(InteractionMode.SIZE_SELECTION)
		InteractionMode.VOICE_RECORDING:
			# Cancel recording, go back to aiming
			if voice_controller and voice_controller.is_recording():
				voice_controller.stop_voice_recording()
			set_mode(InteractionMode.VOICE_MODE)
		InteractionMode.LOCKED:
			set_mode(InteractionMode.SIZE_SELECTION)
		_:
			# No action in other states
			pass

func _on_controller_secondary_button():
	# Size cycling only in size selection
	if current_mode == InteractionMode.SIZE_SELECTION:
		cycle_chunk_size()

func _on_thumbstick_size_up():
	if current_mode == InteractionMode.SIZE_SELECTION:
		increase_chunk_size()

func _on_thumbstick_size_down():
	if current_mode == InteractionMode.SIZE_SELECTION:
		decrease_chunk_size()

func _on_thumbstick_mode_toggle():
	# Thumbstick click triggers terrain export to editor
	print("InteractionManager: Thumbstick click - triggering export to editor")
	trigger_export()

func cycle_chunk_size():
	match selected_chunk_size:
		GridManager.ChunkSize.SMALL_8x8:
			selected_chunk_size = GridManager.ChunkSize.MEDIUM_16x16
		GridManager.ChunkSize.MEDIUM_16x16:
			selected_chunk_size = GridManager.ChunkSize.LARGE_32x32
		GridManager.ChunkSize.LARGE_32x32:
			selected_chunk_size = GridManager.ChunkSize.SMALL_8x8
	
	chunk_size_changed.emit(selected_chunk_size)
	update_preview_chunk()
	
	print("Chunk size changed to: ", selected_chunk_size)

func increase_chunk_size():
	match selected_chunk_size:
		GridManager.ChunkSize.SMALL_8x8:
			selected_chunk_size = GridManager.ChunkSize.MEDIUM_16x16
		GridManager.ChunkSize.MEDIUM_16x16:
			selected_chunk_size = GridManager.ChunkSize.LARGE_32x32
		# Large stays large
	
	chunk_size_changed.emit(selected_chunk_size)
	update_preview_chunk()

func decrease_chunk_size():
	match selected_chunk_size:
		GridManager.ChunkSize.LARGE_32x32:
			selected_chunk_size = GridManager.ChunkSize.MEDIUM_16x16
		GridManager.ChunkSize.MEDIUM_16x16:
			selected_chunk_size = GridManager.ChunkSize.SMALL_8x8
		# Small stays small
	
	chunk_size_changed.emit(selected_chunk_size)
	update_preview_chunk()

func attempt_placement(grid_pos: Vector2i):
	if GridManager.is_within_bounds(grid_pos) and not GridManager.is_cell_occupied(grid_pos):
		# Create actual terrain chunk
		create_terrain_at_position(grid_pos, selected_chunk_size)
		placement_confirmed.emit(grid_pos, selected_chunk_size)
		set_mode(InteractionMode.LOCKED)
		return true
	else:
		print("Cannot place at ", grid_pos, " - invalid position")
		return false

func create_terrain_at_position(grid_pos: Vector2i, chunk_size: GridManager.ChunkSize):
	var params = TerrainParameters.new()
	params.chunk_size_meters = GridManager.get_chunk_size_meters(chunk_size)
	params.seed_value = randi() * 10000
	params.frequency = randf_range(0.05, 0.15)
	params.amplitude = randf_range(3.0, 8.0)
	params.generation_mode = generation_mode

	# Position in world using proper multi-cell positioning
	var world_position = GridManager.grid_to_world_chunk(grid_pos, selected_chunk_size)

	var terrain_node: Node3D
	match generation_mode:
		TerrainParameters.GenerationMode.DUAL_CONTOURING_3D:
			var dc_chunk = preload("res://scenes/terrain/dual_contouring_chunk.tscn").instantiate()
			params.grid_size_3d = 16
			params.resolution = 16  # Not used for DC but keep consistent
			dc_chunk.global_position = world_position
			get_tree().current_scene.add_child(dc_chunk)
			GridManager.occupy_area(grid_pos, selected_chunk_size, dc_chunk)
			dc_chunk.generate_terrain(params, grid_pos)
			terrain_node = dc_chunk
		_:
			# Default: HEIGHTMAP_2D
			var terrain_chunk = preload("res://scenes/terrain/terrain_chunk.tscn").instantiate()
			params.resolution = 64
			terrain_chunk.global_position = world_position
			get_tree().current_scene.add_child(terrain_chunk)
			GridManager.occupy_area(grid_pos, selected_chunk_size, terrain_chunk)
			terrain_chunk.generate_terrain(params, grid_pos)
			GridManager.store_chunk_data(grid_pos, terrain_chunk.height_data, params)
			terrain_node = terrain_chunk

func set_mode(new_mode: InteractionMode):
	var old_mode = current_mode
	current_mode = new_mode
	mode_changed.emit(old_mode, new_mode)
	
	# Mode-specific setup
	match new_mode:
		InteractionMode.SIZE_SELECTION:
			preview_chunk.visible = false
			# Reset voice controller so it's ready for the next cycle
			if voice_controller and voice_controller.current_state != VoiceTerrainController.VoiceState.IDLE:
				voice_controller.current_state = VoiceTerrainController.VoiceState.IDLE
			print("InteractionManager: [Step 1/4] SIZE SELECTION - Thumbstick to change size, TRIGGER to confirm")

		InteractionMode.VOICE_MODE:
			preview_chunk.visible = true
			update_preview_chunk()
			print("InteractionManager: [Step 2/4] AIM & PLACE - Aim at grid, TRIGGER to confirm position (PRIMARY to go back)")

		InteractionMode.VOICE_RECORDING:
			preview_chunk.visible = true
			print("InteractionManager: [Step 3/4] SPEAK - Hold LEFT GRIP and describe terrain (PRIMARY to cancel)")

		InteractionMode.VOICE_PROCESSING:
			preview_chunk.visible = true
			print("InteractionManager: [Step 4/4] PROCESSING - Generating terrain from voice...")

		InteractionMode.LOCKED:
			preview_chunk.visible = false
			print("InteractionManager: DONE - Terrain placed! TRIGGER to start again")

		InteractionMode.PLACEMENT:
			# Kept for compatibility but not part of voice flow
			preview_chunk.visible = true
			update_preview_chunk()

func update_preview_chunk():
	if not preview_chunk:
		return
		
	# Create simple box mesh representing chunk bounds
	var box_mesh = BoxMesh.new()
	var size = GridManager.get_chunk_size_meters(selected_chunk_size)
	box_mesh.size = Vector3(size, 0.1, size)
	
	preview_chunk.mesh = box_mesh

func _process(delta):
	update_preview_position()

func update_preview_position():
	if current_mode == InteractionMode.VOICE_MODE and preview_chunk.visible:
		# Follow hand while aiming for position
		if primary_controller and primary_controller.is_hovering_valid_cell:
			var world_pos = GridManager.grid_to_world_chunk(primary_controller.current_grid_position, selected_chunk_size)
			preview_chunk.global_position = world_pos + Vector3(0, 0.05, 0)
			preview_position = primary_controller.current_grid_position
