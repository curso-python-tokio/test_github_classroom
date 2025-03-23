# Controlador central para el sistema de movimiento, coordina todos los componentes
class_name MovementController
extends Node

signal movement_update(delta_position: Vector3)
signal rotation_update(delta_rotation: float)
signal destination_reached(destination: Vector3)

@export_category("Components")
## Gestor de estados de movimiento
@export var state_manager: MotionStateManager
## Componente de navegación
@export var navigation: Node
## Componente de locomoción
@export var locomotion: Node
## Componente de evitación de obstáculos
@export var obstacle_avoidance: Node
## Componente de memoria de destinos
@export var destination_memory: Node

@export_category("Configuration")
## Distancia mínima para considerar que se ha llegado al destino
@export var arrival_distance: float = 0.5
## Actualizar orientación automáticamente hacia la dirección de movimiento
@export var auto_orient: bool = true
## Velocidad de rotación (grados/segundo)
@export var rotation_speed: float = 120.0

@export_category("Debug")
@export var debug_enabled: bool = false
@export var draw_path: bool = false

# Variables internas
var _current_destination: Vector3 = Vector3.ZERO
var _has_destination: bool = false
var _current_path: Array = []
var _current_path_index: int = 0
var _current_velocity: Vector3 = Vector3.ZERO
var _desired_facing: float = 0.0
var _current_facing: float = 0.0

# Nodo principal (CharacterBody3D, etc.)
var _character: Node3D

func _ready() -> void:
	_initialize_components()

func _physics_process(delta: float) -> void:
	if not _character:
		return
	
	if _has_destination:
		_process_movement(delta)
	
	if auto_orient:
		_process_orientation(delta)

func _process_movement(delta: float) -> void:
	if _current_path.size() == 0 or not state_manager or state_manager.current_state == MotionStateManager.MotionState.DISABLED:
		return
	
	# Obtener el siguiente punto en la ruta
	var target_point = _current_path[_current_path_index]
	var current_pos = _character.global_position
	
	# Calcular dirección y distancia al punto
	var direction = (target_point - current_pos)
	direction.y = 0  # Mantener movimiento en el plano horizontal
	var distance = direction.length()
	
	# Comprobar si hemos llegado a este punto de la ruta
	if distance < arrival_distance:
		_current_path_index += 1
		
		# Verificar si hemos completado la ruta
		if _current_path_index >= _current_path.size():
			_has_destination = false
			destination_reached.emit(_current_destination)
			return
		
		target_point = _current_path[_current_path_index]
		direction = (target_point - current_pos)
		direction.y = 0
		distance = direction.length()
	
	# Normalizar la dirección y aplicar velocidad
	if distance > 0:
		direction = direction.normalized()
		
		# Establecer la orientación deseada
		if direction.length() > 0.1:
			_desired_facing = atan2(-direction.x, -direction.z)
		
		# Obtener velocidad del gestor de estados
		var speed = state_manager.get_current_speed() if state_manager else 3.0
		
		# Aplicar modificadores de evitación de obstáculos si está disponible
		if obstacle_avoidance and obstacle_avoidance.has_method("modify_direction"):
			direction = obstacle_avoidance.modify_direction(direction)
		
		# Calcular velocidad
		_current_velocity = direction * speed
		
		# Aplicar movimiento a través del componente de locomoción si está disponible
		if locomotion and locomotion.has_method("apply_movement"):
			locomotion.apply_movement(_current_velocity, delta)
		else:
			# Movimiento básico si no hay componente de locomoción
			var delta_position = _current_velocity * delta
			_character.global_position += delta_position
			movement_update.emit(delta_position)

