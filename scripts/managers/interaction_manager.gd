extends Node

enum InteractionMode {
	SIZE_SELECTION,
	PLACEMENT,
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

signal mode_changed(old_mode: InteractionMode, new_mode: InteractionMode)
signal chunk_size_changed(new_size: GridManager.ChunkSize)
signal placement_confirmed(grid_pos: Vector2i, size: GridManager.ChunkSize)

func _ready():
	setup_controller_connections()
	create_preview_chunk()
	
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

func _on_controller_trigger(world_pos: Vector3, grid_pos: Vector2i):
	match current_mode:
		InteractionMode.SIZE_SELECTION:
			# In size selection mode, trigger starts placement mode
			set_mode(InteractionMode.PLACEMENT)
			
		InteractionMode.PLACEMENT:
			# Place chunk at target position
			attempt_placement(grid_pos)
			
		InteractionMode.LOCKED:
			# Maybe select existing chunk for editing?
			pass

func _on_controller_primary_button():
	# Mode switching with primary button
	match current_mode:
		InteractionMode.SIZE_SELECTION:
			set_mode(InteractionMode.PLACEMENT)
		InteractionMode.PLACEMENT:
			set_mode(InteractionMode.SIZE_SELECTION)
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
	var terrain_chunk = TerrainChunk.new()
	terrain_chunk.grid_position = grid_pos
	
	# Add basic visual representation
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	var size_meters = GridManager.get_chunk_size_meters(chunk_size)
	box_mesh.size = Vector3(size_meters * 0.8, 0.5, size_meters * 0.8)
	mesh_instance.mesh = box_mesh
	terrain_chunk.add_child(mesh_instance)
	
	# Position chunk in world
	var world_position = GridManager.grid_to_world(grid_pos)
	terrain_chunk.global_position = world_position
	
	# Add to scene
	get_tree().current_scene.add_child(terrain_chunk)
	
	# Register with grid manager
	GridManager.occupy_cell(grid_pos, terrain_chunk)

func set_mode(new_mode: InteractionMode):
	var old_mode = current_mode
	current_mode = new_mode
	mode_changed.emit(old_mode, new_mode)
	
	# Mode-specific setup
	match new_mode:
		InteractionMode.SIZE_SELECTION:
			preview_chunk.visible = false
			
		InteractionMode.PLACEMENT:
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
	if current_mode == InteractionMode.PLACEMENT and preview_chunk.visible:
		if primary_controller and primary_controller.is_hovering_valid_cell:
			var world_pos = GridManager.grid_to_world(primary_controller.current_grid_position)
			preview_chunk.global_position = world_pos + Vector3(0, 0.05, 0)
			preview_position = primary_controller.current_grid_position
