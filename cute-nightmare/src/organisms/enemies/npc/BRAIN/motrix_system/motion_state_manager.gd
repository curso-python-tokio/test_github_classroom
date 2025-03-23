# Gestiona estados de movimiento y transiciones entre ellos
class_name MotionStateManager
extends Node

signal state_changed(old_state: int, new_state: int)
signal movement_speed_changed(speed: float)
signal movement_capability_changed(capability: int, enabled: bool)

enum MotionState {
	IDLE,       # Sin movimiento
	WALKING,    # Caminando a velocidad normal
	RUNNING,    # Corriendo a velocidad alta
	SPRINTING,  # Velocidad máxima por corto tiempo
	CROUCHING,  # Agachado y movimiento lento
	CRAWLING,   # Movimiento en el suelo, muy lento
	JUMPING,    # En medio de un salto
	FALLING,    # Cayendo en el aire
	CLIMBING,   # Escalando una superficie
	SWIMMING,   # Nadando en agua
	FLOATING,   # Flotando en agua sin moverse
	DIVING,     # Sumergido bajo el agua
	DASHING,    # Movimiento rápido en una dirección
	STRAFING,   # Movimiento lateral
	BACKPEDALING, # Movimiento hacia atrás
	SLIDING,    # Deslizándose en superficie
	STUMBLING,  # Movimiento descontrolado temporal
	STUNNED,    # Aturdido temporalmente con movimiento limitado
	KNOCKED_DOWN, # Derribado en el suelo
	GETTING_UP, # Levantándose del suelo
	LEANING,    # Inclinándose en una dirección
	BALANCING,  # Manteniendo equilibrio en superficie estrecha
	HANGING,    # Colgado de borde o saliente 
	DISABLED    # Incapaz de moverse (paralizado, etc.)
}

enum MovementCapability {
	WALK,
	RUN,
	SPRINT,
	JUMP,
	DOUBLE_JUMP,
	CROUCH,
	CRAWL,
	CLIMB,
	CLIMB_LEDGE,
	SWIM,
	DIVE,
	DASH,
	SLIDE,
	WALL_RUN,
	WALL_JUMP,
	DODGE,
	ROLL,
	BACKFLIP,
	STRAFE,
	LEAN,
	BALANCE,
	HANG
}

@export_category("State Parameters")
## Estado actual de movimiento
@export var current_state: MotionState = MotionState.IDLE:
	set(value):
		if current_state != value:
			var old_state = current_state
			current_state = value
			_handle_state_change(old_state, current_state)

## Multiplicador de velocidad para cada estado
@export var speed_multipliers: Dictionary = {
	MotionState.IDLE: 0.0,
	MotionState.WALKING: 1.0,
	MotionState.RUNNING: 2.5,
	MotionState.SPRINTING: 3.5,
	MotionState.CROUCHING: 0.5,
	MotionState.CRAWLING: 0.3,
	MotionState.CLIMBING: 0.7,
	MotionState.SWIMMING: 0.8,
	MotionState.FLOATING: 0.2,
	MotionState.DIVING: 0.6,
	MotionState.DASHING: 4.0,
	MotionState.STRAFING: 0.8,
	MotionState.BACKPEDALING: 0.6,
	MotionState.SLIDING: 2.0,
	MotionState.STUMBLING: 0.4,
	MotionState.STUNNED: 0.2,
	MotionState.KNOCKED_DOWN: 0.0,
	MotionState.GETTING_UP: 0.3,
	MotionState.LEANING: 0.5,
	MotionState.BALANCING: 0.4,
	MotionState.HANGING: 0.2
}

## Velocidad base en unidades/segundo
@export var base_speed: float = 3.0

## Duración de los estados temporales (como saltar) en segundos
@export var temporary_state_duration: float = 1.0

@export_category("Movement Capabilities")
## Capacidades de movimiento habilitadas
@export var capabilities: Dictionary = {
	MovementCapability.WALK: true,
	MovementCapability.RUN: true,
	MovementCapability.SPRINT: true,
	MovementCapability.JUMP: true,
	MovementCapability.DOUBLE_JUMP: false,
	MovementCapability.CROUCH: true,
	MovementCapability.CRAWL: true,
	MovementCapability.CLIMB: true,
	MovementCapability.CLIMB_LEDGE: true,
	MovementCapability.SWIM: true,
	MovementCapability.DIVE: true,
	MovementCapability.DASH: true,
	MovementCapability.SLIDE: true,
	MovementCapability.WALL_RUN: false,
	MovementCapability.WALL_JUMP: false,
	MovementCapability.DODGE: true,
	MovementCapability.ROLL: true,
	MovementCapability.BACKFLIP: false,
	MovementCapability.STRAFE: true,
	MovementCapability.LEAN: true,
	MovementCapability.BALANCE: true,
	MovementCapability.HANG: true
}

@export_category("Debug")
@export var debug_enabled: bool = false

# Variables privadas
var _current_speed: float = 0.0
var _state_timer: Timer
var _movement_system: Node # Referencia al sistema de movimiento padre

func _ready() -> void:
	_setup_timers()
	_update_current_speed()

func _setup_timers() -> void:
	# Temporizador para estados temporales
	_state_timer = Timer.new()
	_state_timer.one_shot = true
	_state_timer.autostart = false
	_state_timer.timeout.connect(_on_state_timer)
	add_child(_state_timer)

func initialize(movement_system: Node) -> void:
	_movement_system = movement_system