func _process_orientation(delta: float) -> void:
	if abs(_desired_facing - _current_facing) > 0.01:
		# Calcular la rotación más corta
		var rotation_diff = fmod((_desired_facing - _current_facing + PI), (2 * PI)) - PI
		
		# Aplicar rotación suave
		var rotation_amount = sign(rotation_diff) * min(abs(rotation_diff), deg_to_rad(rotation_speed) * delta)
		_current_facing += rotation_amount
		
		# Normalizar la orientación actual
		_current_facing = fmod(_current_facing, 2 * PI)
		
		# Aplicar rotación a través del componente de locomoción si está disponible
		if locomotion and locomotion.has_method("apply_rotation"):
			locomotion.apply_rotation(rotation_amount)
		else:
			# Rotación básica si no hay componente de locomoción
			_character.rotation.y = _current_facing
			rotation_update.emit(rotation_amount)

func _initialize_components() -> void:
	# Encontrar nodo principal subiendo en la jerarquía
	var node = self
	while node and not (node is CharacterBody3D):
		node = node.get_parent()
	
	_character = node
	
	if not _character:
		push_error("MovementController: No CharacterBody3D found in parent hierarchy!")
		return
	
	# Inicializar componentes si existen
	if state_manager:
		state_manager.initialize(self)
	
	if navigation and navigation.has_method("initialize"):
		navigation.initialize(self)
	
	if locomotion and locomotion.has_method("initialize"):
		locomotion.initialize(self)
	
	if obstacle_avoidance and obstacle_avoidance.has_method("initialize"):
		obstacle_avoidance.initialize(self)
	
	if destination_memory and destination_memory.has_method("initialize"):
		destination_memory.initialize(self)

func set_destination(position: Vector3, use_pathfinding: bool = true) -> bool:
	_current_destination = position
	
	# Verificar si el estado de movimiento permite moverse
	if state_manager and state_manager.current_state == MotionStateManager.MotionState.DISABLED:
		if debug_enabled:
			print_debug("Cannot set destination: movement is disabled")
		return false
	
	# Usar navegación si está disponible y se requiere pathfinding
	if navigation and use_pathfinding and navigation.has_method("find_path"):
		_current_path = navigation.find_path(_character.global_position, position)
		
		if _current_path.size() == 0:
			if debug_enabled:
				print_debug("No path found to destination: ", position)
			return false
	else:
		# Ruta directa si no hay navegación o no se requiere pathfinding
		_current_path = [position]
	
	_current_path_index = 0
	_has_destination = true
	
	# Determinar estado de movimiento basado en la distancia
	_update_movement_state()
	
	if debug_enabled:
		print_debug("Destination set: ", position)
		print_debug("Path points: ", _current_path.size())
	
	return true

func clear_destination() -> void:
	_has_destination = false
	_current_path.clear()
	
	# Volver a estado IDLE si no hay destino
	if state_manager and state_manager.current_state != MotionStateManager.MotionState.DISABLED:
		state_manager.set_state(MotionStateManager.MotionState.IDLE)

func set_movement_state(state: int) -> void:
	if state_manager:
		state_manager.set_state(state)

func _update_movement_state() -> void:
	if not state_manager or not _has_destination:
		return
	
	# Si actualmente está quieto, empezar a caminar
	if state_manager.current_state == MotionStateManager.MotionState.IDLE:
		if state_manager.can_perform(MotionStateManager.MovementCapability.WALK):
			state_manager.set_state(MotionStateManager.MotionState.WALKING)

func enable_capability(capability: int, enabled: bool) -> void:
	if state_manager:
		state_manager.set_capability(capability, enabled)

func set_facing_direction(direction: Vector3) -> void:
	if direction.length() > 0.1:
		_desired_facing = atan2(-direction.x, -direction.z)

func set_facing_angle(angle: float) -> void:
	_desired_facing = angle

func get_current_velocity() -> Vector3:
	return _current_velocity

func has_active_destination() -> bool:
	return _has_destination

func get_current_destination() -> Vector3:
	return _current_destination

func get_character() -> Node3D:
	return _character

