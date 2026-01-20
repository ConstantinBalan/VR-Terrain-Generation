class_name VRController
extends XRController3D

@export var is_right_hand: bool = true
@export var interaction_range: float = 10.0
@export var haptic_feedback_enabled: bool = true

@onready var raycast: RayCast3D = $Raycast3D if has_node("RayCast3D") else null
@onready var hand_model = $HandModel if has_node("HandModel") else null
@onready var interaction_sphere = $InteractionSpherre if has_node("InteractionSphere") else null

var trigger_pressed: bool = false
var grip_pressed: bool = false
var primary_button_pressed: bool = false

var current_target_position: Vector3
var current_grid_position: Vector2i
var is_hovering_valid_cell: bool = false

signal trigger_activted(world_pos: Vector3, grid_pos: Vector2i)
signal grip_activated(world_pos: Vector3)
signal primary_button_activated()

func _ready():
	setup_raycast()
	setup_hand_model()
	setup_interaction_feedback()
	
func setup_raycast():
	if raycast:
		raycast.target_position = Vector3(0,0, -interaction_range)
		raycast.collision_mask = 1
		raycast.enabled = true

func setup_hand_model():
	if not hand_model:
		hand_model = MeshInstance3D.new()
		var capsule = CapsuleMesh.new()
		capsule.radius = 0.05
		capsule.height = 0.15
		hand_model.mesh = capsule
		add_child(hand_model)
		hand_model.name = "HandModel"
		
	
func setup_interaction_feedback():
	if not interaction_sphere:
		interaction_sphere = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.02
		interaction_sphere.mesh = sphere
		add_child(interaction_sphere)
		interaction_sphere.name = "InteractionSphere"
		interaction_sphere.visible = false

func _process(delta: float) -> void:
	update_input_state()
	update_raycast_target()
	update_visual_feedback()
	
func update_input_state():
	pass
	
func update_raycast_target():
	pass
	
func update_visual_feedback():
	pass
		
