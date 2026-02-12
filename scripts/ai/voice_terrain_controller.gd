class_name VoiceTerrainController
extends Node

# Voice-controlled terrain generation system
# Handles: VR button hold -> audio recording -> OpenAI API -> terrain generation

@export var recording_enabled: bool = true
@export var python_script_path: String = "res://python/voice_processor.py"
@export var temp_audio_folder: String = "user://audio_temp/"
@export var debug_mode: bool = true
@export var skip_python_processing: bool = true

# Microphone selection
@export var auto_select_vr_mic: bool = true
@export var vr_mic_keywords: Array[String] = ["Index", "Valve", "Headset", "VR"]

# State management
enum VoiceState {
	IDLE,
	RECORDING,
	PROCESSING,
	GENERATING,
	COMPLETED,
	ERROR
}

var current_state: VoiceState = VoiceState.IDLE
var is_button_held: bool = false
var recording_start_time: float = 0.0
var min_recording_duration: float = 1.0  # Minimum 1 second
var max_recording_duration: float = 10.0  # Maximum 10 seconds

# Audio recording components
var audio_stream_player: AudioStreamPlayer
var audio_effect_record: AudioEffectRecord
var audio_bus_index: int = -1

# Controllers and interaction
var left_controller: VRController
var right_controller: VRController
var interaction_manager: InteractionManager

# Currently selected grid position for terrain generation
var target_grid_position: Vector2i
var target_chunk_size: GridManager.ChunkSize

# Debug system
var debug_manager: VoiceDebugManager

# Signals
signal voice_recording_started()
signal voice_recording_stopped(duration: float)
signal voice_processing_started(audio_file_path: String)
signal voice_processing_completed(terrain_params: Dictionary)
signal voice_processing_failed(error_message: String)
signal terrain_generation_started(grid_pos: Vector2i)
signal terrain_generation_completed(chunk: TerrainChunk)

func _ready():
	print("VoiceTerrainController: Initializing voice-controlled terrain system")
	setup_debug_system()
	setup_audio_recording()
	setup_temp_directory()
	connect_to_controllers()
	connect_signals()

func setup_audio_recording():
	# List and optionally select microphone device
	print("======== Available Audio Input Devices ========")
	var device_list = AudioServer.get_input_device_list()
	for i in range(device_list.size()):
		print(i, ": ", device_list[i])
	print("Current default device: ", AudioServer.input_device)
	print("===============================================")

	# Auto-select VR headset microphone if enabled
	if auto_select_vr_mic:
		select_vr_microphone(device_list)

	# Create audio bus for recording
	var bus_count = AudioServer.bus_count
	audio_bus_index = AudioServer.get_bus_index("Record")
	
	
	if audio_bus_index == -1:
		# Create recording bus if it doesn't exist
		AudioServer.add_bus(bus_count)
		AudioServer.set_bus_name(bus_count, "Record")
		audio_bus_index = bus_count
		print("VoiceTerrainController: Created 'Record' audio bus at index ", audio_bus_index)
	
	# Setup audio effect record
	audio_effect_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(audio_bus_index, audio_effect_record)
	
	# Create audio stream player for capturing microphone input
	audio_stream_player = AudioStreamPlayer.new()
	audio_stream_player.bus = "Record"
	add_child(audio_stream_player)
	
	# Set up microphone capture
	var capture = AudioStreamMicrophone.new()
	audio_stream_player.stream = capture
	
	print("VoiceTerrainController: Audio recording setup complete")

func select_vr_microphone(device_list: PackedStringArray):
	# Search for VR headset microphone based on keywords
	for device_name in device_list:
		for keyword in vr_mic_keywords:
			if keyword.to_lower() in device_name.to_lower():
				AudioServer.input_device = device_name
				print("VoiceTerrainController: ✓ Selected VR microphone: ", device_name)
				return

	# If no VR mic found, warn but continue with default
	print("VoiceTerrainController: ⚠ No VR microphone found matching keywords ", vr_mic_keywords)
	print("VoiceTerrainController: Using default device: ", AudioServer.input_device)

