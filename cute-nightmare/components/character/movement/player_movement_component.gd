extends Node3D
class_name MovementComponent


@export var max_speed: float = 5.0
@export var acceleration: float = 15.0
@export var rotation_speed: float = 8.0
@export var stopping_distance: float = 0.2
@export var camera: Camera3D


@export var controlled_body: CharacterBody3D
@export var rotation_pivot: Node3D  # Armature/Mesh para rotación


@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D


var target_position: Vector3
var is_moving: bool = false
var current_speed: float = 0.0

func _ready():
	assert(controlled_body != null, "Asignar CharacterBody3D en el editor")
	assert(rotation_pivot != null, "Asignar nodo de rotación en el editor")
	
	if navigation_agent:
		navigation_agent.path_desired_distance = 0.5
		navigation_agent.target_desired_distance = stopping_distance
		navigation_agent.max_speed = max_speed
	
	

func _physics_process(delta):
	if !is_moving || !navigation_agent: 
		return
	
	if navigation_agent.is_navigation_finished():
		stop_movement()
		return
	
	var next_path_pos = navigation_agent.get_next_path_position()
	var direction = (next_path_pos - controlled_body.global_position).normalized()
	
	current_speed = move_toward(current_speed, max_speed, acceleration * delta)
	controlled_body.velocity = direction * current_speed
	
	_update_rotation(delta)
	controlled_body.move_and_slide()

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = _get_isometric_mouse_position()
		if mouse_pos != Vector3.ZERO:
			set_target_position(mouse_pos)

func _get_isometric_mouse_position() -> Vector3:
	if !camera:
		return Vector3.ZERO
	
	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var plane = Plane(Vector3.UP, 0.0)
	var ray_length = 1000.0
	
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	var intersection = plane.intersects_ray(from, dir * ray_length)
	
	return intersection.snapped(Vector3(0.1, 0.0, 0.1)) if intersection else Vector3.ZERO

func set_target_position(custom_position: Vector3):
	if navigation_agent:
		target_position = custom_position
		navigation_agent.target_position = target_position
		is_moving = true

func stop_movement():
	is_moving = false
	current_speed = 0.0
	controlled_body.velocity = Vector3.ZERO

func _update_rotation(delta):
	if controlled_body.velocity.length() > 0.1:
		var look_direction = Vector2(
			controlled_body.velocity.x, 
			controlled_body.velocity.z
		).normalized()
		
		var target_angle = atan2(look_direction.x, look_direction.y)
		rotation_pivot.rotation.y = lerp_angle(
			rotation_pivot.rotation.y, 
			target_angle, 
			rotation_speed * delta
		)
