extends Node

# Track stitching state
var stitched_edges: Dictionary = {}  # {Vector2i: Array[Vector2i]} - chunk to neighbor list
var pending_stitches: Array[Vector2i] = []

# Connect to GridManager signals
func _ready():
	GridManager.cell_occupied.connect(_on_chunk_placed)

func _on_chunk_placed(grid_pos: Vector2i, chunk: TerrainChunk):
	print("TerrainStitcher: Chunk placed at ", grid_pos)
	if not chunk.generation_complete.is_connected(_on_chunk_generation_complete_wrapper):
		chunk.generation_complete.connect(_on_chunk_generation_complete_wrapper.bind(grid_pos))
		print("TerrainStitcher: Connected to generation_complete signal for chunk at ", grid_pos)

func _on_chunk_generation_complete_wrapper(chunk: TerrainChunk, grid_pos: Vector2i):
	print("TerrainStitcher: Chunk generation complete at ", grid_pos, " - starting stitching")
	stitch_chunk_with_neighbors(grid_pos)

func _on_chunk_generation_complete(grid_pos: Vector2i):
	print("TerrainStitcher: Chunk generation complete at ", grid_pos, " - starting stitching")
	stitch_chunk_with_neighbors(grid_pos)

func stitch_chunk_with_neighbors(grid_pos: Vector2i):
	var chunk = GridManager.get_chunk_at(grid_pos)
	if not chunk:
		return
		
	# Get all cells occupied by this chunk
	var chunk_metadata = GridManager.chunk_metadata.get(chunk)
	if not chunk_metadata:
		print("TerrainStitcher: No metadata found for chunk")
		return
		
	var chunk_cells = chunk_metadata["occupied_cells"]
	print("TerrainStitcher: Checking neighbors for chunk with ", chunk_cells.size(), " cells")
	
	# Find all adjacent chunks by checking neighbors of all our cells
	var adjacent_chunks = {}  # chunk -> array of adjacent cell pairs
	
	for cell in chunk_cells:
		var neighbors = GridManager.get_neighbor_cells(cell, false)
		for neighbor_cell in neighbors:
			if GridManager.is_cell_occupied(neighbor_cell):
				var neighbor_chunk = GridManager.get_chunk_at(neighbor_cell)
				if neighbor_chunk and neighbor_chunk != chunk:
					# Found an adjacent different chunk
					if not adjacent_chunks.has(neighbor_chunk):
						adjacent_chunks[neighbor_chunk] = []
					adjacent_chunks[neighbor_chunk].append([cell, neighbor_cell])
	
	# Perform stitching for each adjacent chunk
	for neighbor_chunk in adjacent_chunks.keys():
		var cell_pairs = adjacent_chunks[neighbor_chunk]
		print("TerrainStitcher: Found adjacent chunk with ", cell_pairs.size(), " shared edges")
		stitch_between_chunks(chunk, neighbor_chunk, cell_pairs)

func stitch_between_chunks(chunk: TerrainChunk, neighbor_chunk: TerrainChunk, cell_pairs: Array):
	print("TerrainStitcher: Stitching between chunk at ", chunk.grid_position, " and neighbor at ", neighbor_chunk.grid_position)
	
	# For multi-cell chunks, we need to stitch along all shared edges
	for pair in cell_pairs:
		var chunk_cell = pair[0]
		var neighbor_cell = pair[1]
		var edge_direction = neighbor_cell - chunk_cell
		
		print("TerrainStitcher: Stitching edge between cells ", chunk_cell, " -> ", neighbor_cell, " (direction: ", edge_direction, ")")
		
		# Get edge heights for this specific cell pair
		var chunk_edge_heights = get_cell_edge_heights(chunk, chunk_cell, edge_direction)
		var neighbor_edge_heights = get_cell_edge_heights(neighbor_chunk, neighbor_cell, -edge_direction)
		
		if chunk_edge_heights.is_empty() or neighbor_edge_heights.is_empty():
			print("TerrainStitcher: Skipping edge - no height data")
			continue
			
		# Apply stitching by averaging edge heights
		apply_cell_edge_averaging(chunk, neighbor_chunk, chunk_cell, neighbor_cell, edge_direction, chunk_edge_heights, neighbor_edge_heights)
	
	print("TerrainStitcher: Completed stitching between chunks")

