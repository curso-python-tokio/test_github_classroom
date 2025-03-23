# Componente para evitar obstáculos dinámicamente durante el movimiento
class_name ObstacleAvoidanceComponent
extends Node

signal obstacle_detected(obstacle: Node3D, position: Vector3, normal: Vector3)
signal avoidance_started(direction: Vector3)
signal avoidance_ended()

@export_category("Configuration")
## Radio de detección de obstáculos
@export var detection_radius: float = 1.0
## Número de rayos para detección
@export var ray_count: int = 8
## Longitud de los rayos de detección
@export var ray_length: float = 2.0
## Fuerza de repulsión de obstáculos
@export var avoidance_force: float = 1.5
## Máscara de colisión para obstáculos
@export var collision_mask: int = 1
## Usar algoritmo de campos de fuerza para evitación
@export var use_force_field: bool = true
## Peso para preservar movimiento original vs. evitación
@export var original_direction_weight: float = 0.5

@export_category("Dynamic Obstacles")
## Priorizar obstáculos en movimiento
@export var prioritize_moving_obstacles: bool = true
## Factor adicional para obstáculos en movimiento
@export var moving_obstacle_factor: float = 1.5
## Tiempo de predicción para obstáculos en movimiento (segundos)
@export var prediction_time: float = 0.5
## Distancia para considerar evitación frontal vs. lateral
@export var frontal_avoidance_threshold: float = 0.7

@export_category("Debug")
@export var debug_enabled: bool = false
@export var draw_rays: bool = false
@export var draw_avoidance_vectors: bool = false

# Variables internas
var _character: Node3D
var _movement_controller: MovementController
var _avoidance_rays: Array = []
var _detected_obstacles: Dictionary = {}  # {instance_id: {object, position, normal, etc}}
var _is_avoiding: bool = false
var _active_avoidance_direction: Vector3 = Vector3.ZERO
var _last_original_direction: Vector3 = Vector3.ZERO
var _accumulated_avoidance: Vector3 = Vector3.ZERO
var _avoidance_decay: float = 0.9

func _ready() -> void:
	_setup_raycasts()

func _physics_process(delta: float) -> void:
	_update_obstacle_detection()
	_update_avoidance_decay(delta)
	
	if draw_rays:
		_draw_debug_rays()

func _setup_raycasts() -> void:
	# Limpiar rayos existentes
	for ray in _avoidance_rays:
		if is_instance_valid(ray):
			ray.queue_free()
	
	_avoidance_rays.clear()
	
	# Crear nuevos rayos en distintas direcciones
	for i in range(ray_count):
		var angle = 2.0 * PI * i / ray_count
		var direction = Vector3(cos(angle), 0, sin(angle))
		
		var ray = RayCast3D.new()
		ray.enabled = true
		ray.collision_mask = collision_mask
		ray.target_position = direction * ray_length
		ray.exclude_parent = true
		
		add_child(ray)
		_avoidance_rays.append(ray)
	
	# Añadir rayo adicional hacia abajo para detectar precipicios
	var down_ray = RayCast3D.new()
	down_ray.enabled = true
	down_ray.collision_mask = collision_mask
	down_ray.target_position = Vector3(0, -ray_length * 0.5, ray_length * 0.5)  # Ángulo hacia abajo y adelante
	down_ray.exclude_parent = true
	
	add_child(down_ray)
	_avoidance_rays.append(down_ray)

func initialize(controller: MovementController) -> void:
	_movement_controller = controller
	_character = controller.get_character()
	
	# Para rayos que requieren excluir el cuerpo del personaje
	for ray in _avoidance_rays:
		if _character is CollisionObject3D:
			ray.add_exception(_character)

func modify_direction(original_direction: Vector3) -> Vector3:
	if original_direction.length() < 0.01:
		return original_direction
	
	_last_original_direction = original_direction
	
	# Si no hay obstáculos, mantener dirección original
	if _detected_obstacles.size() == 0 and _accumulated_avoidance.length() < 0.01:
		if _is_avoiding:
			_is_avoiding = false
			avoidance_ended.emit()
		return original_direction
	
	var avoidance_direction = Vector3.ZERO
	
	if use_force_field:
		avoidance_direction = _calculate_force_field_avoidance()
	else:
		avoidance_direction = _calculate_simple_avoidance()
	
	# Combinar con dirección acumulada de evasiones anteriores
	avoidance_direction += _accumulated_avoidance
	
	if avoidance_direction.length() > 0.01:
		if not _is_avoiding:
			_is_avoiding = true
			avoidance_started.emit(avoidance_direction)
		
		_active_avoidance_direction = avoidance_direction
		
		# Combinar dirección original con dirección de evitación
		var final_direction = (original_direction * original_direction_weight +
			avoidance_direction.normalized() * (1.0 - original_direction_weight)).normalized()
		
		if draw_avoidance_vectors:
			_draw_debug_vectors(original_direction, avoidance_direction, final_direction)
		
		return final_direction
	else:
		if _is_avoiding:
			_is_avoiding = false
			avoidance_ended.emit()
		
		return original_direction

