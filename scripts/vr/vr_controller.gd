class_name VRController
extends XRController3D

@export var is_right_hand: bool = true
@export var interaction_range: float = 300.0

@onready var raycast: RayCast3D = get_node_or_null("LeftRaycast") if not is_right_hand else get_node_or_null("RightRaycast")
@onready var hand_model = get_node_or_null("LeftHandModel") if not is_right_hand else get_node_or_null("RightHandModel")
@onready var interaction_sphere = get_node_or_null("InteractionSphere") if is_right_hand else null

var trigger_pressed: bool = false
var primary_button_pressed: bool = false
var secondary_button_pressed: bool = false
var thumbstick_click_pressed: bool = false

var current_target_position: Vector3
var current_grid_position: Vector2i
var is_hovering_valid_cell: bool = false
var grid_cell_preview: MeshInstance3D

signal trigger_activated(world_pos: Vector3, grid_pos: Vector2i)
signal primary_button_activated()
signal secondary_button_activated()
signal thumbstick_size_up()
signal thumbstick_size_down() 
signal thumbstick_mode_toggle()

func _ready():
	print("VRController _ready() called for ", name, " (is_right_hand=", is_right_hand, ")")
	print("  Raycast node: ", raycast)
	print("  Hand model: ", hand_model)
	print("  Interaction sphere: ", interaction_sphere)
	setup_raycast()
	setup_hand_model()
	setup_interaction_feedback()
	
func setup_raycast():
	if raycast:
		raycast.target_position = Vector3(0,0, -interaction_range)
		raycast.collision_mask = 1
		raycast.enabled = true
		raycast.visible = true
		
		# Create a cylinder to visualize the raycast instead of lines
		var ray_visual = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.height = interaction_range
		cylinder.top_radius = 0.01  # Very thin cylinder
		cylinder.bottom_radius = 0.01
		ray_visual.mesh = cylinder
		
		# Rotate cylinder to point forward (along Z-axis) and position it
		ray_visual.rotation_degrees = Vector3(90, 0, 0)  # Rotate 90 degrees around X-axis
		ray_visual.position = Vector3(0, 0, -interaction_range / 2)
		ray_visual.name = "RaycastVisualization"
		raycast.add_child(ray_visual)
		
		# Create material for the ray
		var material = StandardMaterial3D.new()
		material.albedo_color = Color.RED if is_right_hand else Color.BLUE
		material.flags_unshaded = true
		material.flags_transparent = true
		material.albedo_color.a = 0.7
		ray_visual.material_override = material
		
		print("Raycast setup for ", name, ": enabled=", raycast.enabled, " visible=", raycast.visible)
	else:
		print("Warning: No raycast found for controller ", name)

func setup_hand_model():
	if not hand_model:
		hand_model = MeshInstance3D.new()
		var capsule = CapsuleMesh.new()
		capsule.radius = 0.075
		capsule.height = 0.15
		hand_model.mesh = capsule
		add_child(hand_model)
		hand_model.name = "HandModel"
		
		# Make hand model more visible
		var hand_material = StandardMaterial3D.new()
		hand_material.albedo_color = Color.GREEN if is_right_hand else Color.BLUE
		hand_material.flags_unshaded = true
		hand_model.material_override = hand_material
		
		print("Hand model created for ", name, " (", "right" if is_right_hand else "left", ")")
		
	
func setup_interaction_feedback():
	if is_right_hand:
		# Create grid cell preview instead of simple sphere
		if not grid_cell_preview:
			grid_cell_preview = MeshInstance3D.new()
			update_preview_size()  # Set initial size based on selected chunk
			add_child(grid_cell_preview)
			grid_cell_preview.name = "GridCellPreview"
			grid_cell_preview.visible = false
			
			# Create transparent material for preview
			var preview_material = StandardMaterial3D.new()
			preview_material.albedo_color = Color.GREEN
			preview_material.flags_transparent = true
			preview_material.flags_unshaded = true
			preview_material.albedo_color.a = 0.5
			grid_cell_preview.material_override = preview_material
			
			print("Grid cell preview created for right hand controller")
		
		# Keep the original sphere for backward compatibility if needed
		if not interaction_sphere:
			interaction_sphere = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.05
			interaction_sphere.mesh = sphere
			add_child(interaction_sphere)
			interaction_sphere.name = "InteractionSphere"
			interaction_sphere.visible = false
	else:
		print("Skipping interaction feedback - left hand controller")

func _process(delta: float) -> void:
	update_input_state()
	update_raycast_target()
	update_visual_feedback()
	
	# Debug output every 60 frames (roughly once per second at 60 FPS)
	#if Engine.get_process_frames() % 60 == 0 and is_right_hand:
		#debug_raycast_status()

func update_input_state():
	var old_trigger = trigger_pressed
	var old_primary = primary_button_pressed
	var old_secondary = secondary_button_pressed
	var old_thumbstick_click = thumbstick_click_pressed
	
	trigger_pressed = get_float("terrain_trigger") > 0.5
	primary_button_pressed = is_button_pressed("terrain_primary")
	secondary_button_pressed = is_button_pressed("terrain_secondary")  
	thumbstick_click_pressed = is_button_pressed("terrain_thumbstick_click")
	
	if trigger_pressed and not old_trigger:
		handle_trigger_press()
	
	if primary_button_pressed and not old_primary:
		handle_primary_button_press()
		
	if secondary_button_pressed and not old_secondary:
		handle_secondary_button_press()
		
	if thumbstick_click_pressed and not old_thumbstick_click:
		handle_thumbstick_mode_toggle()
	
	# Handle thumbstick directional input
	handle_thumbstick_input()

