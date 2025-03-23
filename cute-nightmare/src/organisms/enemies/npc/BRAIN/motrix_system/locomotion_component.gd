# Componente que gestiona la locomoción física del personaje
class_name LocomotionComponent
extends Node

signal jump_executed(strength: float)
signal dash_executed(direction: Vector3, strength: float)
signal movement_type_changed(movement_type: String)

@export_category("Configuration")
## Altura del salto en unidades
@export var jump_height: float = 3.0
## Fuerza del dash (multiplicador de velocidad)
@export var dash_strength: float = 2.5
## Duración del dash en segundos
@export var dash_duration: float = 0.3
## Fuerza de gravedad para caídas
@export var gravity_force: float = 9.8
## Factor para movimientos especiales
@export var special_movement_factor: float = 1.2
## Máxima pendiente que se puede caminar (grados)
@export var max_slope_angle: float = 45.0

@export_category("Physics")
## Usar físicas de CharacterBody3D (en vez de modificar posición directamente)
@export var use_character_body_physics: bool = true
## Factor de fricción para deslizamientos
@export var friction_factor: float = 0.1
## Fuerza para empujones
@export var push_force: float = 5.0
## Fuerza de rebote para colisiones
@export var bounce_factor: float = 0.3

@export_category("Animation")
## Umbral de velocidad para cambiar animaciones
@export var animation_speed_threshold: float = 0.1
## Transición suave entre animaciones
@export var animation_blend_time: float = 0.2

@export_category("Debug")
@export var debug_enabled: bool = false

# Variables internas
var _character: Node3D
var _movement_controller: MovementController
var _character_body: CharacterBody3D
var _current_velocity: Vector3 = Vector3.ZERO
var _vertical_velocity: float = 0.0
var _current_movement_type: String = "ground"
var _dash_timer: Timer
var _special_movement_timer: Timer
var _is_dashing: bool = false
var _is_special_movement: bool = false
var _movement_modifiers: Dictionary = {}

func _ready() -> void:
	_setup_timers()

func _physics_process(delta: float) -> void:
	if use_character_body_physics and _character_body:
		_apply_gravity(delta)
		_character_body.move_and_slide()

func _setup_timers() -> void:
	# Timer para dash
	_dash_timer = Timer.new()
	_dash_timer.one_shot = true
	_dash_timer.wait_time = dash_duration
	_dash_timer.timeout.connect(_on_dash_timer_timeout)
	add_child(_dash_timer)
	
	# Timer para movimientos especiales
	_special_movement_timer = Timer.new()
	_special_movement_timer.one_shot = true
	_special_movement_timer.timeout.connect(_on_special_movement_timeout)
	add_child(_special_movement_timer)

func initialize(controller: MovementController) -> void:
	_movement_controller = controller
	_character = controller.get_character()
	
	# Verificar si el personaje es un CharacterBody3D
	if use_character_body_physics:
		if _character is CharacterBody3D:
			_character_body = _character
		else:
			push_warning("LocomotionComponent: Character is not a CharacterBody3D, but use_character_body_physics is true.")
			use_character_body_physics = false

func apply_movement(velocity: Vector3, delta: float) -> void:
	_current_velocity = velocity
	
	# Modificar velocidad según modificadores activos
	for modifier_name in _movement_modifiers:
		var modifier = _movement_modifiers[modifier_name]
		if modifier.is_active:
			_current_velocity *= modifier.factor
	
	# Aplicar movimiento según el tipo de nodo
	if use_character_body_physics and _character_body:
		# Conservar velocidad vertical
		_current_velocity.y = _vertical_velocity
		_character_body.velocity = _current_velocity
		# El movimiento real se aplicará en _physics_process
	else:
		# Mover directamente
		_character.global_position += _current_velocity * delta

func apply_rotation(rotation_amount: float) -> void:
	if _character:
		_character.rotation.y += rotation_amount

func execute_jump(direction: Vector3 = Vector3.ZERO, strength: float = 1.0) -> void:
	if not _character:
		return
	
	var jump_power = jump_height * strength
	
	if use_character_body_physics and _character_body:
		_vertical_velocity = sqrt(2.0 * gravity_force * jump_power)
		
		# Añadir impulso horizontal si hay dirección
		if direction.length() > 0.1:
			var horizontal_boost = direction.normalized() * jump_power * 0.5
			_character_body.velocity += Vector3(horizontal_boost.x, 0, horizontal_boost.z)
	else:
		# Simulación básica sin física completa
		var jump_vec = Vector3(0, jump_power, 0)
		if direction.length() > 0.1:
			jump_vec += direction.normalized() * jump_power * 0.5
		
		# Aplicar como impulso instantáneo
		_character.global_position += jump_vec * 0.1
	
	# Señal de salto ejecutado
	jump_executed.emit(strength)
	
	if debug_enabled:
		print_debug("Jump executed with strength: ", strength)

func execute_dash(direction: Vector3, strength: float = 1.0) -> void:
	if not _character:
		return
	
	_is_dashing = true
	
	# Calcular el impulso del dash
	var dash_impulse = direction.normalized() * dash_strength * strength
	
	if use_character_body_physics and _character_body:
		# Aplicar a la velocidad actual (sin modificar velocidad vertical)
		var current_vel = _character_body.velocity
		_character_body.velocity = Vector3(
			dash_impulse.x,
			current_vel.y,
			dash_impulse.z
		)
	else:
		# Aplicar impulso directo a la posición
		_character.global_position += dash_impulse * 0.1
	
	# Iniciar temporizador de dash
	_dash_timer.start(dash_duration)
	
	# Emitir señal
	dash_executed.emit(direction, strength)
	
	if debug_enabled:
		print_debug("Dash executed with strength: ", strength)

