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

@export var resolution: int = 64 # vertices per side
@export var chunk_size_meters: float = 8.0

enum TerrainType {
	FLAT,
	HILLS,
	MOUNTAINS,
	VALLEYS,
	PLATEAU,
	CUSTOM
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
	return {
		"seed": seed_value ,
		"frequency": frequency,
		"amplitude": amplitude,
		"octaves": octaves,
		"lacunarity": lacunarity,
		"persistance": persistance,
		"terrain_type": terrain_type,
		"erosion": erosion_strength,
		"plateau": plateau_level,
		"resolution": resolution,
		"size_meters": chunk_size_meters
	}
	
static func from_dictionary(data: Dictionary) -> TerrainParameters:
	var params = TerrainParameters.new()
	params.seed_value = data.get("seed", 0)
	params.frequency = data.get("frequency", 0.1)
	params.amplitude = data.get("amplitude", 5.0)
	params.octaves = data.get("octaves", 3)
	params.lacunarity = data.get("lacunarity", 2.0)
	params.persistance = data.get("persistenc", 0.5)
	params.terrain_type = data.get("terrain_type", TerrainType.HILLS)
	params.erosion_strength = data.get("erosion", 0.0)
	params.plateau_level = data.get("plateau", 0.0)
	params.resolution = data.get("resolution", 64)
	params.chunk_size_meters = data.get("size_meters", 8.0)
	params.validate_parameters()
	return params
	
	
	
