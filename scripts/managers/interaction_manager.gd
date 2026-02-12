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

var left_controller: VRController
var right_controller: VRController
var primary_controller: VRController

var preview_chunk: MeshInstance3D
var preview_position: Vector2i

# Voice terrain control integration
var voice_controller: VoiceTerrainController

signal mode_changed(old_mode: InteractionMode, new_mode: InteractionMode)
signal chunk_size_changed(new_size: GridManager.ChunkSize)
signal placement_confirmed(grid_pos: Vector2i, size: GridManager.ChunkSize)
signal voice_recording_started()
signal voice_recording_stopped()

func _ready():
	setup_controller_connections()
	create_preview_chunk()
	setup_voice_controller()
	
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

func _on_voice_terrain_completed(chunk: TerrainChunk):
	print("InteractionManager: Voice-generated terrain completed at ", chunk.grid_position)
	set_mode(InteractionMode.LOCKED)  # Lock after successful voice generation

func _on_controller_trigger(world_pos: Vector3, grid_pos: Vector2i):
	match current_mode:
		InteractionMode.SIZE_SELECTION:
			# In size selection mode, trigger starts placement mode
			set_mode(InteractionMode.PLACEMENT)
			
		InteractionMode.PLACEMENT:
			# Regular terrain placement
			attempt_placement(grid_pos)
		
		InteractionMode.VOICE_MODE:
			# Voice mode: trigger sets position, then wait for grip to record
			if voice_controller and voice_controller.can_start_recording():
				voice_controller.target_grid_position = grid_pos
				voice_controller.target_chunk_size = selected_chunk_size
				set_mode(InteractionMode.VOICE_RECORDING)
				print("InteractionManager: Voice target set at ", grid_pos, " - Hold LEFT GRIP and speak")
			
		InteractionMode.VOICE_RECORDING, InteractionMode.VOICE_PROCESSING:
			# Voice system is handling interaction - ignore trigger
			print("InteractionManager: Voice system active - trigger ignored")
			pass
			
		InteractionMode.LOCKED:
			# Maybe select existing chunk for editing?
			pass

func _on_controller_primary_button():
	# Mode switching with primary button - cycles through modes
	match current_mode:
		InteractionMode.SIZE_SELECTION:
			set_mode(InteractionMode.PLACEMENT)
		InteractionMode.PLACEMENT:
			set_mode(InteractionMode.VOICE_MODE)  # Add voice mode to cycle
		InteractionMode.VOICE_MODE:
			set_mode(InteractionMode.SIZE_SELECTION)  # Cycle back to start
		InteractionMode.VOICE_RECORDING, InteractionMode.VOICE_PROCESSING:
			# Can't change modes while voice system is active
			print("InteractionManager: Cannot change modes during voice operation")
		InteractionMode.LOCKED:
			set_mode(InteractionMode.SIZE_SELECTION)

func _on_controller_secondary_button():
	# Size cycling with secondary button (only in size selection mode)
	if current_mode == InteractionMode.SIZE_SELECTION:
		cycle_chunk_size()

func _on_thumbstick_size_up():
	if current_mode == InteractionMode.SIZE_SELECTION:
		increase_chunk_size()

func _on_thumbstick_size_down():
	if current_mode == InteractionMode.SIZE_SELECTION:
		decrease_chunk_size()

func _on_thumbstick_mode_toggle():
	# Alternative mode toggle using thumbstick click
	_on_controller_primary_button()

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
	# Create basic terrain chunk for MVP (will be enhanced in Phase 2)
	var terrain_chunk = preload("res://scenes/terrain/terrain_chunk.tscn").instantiate()
	
	var params = TerrainParameters.new()
	params.chunk_size_meters = GridManager.get_chunk_size_meters(chunk_size)
	params.resolution = 64
	params.seed_value = randi() * 10000
	params.frequency = randf_range(0.05, 0.15)
	params.amplitude = randf_range(3.0, 8.0)
	# Position chunk in world using proper multi-cell positioning
	var world_position = GridManager.grid_to_world_chunk(grid_pos, selected_chunk_size)
	terrain_chunk.global_position = world_position
	
	# Add to scene
	get_tree().current_scene.add_child(terrain_chunk)
	
	# Register with grid manager using area occupation first so stitcher can connect
	GridManager.occupy_area(grid_pos, selected_chunk_size, terrain_chunk)
	
	# Then generate terrain (this will emit generation_complete signal)
	terrain_chunk.generate_terrain(params, grid_pos)

func set_mode(new_mode: InteractionMode):
	var old_mode = current_mode
	current_mode = new_mode
	mode_changed.emit(old_mode, new_mode)
	
	# Mode-specific setup
	match new_mode:
		InteractionMode.SIZE_SELECTION:
			preview_chunk.visible = false
			print("InteractionManager: SIZE SELECTION mode - Use thumbstick to change chunk size, trigger to place")
			
		InteractionMode.PLACEMENT:
			preview_chunk.visible = true
			update_preview_chunk()
			print("InteractionManager: PLACEMENT mode - Trigger places terrain immediately")
		
		InteractionMode.VOICE_MODE:
			preview_chunk.visible = true
			update_preview_chunk()
			print("InteractionManager: VOICE MODE - Trigger sets position, then HOLD LEFT GRIP and speak")
		
		InteractionMode.VOICE_RECORDING:
			# Show preview at target location during voice recording
			preview_chunk.visible = true
			update_preview_chunk()
			print("InteractionManager: VOICE_RECORDING active - Hold left grip and speak")
		
		InteractionMode.VOICE_PROCESSING:
			# Keep preview visible during processing
			preview_chunk.visible = true
			print("InteractionManager: Processing voice command...")
		
		InteractionMode.LOCKED:
			preview_chunk.visible = false
			print("InteractionManager: Terrain locked in place")

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
	if current_mode == InteractionMode.PLACEMENT and preview_chunk.visible:
		if primary_controller and primary_controller.is_hovering_valid_cell:
			var world_pos = GridManager.grid_to_world(primary_controller.current_grid_position)
			preview_chunk.global_position = world_pos + Vector3(0, 0.05, 0)
			preview_position = primary_controller.current_grid_position
