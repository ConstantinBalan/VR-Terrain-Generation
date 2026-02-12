class_name DebugDisplay
extends Node3D

# Wrist-mounted debug display for VR
# Shows current state information from managers

@onready var label_3d: Label3D = $Label3D

var voice_controller: VoiceTerrainController
var right_controller: VRController

func _ready():
	print("DebugDisplay: Initializing wrist-mounted debug display")

	# Position at wrist location (slightly forward and up)
	position = Vector3(0, 0.05, -0.1)

	# Get reference to VoiceTerrainController through InteractionManager
	if InteractionManager and InteractionManager.voice_controller:
		voice_controller = InteractionManager.voice_controller
		print("DebugDisplay: Connected to VoiceTerrainController")
	else:
		print("DebugDisplay: Warning - VoiceTerrainController not found")

	# Get reference to right controller for grid position info
	if InteractionManager and InteractionManager.right_controller:
		right_controller = InteractionManager.right_controller
		print("DebugDisplay: Connected to right controller")

	# Configure Label3D if it exists
	if label_3d:
		configure_label()
	else:
		print("DebugDisplay: Warning - Label3D child not found")

func configure_label():
	label_3d.font_size = 32
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.outline_size = 2
	label_3d.outline_modulate = Color.BLACK
	label_3d.modulate = Color.WHITE

	# Use pixel size for better VR visibility
	label_3d.pixel_size = 0.001

	print("DebugDisplay: Label3D configured for VR")

func _process(_delta):
	if label_3d:
		update_display_text()

func update_display_text():
	# Build comprehensive state display
	var text = "[DEBUG DISPLAY]\n"

	# Interaction mode
	if InteractionManager:
		text += get_mode_text()
		text += "\n"
		text += get_chunk_size_text()
		text += "\n"

	# Grid position from right controller
	if right_controller:
		text += get_grid_position_text()
		text += "\n"
		text += get_validity_text()
		text += "\n\n"
	else:
		text += "Grid: N/A\nValid: N/A\n\n"

	# Voice state
	if voice_controller:
		text += get_voice_state_text()
	else:
		text += "Voice: N/A"

	label_3d.text = text

	# Update color based on state
	update_label_color()

func get_mode_text() -> String:
	var mode_name = get_interaction_mode_name()
	return "Mode: " + mode_name

func get_chunk_size_text() -> String:
	var size_enum = InteractionManager.selected_chunk_size
	var size_name = get_chunk_size_name(size_enum)
	var size_meters = GridManager.get_chunk_size_meters(size_enum)
	return "Size: " + size_name + " (" + str(size_meters) + "m)"

func get_grid_position_text() -> String:
	if right_controller.is_hovering_valid_cell or right_controller.raycast.is_colliding():
		var grid_pos = right_controller.current_grid_position
		return "Grid: (" + str(grid_pos.x) + ", " + str(grid_pos.y) + ")"
	else:
		return "Grid: N/A"

func get_validity_text() -> String:
	if right_controller.is_hovering_valid_cell:
		return "Valid: YES"
	else:
		return "Valid: NO"

func get_voice_state_text() -> String:
	var state_name = voice_controller.get_current_state_name()
	var text = "Voice: " + state_name

	# Add recording duration if recording
	if voice_controller.is_recording():
		var duration = Time.get_time_dict_from_system()["unix"] - voice_controller.recording_start_time
		text += " (" + str(snappedf(duration, 0.1)) + "s)"

	return text

func get_interaction_mode_name() -> String:
	match InteractionManager.current_mode:
		InteractionManager.InteractionMode.SIZE_SELECTION:
			return "SIZE_SELECT"
		InteractionManager.InteractionMode.PLACEMENT:
			return "PLACEMENT"
		InteractionManager.InteractionMode.VOICE_MODE:
			return "VOICE_MODE"
		InteractionManager.InteractionMode.VOICE_RECORDING:
			return "RECORDING"
		InteractionManager.InteractionMode.VOICE_PROCESSING:
			return "PROCESSING"
		InteractionManager.InteractionMode.LOCKED:
			return "LOCKED"
		InteractionManager.InteractionMode.EDITING:
			return "EDITING"
		_:
			return "UNKNOWN"

func get_chunk_size_name(size: GridManager.ChunkSize) -> String:
	match size:
		GridManager.ChunkSize.SMALL_8x8:
			return "8x8"
		GridManager.ChunkSize.MEDIUM_16x16:
			return "16x16"
		GridManager.ChunkSize.LARGE_32x32:
			return "32x32"
		_:
			return "UNKNOWN"

func update_label_color():
	# Apply color coding based on current state
	var color = Color.WHITE  # Default

	# Priority: Voice state > Validity > Mode
	if voice_controller:
		match voice_controller.current_state:
			voice_controller.VoiceState.RECORDING:
				# Pulsing red for recording
				var pulse = sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5
				color = Color.RED.lerp(Color.WHITE, pulse)
			voice_controller.VoiceState.PROCESSING:
				color = Color.YELLOW
			voice_controller.VoiceState.GENERATING:
				color = Color.CYAN
			voice_controller.VoiceState.COMPLETED:
				color = Color.GREEN
			voice_controller.VoiceState.ERROR:
				color = Color.DARK_RED
			_:
				# Voice idle - check other states
				color = get_validity_color()
	else:
		color = get_validity_color()

	label_3d.modulate = color

func get_validity_color() -> Color:
	# Color based on placement validity
	if right_controller and right_controller.is_hovering_valid_cell:
		return Color.GREEN
	elif right_controller and right_controller.raycast.is_colliding():
		return Color.RED  # Hovering but invalid position
	else:
		return Color.WHITE  # Default/not hovering