func setup_debug_system():
	# Create debug manager for testing voice recording
	debug_manager = VoiceDebugManager.new()
	add_child(debug_manager)
	print("VoiceTerrainController: Debug system initialized")

func setup_temp_directory():
	# Create temporary audio directory
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(temp_audio_folder):
		dir.make_dir_recursive(temp_audio_folder)
		print("VoiceTerrainController: Created temp audio directory: ", temp_audio_folder)

func connect_to_controllers():
	# Find controllers through the interaction manager
	interaction_manager = InteractionManager
	if interaction_manager:
		left_controller = interaction_manager.left_controller
		right_controller = interaction_manager.right_controller
		print("VoiceTerrainController: Connected to VR controllers via InteractionManager")
	else:
		print("VoiceTerrainController: Warning - InteractionManager not found")

func connect_signals():
	# Connect to controller input for voice recording trigger
	if left_controller:
		# Use grip button for voice recording on left hand
		# Note: We'll monitor grip input in _process instead of signal connection
		# since the VRController doesn't emit input_float_changed signals
		print("VoiceTerrainController: Left controller connected for voice recording")
	
	if right_controller:
		right_controller.trigger_activated.connect(_on_trigger_activated)
		print("VoiceTerrainController: Right controller connected for trigger input")

func _process(delta):
	update_recording_state()
	update_visual_feedback()
	monitor_grip_input()

func update_recording_state():
	match current_state:
		VoiceState.RECORDING:
			var recording_duration = Time.get_time_dict_from_system()["unix"] - recording_start_time
			if recording_duration >= max_recording_duration:
				print("VoiceTerrainController: Max recording duration reached, stopping recording")
				stop_voice_recording()
		
		VoiceState.PROCESSING:
			# Could add timeout handling here
			pass

func update_visual_feedback():
	# Update visual feedback based on current state
	if right_controller and right_controller.interaction_sphere:
		var material = right_controller.interaction_sphere.get_surface_override_material(0)
		if not material:
			material = StandardMaterial3D.new()
			right_controller.interaction_sphere.set_surface_override_material(0, material)
		
		# Check if we're in voice mode via InteractionManager
		var in_voice_mode = false
		if interaction_manager:
			in_voice_mode = (interaction_manager.current_mode == InteractionManager.InteractionMode.VOICE_MODE or 
							 interaction_manager.current_mode == InteractionManager.InteractionMode.VOICE_RECORDING or
							 interaction_manager.current_mode == InteractionManager.InteractionMode.VOICE_PROCESSING)
		
		if in_voice_mode:
			# Color coding based on voice state when in voice mode
			match current_state:
				VoiceState.IDLE:
					material.albedo_color = Color.CYAN  # Cyan = ready for voice commands
				VoiceState.RECORDING:
					# Pulsing red while recording
					var pulse = sin(Time.get_time_dict_from_system()["unix"] * 8.0) * 0.5 + 0.5
					material.albedo_color = Color.RED.lerp(Color.WHITE, pulse)
				VoiceState.PROCESSING:
					material.albedo_color = Color.YELLOW
				VoiceState.GENERATING:
					material.albedo_color = Color.BLUE
				VoiceState.COMPLETED:
					material.albedo_color = Color.GREEN
				VoiceState.ERROR:
					material.albedo_color = Color.DARK_RED
		# If not in voice mode, don't override the normal controller colors

func monitor_grip_input():
	# Monitor left controller grip button for voice recording using OpenXR action map
	if not left_controller:
		return
	
	# Use left controller's OpenXR action system (same as VRController uses)
	var grip_value = left_controller.get_float("terrain_grip") if left_controller.has_method("get_float") else 0.0
	var is_pressed = grip_value > 0.5
	
	# Debug output for testing
	if debug_mode and grip_value > 0.1:  # Show any grip activity
		print("VoiceTerrainController: Grip detected - value: ", grip_value, " pressed: ", is_pressed)
	
	if is_pressed and not is_button_held and current_state == VoiceState.IDLE:
		print("VoiceTerrainController: Starting voice recording from grip input")
