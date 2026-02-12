class_name VoiceDebugManager
extends Node

# Debug manager for voice recording system
# Allows testing audio capture, file saving, and basic processing without Python integration

@export var debug_enabled: bool = true
@export var save_debug_recordings: bool = true
@export var auto_play_recordings: bool = false
@export var debug_ui_enabled: bool = true

# Debug UI components
var debug_panel: Control
var debug_label: Label
var recording_indicator: ColorRect
var audio_level_bar: ProgressBar
var recording_list: ItemList
var playback_player: AudioStreamPlayer

# Audio monitoring
var audio_spectrum: AudioEffectSpectrumAnalyzer
var spectrum_instance: AudioEffectSpectrumAnalyzerInstance

# Debug state
var debug_recordings: Array[Dictionary] = []
var current_recording_info: Dictionary = {}

signal debug_recording_started(info: Dictionary)
signal debug_recording_stopped(info: Dictionary)
signal debug_recording_played(file_path: String)

func _ready():
	if debug_enabled:
		setup_debug_ui()
		setup_audio_monitoring()
		print("VoiceDebugManager: Debug system initialized")

func setup_debug_ui():
	if not debug_ui_enabled:
		return
		
	# Create debug UI panel
	debug_panel = Control.new()
	debug_panel.name = "VoiceDebugPanel"
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	debug_panel.size = Vector2(400, 300)
	debug_panel.position = Vector2(20, 20)
	
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.size = debug_panel.size
	debug_panel.add_child(bg)
	
	# Title label
	var title = Label.new()
	title.text = "Voice Recording Debug"
	title.position = Vector2(10, 10)
	title.add_theme_color_override("font_color", Color.WHITE)
	debug_panel.add_child(title)
	
	# Recording status
	debug_label = Label.new()
	debug_label.text = "Status: Idle"
	debug_label.position = Vector2(10, 40)
	debug_label.size = Vector2(380, 20)
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	debug_panel.add_child(debug_label)
	
	# Recording indicator
	recording_indicator = ColorRect.new()
	recording_indicator.color = Color.GRAY
	recording_indicator.size = Vector2(20, 20)
	recording_indicator.position = Vector2(370, 40)
	debug_panel.add_child(recording_indicator)
	
	# Audio level bar
	var level_label = Label.new()
	level_label.text = "Audio Level:"
	level_label.position = Vector2(10, 70)
	level_label.add_theme_color_override("font_color", Color.WHITE)
	debug_panel.add_child(level_label)
	
	audio_level_bar = ProgressBar.new()
	audio_level_bar.position = Vector2(100, 70)
	audio_level_bar.size = Vector2(280, 20)
	audio_level_bar.max_value = 100.0
	audio_level_bar.value = 0.0
	debug_panel.add_child(audio_level_bar)
	
	# Recording list
	var list_label = Label.new()
	list_label.text = "Debug Recordings:"
	list_label.position = Vector2(10, 100)
	list_label.add_theme_color_override("font_color", Color.WHITE)
	debug_panel.add_child(list_label)
	
	recording_list = ItemList.new()
	recording_list.position = Vector2(10, 120)
	recording_list.size = Vector2(380, 120)
	recording_list.item_selected.connect(_on_recording_selected)
	debug_panel.add_child(recording_list)
	
	# Playback controls
	var play_button = Button.new()
	play_button.text = "Play Selected"
	play_button.position = Vector2(10, 250)
	play_button.size = Vector2(100, 30)
	play_button.pressed.connect(_on_play_button_pressed)
	debug_panel.add_child(play_button)
	
	var delete_button = Button.new()
	delete_button.text = "Delete Selected"
	delete_button.position = Vector2(120, 250)
	delete_button.size = Vector2(100, 30)
	delete_button.pressed.connect(_on_delete_button_pressed)
	debug_panel.add_child(delete_button)
	
	var clear_button = Button.new()
	clear_button.text = "Clear All"
	clear_button.position = Vector2(230, 250)
	clear_button.size = Vector2(80, 30)
	clear_button.pressed.connect(_on_clear_button_pressed)
	debug_panel.add_child(clear_button)
	
	var toggle_button = Button.new()
	toggle_button.text = "Hide"
	toggle_button.position = Vector2(320, 250)
	toggle_button.size = Vector2(60, 30)
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	debug_panel.add_child(toggle_button)
	
	# Playback player
	playback_player = AudioStreamPlayer.new()
	playback_player.finished.connect(_on_playback_finished)
	debug_panel.add_child(playback_player)
	
	# Add to main scene
	get_tree().current_scene.add_child(debug_panel)
	
	print("VoiceDebugManager: Debug UI created")

