# Maneja parpadeo natural y reacciones a irritantes
class_name BlinkController
extends Node

signal blink_started()
signal blink_ended()
signal blinking_state_changed(is_blinking_mode: bool)

@export_category("Blink Parameters")
## Blinking frequency when in continuous blinking state (blinks per second)
@export_range(0.1, 5.0, 0.1) var blink_frequency: float = 0.2:
	set(value):
		blink_frequency = value
		if _blink_timer:
			_blink_timer.wait_time = 1.0 / blink_frequency

## Duration of each blink in seconds
@export_range(0.05, 0.5, 0.01) var blink_duration: float = 0.1
## Whether to enable natural blinking
@export var natural_blinking_enabled: bool = true
## Natural blink interval range (min seconds between blinks)
@export_range(3.0, 10.0, 0.5) var natural_blink_min_interval: float = 4.0
## Natural blink interval range (max seconds between blinks)
@export_range(5.0, 15.0, 0.5) var natural_blink_max_interval: float = 8.0

@export_category("Debug")
@export var debug_enabled: bool = false

# Private variables
var _blink_timer: Timer
var _natural_blink_timer: Timer
var _is_in_blinking_state: bool = false
var _is_blinking: bool = false:
	set(value):
		if _is_blinking != value:
			_is_blinking = value
			if _is_blinking:
				blink_started.emit()
			else:
				blink_ended.emit()

var _state_manager: VisionStateManager

# Public accessors
var is_blinking: bool:
	get: return _is_blinking

func _ready() -> void:
	_setup_timers()

func _setup_timers() -> void:
	# Blink timer for continuous blinking
	_blink_timer = Timer.new()
	_blink_timer.wait_time = 1.0 / blink_frequency
	_blink_timer.one_shot = false
	_blink_timer.autostart = false
	_blink_timer.timeout.connect(_on_blink_timer)
	add_child(_blink_timer)
	
	# Natural blinking timer
	_natural_blink_timer = Timer.new()
	_natural_blink_timer.wait_time = _get_random_blink_interval()
	_natural_blink_timer.one_shot = true
	_natural_blink_timer.autostart = natural_blinking_enabled
	_natural_blink_timer.timeout.connect(_on_natural_blink_timer)
	add_child(_natural_blink_timer)

func initialize(state_manager: VisionStateManager) -> void:
	_state_manager = state_manager
	
	# Connect to state manager signals
	if _state_manager:
		_state_manager.state_changed.connect(_on_vision_state_changed)

func _on_vision_state_changed(old_state: int, new_state: int) -> void:
	# Update blinking based on vision state changes
	if new_state == VisionStateManager.VisionState.BLINKING:
		start_blinking_state()
	elif old_state == VisionStateManager.VisionState.BLINKING:
		stop_blinking_state()

func _on_blink_timer() -> void:
	if not _is_in_blinking_state:
		_blink_timer.stop()
		return
	
	_is_blinking = true
	
	if debug_enabled:
		print_debug("Blink started")
	
	# End blink after duration
	await get_tree().create_timer(blink_duration).timeout
	
	if is_instance_valid(self):  # Ensure we haven't been freed
		_is_blinking = false
		
		if debug_enabled:
			print_debug("Blink ended")

func _on_natural_blink_timer() -> void:
	if not natural_blinking_enabled or _is_in_blinking_state:
		return
	
	# Execute a single blink
	blink_once()
	
	# Schedule next natural blink
	_natural_blink_timer.wait_time = _get_random_blink_interval()
	_natural_blink_timer.start()

func _get_random_blink_interval() -> float:
	return randf_range(natural_blink_min_interval, natural_blink_max_interval)

func start_blinking_state(frequency: float = -1.0) -> void:
	if frequency > 0:
		blink_frequency = frequency
		_blink_timer.wait_time = 1.0 / blink_frequency
	
	_is_in_blinking_state = true
	_blink_timer.start()
	blinking_state_changed.emit(true)
	
	if _state_manager:
		_state_manager.current_state = VisionStateManager.VisionState.BLINKING
	
	if debug_enabled:
		print_debug("Blinking state started with frequency: ", blink_frequency)

func stop_blinking_state() -> void:
	_is_in_blinking_state = false
	_blink_timer.stop()
	_is_blinking = false
	blinking_state_changed.emit(false)
	
	if _state_manager and _state_manager.current_state == VisionStateManager.VisionState.BLINKING:
		_state_manager.current_state = VisionStateManager.VisionState.NORMAL
	
	if debug_enabled:
		print_debug("Blinking state stopped")

func blink_once() -> void:
	if _state_manager and _state_manager.current_state == VisionStateManager.VisionState.BLIND:
		return
	
	_is_blinking = true
	
	if debug_enabled:
		print_debug("Single blink executed")
	
	await get_tree().create_timer(blink_duration).timeout
	
	if is_instance_valid(self):  # Ensure we haven't been freed
		_is_blinking = false

func react_to_irritant(intensity: float) -> void:
	# Increase blink frequency based on irritant intensity
	var new_frequency = blink_frequency + intensity * 2.0
	
	if not _is_in_blinking_state:
		start_blinking_state(new_frequency)
	else:
		blink_frequency = new_frequency

func set_natural_blinking(enabled: bool) -> void:
	natural_blinking_enabled = enabled
	
	if natural_blinking_enabled:
		if not _natural_blink_timer.is_stopped():
			_natural_blink_timer.start(_get_random_blink_interval())
	else:
		_natural_blink_timer.stop()

func is_in_blinking_state() -> bool:
	return _is_in_blinking_state
