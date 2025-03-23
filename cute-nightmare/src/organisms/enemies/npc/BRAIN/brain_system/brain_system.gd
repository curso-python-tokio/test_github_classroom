# Main controller for AI autonomous behavior
class_name BrainSystem
extends Node3D

signal state_changed(old_state: String, new_state: String)
signal target_selected(target: Node3D)
# signal point_of_interest_found(position: Vector3, type: String)

@export_category("Systems")
## Reference to the vision system
@export var vision_system: VisionSystem
## Reference to the movement system
@export var motrix_system: MotrixSystem
## AI State manager
@export var state_manager: AIStateManager

@export_category("Configuration")
## How often to update decision making (seconds)
@export var decision_interval: float = 0.5
## Maximum distance for wander behavior
@export var wander_radius: float = 15.0
## Distance to consider destination reached
@export var arrival_distance: float = 1.0
## Enable automatic behavior
@export var autonomous_enabled: bool = true:
	set(value):
		autonomous_enabled = value
		if autonomous_enabled:
			_decision_timer.start()
		else:
			_decision_timer.stop()
			
## Default starting state
@export var default_state: String = "wander" # Changed from idle to wander

@export_category("Debug")
@export var debug_enabled: bool = false

# Private variables
var _decision_timer: Timer
var _current_target: Node3D
var _points_of_interest: Array = []
var _blackboard: Blackboard
var _character: Node3D

func _ready() -> void:
	if debug_enabled:
		print_debug("BrainSystem initializing...")
	
	# Find character node
	_character = get_parent() # Assumes BrainSystem is a child of the character
	if debug_enabled:
		var character_name = "NONE"
		if _character != null:
			character_name = _character.name
			print_debug("Character found: ", character_name)
	
	# Create Blackboard as a child node
	_blackboard = Blackboard.new()
	_blackboard.name = "Blackboard"
	add_child(_blackboard)
	
	_blackboard.brain = self
	_blackboard.vision = vision_system
	_blackboard.motrix = motrix_system
	
	_setup_timers()
	_connect_signals()
	
	# Wait until next frame to ensure nodes are ready
	await get_tree().process_frame
	
	# Set initial state
	if state_manager:
		state_manager.blackboard = _blackboard
		if debug_enabled:
			print_debug("Setting initial state to: ", default_state)
		state_manager.set_state(default_state)
		
		# Force movement right away
		_test_movement()
	else:
		print("ERROR: No state manager assigned!")

func _setup_timers() -> void:
	_decision_timer = Timer.new()
	_decision_timer.name = "DecisionTimer"
	_decision_timer.wait_time = decision_interval
	_decision_timer.one_shot = false
	_decision_timer.autostart = autonomous_enabled
	_decision_timer.timeout.connect(_on_decision_timer)
	add_child(_decision_timer)
	if debug_enabled:
		print_debug("Decision timer set up with interval: ", decision_interval)

func _connect_signals() -> void:
	if vision_system:
		vision_system.target_detected.connect(_on_target_detected)
		vision_system.target_lost.connect(_on_target_lost)
		if debug_enabled:
			print_debug("Vision system signals connected")
	else:
		print("WARNING: No vision system assigned")
	
	if motrix_system:
		motrix_system.destination_reached.connect(_on_destination_reached)
		motrix_system.obstacle_encountered.connect(_on_obstacle_encountered)
		if debug_enabled:
			print_debug("Motrix system signals connected")
	else:
		print("WARNING: No motrix system assigned")
	
	if state_manager:
		state_manager.state_changed.connect(_on_state_changed)
		if debug_enabled:
			print_debug("State manager signals connected")
	else:
		print("WARNING: No state manager assigned")

func _on_decision_timer() -> void:
	if debug_enabled:
		print_debug("Decision timer tick")
		
	if not autonomous_enabled or not state_manager:
		return
	
	# Update perception data in blackboard
	_update_blackboard()
	
	# Let the current state make decisions
	state_manager.update_current_state()

func _update_blackboard() -> void:
	if not _blackboard:
		print("ERROR: No blackboard available for update")
		return
	
	# Update position
	if _character:
		_blackboard.current_position = _character.global_position
	
	# Update targets from vision system
	if vision_system:
		_blackboard.visible_targets = vision_system.get_detected_targets()
		_blackboard.remembered_targets = vision_system.get_remembered_targets()
		_blackboard.is_perception_blocked = vision_system.is_perception_blocked()
	
	# Update movement data from motrix system
	if motrix_system:
		_blackboard.is_moving = motrix_system.is_moving()
		_blackboard.current_velocity = motrix_system.get_current_velocity()
		
		# Check if path is clear in forward direction
		var direction = _blackboard.current_velocity.normalized() if _blackboard.current_velocity.length() > 0 else Vector3.FORWARD
		_blackboard.is_path_blocked = not motrix_system.is_path_clear(direction, 2.0)

	# Update internal data
	_blackboard.current_target = _current_target
	_blackboard.points_of_interest = _points_of_interest

func _on_target_detected(target: Node3D, pos: Vector3) -> void:
	print("Target detected: ", target.name, " at position: ", pos)
	if not autonomous_enabled:
		return
	
	if _blackboard:
		_blackboard.last_detected_target = target
		_blackboard.last_detected_position = pos
	
	target_selected.emit(target)

func _on_target_lost(target: Node3D) -> void:
	print("Target lost: ", target.name)
	if target == _current_target:
		_current_target = null
		
		if _blackboard:
			_blackboard.current_target = null

func _on_destination_reached(pos: Vector3) -> void:
	if debug_enabled:
		print("Destination reached: ", pos)
	if _blackboard:
		_blackboard.last_reached_position = pos
		_blackboard.destination_reached = true
	
	if state_manager:
		state_manager.on_destination_reached(pos)

func _on_obstacle_encountered(obstacle: Node3D) -> void:
	if debug_enabled:
		print_debug("Obstacle encountered: ", obstacle.name)
	if _blackboard:
		_blackboard.last_obstacle = obstacle
		_blackboard.has_obstacle = true

func _on_state_changed(old_state: String, new_state: String) -> void:
	if debug_enabled:
		print_debug("Brain state changed: ", old_state, " -> ", new_state)
	state_changed.emit(old_state, new_state)

func wander_to_random_location() -> bool:
	if debug_enabled:
		print_debug("Forcing wander to random location")
	if not motrix_system or not _character:
		print_debug("Cannot wander: no motrix system or character")
		return false
	
	# Generate a random point within wander radius
	var random_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var distance = randf_range(5.0, wander_radius)
	var target_pos = _character.global_position + random_dir * distance
	
	if debug_enabled:
		print_debug("Wander target: ", target_pos)
	return motrix_system.move_to(target_pos)

func go_to_location(pos: Vector3) -> bool:
	if debug_enabled:
		print_debug("Going to location: ", pos)
	if motrix_system:
		return motrix_system.move_to(pos)
	return false

func _test_movement() -> void:
	if debug_enabled:
		print_debug("TESTING MOVEMENT")
	# Try both direct movement and wander
	if not go_to_location(Vector3(10, 0, 10)):
		print("Direct movement failed, trying wander")
		wander_to_random_location()
