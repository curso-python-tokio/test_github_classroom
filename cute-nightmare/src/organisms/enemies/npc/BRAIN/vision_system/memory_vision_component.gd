# Component for storing and managing visual memory of detected targets
class_name MemoryVisionComponent
extends Node3D

## Signal emitted when a target is remembered (either new or refreshed)
signal target_remembered(target: Node3D, memory_data: Dictionary)

## Signal emitted when a target memory is significantly deteriorated
signal memory_deteriorated(target: Node3D, confidence: float) 

## Signal emitted when a target is completely forgotten
signal target_forgotten(target: Node3D)

@export_category("Components")
## Link to TargetRecognitionComponent
@export var target_recognition: TargetRecognitionComponent

@export_category("Configuration")
## How long a target is remembered after losing detection (seconds)
@export var memory_duration: float = 30.0
## How confident memory is when first stored (0.0-1.0)
@export var initial_memory_confidence: float = 0.9
## How quickly memory confidence decays per second
@export var memory_decay_rate: float = 0.03
## Memory decay curve (1.0 = linear, >1.0 = slow start/fast end, <1.0 = fast start/slow end)
@export_range(0.1, 5.0, 0.1) var memory_decay_curve: float = 2.0
## Threshold below which memories are forgotten completely
@export_range(0.01, 0.5, 0.01) var forget_threshold: float = 0.1
## Whether to keep position memory updated with actual position
@export var track_real_positions: bool = false
## Distance at which position memory is updated (meters)
@export var position_update_threshold: float = 3.0
## Update interval in seconds
@export_range(0.1, 1.0, 0.1) var update_interval: float = 0.5

@export_group("Debug", "debug_")
## Show debug information
@export var debug_enabled: bool = false

# Memory storage
var _memories: Dictionary = {} # {instance_id: {target, position, last_seen_time, confidence, etc}}
var _update_timer: Timer

func _ready() -> void:
	_setup_timer()
	_connect_signals()

func _setup_timer() -> void:
	_update_timer = Timer.new()
	_update_timer.wait_time = update_interval
	_update_timer.one_shot = false
	_update_timer.autostart = true
	_update_timer.timeout.connect(_on_update_timer)
	add_child(_update_timer)
	
func _connect_signals() -> void:
	if target_recognition:
		# Connect to TargetRecognitionComponent signals
		target_recognition.target_recognized.connect(_on_target_recognized)
		target_recognition.target_lost.connect(_on_target_lost)
		target_recognition.target_partially_detected.connect(_on_target_partially_detected)
		target_recognition.recognition_state_changed.connect(_on_recognition_state_changed)
	else:
		push_warning("MemoryVisionComponent: No TargetRecognitionComponent assigned!")

func _on_update_timer() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var targets_to_forget = []
	
	for instance_id in _memories:
		var memory = _memories[instance_id]
		
		# Skip if target is no longer valid
		if not is_instance_valid(memory.target):
			targets_to_forget.append(instance_id)
			continue
			
		# Update memory if currently visible or being tracked
		if memory.visible:
			_refresh_memory(instance_id, memory.target, memory.position)
			continue
			
		# Calculate time since last seen
		var elapsed_time = current_time - memory.last_seen_time
		
		# Skip if within memory duration
		if elapsed_time <= memory_duration:
			# Calculate memory decay based on curve
			var decay_factor = pow(elapsed_time / memory_duration, memory_decay_curve)
			var new_confidence = initial_memory_confidence * (1.0 - decay_factor)
			
			# Check if confidence crossed deterioration threshold
			var confidence_threshold = 0.5
			if memory.confidence >= confidence_threshold and new_confidence < confidence_threshold:
				memory_deteriorated.emit(memory.target, new_confidence)
				
				if debug_enabled:
					print_debug("Memory deteriorated: %s (confidence: %.2f)" % [memory.target.name, new_confidence])
			
			# Update confidence
			memory.confidence = new_confidence
			
			# Check if memory should be forgotten
			if memory.confidence < forget_threshold:
				targets_to_forget.append(instance_id)
		else:
			# Memory duration exceeded
			targets_to_forget.append(instance_id)
	
	# Forget targets that have expired
	for instance_id in targets_to_forget:
		var target = _memories[instance_id].target
		_forget_target(target)

func _forget_target(target: Node3D) -> void:
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id):
		target_forgotten.emit(target)
		
		if debug_enabled:
			print_debug("Target forgotten: %s" % target.name)
			
		_memories.erase(instance_id)

# TargetRecognitionComponent signal handlers

func _on_target_recognized(target: Node3D, _confidence: float) -> void:
	if not is_instance_valid(target):
		return
		
	if target_recognition:
		var state = target_recognition.get_recognition_state(target)
		if state.has("position"):
			remember_target(target, state.position, true)
		else:
			remember_target(target, target.global_position, true)
			
	if debug_enabled:
		print_debug("Target recognized and remembered: %s" % target.name)

func _on_target_partially_detected(target: Node3D, detection_state: Dictionary) -> void:
	if not is_instance_valid(target):
		return
		
	if detection_state.has("position"):
		remember_target(target, detection_state.position, false)
	else:
		remember_target(target, target.global_position, false)

func _on_target_lost(target: Node3D) -> void:
	mark_target_not_visible(target)
	
	if debug_enabled:
		print_debug("Target lost but still remembered: %s" % target.name)

