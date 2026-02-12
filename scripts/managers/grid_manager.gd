extends Node

enum ChunkSize {
	SMALL_8x8,
	MEDIUM_16x16,
	LARGE_32x32
}

@export var grid_size: float = 4.0  # Size of each grid cell in meters
@export var grid_offset: Vector3 = Vector3.ZERO
@export var max_grid_extent: int = 50
@export var debug_mode: bool = true

var grid_data: Dictionary = {} #{Vector2i: TerrainChunk}
var occupied_cells: Array[Vector2i] = []
var chunk_metadata: Dictionary = {}
var chunk_height_data: Dictionary = {} # {Vector2i: PackedFloat32Array}
var chunk_parameters: Dictionary = {} # {Vector2i: TerrainParmeters}

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
	
	return Vector2i(clamp(grid_x, -max_grid_extent, max_grid_extent), clamp(grid_z, -max_grid_extent, max_grid_extent))	
	
func grid_to_world(grid_coordinates: Vector2i) -> Vector3:
	var world_x = float(grid_coordinates.x) * grid_size + (grid_size * 0.5)
	var world_z = float(grid_coordinates.y) * grid_size + (grid_size * 0.5)
	
	return Vector3(world_x, 0.0, world_z) + grid_offset

func grid_to_world_chunk(center_grid_pos: Vector2i, chunk_size: ChunkSize) -> Vector3:
	# Get the actual cells this chunk will occupy
	var occupied_cells = get_cells_for_chunk(center_grid_pos, chunk_size)
	
	# Calculate the geometric center of all occupied cells
	var total_x = 0.0
	var total_z = 0.0
	for cell in occupied_cells:
		var cell_world = grid_to_world(cell)
		total_x += cell_world.x
		total_z += cell_world.z
	
	var center_x = total_x / occupied_cells.size()
	var center_z = total_z / occupied_cells.size()
	
	return Vector3(center_x, 0.0, center_z)
	
func is_cell_occupied(grid_coordinates: Vector2i) -> bool:
	return grid_data.has(grid_coordinates)
	
func is_within_bounds(grid_coordinates: Vector2i) -> bool:
	var distance_from_origin = grid_coordinates.length()
	return distance_from_origin <= max_grid_extent
	
func get_chunk_at(grid_coordinates: Vector2i) -> TerrainChunk:
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
	grid_size = state.get("grid_size", 4.0)
	grid_offset = state.get("grid_offset", Vector3.ZERO)
	# Regenerate actual terrain chunks

## Chunk size utility functions
func get_chunk_size_meters(chunk_size: ChunkSize) -> float:
	match chunk_size:
		ChunkSize.SMALL_8x8:
			return grid_size * 2  # 8 meters
		ChunkSize.MEDIUM_16x16:
			return grid_size * 4  # 16 meters 
		ChunkSize.LARGE_32x32:
			return grid_size * 8  # 32 meters
	return grid_size * 2

func get_chunk_size_cells(chunk_size: ChunkSize) -> int:
	match chunk_size:
		ChunkSize.SMALL_8x8:
			return 2
		ChunkSize.MEDIUM_16x16:
			return 4
		ChunkSize.LARGE_32x32:
			return 8
	return 2

func get_cells_for_chunk(center_grid_pos: Vector2i, chunk_size: ChunkSize) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var size_cells = get_chunk_size_cells(chunk_size)
	
	# Calculate the offset from center to top-left corner
	# For even sizes, we need to offset properly to align with grid
	var half_size = size_cells / 2
	var start_x = center_grid_pos.x - half_size + (1 if size_cells % 2 == 0 else 0)
	var start_y = center_grid_pos.y - half_size + (1 if size_cells % 2 == 0 else 0)
	
	# Add all cells that this chunk would occupy
	for x in range(size_cells):
		for y in range(size_cells):
			cells.append(Vector2i(start_x + x, start_y + y))
	
	return cells

func is_area_available(center_grid_pos: Vector2i, chunk_size: ChunkSize) -> bool:
	var required_cells = get_cells_for_chunk(center_grid_pos, chunk_size)
	
	# Check if all required cells are within bounds and unoccupied
	for cell in required_cells:
		if not is_within_bounds(cell) or is_cell_occupied(cell):
			return false
	
	return true

func occupy_area(center_grid_pos: Vector2i, chunk_size: ChunkSize, chunk: TerrainChunk) -> bool:
	var required_cells = get_cells_for_chunk(center_grid_pos, chunk_size)
	
	# First check if the entire area is available
	if not is_area_available(center_grid_pos, chunk_size):
		return false
	
	# Occupy all cells
	for cell in required_cells:
		grid_data[cell] = chunk
		occupied_cells.append(cell)
		cell_occupied.emit(cell, chunk)
	
	# Store metadata about which cells belong to this chunk
	if not chunk_metadata.has(chunk):
		chunk_metadata[chunk] = {
			"center_pos": center_grid_pos,
			"chunk_size": chunk_size,
			"occupied_cells": required_cells
		}
	
	return true

func free_area(chunk: TerrainChunk) -> bool:
	if not chunk_metadata.has(chunk):
		return false
	
	var metadata = chunk_metadata[chunk]
	var cells_to_free = metadata["occupied_cells"]
	
	# Free all cells occupied by this chunk
	for cell in cells_to_free:
		grid_data.erase(cell)
		occupied_cells.erase(cell)
		cell_freed.emit(cell)
	
	# Remove metadata
	chunk_metadata.erase(chunk)
	
	# Queue the chunk for deletion
	if is_instance_valid(chunk):
		chunk.queue_free()
	
	return true

func get_neighbor_heights(chunk_pos: Vector2i, edge_direction: Vector2i) -> PackedFloat32Array:
	var neighbor_pos = chunk_pos + edge_direction
	var neighbor_chunk = get_chunk_at(neighbor_pos)
	
	if not neighbor_chunk:
		return PackedFloat32Array()
	
	# Get heights from the opposite edge of the neighbor
	var reverse_direction = -edge_direction
	return neighbor_chunk.get_edge_heights(reverse_direction)

func store_chunk_data(grid_pos: Vector2i, height_data: PackedFloat32Array, parameters: TerrainParameters):
	chunk_height_data[grid_pos] = height_data.duplicate()
	chunk_parameters[grid_pos] = parameters.duplicate()
	
	chunk_metadata[grid_pos] = {
		"generation_time": Time.get_time_dict_from_system(),
		"resolution": parameters.resolution,
		"seed": parameters.seed_value,
		"size_meters": parameters.chunk_size_meters,
		"vertex_count": height_data.size()
	}
	
	print("Stored data for chunk at ", grid_pos, " - ", height_data.size(), " height samples")
	
	var chunk = get_chunk_at(grid_pos)
	if chunk:
		# Update the chunk's stored data
		chunk.height_data = height_data
		chunk.parameters = parameters