#		start_voice_recording()
	elif not is_pressed and is_button_held:
		print("VoiceTerrainController: Stopping voice recording from grip release")
		stop_voice_recording()

func _on_trigger_activated(world_pos: Vector3, grid_pos: Vector2i):
	# Store the target position for terrain generation
	target_grid_position = grid_pos
	if interaction_manager:
		target_chunk_size = interaction_manager.selected_chunk_size
	else:
		target_chunk_size = GridManager.ChunkSize.SMALL_8x8
	
	print("VoiceTerrainController: Target position set to ", grid_pos, " with size ", target_chunk_size)

# Voice recording functions
func start_voice_recording():
	if current_state != VoiceState.IDLE or not recording_enabled:
		return
	
	print("VoiceTerrainController: Starting voice recording...")
	current_state = VoiceState.RECORDING
	is_button_held = true
#	recording_start_time = Time.get_time_dict_from_system()["unix"]
	
	# Start recording
	audio_effect_record.set_recording_active(true)
	audio_stream_player.play()
	
	# Provide haptic feedback
	if left_controller:
		left_controller.trigger_haptic_pulse_api("Start Voice", 0.3, 0.1)
	
	voice_recording_started.emit()
	
	# Debug callback
	if debug_manager:
		debug_manager.on_recording_started(self)

func stop_voice_recording():
	if current_state != VoiceState.RECORDING:
		return
	
	is_button_held = false
	var recording_duration = Time.get_time_dict_from_system()["unix"] - recording_start_time
	
	print("VoiceTerrainController: Stopping voice recording (duration: ", recording_duration, "s)")
	
	# Stop recording
	audio_stream_player.stop()
	audio_effect_record.set_recording_active(false)
	
	# Check minimum duration
	if recording_duration < min_recording_duration:
		print("VoiceTerrainController: Recording too short (", recording_duration, "s), minimum is ", min_recording_duration, "s")
		current_state = VoiceState.IDLE
		return
	
	# Save the recording and process it
	save_and_process_recording(recording_duration)
	
	# Provide haptic feedback
	if left_controller:
		left_controller.trigger_haptic_pulse_api("Stop Voice", 0.6, 0.2)
	
	voice_recording_stopped.emit(recording_duration)

func save_and_process_recording(duration: float):
	current_state = VoiceState.PROCESSING
	
	# Get the recorded audio data
	var recording = audio_effect_record.get_recording()
	if not recording:
		handle_processing_error("Failed to get recording data")
		return
	
	# Generate unique filename
	var timestamp = Time.get_time_string_from_system().replace(":", "-")
	var filename = "voice_command_" + timestamp + ".wav"
	var full_path = temp_audio_folder + filename
	
	# Save the audio file
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if not file:
		handle_processing_error("Failed to create audio file: " + full_path)
		return
	
	# Save as WAV format
	recording.save_to_wav(full_path)
	file.close()
	
	print("VoiceTerrainController: Saved recording to ", full_path)
	voice_processing_started.emit(full_path)
	
	# Debug callback for recording completion
	if debug_manager:
		debug_manager.on_recording_stopped(self, duration, full_path)
	
	# Process the audio file through Python script (or use fallback for debugging)
	if skip_python_processing:
		process_audio_fallback(full_path)
	else:
		process_audio_with_python(full_path)

func process_audio_with_python(audio_file_path: String):
	# Create the Python command
	var python_command = [
		"python",
		ProjectSettings.globalize_path(python_script_path),
		ProjectSettings.globalize_path(audio_file_path)
	]
	
	print("VoiceTerrainController: Executing Python script: ", python_command)
	
	# Execute Python script asynchronously
	var output = []
	OS.execute("python", [ProjectSettings.globalize_path(python_script_path), ProjectSettings.globalize_path(audio_file_path)], output)
	
	# Parse the output
	if output.size() > 0:
		var result_json = output[0]
		print("VoiceTerrainController: Python output: ", result_json)
		parse_python_output(result_json)
	else:
		handle_processing_error("No output from Python script")