func _on_recognition_state_changed(target: Node3D, _old_state: Dictionary, new_state: Dictionary) -> void:
	if not is_instance_valid(target):
		return
		
	# Update position if position has changed
	if new_state.has("position") and is_target_remembered(target):
		var instance_id = target.get_instance_id()
		var current_position = _memories[instance_id].position
		var new_position = new_state.position
		
		if current_position.distance_to(new_position) > position_update_threshold:
			_memories[instance_id].position = new_position
			
			if debug_enabled:
				print_debug("Target position updated from state change: %s" % target.name)

# Public API methods

## Remember a target with its current position
func remember_target(target: Node3D, target_position: Vector3, _is_visible: bool = true) -> void:
	if not is_instance_valid(target):
		return
		
	var instance_id = target.get_instance_id()
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Check if we already have memory of this target
	if _memories.has(instance_id):
		var memory = _memories[instance_id]
		
		# If currently visible, refresh memory
		if _is_visible:
			memory.last_seen_time = current_time
			memory.confidence = initial_memory_confidence
			memory.visible = true
			
			# Update position if changed significantly
			var distance = memory.position.distance_to(target_position)
			if distance > position_update_threshold:
				memory.position = target_position
				
				if debug_enabled:
					print_debug("Target position updated: %s | New position: %s" % [target.name, position])
		else:
			# Mark as not currently visible
			memory.visible = false
	else:
		# Create new memory
		var memory_data = {
			"target": target,
			"position": target_position,
			"last_seen_time": current_time,
			"confidence": initial_memory_confidence,
			"visible": _is_visible,
			"tags": {}  # For additional metadata
		}
		
		_memories[instance_id] = memory_data
		
		if debug_enabled:
			print_debug("New target remembered: %s | Position: %s" % [target.name, target_position])
	
	# Emit signal
	target_remembered.emit(target, _memories[instance_id].duplicate())

## Refresh memory of a target (mark as seen now)
func _refresh_memory(instance_id: int, target: Node3D, target_position: Vector3) -> void:
	if not _memories.has(instance_id) or not is_instance_valid(target):
		return
		
	var current_time = Time.get_ticks_msec() / 1000.0
	
	_memories[instance_id].last_seen_time = current_time
	_memories[instance_id].confidence = initial_memory_confidence
	
	# Update position if tracking real positions
	if track_real_positions:
		_memories[instance_id].position = target.global_position
	else:
		# Only update if position was provided and significantly different
		var distance = _memories[instance_id].position.distance_to(target_position)
		if distance > position_update_threshold:
			_memories[instance_id].position = target_position

## Mark a target as no longer visible
func mark_target_not_visible(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
		
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id):
		_memories[instance_id].visible = false

## Get memory data for a target
func get_memory(target: Node3D) -> Dictionary:
	if not is_instance_valid(target):
		return {}
		
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id):
		return _memories[instance_id].duplicate()
	
	return {}

## Get time since target was last seen (seconds)
func get_time_since_last_seen(target: Node3D) -> float:
	if not is_instance_valid(target):
		return -1.0
		
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id):
		var current_time = Time.get_ticks_msec() / 1000.0
		return current_time - _memories[instance_id].last_seen_time
	
	return -1.0

## Get all remembered targets (both visible and not visible)
func get_remembered_targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	
	for memory in _memories.values():
		if is_instance_valid(memory.target):
			result.append(memory.target)
	
	return result

## Get all recently seen targets (within specified time window)
func get_recently_seen_targets(time_window: float = 5.0) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var current_time = Time.get_ticks_msec() / 1000.0
	
	for memory in _memories.values():
		if is_instance_valid(memory.target):
			var time_since_seen = current_time - memory.last_seen_time
			if time_since_seen <= time_window:
				result.append(memory.target)
	
	return result

## Get memory confidence for a target
func get_memory_confidence(target: Node3D) -> float:
	if not is_instance_valid(target):
		return 0.0
		
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id):
		return _memories[instance_id].confidence
	
	return 0.0

## Get last remembered position for a target
func get_last_position(target: Node3D) -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
		
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id):
		return _memories[instance_id].position
	
	return Vector3.ZERO

## Check if target is remembered
func is_target_remembered(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
		
	var instance_id = target.get_instance_id()
	return _memories.has(instance_id)

## Check if target is currently visible
func is_target_visible(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
		
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id):
		return _memories[instance_id].visible
	
	return false

## Add a tag to a target's memory
func add_memory_tag(target: Node3D, tag_name: String, tag_value: Variant) -> void:
	if not is_instance_valid(target):
		return
		
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id):
		_memories[instance_id].tags[tag_name] = tag_value

## Get a tag from a target's memory
func get_memory_tag(target: Node3D, tag_name: String) -> Variant:
	if not is_instance_valid(target):
		return null
		
	var instance_id = target.get_instance_id()
	
	if _memories.has(instance_id) and _memories[instance_id].tags.has(tag_name):
		return _memories[instance_id].tags[tag_name]
	
	return null

## Get targets with a specific tag
func get_targets_with_tag(tag_name: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	
	for memory in _memories.values():
		if is_instance_valid(memory.target) and memory.tags.has(tag_name):
			result.append(memory.target)
	
	return result

## Clear all memories
func clear_all_memories() -> void:
	_memories.clear()

## Remove memory of a specific target
func forget_target_manually(target: Node3D) -> void:
	if is_instance_valid(target):
		_forget_target(target)
