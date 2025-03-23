# Componente para navegación y pathfinding
class_name NavigationComponent
extends Node3D

signal path_found(path: Array, destination: Vector3)
signal path_failed(destination: Vector3)
signal navigation_state_changed(state: String)

enum TerrainType {
	NORMAL,
	ROUGH,
	SLIPPERY,
	STEEP,
	WATER,
	MUD,
	OBSTACLE
}

@export_category("Configuration")
## Usar sistema de navegación nativo de Godot
@export var use_godot_navigation: bool = true
## Máxima pendiente que puede navegar (grados)
@export var max_slope_angle: float = 45.0
## Radio para simplificar la ruta
@export var path_simplification_radius: float = 0.5
## Costo de cada tipo de terreno (multiplicador)
@export var terrain_costs: Dictionary = {
	TerrainType.NORMAL: 1.0,
	TerrainType.ROUGH: 2.0,
	TerrainType.SLIPPERY: 1.5,
	TerrainType.STEEP: 3.0,
	TerrainType.WATER: 2.5,
	TerrainType.MUD: 2.5,
	TerrainType.OBSTACLE: 10.0
}
## Distancia de vista previa de ruta
@export var path_lookahead_distance: float = 2.0
## Radio para unir puntos de ruta cercanos
@export var waypoint_join_radius: float = 1.0

@export_category("Advanced Pathfinding")
## Radio de detección de obstáculos
@export var obstacle_detection_radius: float = 0.5
## Máxima diferencia de altura para navegar sin saltar
@export var max_step_height: float = 0.3
## Intervalo para recalcular ruta cuando hay obstáculos
@export var repath_interval: float = 1.0
## Distancia para considerar un destino como inalcanzable
@export var unreachable_distance: float = 50.0

@export_category("Debug")
@export var debug_enabled: bool = false
@export var draw_path: bool = false
@export var draw_terrain_costs: bool = false

# Variables internas
var _character: Node3D
var _movement_controller: MovementController
var _navigation_map: RID
var _current_path: Array = []
var _current_destination: Vector3
var _last_path_attempt_time: float = 0.0
var _navigation_state: String = "idle"
var _repath_timer: Timer
var _terrain_detector: RayCast3D

func _ready() -> void:
	_setup_components()
	_setup_timers()

func _setup_components() -> void:
	# Detector de terreno
	_terrain_detector = RayCast3D.new()
	_terrain_detector.enabled = true
	_terrain_detector.collision_mask = 1  # Ajustar según la capa de colisión del terreno
	_terrain_detector.target_position = Vector3(0, -1, 0)
	add_child(_terrain_detector)

func _setup_timers() -> void:
	# Timer para recalcular ruta
	_repath_timer = Timer.new()
	_repath_timer.wait_time = repath_interval
	_repath_timer.one_shot = false
	_repath_timer.autostart = false
	_repath_timer.timeout.connect(_on_repath_timer)
	add_child(_repath_timer)

func _process(_delta: float) -> void:
	if draw_path and _current_path.size() > 1:
		_draw_debug_path()

func initialize(controller: MovementController) -> void:
	_movement_controller = controller
	_character = controller.get_character()
	
	# Obtener el mapa de navegación por defecto
	if use_godot_navigation:
		_navigation_map = get_world_3d().get_navigation_map()
		
		if _navigation_map == RID():
			push_warning("NavigationComponent: No navigation map found in the world.")

func find_path(from_position: Vector3, to_position: Vector3) -> Array:
	_current_destination = to_position
	
	# Verificar si el destino está demasiado lejos
	if from_position.distance_to(to_position) > unreachable_distance:
		if debug_enabled:
			print_debug("Destination too far: ", to_position)
		path_failed.emit(to_position)
		return []
	
	var path_array = []
	
	# Usar navegación nativa de Godot
	if use_godot_navigation and _navigation_map != RID():
		path_array = NavigationServer3D.map_get_path(
			_navigation_map,
			from_position,
			to_position,
			true  # Optimizar
		)
		
		# Guardar tiempo del último intento
		_last_path_attempt_time = Time.get_ticks_msec() / 1000.0
		
		if path_array.size() > 0:
			_process_found_path(path_array)
		else:
			path_failed.emit(to_position)
			
			if debug_enabled:
				print_debug("No path found to: ", to_position)
	else:
		# Alternativa básica sin navegación (línea recta)
		path_array = [from_position, to_position]
	
	return path_array

func _process_found_path(path_array: Array) -> void:
	# Guardar el camino encontrado
	_current_path = path_array
	
	# Aplicar simplificación de ruta
	if path_simplification_radius > 0:
		_simplify_path()
	
	# Actualizar estado de navegación
	_set_navigation_state("following_path")
	
	# Iniciar timer para recálculo periódico
	_repath_timer.start()
	
	# Emitir señal
	path_found.emit(_current_path, _current_destination)
	
	if debug_enabled:
		print_debug("Path found with ", _current_path.size(), " points")

