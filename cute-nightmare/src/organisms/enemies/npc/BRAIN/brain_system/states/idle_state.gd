# Estado básico para comportamiento inactivo
class_name IdleState
extends AIState

@export_category("Idle Configuration")
## Tiempo máximo en estado inactivo antes de cambiar a otro estado
@export var max_idle_time: float = 10.0
## Probabilidad de mirar alrededor durante idle
@export var look_around_probability: float = 0.3
## Duración de la animación de mirar
@export var look_duration: float = 1.5
## Máximo ángulo de rotación al mirar
@export var max_look_angle: float = 45.0

# Variables privadas
var _idle_rotation: float = 0.0
var _is_looking: bool = false
var _look_direction: Vector3
var _look_timer: float = 0.0

func enter_state() -> void:
	super.enter_state()
	
	# Detener el movimiento al entrar en idle
	stop_movement()
	
	# Reiniciar variables de estado
	_is_looking = false
	_look_timer = 0.0
	
	if debug_enabled:
		print_debug("Idle state entered")

func update_state() -> void:
	super.update_state()
	
	var blackboard = get_blackboard()
	if not blackboard:
		return
	
	# Verificar si debemos mirar alrededor
	if not _is_looking and randf() < look_around_probability:
		_start_looking()
	
	# Gestionar el comportamiento de mirar
	if _is_looking:
		_look_timer += blackboard.brain.decision_interval
		
		# Aplicar rotación
		var motrix = get_motrix()
		if motrix:
			motrix.set_facing_direction(_look_direction)
		
		# Terminar de mirar después del tiempo establecido
		if _look_timer >= look_duration:
			_is_looking = false
	
	# Comprobar si hay objetivos o puntos de interés
	if blackboard.visible_targets.size() > 0:
		transition_to("follow")
	elif blackboard.points_of_interest.size() > 0:
		transition_to("investigate")
	
	# Verificar si hemos estado inactivos demasiado tiempo
	if get_time_in_state() > max_idle_time:
		transition_to("wander")

func _start_looking() -> void:
	_is_looking = true
	_look_timer = 0.0
	
	# Generar dirección aleatoria para mirar
	var random_angle = deg_to_rad(randf_range(-max_look_angle, max_look_angle))
	var blackboard = get_blackboard()
	if blackboard:
		var current_forward = Vector3(0, 0, -1).rotated(Vector3.UP, _idle_rotation)
		_look_direction = current_forward.rotated(Vector3.UP, random_angle)
	else:
		_look_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
