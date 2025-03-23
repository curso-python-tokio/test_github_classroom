# Estado para huir de amenazas o peligros
class_name FleeState
extends AIState

@export_category("Flee Configuration")
## Distancia mínima de huida (metros)
@export var min_flee_distance: float = 15.0
## Velocidad de huida (multiplicador)
@export var flee_speed_multiplier: float = 1.5
## Tiempo de espera antes de verificar si es seguro
@export var safety_check_time: float = 3.0
## Distancia segura para transicionar a otro estado
@export var safe_distance: float = 25.0
## Utilizar refugios conocidos
@export var use_known_shelters: bool = true
## Intentar esconderse
@export var try_to_hide: bool = true
## Probabilidad de dash durante la huida
@export var dash_probability: float = 0.3
## Máximo número de intentos de huida
@export var max_flee_attempts: int = 3

# Variables privadas
var _threat: Node3D
var _threat_position: Vector3
var _flee_destination: Vector3
var _safety_timer: float = 0.0
var _is_checking_safety: bool = false
var _flee_attempts: int = 0
var _has_shelter: bool = false
var _shelter_position: Vector3

func enter_state() -> void:
	super.enter_state()
	
	# Reiniciar variables
	_safety_timer = 0.0
	_is_checking_safety = false
	_flee_attempts = 0
	_has_shelter = false
	
	# Identificar amenaza
	_identify_threat()
	
	# Establecer velocidad de huida
	var motrix = get_motrix()
	if motrix and motrix.state_manager:
		motrix.state_manager.set_state(MotionStateManager.MotionState.RUNNING)
		
		# Intentar dash inmediatamente
		if randf() < dash_probability:
			_do_dash()
	
	# Calcular destino de huida
	_determine_flee_destination()
	
	if debug_enabled:
		print_debug("Flee state entered, threat: ", owner.threat.name if owner.threat != null else "unknown")


func update_state() -> void:
	super.update_state()
	
	var blackboard = get_blackboard()
	if not blackboard:
		return
	
	# Verificar si es seguro periódicamente
	if _is_checking_safety:
		_safety_timer += blackboard.brain.decision_interval
		
		if _safety_timer >= safety_check_time:
			if _is_safe():
				transition_to("wander")
				return
			else:
				# Seguir huyendo
				_is_checking_safety = false
	
	# Si no estamos en movimiento, podríamos estar atascados
	if not blackboard.is_moving:
		_flee_attempts += 1
		
		if _flee_attempts >= max_flee_attempts:
			# Demasiados intentos, esconderse o cambiar de estado
			if try_to_hide:
				_try_to_hide()
			else:
				transition_to("wander")
		else:
			# Intentar nuevo destino de huida
			_determine_flee_destination()
	
	# Intentar dash ocasionalmente mientras huimos
	if randf() < dash_probability * blackboard.brain.decision_interval:
		_do_dash()

func on_destination_reached(_position: Vector3) -> void:
	# Llegamos al destino de huida
	_is_checking_safety = true
	_safety_timer = 0.0
	
	if _has_shelter:
		# Llegamos a un refugio, quedarnos aquí más tiempo
		_safety_timer = -safety_check_time  # Esperar más tiempo

func on_obstacle_encountered(_obstacle: Node3D) -> void:
	# Intentar otro camino
	_determine_flee_destination()

func _identify_threat() -> void:
	var blackboard = get_blackboard()
	if not blackboard:
		return
	
	# Buscar amenaza en targets visibles
	for target in blackboard.visible_targets:
		if target:
			_threat = target
			_threat_position = target.global_position
			return
	
	# Si no hay target visible, usar posición del último detectado
	if blackboard.last_detected_target:
		_threat = blackboard.last_detected_target
		_threat_position = blackboard.last_detected_position
	else:
		# Sin amenaza clara, usar posición actual y huir en dirección aleatoria
		_threat = null
		_threat_position = blackboard.current_position