func _simplify_path() -> void:
	if _current_path.size() <= 2:
		return
	
	var simplified_path = [_current_path[0]]
	var current_point = 1
	
	while current_point < _current_path.size() - 1:
		var can_skip = true
		var current_pos = _current_path[current_point]
		var next_pos = _current_path[current_point + 1]
		
		# Verificar si se puede saltar este punto
		if current_pos.distance_to(next_pos) > path_simplification_radius * 2:
			can_skip = false
		
		# Si el ángulo es muy pronunciado, no simplificar
		if can_skip and simplified_path.size() > 0:
			var prev_dir = (current_pos - simplified_path[simplified_path.size() - 1]).normalized()
			var next_dir = (next_pos - current_pos).normalized()
			if prev_dir.dot(next_dir) < 0.7:  # Aproximadamente 45 grados
				can_skip = false
		
		if not can_skip:
			simplified_path.append(current_pos)
		
		current_point += 1
	
	# Añadir siempre el último punto
	simplified_path.append(_current_path[_current_path.size() - 1])
	
	_current_path = simplified_path

func update_path() -> void:
	if _character and _current_destination:
		find_path(_character.global_position, _current_destination)

func abort_navigation() -> void:
	_current_path.clear()
	_repath_timer.stop()
	_set_navigation_state("idle")
	
	if debug_enabled:
		print_debug("Navigation aborted")

func get_current_path() -> Array:
	return _current_path

func get_next_waypoint() -> Vector3:
	if _current_path.size() <= 1:
		return Vector3.ZERO
	
	# Si estamos en medio de la ruta, devolver el siguiente punto
	if _movement_controller and _movement_controller.has_active_destination():
		var current_index = _movement_controller._current_path_index
		if current_index < _current_path.size():
			return _current_path[current_index]
	
	return _current_path[1]  # El primer punto suele ser la posición actual

func get_path_preview(lookahead_points: int = 3) -> Array:
	if _current_path.size() <= 1:
		return []
	
	var preview = []
	var start_index = 1  # Comenzar desde el siguiente punto (ignorar posición actual)
	
	if _movement_controller and _movement_controller.has_active_destination():
		start_index = _movement_controller._current_path_index
	
	for i in range(start_index, min(start_index + lookahead_points, _current_path.size())):
		preview.append(_current_path[i])
	
	return preview

func get_terrain_type_at_position(pos: Vector3) -> int:
	# Colocar detector en posición
	_terrain_detector.global_position = pos + Vector3.UP
	
	# Forzar actualización inmediata
	_terrain_detector.force_raycast_update()
	
	# Verificar colisión
	if _terrain_detector.is_colliding():
		var collider = _terrain_detector.get_collider()
		
		# Determinar tipo de terreno según propiedades del collider
		if collider and collider.get("terrain_type") != null:
			return collider.terrain_type
		
		# Si el collider no tiene propiedad terrain_type, inferir por material, grupo, etc.
		if collider.is_in_group("water"):
			return TerrainType.WATER
		elif collider.is_in_group("mud"):
			return TerrainType.MUD
		
		# Comprobar la pendiente
		var normal = _terrain_detector.get_collision_normal()
		var slope_angle = rad_to_deg(acos(normal.dot(Vector3.UP)))
		
		if slope_angle > max_slope_angle:
			return TerrainType.OBSTACLE
		elif slope_angle > max_slope_angle * 0.7:
			return TerrainType.STEEP
		
	return TerrainType.NORMAL

func calculate_path_cost(path: Array) -> float:
	var total_cost = 0.0
	
	for i in range(1, path.size()):
		var segment_length = path[i-1].distance_to(path[i])
		var terrain_type = get_terrain_type_at_position(path[i])
		
		var terrain_cost = terrain_costs.get(terrain_type, 1.0)
		total_cost += segment_length * terrain_cost
	
	return total_cost

func _on_repath_timer() -> void:
	# Recalcular ruta periódicamente si hay obstáculos o el personaje se ha desviado demasiado
	if _character and _current_destination:
		var current_pos = _character.global_position
		
		# Verificar si estamos lejos de la ruta actual
		var should_repath = false
		
		if _current_path.size() > 1:
			var nearest_point = _find_nearest_path_point(current_pos)
			var distance_to_path = current_pos.distance_to(nearest_point)
			
			if distance_to_path > path_lookahead_distance:
				should_repath = true
				
				if debug_enabled:
					print_debug("Repathing: character too far from path (", distance_to_path, " units)")
		
		if should_repath:
			update_path()

func _find_nearest_path_point(pos: Vector3) -> Vector3:
	if _current_path.size() == 0:
		return Vector3.ZERO
	
	var nearest_point = _current_path[0]
	var nearest_distance = pos.distance_to(nearest_point)
	
	for point in _current_path:
		var distance = pos.distance_to(point)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_point = point
	
	return nearest_point

func _set_navigation_state(state: String) -> void:
	if _navigation_state != state:
		_navigation_state = state
		navigation_state_changed.emit(state)
		
		if debug_enabled:
			print_debug("Navigation state changed to: ", state)

func _draw_debug_path() -> void:
	if not Engine.is_editor_hint() and not debug_enabled:
		return
	
	# Dibujar líneas entre puntos de ruta
	var prev_point = null
	
	for point in _current_path:
		if prev_point:
			DebugDraw.draw_line_3d(prev_point, point, Color.GREEN)
		
		# Dibujar esfera en cada punto
		DebugDraw.draw_sphere(point, 0.1, Color.YELLOW)
		
		prev_point = point
	
	# Destacar el destino final
	if _current_path.size() > 0:
		DebugDraw.draw_sphere(_current_path[_current_path.size() - 1], 0.2, Color.RED)
