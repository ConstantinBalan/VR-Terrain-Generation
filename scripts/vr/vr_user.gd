extends Node3D
class_name VRUser

@export var maximum_refresh_rate : int = 90
@export var enable_vr: bool = true
@export var fallback_to_desktop: bool = true

var xr_interface: OpenXRInterface
var xr_is_focused = false
var vr_active = false

# VR session signals
signal focus_lost
signal focus_gained  
signal pose_recentered

# Initialization signals for main scene
signal vr_initialized
signal vr_fallback_activated

func _ready():
	setup_xr_interface()

func setup_xr_interface():
	if enable_vr:
		xr_interface = XRServer.find_interface("OpenXR")
		if xr_interface and xr_interface.is_initialized():
			print("OpenXR initialized successfully")
			var vp: Viewport = get_viewport()
			
			vp.use_xr = true
			
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

			if RenderingServer.get_rendering_device():
				vp.vrs_mode = Viewport.VRS_XR
			elif int(ProjectSettings.get_setting("xr/openxr/foveation_level")) == 0:
				push_warning("OpenXR: Recommend setting Foveation level to High in Project Settings")

			xr_interface.session_begun.connect(_on_openxr_session_begun)
			xr_interface.session_visible.connect(_on_openxr_visible_state)
			xr_interface.session_focussed.connect(_on_openxr_focused_state)
			xr_interface.session_stopping.connect(_on_openxr_stopping)
			xr_interface.pose_recentered.connect(_on_openxr_pose_recentered)
			
			vr_active = true
			vr_initialized.emit()
			
		else:
			print("OpenXR not initialized, please check if your headset is connected")
			if fallback_to_desktop:
				handle_vr_fallback()
			else:
				get_tree().quit()
	else:
		handle_vr_fallback()

func handle_vr_fallback():
	print("VR not available - signaling fallback mode")
	vr_active = false
	vr_fallback_activated.emit()

func is_vr_active() -> bool:
	return vr_active and xr_interface != null and xr_interface.is_initialized()

func _on_openxr_session_begun() -> void:
	# Get the reported refresh rate
	var current_refresh_rate = xr_interface.get_display_refresh_rate()
	if current_refresh_rate > 0:
		print("OpenXR: Refresh rate reported as ", str(current_refresh_rate))
	else:
		print("OpenXR: No refresh rate given by XR runtime")

	# See if we have a better refresh rate available
	var new_rate = current_refresh_rate
	var available_rates : Array = xr_interface.get_available_display_refresh_rates()
	if available_rates.size() == 0:
		print("OpenXR: Target does not support refresh rate extension")
	elif available_rates.size() == 1:
		# Only one available, so use it
		new_rate = available_rates[0]
	else:
		for rate in available_rates:
			if rate > new_rate and rate <= maximum_refresh_rate:
				new_rate = rate

	# Did we find a better rate?
	if current_refresh_rate != new_rate:
		print("OpenXR: Setting refresh rate to ", str(new_rate))
		xr_interface.set_display_refresh_rate(new_rate)
		current_refresh_rate = new_rate

	# Now match our physics rate
	Engine.physics_ticks_per_second = current_refresh_rate
	
func _on_openxr_visible_state() -> void:
	# We always pass this state at startup,
	# but the second time we get this it means our player took off their headset
	if xr_is_focused:
		print("OpenXR lost focus")

		xr_is_focused = false

		# pause our game
		get_tree().paused = true

		emit_signal("focus_lost")
		
func _on_openxr_focused_state() -> void:
	print("OpenXR gained focus")
	xr_is_focused = true

	# unpause our game
	get_tree().paused = false

	emit_signal("focus_gained")
		
func _on_openxr_stopping() -> void:
	# Our session is being stopped.
	print("OpenXR is stopping")
	
func _on_openxr_pose_recentered() -> void:
	# User recentered view, we have to react to this by recentering the view.
	# This is game implementation dependent.
	emit_signal("pose_recentered")
