extends Node3D

func _ready():
	test_coordinate_conversion()
	test_boundary_conditions()
	test_neighbor_finding()
	
func test_coordinate_conversion() -> void:
	print("Testing coordinate conversion")
	
	var test_positions = [
		Vector3(0,0,0),
		Vector3(4,0,4),
		Vector3(8,0,8),
		Vector3(-4,0,-4),
		Vector3(7.99, 0, 7.99)
	]
	
	for pos in test_positions:
		var grid_coordinate = GridManager.world_to_grid(pos)
		var world_position = GridManager.grid_to_world(grid_coordinate)
		print("World: ", pos, " -> Grid: ", grid_coordinate, " -> World: ", world_position)

func test_boundary_conditions():
	print("Testing boundary conditions")
	
	var boundary_test = Vector2i(GridManager.max_grid_extent + 1, 0)
	print("Beyond boundary acceptable: ", GridManager.is_within_bounds(boundary_test))
	
func test_neighbor_finding():
	print("Testing neighbor detection")
	
	var center = Vector2i(0,0)
	var neighbors = GridManager.get_neighbor_cells(center)
	print("Neighbors of " + str(center), ": ", str(neighbors))
	