func process_audio_fallback(audio_file_path: String):
	# Debug/testing mode - simulate processing without Python
	print("VoiceTerrainController: Using fallback processing (no Python) for: ", audio_file_path)
	
	# Simulate processing delay
	await get_tree().create_timer(1.0).timeout
	
	# Create mock result based on filename or random selection
	var filename = audio_file_path.get_file().to_lower()
	var mock_result = create_mock_voice_result(filename)
	
	# Process as if it came from Python
	var terrain_params = extract_terrain_parameters(mock_result)
	
	print("VoiceTerrainController: Fallback processing complete: ", terrain_params)
	voice_processing_completed.emit(terrain_params)
	
	# Debug callback
	if debug_manager:
		debug_manager.on_processing_completed(self, terrain_params)
	
	# Generate terrain
	generate_terrain_from_voice(terrain_params)

func create_mock_voice_result(filename: String) -> Dictionary:
	# Create realistic mock results for testing
	var mock_scenarios = [
		{
			"text": "I want rolling hills",
			"keywords": ["hills", "rolling"],
			"parameters": {
				"terrain_type": TerrainParameters.TerrainType.HILLS,
				"amplitude": 8.0,
				"frequency": 0.1,
				"octaves": 3
			}
		},
		{
			"text": "Create rocky mountains",
			"keywords": ["mountains", "rocky"],
			"parameters": {
				"terrain_type": TerrainParameters.TerrainType.MOUNTAINS,
				"amplitude": 15.0,
				"frequency": 0.05,
				"octaves": 5,
				"lacunarity": 2.5
			}
		},
		{
			"text": "Make a flat valley with a river",
			"keywords": ["valley", "flat", "river"],
			"parameters": {
				"terrain_type": TerrainParameters.TerrainType.VALLEYS,
				"amplitude": 6.0,
				"erosion": 0.4,
				"octaves": 2
			}
		},
		{
			"text": "Generate smooth gentle terrain",
			"keywords": ["smooth", "gentle"],
			"parameters": {
				"terrain_type": TerrainParameters.TerrainType.HILLS,
				"amplitude": 5.0,
				"frequency": 0.08,
				"octaves": 2,
				"persistence": 0.3
			}
		}
	]
	
	# Try to match filename to scenario
	for scenario in mock_scenarios:
		for keyword in scenario.keywords:
			if keyword in filename:
				print("VoiceTerrainController: Matched filename keyword '", keyword, "' - using scenario: ", scenario.text)
				return scenario
	
	# Random selection if no match
	var selected = mock_scenarios[randi() % mock_scenarios.size()]
	print("VoiceTerrainController: No keyword match - using random scenario: ", selected.text)
	return selected

func parse_python_output(json_string: String):
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		handle_processing_error("Failed to parse Python output as JSON: " + json_string)
		return
	
	var result_data = json.data
	
	if result_data.has("error"):
		handle_processing_error("Python script error: " + str(result_data["error"]))
		return
	
	# Extract terrain parameters from the result
	var terrain_params = extract_terrain_parameters(result_data)
	
	print("VoiceTerrainController: Extracted terrain parameters: ", terrain_params)
	voice_processing_completed.emit(terrain_params)
	
	# Debug callback for processing completion
	if debug_manager:
		debug_manager.on_processing_completed(self, terrain_params)
	
	# Generate terrain with the new parameters
	generate_terrain_from_voice(terrain_params)

