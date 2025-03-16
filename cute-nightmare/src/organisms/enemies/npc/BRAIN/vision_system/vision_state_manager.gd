# Gestiona estados visuales y transiciones entre ellos
class_name VisionStateManager
extends Node

signal state_changed(old_state: int, new_state: int)
signal position_uncertainty_changed(value: float)

enum VisionState {
	NORMAL,      # Regular vision
	BLURRED,     # Unfocused vision
	DARK_ADAPTED,# Adjusted to darkness
	DAZZLED,     # Overwhelmed by bright light
	OBSCURED,    # Partially blocked
	BLINKING,    # In the process of blinking
	BLIND        # Cannot see
}

@export_category("State Parameters")
## Current vision state
@export var current_state: VisionState = VisionState.NORMAL:
	set(value):
		if current_state != value:
			var old_state = current_state
			current_state = value
			_handle_state_change(old_state, current_state)

## How long blurred vision persists when damaged (seconds)
@export var blur_duration: float = 3.0
## How long dazzled effect lasts after bright light exposure (seconds)
@export var dazzle_duration: float = 5.0
## How long dark adaptation takes (seconds)
@export var dark_adapt_duration: float = 10.0

@export_category("Debug")
@export var debug_enabled: bool = false

# Private variables
var _position_uncertainty: float = 0.0
var _state_timer: Timer
var _vision_system: Node # Reference to parent vision system 

func _ready() -> void:
	_setup_timers()

func _setup_timers() -> void:
	# State change timer
	_state_timer = Timer.new()
	_state_timer.one_shot = true
	_state_timer.autostart = false
	_state_timer.timeout.connect(_on_state_timer)
	add_child(_state_timer)

func initialize(vision_system: Node) -> void:
	_vision_system = vision_system

func _handle_state_change(old_state: VisionState, new_state: VisionState) -> void:
	match new_state:
		VisionState.NORMAL:
			_position_uncertainty = 0.0
			
		VisionState.BLURRED:
			_state_timer.start(blur_duration)
			_position_uncertainty = 1.0
			
		VisionState.DAZZLED:
			_state_timer.start(dazzle_duration)
			_position_uncertainty = 2.0
			
		VisionState.DARK_ADAPTED:
			_position_uncertainty = 0.5
			
		VisionState.OBSCURED:
			_position_uncertainty = 1.5
			
		VisionState.BLIND:
			_position_uncertainty = 3.0
	
	position_uncertainty_changed.emit(_position_uncertainty)
	state_changed.emit(old_state, new_state)
	
	if debug_enabled:
		var state_names = ["NORMAL", "BLURRED", "DARK_ADAPTED", "DAZZLED", "OBSCURED", "BLINKING", "BLIND"]
		print_debug("Vision state changed: ", state_names[old_state], " -> ", state_names[new_state])

func _on_state_timer() -> void:
	match current_state:
		VisionState.BLURRED:
			current_state = VisionState.NORMAL
			
		VisionState.DAZZLED:
			current_state = VisionState.NORMAL

func get_position_uncertainty() -> float:
	return _position_uncertainty

func set_state(state: VisionState, duration: float = 0.0) -> void:
	current_state = state
	
	if duration > 0:
		_state_timer.start(duration)
		
	if debug_enabled:
		print_debug("Vision state manually set to: ", get_state_name())
		if duration > 0:
			print_debug("State will revert after: ", duration, " seconds")

func react_to_light_change(light_level: float, old_level: float) -> void:
	# Handle transitions between light levels
	if light_level <= 0.2 and old_level > 0.2:
		# Transition to darkness, start dark adaptation after delay
		if current_state != VisionState.DARK_ADAPTED and current_state != VisionState.BLIND:
			get_tree().create_timer(dark_adapt_duration).timeout.connect(
				func():
					if light_level <= 0.2 and current_state != VisionState.BLIND:
						current_state = VisionState.DARK_ADAPTED
			)
			
			if debug_enabled:
				print_debug("Starting dark adaptation process...")
				
	elif light_level >= 0.8 and old_level < 0.8:
		# Sudden bright light when not adapted
		if current_state == VisionState.DARK_ADAPTED:
			current_state = VisionState.DAZZLED
			
			if debug_enabled:
				print_debug("Dark-adapted eyes dazzled by bright light!")

func is_perception_blocked() -> bool:
	return current_state == VisionState.BLIND

func get_state_name() -> String:
	match current_state:
		VisionState.NORMAL:
			return "Normal"
		VisionState.BLURRED:
			return "Blurred"
		VisionState.DARK_ADAPTED:
			return "DarkAdapted"
		VisionState.DAZZLED:
			return "Dazzled"
		VisionState.OBSCURED:
			return "Obscured"
		VisionState.BLINKING:
			return "Blinking"
		VisionState.BLIND:
			return "Blind"
	return "Unknown"