func start_climbing(surface_normal: Vector3) -> void:
	_current_movement_type = "climbing"
	
	# Cancelar gravedad durante la escalada
	_vertical_velocity = 0.0
	
	# Añadir modificador para reducir velocidad en escalada
	add_movement_modifier("climbing", 0.7, -1.0)  # -1.0 significa indefinido
	
	# Emitir cambio de tipo de movimiento
	movement_type_changed.emit(_current_movement_type)
	
	if debug_enabled:
		print_debug("Started climbing on surface with normal: ", surface_normal)

func stop_climbing() -> void:
	_current_movement_type = "ground"
	
	# Eliminar modificador de escalada
	remove_movement_modifier("climbing")
	
	# Emitir cambio de tipo de movimiento
	movement_type_changed.emit(_current_movement_type)
	
	if debug_enabled:
		print_debug("Stopped climbing")

func start_swimming(direction: Vector3) -> void:
	_current_movement_type = "swimming"
	
	# Reducir el efecto de la gravedad en agua
	_vertical_velocity *= 0.2
	
	# Añadir modificador para reducir velocidad en agua
	add_movement_modifier("swimming", 0.6, -1.0)  # -1.0 significa indefinido
	
	# Emitir cambio de tipo de movimiento
	movement_type_changed.emit(_current_movement_type)
	
	if debug_enabled:
		print_debug("Started swimming in direction: ", direction)

func stop_swimming() -> void:
	_current_movement_type = "ground"
	
	# Eliminar modificador de natación
	remove_movement_modifier("swimming")
	
	# Emitir cambio de tipo de movimiento
	movement_type_changed.emit(_current_movement_type)
	
	if debug_enabled:
		print_debug("Stopped swimming")

func start_crawling() -> void:
	_current_movement_type = "crawling"
	
	# Añadir modificador para reducir velocidad al arrastrarse
	add_movement_modifier("crawling", 0.3, -1.0)  # -1.0 significa indefinido
	
	# Emitir cambio de tipo de movimiento
	movement_type_changed.emit(_current_movement_type)
	
	if debug_enabled:
		print_debug("Started crawling")

func stop_crawling() -> void:
	_current_movement_type = "ground"
	
	# Eliminar modificador de arrastre
	remove_movement_modifier("crawling")
	
	# Emitir cambio de tipo de movimiento
	movement_type_changed.emit(_current_movement_type)
	
	if debug_enabled:
		print_debug("Stopped crawling")

func apply_strafe(direction: Vector3) -> void:
	if not _character:
		return
	
	# Aplicar movimiento de strafe
	if use_character_body_physics and _character_body:
		var current_vel = _character_body.velocity
		_character_body.velocity = Vector3(
			direction.x,
			current_vel.y,
			direction.z
		)
	else:
		# Aplicar directamente a la posición con un factor de tiempo
		_character.global_position += direction * 0.016  # aproximado para 60fps

func apply_push(push_direction: Vector3, strength: float = 1.0) -> void:
	if not _character:
		return
	
	var push_vector = push_direction.normalized() * push_force * strength
	
	if use_character_body_physics and _character_body:
		_character_body.velocity += push_vector
	else:
		# Aplicar directamente a la posición
		_character.global_position += push_vector * 0.016

func add_movement_modifier(modifier_name: String, factor: float, duration: float = -1.0) -> void:
	_movement_modifiers[modifier_name] = {
		"factor": factor,
		"is_active": true
	}
	
	if duration > 0:
		_special_movement_timer.start(duration)
		
	if debug_enabled:
		print_debug("Added movement modifier: ", modifier_name, " with factor: ", factor)

func remove_movement_modifier(modifier_name: String) -> void:
	if _movement_modifiers.has(modifier_name):
		_movement_modifiers.erase(modifier_name)
		
		if debug_enabled:
			print_debug("Removed movement modifier: ", modifier_name)

func _apply_gravity(delta: float) -> void:
	if not use_character_body_physics or not _character_body:
		return
	
	# No aplicar gravedad si está escalando o nadando
	if _current_movement_type == "climbing" or _current_movement_type == "swimming":
		_vertical_velocity = 0.0
		return
	
	# Verificar si está en el suelo
	if _character_body.is_on_floor():
		_vertical_velocity = -0.1  # Pequeño valor negativo para mantener contacto con el suelo
	else:
		_vertical_velocity -= gravity_force * delta
	
	# Aplicar velocidad vertical
	_character_body.velocity.y = _vertical_velocity

func _on_dash_timer_timeout() -> void:
	_is_dashing = false
	
	if debug_enabled:
		print_debug("Dash ended")

func _on_special_movement_timeout() -> void:
	_is_special_movement = false
	
	if debug_enabled:
		print_debug("Special movement ended")

func is_on_ground() -> bool:
	if use_character_body_physics and _character_body:
		return _character_body.is_on_floor()
	
	# Simulación básica sin CharacterBody3D - Raycast hacia abajo
	var space_state = _character.get_world_3d().direct_space_state
	var origin = _character.global_position
	var end = origin + Vector3.DOWN * 0.1
	
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	return not result.is_empty()

func get_movement_type() -> String:
	return _current_movement_type

func get_current_vertical_velocity() -> float:
	return _vertical_velocity
