# Shared memory for AI states to read/write data
class_name Blackboard
extends Node

# System references - removed type annotations to fix compatibility issues
var brain  # BrainSystem reference
var vision  # VisionSystem reference 
var motrix  # MotrixSystem reference

# Perception data
var visible_targets: Array = []
var remembered_targets: Array = []
var is_perception_blocked: bool = false
var last_detected_target: Node3D
var last_detected_position: Vector3

# Movement data
var is_moving: bool = false
var current_velocity: Vector3
var current_position: Vector3
var is_path_blocked: bool = false
var destination_reached: bool = false
var last_reached_position: Vector3
var last_obstacle: Node3D
var has_obstacle: bool = false
var path_failed: bool = false
var failed_destination: Vector3

# Target tracking
var current_target: Node3D
var points_of_interest: Array = []
var interest_points_visited: Dictionary = {}
var patrol_points: Array = []
var patrol_index: int = 0

# Internal state
var state_data: Dictionary = {}
var timers: Dictionary = {}
var last_state: String = ""
var state_enter_time: float = 0.0
var known_locations: Dictionary = {}

func reset() -> void:
	visible_targets.clear()
	remembered_targets.clear()
	points_of_interest.clear()
	interest_points_visited.clear()
	state_data.clear()
	timers.clear()
	
	is_perception_blocked = false
	is_moving = false
	current_velocity = Vector3.ZERO
	is_path_blocked = false
	destination_reached = false
	last_detected_position = Vector3.ZERO
	last_reached_position = Vector3.ZERO
	has_obstacle = false
	path_failed = false
	
	last_detected_target = null
	current_target = null
	last_obstacle = null

func store(key: String, value: Variant) -> void:
	state_data[key] = value

func retrieve(key: String, default_value: Variant = null) -> Variant:
	return state_data.get(key, default_value)

func has_key(key: String) -> bool:
	return state_data.has(key)

func erase(key: String) -> void:
	if state_data.has(key):
		state_data.erase(key)

func get_closest_point_of_interest(position: Vector3, max_distance: float = -1) -> Dictionary:
	if points_of_interest.size() == 0:
		return {}
	
	var closest_point = points_of_interest[0]
	var closest_distance = position.distance_to(closest_point.position)
	
	for point in points_of_interest:
		var distance = position.distance_to(point.position)
		if distance < closest_distance:
			closest_distance = distance
			closest_point = point
	
	if max_distance > 0 and closest_distance > max_distance:
		return {}
	
	return closest_point

func get_time_in_current_state() -> float:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_time - state_enter_time

func mark_point_visited(position: Vector3) -> void:
	var key = _get_position_key(position)
	interest_points_visited[key] = {
		"time": Time.get_ticks_msec() / 1000.0,
		"visits": interest_points_visited.get(key, {}).get("visits", 0) + 1
	}
	
	# Remove from points of interest
	for i in range(points_of_interest.size() - 1, -1, -1):
		var point = points_of_interest[i]
		if position.distance_to(point.position) < 2.0:
			points_of_interest.remove_at(i)

func was_position_visited(position: Vector3, within_seconds: float = -1) -> bool:
	var key = _get_position_key(position)
	
	if not interest_points_visited.has(key):
		return false
	
	if within_seconds > 0:
		var visit_time = interest_points_visited[key].time
		var current_time = Time.get_ticks_msec() / 1000.0
		return (current_time - visit_time) <= within_seconds
	
	return true

func get_visit_count(position: Vector3) -> int:
	var key = _get_position_key(position)
	if interest_points_visited.has(key):
		return interest_points_visited[key].visits
	return 0

func remember_location(location_name: String, position: Vector3, type: String = "generic") -> void:
	known_locations[location_name] = {
		"position": position,
		"type": type,
		"time": Time.get_ticks_msec() / 1000.0
	}

func get_known_location(location_name: String) -> Vector3:
	if known_locations.has(location_name):
		return known_locations[location_name].position
	return Vector3.ZERO

func get_known_locations_by_type(type: String) -> Array:
	var result = []
	
	for location_name in known_locations:
		if known_locations[location_name].type == type:
			result.append({
				"name": location_name,
				"position": known_locations[location_name].position
			})
	return result

func get_nearest_known_location(position: Vector3, type: String = "") -> Dictionary:
	var nearest = {}
	var nearest_dist = INF
	
	for location_name in known_locations:
		if type != "" and known_locations[location_name].type != type:
			continue
			
		var loc_pos = known_locations[location_name].position
		var dist = position.distance_to(loc_pos)
		
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = {
				"name": location_name,
				"position": loc_pos,
				"distance": dist,
				"type": known_locations[location_name].type
			}
	
	return nearest

func clear_known_locations() -> void:
	known_locations.clear()

func _get_position_key(position: Vector3) -> String:
	# Grid-based position key (5-unit grid)
	var grid_size = 5.0
	var grid_x = floor(position.x / grid_size)
	var grid_y = floor(position.y / grid_size)
	var grid_z = floor(position.z / grid_size)
	return "%d_%d_%d" % [grid_x, grid_y, grid_z]