func _handle_state_change(old_state: MotionState, new_state: MotionState) -> void:
	# Iniciar temporizador para estados temporales
	match new_state:
		MotionState.JUMPING:
			_state_timer.start(temporary_state_duration)
	
	# Actualizar velocidad basada en el nuevo estado
	_update_current_speed()
	
	# Emitir señal de cambio de estado
	state_changed.emit(old_state, new_state)
	
	if debug_enabled:
		var state_names = ["IDLE", "WALKING", "RUNNING", "CROUCHING", "JUMPING", "FALLING", "CLIMBING", "SWIMMING", "DISABLED"]
		print_debug("Motion state changed: ", state_names[old_state], " -> ", state_names[new_state])

func _update_current_speed() -> void:
	var old_speed = _current_speed
	
	if current_state == MotionState.DISABLED:
		_current_speed = 0.0
	elif speed_multipliers.has(current_state):
		_current_speed = base_speed * speed_multipliers[current_state]
	else:
		_current_speed = 0.0
	
	if old_speed != _current_speed:
		movement_speed_changed.emit(_current_speed)

func _on_state_timer() -> void:
	match current_state:
		MotionState.JUMPING:
			# Transición a caída después de saltar
			current_state = MotionState.FALLING
		# Añadir otros casos para estados temporales

func set_state(state: MotionState, duration: float = 0.0) -> void:
	# Verificar que el estado solicitado sea válido según las capacidades
	if not _is_state_allowed(state):
		if debug_enabled:
			print_debug("Cannot change to state ", get_state_name(state), ": capability disabled")
		return
	
	# Cambiar al nuevo estado
	current_state = state
	
	# Si se especifica duración, iniciar temporizador
	if duration > 0:
		_state_timer.start(duration)
		
	if debug_enabled:
		print_debug("Motion state manually set to: ", get_state_name())
		if duration > 0:
			print_debug("State will change after: ", duration, " seconds")

func _is_state_allowed(state: MotionState) -> bool:
	match state:
		MotionState.WALKING:
			return capabilities[MovementCapability.WALK]
		MotionState.RUNNING:
			return capabilities[MovementCapability.RUN]
		MotionState.SPRINTING:
			return capabilities[MovementCapability.SPRINT]
		MotionState.JUMPING:
			return capabilities[MovementCapability.JUMP]
		MotionState.CROUCHING:
			return capabilities[MovementCapability.CROUCH]
		MotionState.CRAWLING:
			return capabilities[MovementCapability.CRAWL]
		MotionState.CLIMBING:
			return capabilities[MovementCapability.CLIMB]
		MotionState.SWIMMING:
			return capabilities[MovementCapability.SWIM]
		MotionState.DIVING:
			return capabilities[MovementCapability.DIVE]
		MotionState.DASHING:
			return capabilities[MovementCapability.DASH]
		MotionState.SLIDING:
			return capabilities[MovementCapability.SLIDE]
		MotionState.STRAFING:
			return capabilities[MovementCapability.STRAFE]
		MotionState.LEANING:
			return capabilities[MovementCapability.LEAN]
		MotionState.BALANCING:
			return capabilities[MovementCapability.BALANCE]
		MotionState.HANGING:
			return capabilities[MovementCapability.HANG]
		_:
			return true

func set_capability(capability: MovementCapability, enabled: bool) -> void:
	if capabilities.has(capability) and capabilities[capability] != enabled:
		capabilities[capability] = enabled
		movement_capability_changed.emit(capability, enabled)
		
		# Si se deshabilita una capacidad y estamos en ese estado, cambiar a IDLE
		if not enabled:
			match capability:
				MovementCapability.WALK:
					if current_state == MotionState.WALKING:
						current_state = MotionState.IDLE
				MovementCapability.RUN:
					if current_state == MotionState.RUNNING:
						current_state = MotionState.WALKING if capabilities[MovementCapability.WALK] else MotionState.IDLE
				MovementCapability.JUMP:
					if current_state == MotionState.JUMPING:
						current_state = MotionState.FALLING
				MovementCapability.CROUCH:
					if current_state == MotionState.CROUCHING:
						current_state = MotionState.IDLE
				MovementCapability.CLIMB:
					if current_state == MotionState.CLIMBING:
						current_state = MotionState.FALLING
				MovementCapability.SWIM:
					if current_state == MotionState.SWIMMING:
						current_state = MotionState.FALLING

func get_current_speed() -> float:
	return _current_speed

func set_base_speed(speed: float) -> void:
	base_speed = speed
	_update_current_speed()

func get_state_name(state: MotionState = current_state) -> String:
	match state:
		MotionState.IDLE:
			return "Idle"
		MotionState.WALKING:
			return "Walking"
		MotionState.RUNNING:
			return "Running"
		MotionState.SPRINTING:
			return "Sprinting"
		MotionState.CROUCHING:
			return "Crouching"
		MotionState.CRAWLING:
			return "Crawling"
		MotionState.JUMPING:
			return "Jumping"
		MotionState.FALLING:
			return "Falling"
		MotionState.CLIMBING:
			return "Climbing"
		MotionState.SWIMMING:
			return "Swimming"
		MotionState.FLOATING:
			return "Floating"
		MotionState.DIVING:
			return "Diving"
		MotionState.DASHING:
			return "Dashing"
		MotionState.STRAFING:
			return "Strafing"
		MotionState.BACKPEDALING:
			return "Backpedaling"
		MotionState.SLIDING:
			return "Sliding"
		MotionState.STUMBLING:
			return "Stumbling"
		MotionState.STUNNED:
			return "Stunned"
		MotionState.KNOCKED_DOWN:
			return "KnockedDown"
		MotionState.GETTING_UP:
			return "GettingUp"
		MotionState.LEANING:
			return "Leaning"
		MotionState.BALANCING:
			return "Balancing"
		MotionState.HANGING:
			return "Hanging"
		MotionState.DISABLED:
			return "Disabled"
	return "Unknown"

func can_perform(capability: MovementCapability) -> bool:
	return capabilities.has(capability) and capabilities[capability]
