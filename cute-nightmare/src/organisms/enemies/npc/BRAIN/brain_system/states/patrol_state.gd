# Estado para seguir puntos de patrulla
class_name PatrolState
extends AIState

@export_category("Patrol Configuration")
## Tiempo de espera en cada punto de patrulla
@export var wait_time_at_points: float = 2.0
## Permitir mirar alrededor en puntos de patrulla
@export var look_around_at_points: bool = true
## Radio de llegada a los puntos de patrulla
@export var arrival_distance: float = 1.0
## Permitir modos de patrulla aleatorios
@export var allow_random_patrol: bool = false

# Variables privadas
var _current_point_index: int = 0
var _waiting_at_point: bool = false
var _wait_timer: float = 0.0
var _patrol_points: Array = []
var _patrol_direction: int = 1 # 1 = adelante, -1 = atrás

func enter_state() -> void:
	super.enter_state()
	
	# Reiniciar variables de estado
	_waiting_at_point = false
	_wait_timer = 0.0
	
	# Cargar puntos de patrulla desde blackboard
	var blackboard = get_blackboard()
	if blackboard:
		_patrol_points = blackboard.patrol_points
		_current_point_index = blackboard.patrol_index
	
	# Si no hay puntos de patrulla, fallar a estado wander
	if _patrol_points.size() == 0:
		transition_to("wander")
		if debug_enabled:
			print_debug("No patrol points available, transitioning to wander")
		return
	
	# Comenzar a moverse hacia el punto actual
	_move_to_current_point()
	
	if debug_enabled:
		print_debug("Patrol state entered. Points: ", _patrol_points.size())

func update_state() -> void:
	super.update_state()
	
	var blackboard = get_blackboard()
	if not blackboard:
		return
	
	# Si estamos esperando en un punto
	if _waiting_at_point:
		_wait_timer += blackboard.brain.decision_interval
		
		# Comprobar si hemos esperado suficiente
		if _wait_timer >= wait_time_at_points:
			_waiting_at_point = false
			
			# Avanzar al siguiente punto
			_move_to_next_point()
	
	# Verificar si hay objetivos de alta prioridad
	if blackboard.visible_targets.size() > 0:
		# Guardar el índice actual para continuar después
		blackboard.patrol_index = _current_point_index
		transition_to("follow")

func on_destination_reached(position: Vector3) -> void:
	if _waiting_at_point:
		return
	
	# Hemos llegado a un punto de patrulla
	_waiting_at_point = true
	_wait_timer = 0.0
	
	if debug_enabled:
		print_debug("Reached patrol point ", _current_point_index)
	
	# Opcionalmente mirar alrededor
	if look_around_at_points:
		var look_dir = _get_next_patrol_direction()
		face_toward(position + look_dir)

func _move_to_current_point() -> void:
	if _patrol_points.size() == 0 or _current_point_index >= _patrol_points.size():
		transition_to("wander")
		return
	
	move_to(_patrol_points[_current_point_index])

func _move_to_next_point() -> void:
	if _patrol_points.size() <= 1:
		_move_to_current_point()  # Solo tenemos un punto, volver a él
		return
	
	if allow_random_patrol and randf() < 0.2:
		# Ocasionalmente elegir un punto aleatorio diferente al actual
		var new_index = _current_point_index
		while new_index == _current_point_index:
			new_index = randi() % _patrol_points.size()
		_current_point_index = new_index
	else:
		# Avanzar en la dirección actual
		_current_point_index += _patrol_direction
		
		# Comprobar límites
		if _current_point_index >= _patrol_points.size():
			# Llegamos al final, cambiar dirección o volver al inicio
			if randf() < 0.5:
				_patrol_direction = -1
				_current_point_index = _patrol_points.size() - 2  # Penúltimo punto
			else:
				_current_point_index = 0  # Volver al inicio
		elif _current_point_index < 0:
			# Llegamos al inicio en dirección inversa
			if randf() < 0.5:
				_patrol_direction = 1
				_current_point_index = 1  # Segundo punto
			else:
				_current_point_index = _patrol_points.size() - 1  # Ir al final
	
	# Actualizar índice en blackboard
	var blackboard = get_blackboard()
	if blackboard:
		blackboard.patrol_index = _current_point_index
	
	# Moverse al siguiente punto
	_move_to_current_point()

func _get_next_patrol_direction() -> Vector3:
	# Calcular dirección hacia el siguiente punto
	var next_index = (_current_point_index + _patrol_direction) % _patrol_points.size()
	if next_index < 0:
		next_index = _patrol_points.size() - 1
	
	var current_pos = _patrol_points[_current_point_index]
	var next_pos = _patrol_points[next_index]
	
	return (next_pos - current_pos).normalized()
	
