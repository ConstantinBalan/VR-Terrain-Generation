class_name TerrainChunk
extends Node3D

@export var grid_position: Vector2i = Vector2i.ZERO
@export var is_locked: bool = false

var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

func _ready():
	name = "TerrainChunk_" + str(grid_position.x) + "_" + str(grid_position.y)
	
func set_parameters(params: Dictionary):
	pass
	
func generate_mesh():
	pass
	
func has_generated_mesh():
	pass
