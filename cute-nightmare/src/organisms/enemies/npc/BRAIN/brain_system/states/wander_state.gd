# AI state for wandering around randomly
class_name WanderState
extends AIState

@export_category("Wander Configuration")
## Minimum wandering radius
@export var min_distance: float = 5.0
## Maximum wandering radius
@export var max_distance: float = 15.0
## How long to stay in one place before moving again (seconds)
@export var idle_time: float = 2.0

# Private variables
var _wander_timer: float = 0.0
var _is_at_destination: bool = false

func enter_state() -> void:
	super.enter_state()
	if debug_enabled:
		print_debug("WanderState: Entered")
	
	# Reset state
	_wander_timer = 0.0
	_is_at_destination = false
	
	# Start wandering immediately
	_pick_new_destination()

func update_state() -> void:
	super.update_state()
	
	var blackboard = get_blackboard()
	if not blackboard:
		if debug_enabled:
			print_debug("WanderState: No blackboard available")
		return
	
	# Update timer
	_wander_timer += blackboard.brain.decision_interval
	
	# Check if we're idle at destination
	if _is_at_destination:
		if _wander_timer >= idle_time:
			if debug_enabled:
				print_debug("WanderState: Idle time expired, picking new destination")
			# Time to move again
			_pick_new_destination()
			_wander_timer = 0.0
	elif not blackboard.is_moving:
		if debug_enabled:
			print_debug("WanderState: Not moving, may be stuck")
		# Not at destination but not moving - might be stuck
		_pick_new_destination(true)

func on_destination_reached(position: Vector3) -> void:
	if debug_enabled:
		print_debug("WanderState: Destination reached at ", position)
	_is_at_destination = true
	_wander_timer = 0.0

func _pick_new_destination(_avoid_last: bool = false) -> void:
	if debug_enabled:
		if debug_enabled:
			print_debug("WanderState: Picking new destination")
	var blackboard = get_blackboard()
	if not blackboard or not blackboard.brain:
		if debug_enabled:
			print_debug("WanderState: Cannot pick destination - no blackboard or brain")
		return
	
	var brain = blackboard.brain
	if not brain:
		if debug_enabled:
			print_debug("WanderState: No brain reference in blackboard")
		return
		
	# Let the brain handle the wander logic
	var success = brain.wander_to_random_location()
	if debug_enabled:
		print_debug("WanderState: Wander movement request result: ", success)
	
	if success:
		_is_at_destination = false
	else:
		print_debug("WanderState: Failed to set wander destination")