func extract_terrain_parameters(voice_data: Dictionary) -> Dictionary:
	# Extract terrain parameters from voice processing results
	var params = {
		"seed": randi() % 10000,
		"frequency": 0.1,
		"amplitude": 5.0,
		"octaves": 3,
		"lacunarity": 2.0,
		"persistence": 0.5,
		"terrain_type": TerrainParameters.TerrainType.HILLS,
		"erosion": 0.0,
		"plateau": 0.0
	}
	
	# Parse voice commands for terrain features
	if voice_data.has("text"):
		var voice_text = voice_data["text"].to_lower()
		params.merge(parse_voice_keywords(voice_text), true)
	
	if voice_data.has("keywords"):
		var keywords = voice_data["keywords"]
		params.merge(parse_keyword_parameters(keywords), true)
	
	if voice_data.has("parameters"):
		# Direct parameter specification from AI
		params.merge(voice_data["parameters"], true)
	
	return params

func parse_voice_keywords(text: String) -> Dictionary:
	var params = {}
	
	# Terrain type keywords
	if "mountain" in text or "mountains" in text or "peak" in text:
		params["terrain_type"] = TerrainParameters.TerrainType.MOUNTAINS
		params["amplitude"] = 15.0
		params["frequency"] = 0.05
	elif "hill" in text or "hills" in text or "hilly" in text:
		params["terrain_type"] = TerrainParameters.TerrainType.HILLS
		params["amplitude"] = 8.0
		params["frequency"] = 0.1
	elif "valley" in text or "valleys" in text or "depression" in text:
		params["terrain_type"] = TerrainParameters.TerrainType.VALLEYS
		params["amplitude"] = 6.0
	elif "flat" in text or "plain" in text or "plains" in text:
		params["terrain_type"] = TerrainParameters.TerrainType.FLAT
		params["amplitude"] = 1.0
	elif "plateau" in text or "mesa" in text:
		params["terrain_type"] = TerrainParameters.TerrainType.PLATEAU
		params["plateau"] = 5.0
	
	# Size/scale keywords
	if "large" in text or "big" in text or "huge" in text:
		params["frequency"] = 0.03
		params["amplitude"] = params.get("amplitude", 5.0) * 1.5
	elif "small" in text or "tiny" in text or "little" in text:
		params["frequency"] = 0.2
		params["amplitude"] = params.get("amplitude", 5.0) * 0.7
	
	# Feature keywords
	if "rough" in text or "jagged" in text or "rocky" in text:
		params["octaves"] = 5
		params["lacunarity"] = 2.5
	elif "smooth" in text or "gentle" in text or "rolling" in text:
		params["octaves"] = 2
		params["persistence"] = 0.3
	
	# Water features
	if "river" in text or "stream" in text:
		params["erosion"] = 0.3
		params["terrain_type"] = TerrainParameters.TerrainType.VALLEYS
	
	# Detail level
	if "detailed" in text or "complex" in text:
		params["octaves"] = 6
	elif "simple" in text or "basic" in text:
		params["octaves"] = 2
	
	print("VoiceTerrainController: Parsed keywords from '", text, "': ", params)
	return params

func parse_keyword_parameters(keywords: Array) -> Dictionary:
	# Parse structured keywords from AI processing
	var params = {}
	
	for keyword in keywords:
		match keyword.to_lower():
			"mountains", "mountain":
				params["terrain_type"] = TerrainParameters.TerrainType.MOUNTAINS
				params["amplitude"] = 15.0
			"hills", "hilly":
				params["terrain_type"] = TerrainParameters.TerrainType.HILLS
				params["amplitude"] = 8.0
			"valleys", "valley":
				params["terrain_type"] = TerrainParameters.TerrainType.VALLEYS
			"flat", "plains":
				params["terrain_type"] = TerrainParameters.TerrainType.FLAT
				params["amplitude"] = 1.0
			"river", "stream":
				params["erosion"] = 0.4
			"rough", "jagged":
				params["octaves"] = 5
			"smooth", "gentle":
				params["persistence"] = 0.3
	
	return params