func set_movement_speed(speed: float) -> void:
	if state_manager:
		state_manager.set_base_speed(speed)

func remember_location(loc_name: String, position: Vector3) -> void:
	if destination_memory and destination_memory.has_method("remember_location"):
		destination_memory.remember_location(loc_name, position)

func go_to_remembered_location(loc_name: String) -> bool:
	if destination_memory and destination_memory.has_method("get_location"):
		var location = destination_memory.get_location(loc_name)
		if location != Vector3.ZERO:
			return set_destination(location)
	return false

# Movimientos especiales específicos
func jump(direction: Vector3 = Vector3.ZERO, strength: float = 1.0) -> bool:
	if not state_manager or not state_manager.can_perform(MotionStateManager.MovementCapability.JUMP):
		return false
		
	if locomotion and locomotion.has_method("execute_jump"):
		locomotion.execute_jump(direction, strength)
		state_manager.set_state(MotionStateManager.MotionState.JUMPING)
		return true
	return false

func crouch(enable: bool = true) -> bool:
	if not state_manager:
		return false
		
	if enable and not state_manager.can_perform(MotionStateManager.MovementCapability.CROUCH):
		return false
		
	if enable:
		state_manager.set_state(MotionStateManager.MotionState.CROUCHING)
	else:
		state_manager.set_state(MotionStateManager.MotionState.IDLE)
	return true

func run(enable: bool = true) -> bool:
	if not state_manager:
		return false
		
	if enable and not state_manager.can_perform(MotionStateManager.MovementCapability.RUN):
		return false
		
	if enable:
		state_manager.set_state(MotionStateManager.MotionState.RUNNING)
	else:
		state_manager.set_state(MotionStateManager.MotionState.WALKING)
	return true

func climb(surface_normal: Vector3) -> bool:
	if not state_manager or not state_manager.can_perform(MotionStateManager.MovementCapability.CLIMB):
		return false
		
	if locomotion and locomotion.has_method("start_climbing"):
		locomotion.start_climbing(surface_normal)
		state_manager.set_state(MotionStateManager.MotionState.CLIMBING)
		return true
	return false

func swim(direction: Vector3) -> bool:
	if not state_manager or not state_manager.can_perform(MotionStateManager.MovementCapability.SWIM):
		return false
		
	if locomotion and locomotion.has_method("start_swimming"):
		locomotion.start_swimming(direction)
		state_manager.set_state(MotionStateManager.MotionState.SWIMMING)
		return true
	return false

func crawl() -> bool:
	if not state_manager or not state_manager.can_perform(MotionStateManager.MovementCapability.CROUCH):
		return false
		
	if locomotion and locomotion.has_method("start_crawling"):
		locomotion.start_crawling()
		state_manager.set_state(MotionStateManager.MotionState.CROUCHING)
		return true
	return false

func dash(direction: Vector3, strength: float = 1.0) -> bool:
	if not state_manager or not state_manager.can_perform(MotionStateManager.MovementCapability.RUN):
		return false
		
	if locomotion and locomotion.has_method("execute_dash"):
		locomotion.execute_dash(direction, strength)
		return true
	return false

func stop_immediately() -> void:
	_current_velocity = Vector3.ZERO
	_has_destination = false
	_current_path.clear()
	
	if state_manager:
		state_manager.set_state(MotionStateManager.MotionState.IDLE)

func strafe(direction: Vector3, keep_facing: bool = true) -> bool:
	if not state_manager or state_manager.current_state == MotionStateManager.MotionState.DISABLED:
		return false
		
	var temp_auto_orient = auto_orient
	auto_orient = !keep_facing
	
	if locomotion and locomotion.has_method("apply_strafe"):
		locomotion.apply_strafe(direction)
		return true
	else:
		# Movimiento básico de strafe si no hay implementación específica
		_current_velocity = direction * state_manager.get_current_speed()
		auto_orient = temp_auto_orient
		return true
