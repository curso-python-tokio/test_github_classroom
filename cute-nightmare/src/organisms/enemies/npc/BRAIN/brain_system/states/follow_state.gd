# AI state for following a target
class_name FollowState
extends AIState

@export_category("Follow Configuration")
## Optimal distance to keep from target
@export var follow_distance: float = 3.0
## Maximum follow distance - switch to memory/searching if beyond this
@export var max_follow_distance: float = 20.0
## How close to get when intercepting
@export var intercept_distance: float = 1.5
## How often to update the follow path (seconds)
@export var update_interval: float = 0.5
## Use prediction for moving targets
@export var use_prediction: bool = true
## Time to wait before giving up after losing target
@export var target_memory_duration: float = 8.0
## Search when target lost
@export var search_on_target_lost: bool = true

# Private variables
var _update_timer: float = 0.0
var _last_known_position: Vector3
var _lost_target_timer: float = 0.0
var _target_lost: bool = false
var _searching: bool = false
var _search_positions: Array = []
var _current_search_index: int = 0

func enter_state() -> void:
	super.enter_state()
	
	_update_timer = 0.0
	_target_lost = false
	_lost_target_timer = 0.0
	_searching = false
	_search_positions.clear()
	_current_search_index = 0
	
	# Start following immediately
	_update_follow_position()

func exit_state() -> void:
	super.exit_state()
	stop_movement()

func update_state() -> void:
	super.update_state()
	
	var blackboard = get_blackboard()
	if not blackboard:
		return
		
	_update_timer += blackboard.brain.decision_interval
	
	if _target_lost:
		_lost_target_timer += blackboard.brain.decision_interval
		
		if _lost_target_timer > target_memory_duration:
			# Give up and transition to wander
			transition_to("wander")
			return
		
		if search_on_target_lost and not _searching:
			_start_search_pattern()
			
		if _searching:
			_update_search()
	else:
		# Update follow position periodically
		if _update_timer >= update_interval:
			_update_follow_position()
			_update_timer = 0.0

func get_next_state() -> String:
	# First check super class for any requested transitions
	var next_state = super.get_next_state()
	if next_state:
		return next_state
		
	var blackboard = get_blackboard()
	if not blackboard:
		return ""
		
	# If no target, go back to idle or wander
	if not blackboard.current_target and not _target_lost:
		return "wander"
		
	# If there are high priority points of interest, investigate them
	if blackboard.points_of_interest.size() > 0:
		var highest_poi = blackboard.points_of_interest[0]
		if highest_poi.priority > 3.0: 
			return "investigate"
			
	return ""

func on_destination_reached(_position: Vector3) -> void:
	if _searching:
		# Move to next search position
		_current_search_index += 1
		if _current_search_index >= _search_positions.size():
			# End search if we've checked all positions
			transition_to("wander")
		else:
			# Continue to next search position
			var next_pos = _search_positions[_current_search_index]
			move_to(next_pos)
	else:
		# We reached the follow position, update it again
		_update_follow_position()

func on_target_lost(target: Node3D) -> void:
	var blackboard = get_blackboard()
	if not blackboard or target != blackboard.current_target:
		return
		
	_target_lost = true
	_lost_target_timer = 0.0
	
	# Remember last position
	if blackboard.last_detected_position != Vector3.ZERO:
		_last_known_position = blackboard.last_detected_position
	
	if debug_enabled:
		print_debug("Target lost in follow state: ", target.name)

func _update_follow_position() -> void:
	var blackboard = get_blackboard()
	if not blackboard:
		return
		
	var target = blackboard.current_target
	
	# Check if we still have a valid target
	if not target or not is_instance_valid(target):
		if not _target_lost:
			on_target_lost(target)
		return
		
	# Target is visible again
	if _target_lost and blackboard.visible_targets.has(target):
		_target_lost = false
		_searching = false
		
	var target_pos = target.global_position
	var current_pos = blackboard.current_position
	
	# Calculate direction to target
	var dir_to_target = target_pos - current_pos
	var distance_to_target = dir_to_target.length()
	
	# Check if we should maintain distance
	if distance_to_target < follow_distance:
		# Too close, back away slightly
		var back_dir = -dir_to_target.normalized()
		var back_pos = current_pos + back_dir * (follow_distance - distance_to_target)
		move_to(back_pos)
	elif distance_to_target > max_follow_distance:
		# Too far, move directly toward target
		move_to(target_pos)
	else:
		# Predict target's future position if it's moving
		var target_vel = Vector3.ZERO
		if use_prediction and target is Node3D and target.has_method("get_velocity"):
			target_vel = target.get_velocity()
			
		if target_vel.length() > 0.5:
			# Target is moving, predict future position
			var prediction_time = distance_to_target / 5.0 # Adjust based on speed
			var predicted_pos = target_pos + target_vel * prediction_time
			
			# Move to intercept
			var intercept_dir = (predicted_pos - current_pos).normalized()
			var dest_pos = predicted_pos - intercept_dir * intercept_distance
			move_to(dest_pos)
		else:
			# Target is stationary, move to optimal distance
			var approach_dir = dir_to_target.normalized()
			var dest_pos = target_pos - approach_dir * follow_distance
			move_to(dest_pos)
	
	# Face toward target
	face_toward(target_pos)

func _start_search_pattern() -> void:
	_searching = true
	_current_search_index = 0
	_generate_search_positions()
	
	if _search_positions.size() > 0:
		move_to(_search_positions[0])
	else:
		# If no search positions, just go to last known position
		move_to(_last_known_position)

func _generate_search_positions() -> void:
	_search_positions.clear()
	
	# Add last known position first
	_search_positions.append(_last_known_position)
	
	# Generate positions in a search pattern around last known position
	var search_radius = 10.0
	var num_points = 8
	
	for i in range(num_points):
		var angle = TAU * i / num_points
		var offset = Vector3(cos(angle), 0, sin(angle)) * search_radius
		_search_positions.append(_last_known_position + offset)
		
	# Add a wider search pattern
	search_radius = 20.0
	for i in range(num_points):
		var angle = TAU * i / num_points + (TAU / (num_points * 2)) # Offset the angles
		var offset = Vector3(cos(angle), 0, sin(angle)) * search_radius
		_search_positions.append(_last_known_position + offset)

func _update_search() -> void:
	# Check if we found the target during search
	var blackboard = get_blackboard()
	if not blackboard:
		return
		
	var target = blackboard.current_target
	if target and blackboard.visible_targets.has(target):
		_target_lost = false
		_searching = false
		_update_follow_position()