func generate_terrain_from_voice(voice_params: Dictionary):
	# Validate that we have a target position
	if not GridManager.is_within_bounds(target_grid_position):
		handle_processing_error("Invalid target grid position: " + str(target_grid_position))
		return
	
	if GridManager.is_cell_occupied(target_grid_position):
		handle_processing_error("Target position already occupied: " + str(target_grid_position))
		return
	
	current_state = VoiceState.GENERATING
	terrain_generation_started.emit(target_grid_position)
	
	# Create terrain parameters from voice data
	var terrain_params = TerrainParameters.new()
	terrain_params.chunk_size_meters = GridManager.get_chunk_size_meters(target_chunk_size)
	terrain_params.resolution = 64  # Good balance for VR
	
	# Apply voice-derived parameters
	terrain_params.seed_value = voice_params.get("seed", randi() % 10000)
	terrain_params.frequency = voice_params.get("frequency", 0.1)
	terrain_params.amplitude = voice_params.get("amplitude", 5.0)
	terrain_params.octaves = voice_params.get("octaves", 3)
	terrain_params.lacunarity = voice_params.get("lacunarity", 2.0)
	terrain_params.persistance = voice_params.get("persistence", 0.5)
	terrain_params.terrain_type = voice_params.get("terrain_type", TerrainParameters.TerrainType.HILLS)
	terrain_params.erosion_strength = voice_params.get("erosion", 0.0)
	terrain_params.plateau_level = voice_params.get("plateau", 0.0)
	
	# Validate parameters
	terrain_params.validate_parameters()
	
	print("VoiceTerrainController: Generating terrain at ", target_grid_position, " with voice-derived parameters")
	
	# Create and place the terrain chunk
	create_voice_terrain_chunk(terrain_params)

func create_voice_terrain_chunk(params: TerrainParameters):
	# Create terrain chunk
	var terrain_chunk = preload("res://scenes/terrain/terrain_chunk.tscn").instantiate()
	
	# Position chunk in world
	var world_position = GridManager.grid_to_world_chunk(target_grid_position, target_chunk_size)
	terrain_chunk.global_position = world_position
	
	# Add to scene
	get_tree().current_scene.add_child(terrain_chunk)
	
	# Connect completion signal
	terrain_chunk.generation_complete.connect(_on_terrain_generation_complete)
	terrain_chunk.generation_failed.connect(_on_terrain_generation_failed)
	
	# Register with grid manager
	GridManager.occupy_area(target_grid_position, target_chunk_size, terrain_chunk)
	
	# Generate terrain
	terrain_chunk.generate_terrain(params, target_grid_position)

func _on_terrain_generation_complete(chunk: TerrainChunk):
	print("VoiceTerrainController: Voice-generated terrain complete at ", chunk.grid_position)
	current_state = VoiceState.COMPLETED
	terrain_generation_completed.emit(chunk)
	
	# Reset to idle after a short delay
	await get_tree().create_timer(2.0).timeout
	current_state = VoiceState.IDLE

func _on_terrain_generation_failed(chunk: TerrainChunk, error: String):
	handle_processing_error("Terrain generation failed: " + error)

func handle_processing_error(error_message: String):
	print("VoiceTerrainController ERROR: ", error_message)
	current_state = VoiceState.ERROR
	voice_processing_failed.emit(error_message)
	
	# Debug callback for processing failure
	if debug_manager:
		debug_manager.on_processing_failed(self, error_message)
	
	# Reset to idle after displaying error
	await get_tree().create_timer(3.0).timeout
	current_state = VoiceState.IDLE

# Utility functions
func get_current_state_name() -> String:
	match current_state:
		VoiceState.IDLE: return "IDLE"
		VoiceState.RECORDING: return "RECORDING"
		VoiceState.PROCESSING: return "PROCESSING" 
		VoiceState.GENERATING: return "GENERATING"
		VoiceState.COMPLETED: return "COMPLETED"
		VoiceState.ERROR: return "ERROR"
		_: return "UNKNOWN"

func is_recording() -> bool:
	return current_state == VoiceState.RECORDING

func is_voice_processing() -> bool:
	return current_state == VoiceState.PROCESSING or current_state == VoiceState.GENERATING

func can_start_recording() -> bool:
	return current_state == VoiceState.IDLE and recording_enabled
