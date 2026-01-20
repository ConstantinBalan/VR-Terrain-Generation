extends Node

@export var grid_size: float = 4.0
@export var grid_offset: Vector3 = Vector3.ZERO
@export var max_grid_extent: int = 50
@export var debug_mode: bool = true

var grid_data: Dictionary = {} #{Vector2i: TerrainChunk}
var occupied_cells: Array[Vector2i] = []
var chunk_metadata: Dictionary = {}

signal cell_occupied(gris_pos: Vector2i, chunk: TerrainChunk)
signal cell_freed(grid_pos: Vector2i)
signal grid_bounds_exceeded(attempted_pos: Vector2i)
signal grid_size_changed(old_size: float, new_size: float)

func _ready():
	print("GridManager initialized - Cell Size: ", grid_size, "m, Max extent: ", max_grid_extent)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var adjusted_position = world_pos - grid_offset
	
	var grid_x = int(floor(adjusted_position.x / grid_size))
	var grid_z = int(floor(adjusted_position.z / grid_size))
	
	return Vector2i(clamp(grid_x, -grid_size, grid_size), clamp(grid_z, -grid_size, grid_size))	
	
func grid_to_world(grid_coordinates: Vector2i) -> Vector3:
	var world_x = float(grid_coordinates.x) * grid_size + (grid_size * 0.5)
	var world_z = float(grid_coordinates.y) * grid_size + (grid_size * 0.5)
	
	return Vector3(world_x, 0.0, world_z) + grid_offset
	
func is_cell_occupied(grid_coordinates: Vector2i) -> bool:
	return grid_data.has(grid_coordinates)
	
func is_within_bounds(grid_coordinates: Vector2i) -> bool:
	var distance_from_origin = grid_coordinates.length()
	return distance_from_origin <= max_grid_extent
	
func get_chunk_at(grid_coordinates: Vector2i, chunk: TerrainChunk) -> bool:
	if grid_data.get(grid_coordinates) == null:
		push_warning("Chunk could not be found at: " + str(grid_coordinates))
	return grid_data.get(grid_coordinates, null)
	
func occupy_cell(grid_coordinates: Vector2i, chunk: TerrainChunk) -> bool:
	if not is_within_bounds(grid_coordinates):
		if debug_mode:
			push_warning("Grid position out of bounds: " + str(grid_coordinates))
		grid_bounds_exceeded.emit(grid_coordinates)
		return false
	if is_cell_occupied(grid_coordinates):
		if debug_mode:
			push_warning("Attempted to occupy already occupied cell: " + str(grid_coordinates))
		return false
	grid_data[grid_coordinates] = chunk
	occupied_cells.append(grid_coordinates)
	
	cell_occupied.emit(grid_coordinates, chunk)
	return true
	
func free_cell(grid_coordinates: Vector2i) -> bool:
	if not is_cell_occupied(grid_coordinates):
		return false
	
	var freed_chunk = grid_data[grid_coordinates]
	grid_data.erase(grid_coordinates)
	occupied_cells.erase(grid_coordinates)
	
	#TODO: Also delete the Terrain itself, disconnect signals
	if freed_chunk and is_instance_valid(freed_chunk):
		freed_chunk.queue_free()
	
	cell_freed.emit(grid_coordinates)
	return true
	

func get_neighbor_cells(grid_coordinates: Vector2i, include_diagonals: bool = false) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var cardinal_directions = [
		Vector2i(-1, 0),   # Left
		Vector2i(1, 0),    # Right  
		Vector2i(0, -1),   # Up
		Vector2i(0, 1),    # Down
	]
	var diagonal_directions = [ #I don't know a better way to name these
		Vector2i(-1, -1), # Southwest
		Vector2i(-1, 1), # Northwest
		Vector2i(1, -1), # Southeast
		Vector2i(1, 1) # Northeast
	]
	
	for direction in cardinal_directions:
		neighbors.append(grid_coordinates + direction)
	
	if include_diagonals:
		for diag_direction in diagonal_directions:
			neighbors.append(grid_coordinates + diag_direction)
	
	return neighbors
	
func get_occupied_neighbors(grid_coordinates: Vector2i) -> Array[Vector2i]:
	var all_neighbors = get_neighbor_cells(grid_coordinates)
	var occupied_neighbors: Array[Vector2i] = []
	
	for neighbor in all_neighbors:
		if is_cell_occupied(neighbor):
			occupied_neighbors.append(neighbor)
			
	return occupied_neighbors
	
func set_grid_size(new_size: float) -> void:
	if new_size <= 0:
		push_error("Grid size cannot be negative")
		return
	
	var old_size = grid_size
	grid_size = new_size
	grid_size_changed.emit(old_size, new_size)
	
func save_grid_state() -> Dictionary:
	return {
		"grid_size": grid_size,
		"grid_offset": grid_offset,
		"occupied_positions": occupied_cells,
		"chunk_metadata": chunk_metadata
	}

func load_grid_state(state: Dictionary):
	grid_size = state.get("grid_size", 8.0)
	grid_offset = state.get("grid_offset", Vector3.ZERO)
	# Regenerate actual terrain chunks
