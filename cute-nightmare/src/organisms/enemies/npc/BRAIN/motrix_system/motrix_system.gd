# Sistema de movimiento completo para NPCs - Fachada para todos los componentes
class_name MotrixSystem
extends Node3D

signal destination_reached(position: Vector3)
signal state_changed(old_state: int, new_state: int)
signal obstacle_encountered(obstacle: Node3D)
signal path_found(path: Array)
signal path_failed(destination: Vector3)

@export_category("Components")
## Controlador de movimiento principal
@export var movement_controller: MovementController
## Gestor de estados de movimiento
@export var state_manager: MotionStateManager
## Componente de navegación
@export var navigation: NavigationComponent
## Componente de locomoción
@export var locomotion: LocomotionComponent
## Componente de evitación de obstáculos
@export var obstacle_avoidance: ObstacleAvoidanceComponent
## Componente de memoria de destinos
@export var destination_memory: DestinationMemoryComponent

@export_category("Configuration")
## Distancia mínima para considerar que se ha llegado al destino
@export var arrival_distance: float = 0.5
## Velocidad base para el movimiento (unidades/segundo)
@export var base_speed: float = 3.0

@export_category("Debug")
@export var debug_enabled: bool = false

# Nodo principal (CharacterBody3D, etc.)
var _character: Node3D

func _ready() -> void:
	_initialize_components()
	_connect_signals()

func _initialize_components() -> void:
	# Encontrar nodo principal subiendo en la jerarquía
	var node = self
	while node and not (node is CharacterBody3D):
		node = node.get_parent()
	
	_character = node
	
	if not _character:
		push_error("MotrixSystem: No CharacterBody3D found in parent hierarchy!")
		return
	
	# Verificar que todos los componentes estén presentes
	if not movement_controller:
		push_error("MotrixSystem: MovementController component not assigned!")
		return
		
	if not state_manager:
		push_error("MotrixSystem: MotionStateManager component not assigned!")
	
	# Inicializar controlador de movimiento
	movement_controller.arrival_distance = arrival_distance
	
	# Establecer velocidad base
	if state_manager:
		state_manager.base_speed = base_speed

func _connect_signals() -> void:
	# Conectar señales del controlador de movimiento
	if movement_controller:
		movement_controller.destination_reached.connect(_on_destination_reached)
	
	# Conectar señales del gestor de estados
	if state_manager:
		state_manager.state_changed.connect(_on_state_changed)
	
	# Conectar señales de navegación
	if navigation:
		navigation.path_found.connect(_on_path_found)
		navigation.path_failed.connect(_on_path_failed)
	
	# Conectar señales de evitación de obstáculos
	if obstacle_avoidance:
		obstacle_avoidance.obstacle_detected.connect(_on_obstacle_detected)

# API Pública - Métodos de alto nivel para control de movimiento

func move_to(pos: Vector3, use_pathfinding: bool = true) -> bool:
	if movement_controller:
		return movement_controller.set_destination(pos, use_pathfinding)
	return false

func move_to_location(loc_name: String) -> bool:
	if movement_controller and destination_memory:
		return movement_controller.go_to_remembered_location(loc_name)
	return false

func stop_movement() -> void:
	if movement_controller:
		movement_controller.clear_destination()

func set_movement_state(state: int) -> void:
	if movement_controller:
		movement_controller.set_movement_state(state)

func remember_current_location(loc_name: String, category: String = "navigation", 
							priority: float = -1.0) -> void:
	if destination_memory and _character:
		destination_memory.remember_location(loc_name, _character.global_position, 
											category, priority)

func remember_location(loc_name: String, pos: Vector3, category: String = "navigation", 
					priority: float = -1.0) -> void:
	if destination_memory:
		destination_memory.remember_location(loc_name, pos, category, priority)

func forget_location(loc_name: String) -> bool:
	if destination_memory:
		return destination_memory.forget_location(loc_name)
	return false

func get_nearest_remembered_location(category: String = "") -> Dictionary:
	if destination_memory and _character:
		return destination_memory.get_nearest_location(_character.global_position, category)
	return {}

func find_locations_in_radius(radius: float, category: String = "") -> Array:
	if destination_memory and _character:
		return destination_memory.get_locations_in_radius(_character.global_position, radius, category)
	return []

# Acciones de movimiento específicas

func jump(direction: Vector3 = Vector3.ZERO, strength: float = 1.0) -> bool:
	if movement_controller:
		return movement_controller.jump(direction, strength)
	return false

func dash(direction: Vector3, strength: float = 1.0) -> bool:
	if movement_controller:
		return movement_controller.dash(direction, strength)
	return false

func crouch(enable: bool = true) -> bool:
	if movement_controller:
		return movement_controller.crouch(enable)
	return false

func run(enable: bool = true) -> bool:
	if movement_controller:
		return movement_controller.run(enable)
	return false

func strafe(direction: Vector3, keep_facing: bool = true) -> bool:
	if movement_controller:
		return movement_controller.strafe(direction, keep_facing)
	return false

func set_facing_direction(direction: Vector3) -> void:
	if movement_controller:
		movement_controller.set_facing_direction(direction)

func enable_capability(capability: int, enabled: bool) -> void:
	if movement_controller:
		movement_controller.enable_capability(capability, enabled)

# Getters y estados

func get_current_state() -> int:
	if state_manager:
		return state_manager.current_state
	return -1

func get_current_speed() -> float:
	if state_manager:
		return state_manager.get_current_speed()
	return 0.0

func is_moving() -> bool:
	if movement_controller:
		return movement_controller.has_active_destination()
	return false

func get_current_velocity() -> Vector3:
	if movement_controller:
		return movement_controller.get_current_velocity()
	return Vector3.ZERO

func has_capability(capability: int) -> bool:
	if state_manager:
		return state_manager.can_perform(capability)
	return false

func get_nearest_obstacle() -> Dictionary:
	if obstacle_avoidance:
		return obstacle_avoidance.get_nearest_obstacle()
	return {}

func is_path_clear(direction: Vector3, distance: float) -> bool:
	if obstacle_avoidance:
		return obstacle_avoidance.is_path_clear(direction, distance)
	return true

func is_on_ground() -> bool:
	if locomotion:
		return locomotion.is_on_ground()
	return true

# Handlers de señales

func _on_destination_reached(pos: Vector3) -> void:
	destination_reached.emit(pos)
	
	if debug_enabled:
		print_debug("Destination reached: ", pos)

func _on_state_changed(old_state: int, new_state: int) -> void:
	state_changed.emit(old_state, new_state)

func _on_obstacle_detected(obstacle: Node3D, _position: Vector3, _normal: Vector3) -> void:
	obstacle_encountered.emit(obstacle)

func _on_path_found(path: Array, _destination: Vector3) -> void:
	path_found.emit(path)

func _on_path_failed(destination: Vector3) -> void:
	path_failed.emit(destination)