func update_raycast_target():
	if raycast:
		if raycast.is_colliding():
			current_target_position = raycast.get_collision_point()
			current_grid_position = GridManager.world_to_grid(current_target_position)
			
			# Validate grid position
			is_hovering_valid_cell = GridManager.is_within_bounds(current_grid_position) and \
								   not GridManager.is_cell_occupied(current_grid_position)
			
			# Show grid cell preview at the grid-aligned position
			if grid_cell_preview and is_right_hand:
				var grid_world_pos = GridManager.grid_to_world(current_grid_position)
				grid_cell_preview.global_position = grid_world_pos + Vector3(0, 0.08, 0)  # Slightly above ground
				grid_cell_preview.global_rotation = Vector3.ZERO  # Keep oriented to world, not controller
				grid_cell_preview.visible = true
				
				# Update preview size in case selection changed
				update_preview_size()
				
				# Update preview color based on validity
				update_preview_material()
			
			# Keep interaction sphere for debugging (smaller, less intrusive)
			if interaction_sphere:
				interaction_sphere.global_position = current_target_position + Vector3(0, 0.02, 0)
				interaction_sphere.visible = false  # Hide for now, grid preview is primary
		else:
			is_hovering_valid_cell = false
			if grid_cell_preview:
				grid_cell_preview.visible = false
			if interaction_sphere:
				interaction_sphere.visible = false
	else:
		print("Warning: Raycast is null in update_raycast_target for ", name)

func update_visual_feedback():
	# Legacy interaction sphere feedback (kept for compatibility)
	if interaction_sphere and interaction_sphere.visible:
		var material = interaction_sphere.get_surface_override_material(0)
		if not material:
			material = StandardMaterial3D.new()
			interaction_sphere.set_surface_override_material(0, material)
		
		# Color coding: Green = valid, Red = invalid, Yellow = occupied
		if is_hovering_valid_cell:
			material.albedo_color = Color.GREEN
		elif GridManager.is_cell_occupied(current_grid_position):
			material.albedo_color = Color.YELLOW
		else:
			material.albedo_color = Color.RED

func update_preview_material():
	if not grid_cell_preview or not grid_cell_preview.material_override:
		return
		
	var material = grid_cell_preview.material_override as StandardMaterial3D
	if not material:
		return
	
	# Color coding for grid cell preview
	if is_hovering_valid_cell:
		material.albedo_color = Color.GREEN
		material.albedo_color.a = 0.6  # More opaque for valid placement
	elif GridManager.is_cell_occupied(current_grid_position):
		material.albedo_color = Color.YELLOW
		material.albedo_color.a = 0.4  # Less opaque for occupied
	else:
		material.albedo_color = Color.RED
		material.albedo_color.a = 0.4  # Less opaque for invalid

func update_preview_size():
	if not grid_cell_preview or not InteractionManager:
		return
		
	# Get the current selected chunk size from InteractionManager
	var selected_size = InteractionManager.selected_chunk_size
	var chunk_size_meters = GridManager.get_chunk_size_meters(selected_size)
	
	# Create/update the box mesh to match the terrain chunk size
	var box = BoxMesh.new()
	box.size = Vector3(chunk_size_meters * 0.95, 0.15, chunk_size_meters * 0.95)  # Slightly smaller for visual clarity
	grid_cell_preview.mesh = box
	
	print("Preview size updated to: ", chunk_size_meters, "m (", selected_size, ")")

func handle_trigger_press():
	if is_hovering_valid_cell:
		print("Trigger pressed at valid position: ", current_grid_position)
		trigger_activated.emit(current_target_position, current_grid_position)

func handle_primary_button_press():
	print("Primary button pressed - switching modes")
	primary_button_activated.emit()

func handle_secondary_button_press():  
	print("Secondary button pressed - cycling size")
	secondary_button_activated.emit()

func handle_thumbstick_mode_toggle():
	print("Thumbstick clicked - toggling mode")
	thumbstick_mode_toggle.emit()

func handle_thumbstick_input():
	# Use native XRController3D thumbstick input
	var thumbstick_value = get_vector2("terrain_thumbstick")
	
	# Check for vertical movement (up/down for size selection)
	if thumbstick_value.y > 0.5:
		thumbstick_size_up.emit()
	elif thumbstick_value.y < -0.5:
		thumbstick_size_down.emit()

func debug_raycast_status():
	if raycast:
		print("Raycast Debug for ", name, ":")
		print("  Controller world position: ", global_position)
		print("  Controller transform: ", global_transform)
		print("  Raycast local target: ", raycast.target_position)
		print("  Raycast world from: ", raycast.global_position)
		print("  Raycast world to: ", raycast.global_position + raycast.global_transform.basis * raycast.target_position)
		print("  Enabled: ", raycast.enabled)
		print("  Collision mask: ", raycast.collision_mask)
		print("  Is colliding: ", raycast.is_colliding())
		if raycast.is_colliding():
			print("  Collision point: ", raycast.get_collision_point())
			print("  Collider: ", raycast.get_collider())
		if interaction_sphere:
			print("  Interaction sphere visible: ", interaction_sphere.visible)
	else:
		print("No raycast found for ", name)
