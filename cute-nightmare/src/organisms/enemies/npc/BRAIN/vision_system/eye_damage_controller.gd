# Maneja daño ocular, curación y sus efectos en la visión
class_name EyeDamageController
extends Node

signal damage_changed(old_value: float, new_value: float)
signal healing_started()
signal healing_stopped()

@export_category("Damage Parameters")
## Overall eye damage (0.0 = healthy, 1.0 = blind)
@export_range(0.0, 1.0, 0.01) var eye_damage: float = 0.0:
	set(value):
		var old_value = eye_damage
		eye_damage = clamp(value, 0.0, 1.0)
		if old_value != eye_damage:
			damage_changed.emit(old_value, eye_damage)

@export_category("Recovery")
## Whether eye damage heals over time
@export var auto_healing_enabled: bool = true:
	set(value):
		auto_healing_enabled = value
		if _healing_timer:
			if auto_healing_enabled:
				_healing_timer.start()
			else:
				_healing_timer.stop()

## Rate at which eye damage heals (per second)
@export_range(0.001, 0.1, 0.001) var healing_rate: float = 0.01
## Delay before healing begins after damage (seconds)
@export_range(0.0, 60.0, 1.0) var healing_delay: float = 10.0

@export_category("Debug")
@export var debug_enabled: bool = false

# Private variables
var _healing_timer: Timer
var _vision_system: Node
var _state_manager: VisionStateManager

func _ready() -> void:
	_setup_timers()

func _setup_timers() -> void:
	# Healing timer
	_healing_timer = Timer.new()
	_healing_timer.wait_time = 1.0
	_healing_timer.one_shot = false
	_healing_timer.autostart = auto_healing_enabled
	_healing_timer.timeout.connect(_on_healing_tick)
	add_child(_healing_timer)

func initialize(vision_system: Node, state_manager: VisionStateManager) -> void:
	_vision_system = vision_system
	_state_manager = state_manager

func _on_healing_tick() -> void:
	if not auto_healing_enabled or eye_damage <= 0:
		return
	
	var old_damage = eye_damage
	eye_damage = max(0.0, eye_damage - healing_rate)
	
	if debug_enabled:
		print_debug("Eye damage healing: ", old_damage, " -> ", eye_damage)
	
	# Update state if sufficiently healed
	if _state_manager:
		if eye_damage < 0.7 and _state_manager.current_state == VisionStateManager.VisionState.BLIND:
			_state_manager.current_state = VisionStateManager.VisionState.BLURRED
		elif eye_damage <= 0.1 and _state_manager.current_state == VisionStateManager.VisionState.BLURRED:
			_state_manager.current_state = VisionStateManager.VisionState.NORMAL

func apply_damage(damage_amount: float) -> void:
	var old_damage = eye_damage
	eye_damage = min(eye_damage + damage_amount, 1.0)
	
	if debug_enabled:
		print_debug("Eye damage applied: ", damage_amount, " | Total: ", eye_damage)
	
	# Update state based on damage
	if _state_manager:
		# Temporary blurred vision when damaged
		if damage_amount > 0.1 and _state_manager.current_state != VisionStateManager.VisionState.BLIND:
			_state_manager.current_state = VisionStateManager.VisionState.BLURRED
		
		# Go blind if severely damaged
		if eye_damage >= 0.9 and old_damage < 0.9:
			_state_manager.current_state = VisionStateManager.VisionState.BLIND
	
	# Reset healing timer when new damage is applied
	if auto_healing_enabled:
		_healing_timer.stop()
		healing_stopped.emit()
		_healing_timer.start(healing_delay)
		healing_started.emit()

func reset_damage() -> void:
	eye_damage = 0.0
	
	if debug_enabled:
		print_debug("Eye damage reset to 0")

func is_severely_damaged() -> bool:
	return eye_damage >= 0.7

func is_blind_from_damage() -> bool:
	return eye_damage >= 0.9