func _update_obstacle_detection() -> void:
	var obstacles_to_remove = []
	
	# Actualizar obstáculos existentes
	for instance_id in _detected_obstacles:
		var obstacle_data = _detected_obstacles[instance_id]
		var obstacle = obstacle_data.object
		
		if not is_instance_valid(obstacle):
			obstacles_to_remove.append(instance_id)
			continue
		
		# Actualizar posición del obstáculo si es un objeto en movimiento
		if obstacle.has_method("get_velocity") or obstacle.has_method("get_linear_velocity"):
			var velocity = Vector3.ZERO
			if obstacle.has_method("get_velocity"):
				velocity = obstacle.get_velocity()
			elif obstacle.has_method("get_linear_velocity"):
				velocity = obstacle.get_linear_velocity()
			
			obstacle_data.velocity = velocity
			
			# Predecir futura posición
			if prioritize_moving_obstacles and velocity.length() > 0.1:
				obstacle_data.predicted_position = obstacle.global_position + velocity * prediction_time
				obstacle_data.is_moving = true
			else:
				obstacle_data.predicted_position = obstacle.global_position
				obstacle_data.is_moving = false
	
	# Eliminar obstáculos que ya no son válidos
	for instance_id in obstacles_to_remove:
		_detected_obstacles.erase(instance_id)
	
	# Actualizar detección con rayos
	for ray in _avoidance_rays:
		if ray.is_colliding():
			var collider = ray.get_collider()
			var collider_point = ray.get_collision_point()
			var collider_normal = ray.get_collision_normal()
			
			# Evitar objetos que no son obstáculos (p.ej. triggers)
			if collider.get_collision_layer_value(collision_mask) == false:
				continue
			
			var instance_id = collider.get_instance_id()
			
			if not _detected_obstacles.has(instance_id):
				# Nuevo obstáculo
				var distance = ray.global_position.distance_to(collider_point)
				var direction_to_obstacle = (collider_point - ray.global_position).normalized()
				var dot_product = _last_original_direction.dot(direction_to_obstacle)
				
				var obstacle_data = {
					"object": collider,
					"position": collider_point,
					"normal": collider_normal,
					"distance": distance,
					"frontality": dot_product,
					"velocity": Vector3.ZERO,
					"predicted_position": collider_point,
					"is_moving": false,
					"weight": 1.0  # Peso base para cálculos
				}
				
				_detected_obstacles[instance_id] = obstacle_data
				
				# Emitir señal de detección
				obstacle_detected.emit(collider, collider_point, collider_normal)
				
				if debug_enabled:
					print_debug("Obstacle detected: ", collider.name, " at distance: ", distance)
			else:
				# Actualizar obstáculo existente
				var obstacle_data = _detected_obstacles[instance_id]
				obstacle_data.position = collider_point
				obstacle_data.normal = collider_normal
				obstacle_data.distance = ray.global_position.distance_to(collider_point)
				
				var direction_to_obstacle = (collider_point - ray.global_position).normalized()
				obstacle_data.frontality = _last_original_direction.dot(direction_to_obstacle)

func _calculate_force_field_avoidance() -> Vector3:
	var avoidance_force_vector = Vector3.ZERO
	
	for obstacle_data in _detected_obstacles.values():
		var obstacle_position = obstacle_data.predicted_position if obstacle_data.has("predicted_position") else obstacle_data.position
		var direction_to_obstacle = (obstacle_position - _character.global_position)
		var distance = direction_to_obstacle.length()
		
		if distance < 0.01:
			continue
		
		# Dirección normalizada hacia el obstáculo
		direction_to_obstacle = direction_to_obstacle.normalized()
		
		# Calcular fuerza de repulsión inversa al cuadrado de la distancia
		var repulsion = avoidance_force / max(0.1, distance * distance)
		
		# Aplicar factor adicional si es un obstáculo en movimiento
		if obstacle_data.is_moving:
			repulsion *= moving_obstacle_factor
		
		# Dirección de evitación (opuesta al obstáculo)
		var avoidance_direction = -direction_to_obstacle
		
		# Mayor peso si el obstáculo está directamente en frente
		var frontality = obstacle_data.frontality
		if frontality > frontal_avoidance_threshold:
			repulsion *= 1.0 + frontality
		
		avoidance_force_vector += avoidance_direction * repulsion
	
	return avoidance_force_vector

