# camera_rig.gd
extends Node3D

@export var target: Node3D  # Asigna tu personaje en el inspector
@export var offset: Vector3 = Vector3(10, 10, 10)  # Ajusta según tu isometría
@export var follow_speed: float = 5.0

func _process(_delta: float) -> void:
	if !target:
		return
	
	# Seguir al personaje manteniendo la posición relativa
	global_position = target.global_position + offset
	# Mantener rotación fija (ajusta estos valores según tu ángulo isométrico)
	rotation_degrees = Vector3(-30, 45, 0)
