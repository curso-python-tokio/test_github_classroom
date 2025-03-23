# Base class for all AI states
class_name AIState
extends Node

# State metadata
var state_name: String = ""
var state_manager: AIStateManager

# Configuration - can be set in inspector
@export var debug_enabled: bool = false
@export var default_next_state: String = ""
@export var state_timeout: float = 0.0

# State status
var _entered_at: float = 0.0
var _active: bool = false
var _transition_requested: bool = false
var _next_state: String = ""

# Lifecycle methods

## Called when the state is entered
func enter_state() -> void:
	_entered_at = Time.get_ticks_msec() / 1000.0
	_active = true
	_transition_requested = false
	_next_state = ""
	
	if debug_enabled:
		print_debug(state_name + " state entered")

## Called when the state is exited
func exit_state() -> void:
	_active = false
	
	if debug_enabled:
		print_debug(state_name + " state exited")

## Called every decision update
func update_state() -> void:
	# Check for timeout
	if state_timeout > 0:
		var time_in_state = Time.get_ticks_msec() / 1000.0 - _entered_at
		if time_in_state >= state_timeout:
			transition_to(default_next_state if default_next_state else "idle")

## Determine if a state transition should occur
func get_next_state() -> String:
	if _transition_requested:
		return _next_state
	return ""

# Event handlers

## Called when destination is reached
func on_destination_reached(_position: Vector3) -> void:
	pass

## Called when target is lost
func on_target_lost(_target: Node3D) -> void:
	pass

## Called when obstacle is encountered
func on_obstacle_encountered(_obstacle: Node3D) -> void:
	pass

# Helper methods

## Get the blackboard
func get_blackboard() -> Blackboard:
	if state_manager and state_manager.blackboard:
		return state_manager.blackboard
	return null

## Get the brain system
func get_brain() -> BrainSystem:
	var blackboard = get_blackboard()
	if blackboard:
		return blackboard.brain
	return null

## Get the vision system
func get_vision() -> VisionSystem:
	var blackboard = get_blackboard()
	if blackboard:
		return blackboard.vision
	return null

## Get the motrix system
func get_motrix() -> MotrixSystem:
	var blackboard = get_blackboard()
	if blackboard:
		return blackboard.motrix
	return null

## Move to position
func move_to(position: Vector3) -> bool:
	var motrix = get_motrix()
	if motrix:
		return motrix.move_to(position)
	return false

## Stop movement
func stop_movement() -> void:
	var motrix = get_motrix()
	if motrix:
		motrix.stop_movement()

## Request state transition
func transition_to(next_state: String) -> void:
	if next_state.is_empty():
		return
		
	_transition_requested = true
	_next_state = next_state

## Get time spent in this state
func get_time_in_state() -> float:
	return Time.get_ticks_msec() / 1000.0 - _entered_at

## Jump to the next patrol point
func go_to_next_patrol_point() -> bool:
	var blackboard = get_blackboard()
	if not blackboard or blackboard.patrol_points.size() == 0:
		return false
	
	var index = blackboard.patrol_index
	var point = blackboard.patrol_points[index]
	return move_to(point)

## Store state data for retrieval later
func store_data(key: String, value: Variant) -> void:
	var blackboard = get_blackboard()
	if blackboard:
		blackboard.store(key, value)

## Retrieve stored state data
func retrieve_data(key: String, default_value: Variant = null) -> Variant:
	var blackboard = get_blackboard()
	if blackboard:
		return blackboard.retrieve(key, default_value)
	return default_value

## Face toward target
func face_toward(target_position: Vector3) -> void:
	var motrix = get_motrix()
	if motrix:
		var blackboard = get_blackboard()
		if blackboard:
			var direction = target_position - blackboard.current_position
			if direction.length() > 0.1:
				motrix.set_facing_direction(direction)

## Face away from target
func face_away_from(target_position: Vector3) -> void:
	var motrix = get_motrix()
	if motrix:
		var blackboard = get_blackboard()
		if blackboard:
			var direction = blackboard.current_position - target_position
			if direction.length() > 0.1:
				motrix.set_facing_direction(direction)

## Check if path to target is clear
func is_path_clear(target_position: Vector3) -> bool:
	var motrix = get_motrix()
	if motrix:
		var blackboard = get_blackboard()
		if blackboard:
			var direction = target_position - blackboard.current_position
			return motrix.is_path_clear(direction.normalized(), direction.length())
	return false

## Get best target from visible targets
func get_best_target() -> Node3D:
	var blackboard = get_blackboard()
	if not blackboard or blackboard.visible_targets.size() == 0:
		return null
	
	# Simple approach: return first target
	# More complex approaches could be implemented in subclasses
	return blackboard.visible_targets[0]