func setup_audio_monitoring():
	# Add spectrum analyzer to Record bus for audio level monitoring
	var record_bus_index = AudioServer.get_bus_index("Record")
	if record_bus_index != -1:
		audio_spectrum = AudioEffectSpectrumAnalyzer.new()
		AudioServer.add_bus_effect(record_bus_index, audio_spectrum)
		spectrum_instance = AudioServer.get_bus_effect_instance(record_bus_index, AudioServer.get_bus_effect_count(record_bus_index) - 1)
		print("VoiceDebugManager: Audio monitoring setup on Record bus")
	else:
		print("VoiceDebugManager: Warning - No Record bus found for audio monitoring")

func _process(delta):
	if debug_enabled:
		update_audio_level_display()
		update_recording_indicator()

func update_audio_level_display():
	if not audio_level_bar or not spectrum_instance:
		return
	
	# Get audio magnitude from spectrum analyzer
	var magnitude = 0.0
	if spectrum_instance:
		# Sample a range of frequencies for general audio level
		for freq in range(50, 2000, 100):  # 50Hz to 2kHz range
			magnitude += spectrum_instance.get_magnitude_for_frequency_range(freq, freq + 100).length()
	
	# Convert to decibels and map to 0-100 range
	var db = linear_to_db(magnitude)
	var level = remap(db, -60.0, 0.0, 0.0, 100.0)  # -60dB to 0dB mapped to 0-100
	level = clamp(level, 0.0, 100.0)
	
	audio_level_bar.value = level

func update_recording_indicator():
	if not recording_indicator:
		return
	
	# Get recording state from VoiceTerrainController if available
	var voice_controller = get_node_or_null("../VoiceTerrainController")
	if voice_controller:
		if voice_controller.is_recording():
			# Pulsing red during recording
			var pulse = sin(Time.get_time_dict_from_system()["unix"] * 4.0) * 0.5 + 0.5
			recording_indicator.color = Color.RED.lerp(Color.WHITE, pulse)
		elif voice_controller.is_voice_processing():
			recording_indicator.color = Color.YELLOW
		else:
			recording_indicator.color = Color.GRAY

# Recording debug callbacks
func on_recording_started(voice_controller):
	if not debug_enabled:
		return
		
	current_recording_info = {
		"start_time": Time.get_time_dict_from_system(),
		"start_timestamp": Time.get_time_string_from_system(),
		"state": "recording",
		"duration": 0.0,
		"file_path": "",
		"audio_peak": 0.0
	}
	
	if debug_label:
		debug_label.text = "Status: Recording... (hold grip to continue)"
	
	debug_recording_started.emit(current_recording_info)
	print("VoiceDebugManager: Recording started at ", current_recording_info.start_timestamp)

func on_recording_stopped(voice_controller, duration: float, file_path: String):
	if not debug_enabled:
		return
	
	current_recording_info.duration = duration
	current_recording_info.file_path = file_path
	current_recording_info.state = "completed"
	
	# Add to recordings list
	debug_recordings.append(current_recording_info.duplicate())
	
	# Update UI
	if debug_label:
		debug_label.text = "Status: Processing... (duration: %.1fs)" % duration
	
	if recording_list:
		var list_text = "Recording %d (%.1fs) - %s" % [
			debug_recordings.size(),
			duration,
			current_recording_info.start_timestamp
		]
		recording_list.add_item(list_text)
	
	debug_recording_stopped.emit(current_recording_info)
	print("VoiceDebugManager: Recording stopped - Duration: %.1fs, File: %s" % [duration, file_path])
	
	# Auto-play if enabled
	if auto_play_recordings:
		play_recording(file_path)

func on_processing_completed(voice_controller, terrain_params: Dictionary):
	if not debug_enabled:
		return
	
	if debug_label:
		debug_label.text = "Status: Generation complete!"
		
	# Update the last recording with processing results
	if debug_recordings.size() > 0:
		debug_recordings[-1]["terrain_params"] = terrain_params
		debug_recordings[-1]["processing_success"] = true
	
	print("VoiceDebugManager: Processing completed with parameters: ", terrain_params)