func _calculate_simple_avoidance() -> Vector3:
	# Método alternativo y más simple cuando hay pocos obstáculos
	var closest_obstacle = null
	var closest_distance = 999999.0
	
	for obstacle_data in _detected_obstacles.values():
		if obstacle_data.distance < closest_distance:
			closest_obstacle = obstacle_data
			closest_distance = obstacle_data.distance
	
	if closest_obstacle:
		var normal = closest_obstacle.normal
		if normal.length() < 0.1:
			normal = (_character.global_position - closest_obstacle.position).normalized()
		
		# Proyectar la dirección normal en el plano horizontal
		normal.y = 0
		normal = normal.normalized()
		
		return normal * avoidance_force
	
	return Vector3.ZERO

func _update_avoidance_decay(delta: float) -> void:
	# Reducir gradualmente el efecto de la evitación acumulada
	if _accumulated_avoidance.length() > 0.01:
		_accumulated_avoidance *= pow(_avoidance_decay, delta * 10)
	else:
		_accumulated_avoidance = Vector3.ZERO

func accumulate_avoidance(direction: Vector3, strength: float = 1.0) -> void:
	# Acumular la dirección de evitación para mantener "memoria" de obstáculos
	_accumulated_avoidance += direction.normalized() * strength
	
	# Limitar la magnitud para evitar valores extremos
	if _accumulated_avoidance.length() > 2.0:
		_accumulated_avoidance = _accumulated_avoidance.normalized() * 2.0

func get_nearest_obstacle() -> Dictionary:
	var nearest = null
	var min_distance = 999999.0
	
	for obstacle_data in _detected_obstacles.values():
		if obstacle_data.distance < min_distance:
			min_distance = obstacle_data.distance
			nearest = obstacle_data
	
	return nearest if nearest else {}

func is_path_clear(direction: Vector3, distance: float) -> bool:
	# Comprobar si hay un camino despejado en la dirección dada
	for obstacle_data in _detected_obstacles.values():
		var to_obstacle = obstacle_data.position - _character.global_position
		var projected = to_obstacle.project(direction)
		
		if projected.length() <= distance:
			var perpendicular = to_obstacle - projected
			if perpendicular.length() < detection_radius:
				return false
	
	return true

func get_clear_direction() -> Vector3:
	# Buscar la dirección más despejada
	if _detected_obstacles.size() == 0:
		return _last_original_direction
	
	# Muestrear direcciones posibles
	var directions = []
	var weights = []
	
	for i in range(ray_count):
		var angle = 2.0 * PI * i / ray_count
		var direction = Vector3(cos(angle), 0, sin(angle))
		var weight = 1.0
		
		# Calcular peso basado en cercanía a dirección original
		var dot = direction.dot(_last_original_direction)
		weight *= 0.5 + 0.5 * max(0, dot)  # Favorece dirección original
		
		# Reducir peso si hay obstáculos en esta dirección
		for obstacle_data in _detected_obstacles.values():
			var to_obstacle = (obstacle_data.position - _character.global_position).normalized()
			dot = direction.dot(to_obstacle)
			
			if dot > 0.7:  # Obstáculo aproximadamente adelante
				var distance_factor = clamp(1.0 - obstacle_data.distance / ray_length, 0, 1)
				weight *= 1.0 - distance_factor * dot
		
		directions.append(direction)
		weights.append(weight)
	
	# Encontrar dirección de mayor peso
	var best_direction = _last_original_direction
	var best_weight = 0
	
	for i in range(directions.size()):
		if weights[i] > best_weight:
			best_weight = weights[i]
			best_direction = directions[i]
	
	return best_direction

func has_obstacles() -> bool:
	return _detected_obstacles.size() > 0

func is_avoiding() -> bool:
	return _is_avoiding

func _draw_debug_rays() -> void:
	if not Engine.is_editor_hint() and not debug_enabled:
		return
	
	for ray in _avoidance_rays:
		var start = ray.global_position
		var end = start + ray.target_position
		
		var color = Color.BLUE
		if ray.is_colliding():
			color = Color.RED
			# Dibujar normal en punto de colisión
			var normal_end = ray.get_collision_point() + ray.get_collision_normal()
			DebugDraw.draw_line_3d(ray.get_collision_point(), normal_end, Color.GREEN)
		
		DebugDraw.draw_line_3d(start, end, color)

func _draw_debug_vectors(original_dir: Vector3, avoidance_dir: Vector3, final_dir: Vector3) -> void:
	if not Engine.is_editor_hint() and not debug_enabled:
		return
	
	var start = _character.global_position
	var scale = 2.0  # Escala para visualización
	
	# Dirección original (azul)
	DebugDraw.draw_line_3d(start, start + original_dir * scale, Color.BLUE)
	
	# Dirección de evitación (rojo)
	DebugDraw.draw_line_3d(start, start + avoidance_dir.normalized() * scale, Color.RED)
	
	# Dirección final (verde)
	DebugDraw.draw_line_3d(start, start + final_dir * scale, Color.GREEN)
