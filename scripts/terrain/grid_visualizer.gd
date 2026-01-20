class_name GridVisualizer
extends Node3D

@export var line_material: StandardMaterial3D
@export var occupied_material: StandardMaterial3D
@export var grid_line_width: float = 0.02
@export var visible_radius: int = 20
@export var show_coordinates: bool = true

var grid_lines: Array[MeshInstance3D] = []
var coordinate_labels: Array[Label3D] = []
var current_center: Vector2i = Vector2i.ZERO

func _ready():
	GridManager.cell_occupied.connect(_on_cell_occupied)
	GridManager.cell_freed.connect(_on_cell_freed)
	generate_grid_lines()

func generate_grid_lines() -> void:
	clear_existing_lines()
	
	var grid_size = GridManager.grid_size
	var start_x = current_center.x - visible_radius
	var end_x = current_center.x + visible_radius
	var start_z = current_center.y - visible_radius
	var end_z = current_center.y + visible_radius
	
	for x in range(start_x, end_x + 1):
		var line_mesh_x = create_line_mesh(
			Vector3(x * grid_size, 0, start_z * grid_size),
			Vector3(x * grid_size, 0, end_z * grid_size)
		)
		add_child(line_mesh_x)
		grid_lines.append(line_mesh_x)
		
	for z in range(start_z, end_z + 1):
		var line_mesh_z = create_line_mesh(
			Vector3(start_x * grid_size, 0, z * grid_size),
			Vector3(end_x * grid_size, 0, z * grid_size)
		)
		add_child(line_mesh_z)
		grid_lines.append(line_mesh_z)
		
	if show_coordinates:
		generate_coordinate_labels()
	
func create_line_mesh(start: Vector3, end: Vector3) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	
	# 1. Create Mesh
	var box_mesh = BoxMesh.new()
	var length = start.distance_to(end)
	
	# BoxMesh is aligned along Z by default, which matches Godot's Forward vector
	box_mesh.size = Vector3(grid_line_width, grid_line_width, length)
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = line_material
	
	# 2. Performance: Disable Shadows
	# (Vital for VR performance with many lines)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# 3. Calculate Positions with Y-Lift
	# We lift Y by 0.02 to stop "Z-Fighting" (flickering on the floor)
	var mid_pos = (start + end) / 2.0
	mid_pos.y = 0.02 
	
	var look_target = end
	look_target.y = 0.02
	
	# 4. The Fix: Use look_at_from_position
	# This sets the position AND rotation in one go.
	# It works safely even if the node is not yet in the scene tree.
	if not mid_pos.is_equal_approx(look_target):
		mesh_instance.look_at_from_position(mid_pos, look_target, Vector3.UP)
	
	return mesh_instance
	
func generate_coordinate_labels() -> void:
	var grid_size = GridManager.grid_size
	
	for x in range(current_center.x - visible_radius, current_center.x + visible_radius, 2):
		for z in range(current_center.y - visible_radius, current_center.y + visible_radius, 2):
			var label = Label3D.new()
			label.text = str(x) + "," + str(z)
			label.pixel_size = 0.02
			label.position = Vector3(x * grid_size, 0.1, z * grid_size)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			
			add_child(label)
			coordinate_labels.append(label)
	
func _on_cell_occupied(grid_position: Vector2i, chunk: TerrainChunk) -> void:
	highlight_cell(grid_position, occupied_material)

func _on_cell_freed(grid_position: Vector2i) -> void:
	remove_cell_highlight(grid_position)

func highlight_cell(grid_position: Vector2i, material: Material) -> void:
	var world_position = GridManager.grid_to_world(grid_position)
	var highlight = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(GridManager.grid_size * 0.9, GridManager.grid_size * 0.9)
	
	highlight.mesh = plane_mesh
	highlight.material_override = material
	highlight.position = world_position + Vector3(0, 0.01, 0)
	highlight.name = "cell_highlight_" + str(grid_position.x) + "_" + str(grid_position.y)
	
	add_child(highlight)
	
func remove_cell_highlight(grid_position: Vector2i) -> void:
	pass

func update_center(new_center: Vector2i):
	if new_center.distance_to(current_center) > visible_radius / 2:
		current_center = new_center
		generate_grid_lines()
	
func clear_existing_lines() -> void:
	for line in grid_lines:
		line.queue_free()
	grid_lines.clear()
	
	for label in coordinate_labels:
		label.queue_free()
	coordinate_labels.clear()
	
func set_visibility(visible: bool) -> void:
	self.visible = visible