func on_processing_failed(voice_controller, error_message: String):
	if not debug_enabled:
		return
	
	if debug_label:
		debug_label.text = "Status: ERROR - " + error_message
	
	# Update the last recording with error info
	if debug_recordings.size() > 0:
		debug_recordings[-1]["error"] = error_message
		debug_recordings[-1]["processing_success"] = false
	
	print("VoiceDebugManager: Processing failed - ", error_message)

# UI Event handlers
func _on_recording_selected(index: int):
	if index >= 0 and index < debug_recordings.size():
		var recording = debug_recordings[index]
		var info_text = "Recording %d:\nDuration: %.1fs\nFile: %s\nTime: %s" % [
			index + 1,
			recording.duration,
			recording.file_path,
			recording.start_timestamp
		]
		
		if recording.has("terrain_params"):
			info_text += "\nParameters: " + str(recording.terrain_params)
		
		if recording.has("error"):
			info_text += "\nError: " + recording.error
		
		print("VoiceDebugManager: Selected recording info:\n", info_text)

func _on_play_button_pressed():
	var selected = recording_list.get_selected_items()
	if selected.size() > 0:
		var index = selected[0]
		if index < debug_recordings.size():
			var file_path = debug_recordings[index].file_path
			play_recording(file_path)

func _on_delete_button_pressed():
	var selected = recording_list.get_selected_items()
	if selected.size() > 0:
		var index = selected[0]
		if index < debug_recordings.size():
			var file_path = debug_recordings[index].file_path
			
			# Delete file
			if FileAccess.file_exists(file_path):
				DirAccess.remove_absolute(file_path)
				print("VoiceDebugManager: Deleted recording file: ", file_path)
			
			# Remove from lists
			debug_recordings.remove_at(index)
			recording_list.remove_item(index)

func _on_clear_button_pressed():
	# Delete all recording files
	for recording in debug_recordings:
		if FileAccess.file_exists(recording.file_path):
			DirAccess.remove_absolute(recording.file_path)
	
	debug_recordings.clear()
	recording_list.clear()
	
	if debug_label:
		debug_label.text = "Status: All recordings cleared"
	
	print("VoiceDebugManager: All debug recordings cleared")

func _on_toggle_button_pressed():
	if debug_panel:
		debug_panel.visible = not debug_panel.visible
		print("VoiceDebugManager: Debug UI toggled - visible: ", debug_panel.visible)

func _on_playback_finished():
	print("VoiceDebugManager: Playback finished")

func play_recording(file_path: String):
	if not FileAccess.file_exists(file_path):
		print("VoiceDebugManager: Cannot play - file not found: ", file_path)
		return
	
	if not playback_player:
		print("VoiceDebugManager: No playback player available")
		return
	
	# Load and play the audio file
	var audio_stream = AudioStreamWAV.new()
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		# For WAV files, we need to load them properly
		# This is a basic implementation - you might need to adjust based on your WAV format
		print("VoiceDebugManager: Playing recording: ", file_path)
		# Note: Loading WAV files dynamically is complex in Godot
		# For now, just print the action
		file.close()
		debug_recording_played.emit(file_path)
	else:
		print("VoiceDebugManager: Failed to open audio file: ", file_path)

# Public debug methods
func get_recording_count() -> int:
	return debug_recordings.size()

func get_latest_recording() -> Dictionary:
	if debug_recordings.size() > 0:
		return debug_recordings[-1]
	return {}

func export_debug_log() -> String:
	var log = "Voice Recording Debug Log\n"
	log += "========================\n\n"
	
	for i in range(debug_recordings.size()):
		var recording = debug_recordings[i]
		log += "Recording %d:\n" % (i + 1)
		log += "  Time: %s\n" % recording.start_timestamp
		log += "  Duration: %.1fs\n" % recording.duration
		log += "  File: %s\n" % recording.file_path
		
		if recording.has("terrain_params"):
			log += "  Success: Yes\n"
			log += "  Parameters: %s\n" % str(recording.terrain_params)
		elif recording.has("error"):
			log += "  Success: No\n"
			log += "  Error: %s\n" % recording.error
		else:
			log += "  Success: Pending\n"
		
		log += "\n"
	
	return log

func set_debug_enabled(enabled: bool):
	debug_enabled = enabled
	if debug_panel:
		debug_panel.visible = enabled
	
	print("VoiceDebugManager: Debug mode set to ", enabled)