func _determine_flee_destination() -> void:
	var blackboard = get_blackboard()
	if not blackboard:
		return
	
	# Primero intentar encontrar un refugio conocido
	if use_known_shelters:
		var shelter = blackboard.get_nearest_known_location(blackboard.current_position, "shelter")
		
		# Asegurarse que el refugio esté en dirección opuesta a la amenaza
		if not shelter.is_empty():
			var to_shelter = shelter.position - blackboard.current_position
			var to_threat = _threat_position - blackboard.current_position
			
			# Si el refugio está en dirección contraria a la amenaza, usarlo
			if to_shelter.normalized().dot(to_threat.normalized()) < 0:
				_shelter_position = shelter.position
				_has_shelter = true
				move_to(_shelter_position)
				return
	
	# Si no encontramos refugio, simplemente huir en dirección opuesta
	var flee_direction = blackboard.current_position - _threat_position
	
	# Si estamos en el mismo punto que la amenaza, elegir dirección aleatoria
	if flee_direction.length() < 0.1:
		flee_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	
	flee_direction = flee_direction.normalized()
	_flee_destination = blackboard.current_position + flee_direction * min_flee_distance
	
	# Iniciar movimiento al destino de huida
	move_to(_flee_destination)
	
	# Asegurarnos de mirar en dirección contraria a la amenaza
	face_away_from(_threat_position)
	
	_has_shelter = false

func _do_dash() -> void:
	# Ejecutar dash en dirección de huida
	var blackboard = get_blackboard()
	if not blackboard:
		return
	
	var motrix = get_motrix()
	if motrix and motrix.has_method("dash"):
		var dash_direction = (_flee_destination - blackboard.current_position).normalized()
		motrix.dash(dash_direction, 1.0)

func _is_safe() -> bool:
	var blackboard = get_blackboard()
	if not blackboard:
		return true
	
	# Si la amenaza ya no es visible, podemos estar seguros
	if _threat and is_instance_valid(_threat):
		var vision = get_vision()
		if vision and vision.is_target_visible(_threat):
			return false
	
	# Comprobar distancia a la última posición conocida de la amenaza
	var distance_to_threat = blackboard.current_position.distance_to(_threat_position)
	return distance_to_threat >= safe_distance

func _try_to_hide() -> void:
	var blackboard = get_blackboard()
	if not blackboard:
		return
	
	# Buscar un lugar para esconderse
	var hide_position = _find_hiding_spot()
	
	if hide_position != Vector3.ZERO:
		# Moverse a la posición de escondite
		move_to(hide_position)
		
		# Guardar para futura referencia
		blackboard.remember_location("hide_spot", hide_position, "shelter")
	else:
		# No encontramos lugar para esconderse, cambiamos a wander
		transition_to("wander")

func _find_hiding_spot() -> Vector3:
	var blackboard = get_blackboard()
	if not blackboard:
		return Vector3.ZERO
	
	# Raycast para buscar obstáculos que puedan servir de escondite
	var vision = get_vision()
	if not vision or not vision.raycast_component:
		return Vector3.ZERO
	
	# Prueba diferentes direcciones para encontrar un escondite
	for i in range(8):
		var angle = TAU * i / 8
		var direction = Vector3(cos(angle), 0, sin(angle))
		
		# Verificar que esta dirección sea alejándose de la amenaza
		var to_threat = _threat_position - blackboard.current_position
		if direction.normalized().dot(to_threat.normalized()) < -0.5:
			# Dirección opuesta a la amenaza, buscar obstáculo
			var test_distance = min_flee_distance * 0.5
			var test_position = blackboard.current_position + direction * test_distance
			
			# Verificar línea de visión desde amenaza a posición de prueba
			if _threat and is_instance_valid(_threat):
				# Obtener world a través del árbol de nodos
				var world_3d = get_tree().get_root().get_world_3d()
				var space_state = world_3d.direct_space_state
				var query = PhysicsRayQueryParameters3D.create(_threat_position, test_position)
				var result = space_state.intersect_ray(query)
				
				if not result.is_empty() and result.position.distance_to(test_position) < 3.0:
					# Hay un obstáculo que bloquea la visión, buen lugar para esconderse
					return result.position
	
	return Vector3.ZERO