func get_cell_edge_heights(chunk: TerrainChunk, cell_pos: Vector2i, edge_direction: Vector2i) -> PackedFloat32Array:
	# For multi-cell chunks, we need to calculate which part of the chunk's height data
	# corresponds to this specific cell's edge
	var chunk_metadata = GridManager.chunk_metadata.get(chunk)
	if not chunk_metadata:
		return PackedFloat32Array()
		
	var chunk_cells = chunk_metadata["occupied_cells"]
	var center_pos = chunk_metadata["center_pos"]
	
	# Calculate the relative position of this cell within the chunk
	var cell_offset = cell_pos - center_pos
	
	# For now, use the original edge heights method
	# TODO: This needs to be enhanced to properly handle multi-cell chunks
	return chunk.get_edge_heights(edge_direction)

func apply_cell_edge_averaging(chunk: TerrainChunk, neighbor_chunk: TerrainChunk, 
								chunk_cell: Vector2i, neighbor_cell: Vector2i, edge_direction: Vector2i,
								chunk_heights: PackedFloat32Array, neighbor_heights: PackedFloat32Array):
	
	if chunk_heights.size() != neighbor_heights.size():
		push_warning("Edge height arrays size mismatch: ", chunk_heights.size(), " vs ", neighbor_heights.size())
		return
	
	# Create averaged heights
	var averaged_heights = PackedFloat32Array()
	for i in range(chunk_heights.size()):
		var avg_height = (chunk_heights[i] + neighbor_heights[i]) * 0.5
		averaged_heights.append(avg_height)
	
	# Apply averaged heights to both chunks
	print("TerrainStitcher: Applying averaged heights to both chunks")
	modify_chunk_edge_heights(chunk, edge_direction, averaged_heights)
	modify_chunk_edge_heights(neighbor_chunk, -edge_direction, averaged_heights)
	
	print("Stitched edge between ", chunk.grid_position, " and ", neighbor_chunk.grid_position)

func create_edge_stitching(chunk_pos: Vector2i, neighbor_pos: Vector2i):
	# 🤔 Should stitching modify the original meshes or create new connecting geometry?
	var chunk = GridManager.get_chunk_at(chunk_pos)
	var neighbor = GridManager.get_chunk_at(neighbor_pos)
	
	print("TerrainStitcher: Creating edge stitching between ", chunk_pos, " and ", neighbor_pos)
	
	if not chunk or not neighbor:
		print("TerrainStitcher: Failed - chunk or neighbor not found")
		return
	
	# Skip if trying to stitch chunk with itself (multi-cell chunks)
	if chunk == neighbor:
		print("TerrainStitcher: Skipping - same chunk object (multi-cell chunk)")
		return
	
	# Calculate edge direction
	var edge_direction = neighbor_pos - chunk_pos
	print("TerrainStitcher: Edge direction: ", edge_direction)
	
	# Get edge heights from both chunks
	var chunk_edge_heights = chunk.get_edge_heights(edge_direction)
	var neighbor_edge_heights = GridManager.get_neighbor_heights(chunk_pos, edge_direction)
	
	print("TerrainStitcher: Chunk edge heights count: ", chunk_edge_heights.size())
	print("TerrainStitcher: Neighbor edge heights count: ", neighbor_edge_heights.size())
	
	if chunk_edge_heights.is_empty() or neighbor_edge_heights.is_empty():
		push_warning("Cannot stitch chunks - missing edge data")
		return
	
	# Apply stitching by averaging edge heights
	apply_edge_averaging(chunk, neighbor, edge_direction, chunk_edge_heights, neighbor_edge_heights)
	
	# Track stitching relationship
	if not stitched_edges.has(chunk_pos):
		stitched_edges[chunk_pos] = []
	stitched_edges[chunk_pos].append(neighbor_pos)

func apply_edge_averaging(chunk: TerrainChunk, neighbor: TerrainChunk, edge_direction: Vector2i, 
						 chunk_heights: PackedFloat32Array, neighbor_heights: PackedFloat32Array):
	
	if chunk_heights.size() != neighbor_heights.size():
		push_warning("Edge height arrays size mismatch: ", chunk_heights.size(), " vs ", neighbor_heights.size())
		return
	
	# Create averaged heights
	var averaged_heights = PackedFloat32Array()
	for i in range(chunk_heights.size()):
		var avg_height = (chunk_heights[i] + neighbor_heights[i]) * 0.5
		averaged_heights.append(avg_height)
	
	# Apply averaged heights to chunk edge
	print("TerrainStitcher: Applying heights to chunk at ", chunk.grid_position)
	modify_chunk_edge_heights(chunk, edge_direction, averaged_heights)
	
	# Apply to neighbor edge (reverse direction)
	var reverse_direction = -edge_direction
	print("TerrainStitcher: Applying heights to neighbor at ", neighbor.grid_position, " (reverse direction: ", reverse_direction, ")")
	modify_chunk_edge_heights(neighbor, reverse_direction, averaged_heights)
	
	print("Stitched edge between ", chunk.grid_position, " and ", neighbor.grid_position)

