class_name TerrainParameters
extends Resource

@export var seed_value: int = 0
@export var frequency: float = 0.1
@export var amplitude: float = 5.0
@export var octaves: int = 3
@export var lacunarity: float = 2.0 # Frequency mult per octave
@export var persistance: float = 0.5 # Amplitude mult per active

@export var terrain_type: TerrainType = TerrainType.HILLS
@export var erosion_strength: float = 0.0
@export var plateau_level: float = 0.0

@export var resolution: int = 64 # vertices per side (2D) or grid cells per axis (3D)
@export var chunk_size_meters: float = 8.0
@export var generation_mode: GenerationMode = GenerationMode.HEIGHTMAP_2D

# Dual contouring specific parameters
@export var grid_size_3d: int = 16         # voxel grid cells per axis (density grid)
@export var ground_level: float = 0.3      # vertical position of ground (0-1 fraction of grid)
@export var terrain_strength: float = 0.8  # noise influence on surface shape
@export var cave_enabled: bool = false
@export var cave_threshold: float = 0.3    # lower = fewer/narrower caves
@export var cave_scale: float = 0.08       # lower = longer/smoother tunnels
@export var min_depth: float = 0.4         # solid crust thickness before caves begin

enum TerrainType {
	FLAT,
	HILLS,
	MOUNTAINS,
	VALLEYS,
	PLATEAU,
	CUSTOM
}

enum GenerationMode {
	HEIGHTMAP_2D,        # Classic 2D noise heightmap (current approach)
	DUAL_CONTOURING_3D   # 3D density field with dual contouring (supports caves/overhangs)
}

func validate_parameters() -> bool:
	if resolution > 128:
		push_warning("Resolution too high for VR: " + str(resolution))
		resolution = 128
	
	if frequency < 0.01 or frequency > 1.0:
		push_warning("Frequency out of range: " + str(frequency))
		frequency = clamp(frequency, 0.01, 1.0)
	
	return true
	
func to_dictionary() -> Dictionary:
	var data = {
		"seed": seed_value,
		"frequency": frequency,
		"amplitude": amplitude,
		"octaves": octaves,
		"lacunarity": lacunarity,
		"persistance": persistance,
		"terrain_type": terrain_type,
		"erosion": erosion_strength,
		"plateau": plateau_level,
		"resolution": resolution,
		"size_meters": chunk_size_meters,
		"generation_mode": generation_mode,
	}
	# Include dual contouring params when relevant
	if generation_mode == GenerationMode.DUAL_CONTOURING_3D:
		data["grid_size_3d"] = grid_size_3d
		data["ground_level"] = ground_level
		data["terrain_strength"] = terrain_strength
		data["cave_enabled"] = cave_enabled
		data["cave_threshold"] = cave_threshold
		data["cave_scale"] = cave_scale
		data["min_depth"] = min_depth
	return data
	
static func from_dictionary(data: Dictionary) -> TerrainParameters:
	var params = TerrainParameters.new()
	params.seed_value = data.get("seed", 0)
	params.frequency = data.get("frequency", 0.1)
	params.amplitude = data.get("amplitude", 5.0)
	params.octaves = data.get("octaves", 3)
	params.lacunarity = data.get("lacunarity", 2.0)
	params.persistance = data.get("persistance", 0.5)
	params.terrain_type = data.get("terrain_type", TerrainType.HILLS)
	params.erosion_strength = data.get("erosion", 0.0)
	params.plateau_level = data.get("plateau", 0.0)
	params.resolution = data.get("resolution", 64)
	params.chunk_size_meters = data.get("size_meters", 8.0)
	params.generation_mode = data.get("generation_mode", GenerationMode.HEIGHTMAP_2D)
	# Dual contouring params
	params.grid_size_3d = data.get("grid_size_3d", 16)
	params.ground_level = data.get("ground_level", 0.3)
	params.terrain_strength = data.get("terrain_strength", 0.8)
	params.cave_enabled = data.get("cave_enabled", false)
	params.cave_threshold = data.get("cave_threshold", 0.3)
	params.cave_scale = data.get("cave_scale", 0.08)
	params.min_depth = data.get("min_depth", 0.4)
	params.validate_parameters()
	return params
	
	
	
