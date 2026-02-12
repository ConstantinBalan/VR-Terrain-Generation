class_name TerrainPresets
extends Resource

enum PresetType {
	ROLLING_HILLS,
	STEEP_MOUNTAINS,
	GENTLE_VALLEYS,
	FLAT_PLAINS,
	ROCKY_PLATEAU,
	DESERT_DUNES,
	CUSTOM
}

static func get_preset_parameters(preset: PresetType) -> TerrainParameters:
	var params = TerrainParameters.new()
	
	match preset:
		PresetType.ROLLING_HILLS:
			params.frequency = 0.08
			params.amplitude = 4.0
			params.octaves = 3
			params.terrain_type = TerrainParameters.TerrainType.HILLS
			params.erosion_strength = 0.1
		PresetType.STEEP_MOUNTAINS:
			params.frequency = 0.06
			params.amplitude = 12.0
			params.octaves = 4
			params.lacunarity = 2.2
			params.terrain_type = TerrainParameters.TerrainType.VALLEYS
		PresetType.GENTLE_VALLEYS:
			params.frequency = 0.1
			params.amplitude = 6.0
			params.octaves = 2
			params.terrain_type = TerrainParameters.TerrainType.FLAT
		PresetType.ROCKY_PLATEAU:
			params.frequency = 0.05
			params.amplitude = 8.0
			params.plateau_level = 4.0
			params.terrain_type = TerrainParameters.TerrainType.PLATEAU
		PresetType.DESERT_DUNES:
			params.frequency = 0.12
			params.amplitude = 3.0
			params.octaves = 2
			params.lacunarity = 1.8
			params.terrain_type = TerrainParameters.TerrainType.HILLS
			
	params.seed_value = randi() % 10000
	
	return params
	
static func get_preset_name(preset: PresetType) -> String:
	match preset:
		PresetType.ROLLING_HILLS:
			return "Rolling Hills"
		PresetType.STEEP_MOUNTAINS:
			return "Steep Mountains"
		PresetType.GENTLE_VALLEYS:
			return "Gentle Valleys"
		PresetType.FLAT_PLAINS:
			return "Flat Plains"
		PresetType.ROCKY_PLATEAU:
			return "Rocky Plateau"
		PresetType.DESERT_DUNES:
			return "Desert Dunes"
		PresetType.CUSTOM:
			return "Custom"
	return "Unknown"

static func get_all_preset() -> Array[PresetType]:
	return [
		PresetType.ROLLING_HILLS,
		PresetType.STEEP_MOUNTAINS,
		PresetType.GENTLE_VALLEYS,
		PresetType.FLAT_PLAINS,
		PresetType.ROCKY_PLATEAU,
		PresetType.DESERT_DUNES
	]