func modify_chunk_edge_heights(chunk: TerrainChunk, edge_direction: Vector2i, new_heights: PackedFloat32Array):
	var params = chunk.parameters
	var resolution = params.resolution
	
	# Modify height data
	for i in range(new_heights.size()):
		var height_index = get_edge_height_index(edge_direction, i, resolution)
		if height_index >= 0 and height_index < chunk.height_data.size():
			chunk.height_data[height_index] = new_heights[i]
	
	# Regenerate mesh with updated heights
	print("TerrainStitcher: Regenerating mesh for chunk at ", chunk.grid_position)
	chunk.create_mesh_from_heights()
	chunk.setup_collisions()
	
	# Update stored data in GridManager
	GridManager.store_chunk_data(chunk.grid_position, chunk.height_data, chunk.parameters)
	print("TerrainStitcher: Finished updating chunk at ", chunk.grid_position)

func get_edge_height_index(edge_direction: Vector2i, edge_index: int, resolution: int) -> int:
	# Convert edge position to height data array index
	if edge_direction.x == 1:  # Right edge
		return edge_index * resolution + (resolution - 1)
	elif edge_direction.x == -1:  # Left edge  
		return edge_index * resolution + 0
	elif edge_direction.y == 1:  # Bottom edge
		return (resolution - 1) * resolution + edge_index
	elif edge_direction.y == -1:  # Top edge
		return 0 * resolution + edge_index
	
	return -1  # Invalid direction

## Stitching validation and debugging
func validate_stitching(chunk_pos: Vector2i) -> Dictionary:
	var chunk = GridManager.get_chunk_at(chunk_pos)
	if not chunk:
		return {"valid": false, "error": "Chunk not found"}
	
	var neighbors = GridManager.get_neighbor_cells(chunk_pos, false)
	var validation_results = {
		"valid": true,
		"chunk_pos": chunk_pos,
		"neighbors_found": 0,
		"stitched_neighbors": 0,
		"height_mismatches": []
	}
	
	for neighbor_pos in neighbors:
		if GridManager.is_cell_occupied(neighbor_pos):
			validation_results.neighbors_found += 1
			
			if is_stitched(chunk_pos, neighbor_pos):
				validation_results.stitched_neighbors += 1
				
				# Check for remaining height mismatches
				var mismatch = check_edge_continuity(chunk_pos, neighbor_pos)
				if mismatch.max_difference > 0.1:  # Tolerance threshold
					validation_results.height_mismatches.append(mismatch)
	
	return validation_results

func is_stitched(chunk_pos: Vector2i, neighbor_pos: Vector2i) -> bool:
	return stitched_edges.has(chunk_pos) and neighbor_pos in stitched_edges[chunk_pos]

func check_edge_continuity(chunk_pos: Vector2i, neighbor_pos: Vector2i) -> Dictionary:
	# 🤔 How do you measure stitching quality?
	var edge_direction = neighbor_pos - chunk_pos
	var chunk = GridManager.get_chunk_at(chunk_pos)
	
	var chunk_edge_heights = chunk.get_edge_heights(edge_direction)
	var neighbor_edge_heights = GridManager.get_neighbor_heights(chunk_pos, edge_direction)
	
	var max_difference = 0.0
	var total_difference = 0.0
	
	if chunk_edge_heights.size() == neighbor_edge_heights.size():
		for i in range(chunk_edge_heights.size()):
			var diff = abs(chunk_edge_heights[i] - neighbor_edge_heights[i])
			max_difference = max(max_difference, diff)
			total_difference += diff
	
	return {
		"chunk_pos": chunk_pos,
		"neighbor_pos": neighbor_pos,
		"max_difference": max_difference,
		"average_difference": total_difference / max(chunk_edge_heights.size(), 1),
		"sample_count": chunk_edge_heights.size()
	}
