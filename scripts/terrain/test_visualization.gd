extends Node3D

func _ready():
	test_coordinate_display()
	
func test_coordinate_display():
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
		
		add_child(dummy_chunk
		)
		if GridManager.occupy_cell(pos, dummy_chunk):
			print("Successfully placed test chunk at ", pos)
		else:
			print("Failed to place test chunk at ", pos)

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_G:
			var visualizer = get_node("GridVisualizer")
			if visualizer:
				visualizer.set_visibility(not visualizer.visible)
