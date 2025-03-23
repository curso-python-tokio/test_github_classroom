# Estado para investigar puntos de interés
class_name InvestigateState
extends AIState

@export_category("Investigation Configuration")
## Tiempo de investigación en cada punto
@export var investigation_time: float = 5.0
## Radio para considerar que se ha alcanzado el punto
@export var arrival_distance: float = 1.0
## Realizar búsqueda en patrón alrededor del punto de interés
@export var do_search_pattern: bool = true
## Radio para la búsqueda alrededor del punto
@export var search_radius: float = 5.0
## Número de puntos en el patrón de búsqueda
@export var search_points: int = 3
## Tiempo mínimo de espera entre cambios de dirección durante la búsqueda
@export var search_point_delay: float = 1.0

# Variables privadas
var _current_poi: Dictionary = {}
var _investigating: bool = false
var _investigation_timer: float = 0.0
var _search_positions: Array = []
var _current_search_index: int = 0
var _search_timer: float = 0.0

func enter_state() -> void:
	super.enter_state()
	
	# Reiniciar variables de estado
	_investigating = false
	_investigation_timer = 0.0
	_search_positions.clear()
	_current_search_index = 0
	_search_timer = 0.0
	
	# Seleccionar punto de interés
	_select_point_of_interest()
	
	if debug_enabled:
		print_debug("Investigation state entered")

func update_state() -> void:
	super.update_state()
	
	var blackboard = get_blackboard()
	if not blackboard:
		return
	
	# Si no hay punto para investigar, volver a wander
	if _current_poi.is_empty():
		transition_to("wander")
		return
	
	# Actualizar temporizador si estamos investigando
	if _investigating:
		_investigation_timer += blackboard.brain.decision_interval
		
		# Si estamos en modo búsqueda, actualizar
		if do_search_pattern and _search_positions.size() > 0:
			_search_timer += blackboard.brain.decision_interval
			
			if _search_timer >= search_point_delay:
				_current_search_index = (_current_search_index + 1) % _search_positions.size()
				_search_timer = 0.0
				
				# Moverse al siguiente punto de búsqueda
				move_to(_search_positions[_current_search_index])
		
		# Verificar si hemos terminado la investigación
		if _investigation_timer >= investigation_time:
			# Marcar punto como visitado
			blackboard.mark_point_visited(_current_poi.position)
			
			# Seleccionar nuevo punto o transicionar
			if blackboard.points_of_interest.size() > 0:
				_select_point_of_interest()
			else:
				transition_to("wander")
	
	# Verificar si apareció un objetivo mientras investigamos
	if blackboard.visible_targets.size() > 0:
		var target_priority = 3.0  # Prioridad base para seguir objetivos
		var poi_priority = _current_poi.get("priority", 1.0)
		
		# Solo cambiar a seguimiento si el objetivo es de mayor prioridad
		if target_priority > poi_priority:
			transition_to("follow")

func on_destination_reached(_position: Vector3) -> void:
	# Hemos llegado al punto de interés o a un punto de búsqueda
	if not _investigating:
		_investigating = true
		_investigation_timer = 0.0
		
		# Generar patrón de búsqueda si está habilitado
		if do_search_pattern:
			_generate_search_pattern()
			_current_search_index = 0
			_search_timer = 0.0
			
			# Comenzar búsqueda si tenemos puntos
			if _search_positions.size() > 0:
				move_to(_search_positions[0])
		
		if debug_enabled:
			print_debug("Reached point of interest, starting investigation")

func _select_point_of_interest() -> void:
	var blackboard = get_blackboard()
	if not blackboard or blackboard.points_of_interest.size() == 0:
		_current_poi = {}
		return
	
	# Buscar el punto de interés de mayor prioridad
	var highest_priority = -1.0
	var selected_poi = {}
	
	for poi in blackboard.points_of_interest:
		var priority = poi.get("priority", 1.0)
		if priority > highest_priority:
			highest_priority = priority
			selected_poi = poi
	
	_current_poi = selected_poi
	_investigating = false
	
	# Moverse al punto seleccionado
	if not _current_poi.is_empty():
		move_to(_current_poi.position)
		
		if debug_enabled:
			print_debug("Selected POI for investigation: ", _current_poi.get("type", "unknown"))

func _generate_search_pattern() -> void:
	_search_positions.clear()
	
	if _current_poi.is_empty():
		return
	
	# Incluir la posición central
	_search_positions.append(_current_poi.position)
	
	# Generar puntos de búsqueda alrededor
	for i in range(search_points):
		var angle = TAU * i / search_points
		var offset = Vector3(cos(angle), 0, sin(angle)) * search_radius
		_search_positions.append(_current_poi.position + offset)
