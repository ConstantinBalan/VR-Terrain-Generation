extends Node3D
class_name MainScene

@export var enable_vr: bool = true
@export var fallback_to_desktop: bool = true

# Scene references
@onready var vr_user = $VR_User
@onready var grid_visualizer = $GridVisualizer
@onready var environment = $Environment
@onready var debug_label = $UI/DebugLabel

# VR components (will be found after VR_User initializes)
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_controller: XRController3D
var right_controller: XRController3D

var desktop_camera: Camera3D

func _ready():
	setup_scene()
	setup_environment()
	setup_debug_ui()
	setup_vr_references()
	test_coordinate_display()

func setup_scene():
	# Wait for VR_User to initialize
	if vr_user:
		vr_user.vr_initialized.connect(_on_vr_initialized)
		vr_user.vr_fallback_activated.connect(_on_vr_fallback)

func setup_environment():
	# Setup lighting for terrain visualization
	var light = environment.get_node_or_null("DirectionalLight3D")
	if light:
		light.position = Vector3(10, 10, 10)
		light.look_at(Vector3.ZERO, Vector3.UP)
		light.light_energy = 1.2

func setup_debug_ui():
	if debug_label:
		debug_label.text = "Scene initializing..."

func setup_vr_references():
	# Find VR components after VR_User is ready
	if vr_user:
		xr_origin = vr_user.get_node_or_null("XROrigin3D")
		if xr_origin:
			xr_camera = xr_origin.get_node_or_null("XRCamera")
			left_controller = xr_origin.get_node_or_null("LeftHand")
			right_controller = xr_origin.get_node_or_null("RightHand")
			
			# Setup controller scripts if needed
			setup_controller_interaction()

func setup_controller_interaction():
	# This will be expanded when we add VRController scripts
	if left_controller:
		print("Left controller found: ", left_controller.name)
	if right_controller:
		print("Right controller found: ", right_controller.name)

func _on_vr_initialized():
	print("VR initialized successfully")
	setup_vr_references()
	if debug_label:
		debug_label.text = "VR Mode Active"

func _on_vr_fallback():
	print("VR fallback - setting up desktop camera")
	setup_desktop_camera()
	if debug_label:
		debug_label.text = "Desktop Mode"

func setup_desktop_camera():
	# Create desktop camera for fallback
	if not desktop_camera:
		desktop_camera = Camera3D.new()
		desktop_camera.position = Vector3(0, 2, 5)
		desktop_camera.look_at(Vector3.ZERO, Vector3.UP)
		add_child(desktop_camera)
	
	# Hide VR components
	if xr_origin:
		xr_origin.visible = false

func test_coordinate_display():
	# Wait a frame to ensure GridManager is ready
	await get_tree().process_frame
	
	var test_positions = [
		Vector2i.ZERO,
		Vector2i(1,1),
		Vector2i(-1,2)
	]
	
	for pos in test_positions:
		var dummy_chunk = TerrainChunk.new()
		dummy_chunk.name = "test_chunk_" + str(pos.x) + "_" + str(pos.y)
		dummy_chunk.grid_position = pos
		
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(GridManager.grid_size * 0.8, 0.5, GridManager.grid_size * 0.8)
		mesh_instance.mesh = box_mesh
		dummy_chunk.add_child(mesh_instance)
		
		add_child(dummy_chunk)
		
		if GridManager.occupy_cell(pos, dummy_chunk):
			print("Successfully placed test chunk at ", pos)
		else:
			print("Failed to place test chunk at ", pos)

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_G:
			if grid_visualizer:
				grid_visualizer.set_visibility(not grid_visualizer.visible)

func _process(delta):
	update_debug_info()

func update_debug_info():
	if not debug_label:
		return
		
	var fps = Engine.get_frames_per_second()
	var vr_active = vr_user and vr_user.is_vr_active()
	var controller_connected = false
	
	if right_controller:
		controller_connected = right_controller.get_is_active()
	
	var grid_cell_count = 0
	if GridManager:
		grid_cell_count = GridManager.occupied_cells.size()
	
	debug_label.text = "FPS: %d\nVR Active: %s\nController: %s\nGrid Cells: %d" % [
		fps,
		vr_active,
		controller_connected,
		grid_cell_count
	]
