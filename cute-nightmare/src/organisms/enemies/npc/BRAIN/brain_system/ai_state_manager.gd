# Manages AI state transitions
class_name AIStateManager
extends Node

signal state_changed(old_state: String, new_state: String)

@export_category("States")
## State instance for idle behavior
@export var idle_state: IdleState
## State instance for wandering behavior
@export var wander_state: WanderState
## State instance for patrol behavior
@export var patrol_state: PatrolState
## State instance for investigation behavior
@export var investigate_state: InvestigateState
## State instance for following targets
@export var follow_state: FollowState
## State instance for fleeing from threats
@export var flee_state: FleeState

@export_category("Configuration")
## Minimum time to stay in a state (seconds)
@export var min_state_duration: float = 1.0
## Default state if requested state is not available
@export var fallback_state: String = "idle"
## Allow interrupting states with higher priority
@export var allow_interrupts: bool = true
## State priorities (higher numbers = higher priority)
@export var state_priorities: Dictionary = {
	"idle": 0,
	"wander": 1,
	"patrol": 2,
	"investigate": 3,
	"follow": 4,
	"flee": 5
}
## Enable debug output
@export var debug_enabled: bool = false

# State tracking
var current_state_name: String = "idle"
var _current_state: AIState
var _last_state_change_time: float = 0.0
var _registered_states: Dictionary = {}
var _state_history: Array = []
var _history_max_size: int = 10
var blackboard

func _ready() -> void:
	_register_states()

func _register_states() -> void:
	# Register all exported states
	if idle_state:
		_register_state("idle", idle_state)
	
	if wander_state:
		_register_state("wander", wander_state)
	
	if patrol_state:
		_register_state("patrol", patrol_state)
	
	if investigate_state:
		_register_state("investigate", investigate_state)
	
	if follow_state:
		_register_state("follow", follow_state)
	
	if flee_state:
		_register_state("flee", flee_state)
	
	# Initialize with idle state if available
	if _registered_states.has("idle"):
		set_state("idle")
	elif _registered_states.size() > 0:
		# Use first available state if no idle
		set_state(_registered_states.keys()[0])

func _register_state(state_name: String, state: AIState) -> void:
	state.state_manager = self
	state.state_name = state_name
	_registered_states[state_name] = state

func set_state(new_state_name: String) -> bool:
	# Validate state name
	if not _registered_states.has(new_state_name):
		push_warning("AIStateManager: Unknown state: " + new_state_name)
		
		# Use fallback state
		if new_state_name != fallback_state and _registered_states.has(fallback_state):
			return set_state(fallback_state)
		
		return false
	
	# Check minimum duration
	var current_time = Time.get_ticks_msec() / 1000.0
	if _current_state != null and (current_time - _last_state_change_time) < min_state_duration:
		# Check interrupt priority
		if allow_interrupts and _should_interrupt(new_state_name):
			if debug_enabled:
				print_debug("AIStateManager: State change allowed despite min duration (higher priority)")
		else:
			if debug_enabled:
				print_debug("AIStateManager: State change rejected, min duration not met")
			return false
	
	# Exit current state
	var old_state_name = current_state_name
	if _current_state != null:
		_current_state.exit_state()
	
	# Add to history
	_add_to_history(old_state_name)
	
	# Set new state
	_current_state = _registered_states[new_state_name]
	current_state_name = new_state_name
	_last_state_change_time = current_time
	
	# Update blackboard
	if blackboard:
		blackboard.last_state = old_state_name
		blackboard.state_enter_time = current_time
	
	# Enter new state
	_current_state.enter_state()
	
	# Emit signal
	state_changed.emit(old_state_name, current_state_name)
	
	if debug_enabled:
		print_debug("AIStateManager: State changed: ", old_state_name, " -> ", current_state_name)
	
	return true

func update_current_state() -> void:
	if _current_state:
		# First ask the state if it wants to transition
		var next_state = _current_state.get_next_state()
		
		if next_state != "":
			set_state(next_state)
		else:
			# Otherwise update the current state
			_current_state.update_state()

func get_current_state() -> AIState:
	return _current_state

func get_state_instance(state_name: String) -> AIState:
	if _registered_states.has(state_name):
		return _registered_states[state_name]
	return null

func has_state(state_name: String) -> bool:
	return _registered_states.has(state_name)

func get_previous_state() -> String:
	if _state_history.size() > 0:
		return _state_history[0]
	return ""

func was_in_state(state_name: String, max_steps_back: int = -1) -> bool:
	var steps = min(_state_history.size(), max_steps_back if max_steps_back > 0 else _state_history.size())
	
	for i in range(steps):
		if _state_history[i] == state_name:
			return true
	
	return false

func on_destination_reached(position: Vector3) -> void:
	if _current_state:
		_current_state.on_destination_reached(position)

func on_target_lost(target: Node3D) -> void:
	if _current_state:
		_current_state.on_target_lost(target)

func on_obstacle_encountered(obstacle: Node3D) -> void:
	if _current_state:
		_current_state.on_obstacle_encountered(obstacle)

func register_custom_state(state_name: String, state: AIState) -> void:
	_register_state(state_name, state)

func _add_to_history(state_name: String) -> void:
	_state_history.push_front(state_name)
	
	if _state_history.size() > _history_max_size:
		_state_history.pop_back()

func _should_interrupt(new_state_name: String) -> bool:
	var current_priority = state_priorities.get(current_state_name, 0)
	var new_priority = state_priorities.get(new_state_name, 0)
	
	return new_priority > current_priority
