# Component that integrates field of view, raycast and light detection for target recognition
class_name TargetRecognitionComponent
extends Node3D

## Signal emitted when a target is fully recognized (in FOV, visible and properly lit)
signal target_recognized(target: Node3D, confidence: float)

## Signal emitted when a target is partially detected but not fully recognized
signal target_partially_detected(target: Node3D, detection_state: Dictionary)

## Signal emitted when a previously recognized target is lost
signal target_lost(target: Node3D)

## Signal emitted when recognition state changes
signal recognition_state_changed(target: Node3D, old_state: Dictionary, new_state: Dictionary)

enum DetectionFactor {
	IN_FOV,
	LINE_OF_SIGHT,
	ILLUMINATION
}

@export_category("Components")
## Field of view component - detects targets in area
@export var fov_component: FieldOfViewComponent
## Raycast component - checks line of sight
@export var raycast_component: RaycastComponent
## Light detector component - checks illumination
@export var light_detector: PixelLightDetector

@export_category("Configuration")
## Minimum illumination required for recognition (0.0 - 1.0)
@export_range(0.0, 1.0, 0.01) var min_illumination: float = 0.3
## How much weight to give each detection factor (must sum to 1.0)
@export var detection_weights: Dictionary = {
	DetectionFactor.IN_FOV: 0.3,
	DetectionFactor.LINE_OF_SIGHT: 0.5,
	DetectionFactor.ILLUMINATION: 0.2
}
## Recognition threshold (0.0 - 1.0) - confidence must exceed this value
@export_range(0.0, 1.0, 0.01) var recognition_threshold: float = 0.7
## Update interval in seconds
@export_range(0.01, 1.0, 0.01) var update_interval: float = 0.1

@export_group("Debug", "debug_")
## Show debug information
@export var debug_enabled: bool = false

# Target tracking
var _target_states: Dictionary = {} # {instance_id: {in_fov, visible, illuminated, confidence}}
var _recognized_targets: Dictionary = {} # {instance_id: Node3D}
var _update_timer: Timer

func _ready() -> void:
	_validate_components()
	_connect_signals()
	_setup_timer()
	_validate_weights()

func _validate_components() -> void:
	if not fov_component:
		push_warning("TargetRecognitionComponent: No FOV component assigned!")
	
	if not raycast_component:
		push_warning("TargetRecognitionComponent: No Raycast component assigned!")
	
	if not light_detector:
		push_warning("TargetRecognitionComponent: No Light Detector assigned!")

func _connect_signals() -> void:
	if fov_component:
		fov_component.target_detected.connect(_on_fov_target_detected)
		fov_component.target_lost.connect(_on_fov_target_lost)
		fov_component.target_updated.connect(_on_fov_target_updated)
	
	if light_detector:
		light_detector.illumination_changed.connect(_on_illumination_changed)

func _setup_timer() -> void:
	_update_timer = Timer.new()
	_update_timer.wait_time = update_interval
	_update_timer.one_shot = false
	_update_timer.autostart = true
	_update_timer.timeout.connect(_on_update_timer)
	add_child(_update_timer)

func _validate_weights() -> void:
	var total_weight = 0.0
	for weight in detection_weights.values():
		total_weight += weight
	
	if abs(total_weight - 1.0) > 0.01:
		push_warning("TargetRecognitionComponent: Detection weights don't sum to 1.0! Adjusting...")
		# Normalize weights
		for factor in detection_weights:
			detection_weights[factor] /= total_weight

func _on_update_timer() -> void:
	_update_target_recognition()

func _update_target_recognition() -> void:
	var targets_to_remove = []
	
	# Process each tracked target
	for instance_id in _target_states:
		var state = _target_states[instance_id]
		var target = state.target
		
		# Skip if target is no longer valid
		if not is_instance_valid(target):
			targets_to_remove.append(instance_id)
			continue
		
		var old_state = state.duplicate()
		
		# Update visibility with raycast
		if raycast_component:
			state.visible = raycast_component.is_target_visible(target)
		
		# Calculate confidence score based on detection factors
		state.confidence = _calculate_confidence(state)
		
		# Determine if target is now recognized
		var was_recognized = _recognized_targets.has(instance_id)
		var is_recognized = state.confidence >= recognition_threshold
		
		_handle_recognition_change(instance_id, target, was_recognized, is_recognized, state)
		
		# Emit partial detection signal if partially detected but not fully recognized
		if not is_recognized and (state.in_fov or state.visible):
			target_partially_detected.emit(target, state)
		
		# Emit state changed signal if any state factors changed
		if _state_changed(old_state, state):
			recognition_state_changed.emit(target, old_state, state)
	
	# Clean up invalid targets
	for instance_id in targets_to_remove:
		_target_states.erase(instance_id)
		_recognized_targets.erase(instance_id)

func _handle_recognition_change(instance_id: int, target: Node3D, 
		was_recognized: bool, is_recognized: bool, state: Dictionary) -> void:
	if is_recognized != was_recognized:
		if is_recognized:
			_recognized_targets[instance_id] = target
			target_recognized.emit(target, state.confidence)
			
			if debug_enabled:
				print_debug("Target recognized: %s (confidence: %.2f)" % [target.name, state.confidence])
		else:
			_recognized_targets.erase(instance_id)
			target_lost.emit(target)
			
			if debug_enabled:
				print_debug("Target lost: %s (confidence: %.2f)" % [target.name, state.confidence])

func _calculate_confidence(state: Dictionary) -> float:
	var confidence = 0.0
	
	# Apply weighted factors
	if state.in_fov:
		confidence += detection_weights[DetectionFactor.IN_FOV]
	
	if state.visible:
		confidence += detection_weights[DetectionFactor.LINE_OF_SIGHT]
	
	# For illumination, scale by actual light level if above minimum
	if state.illuminated and state.light_level >= min_illumination:
		var light_factor = state.light_level
		confidence += detection_weights[DetectionFactor.ILLUMINATION] * light_factor
	
	return confidence

func _state_changed(old_state: Dictionary, new_state: Dictionary) -> bool:
	return (
		old_state.in_fov != new_state.in_fov or
		old_state.visible != new_state.visible or
		old_state.illuminated != new_state.illuminated or
		abs(old_state.confidence - new_state.confidence) > 0.05
	)

func _on_fov_target_detected(target: Node3D, target_position: Vector3) -> void:
	var instance_id = target.get_instance_id()
	
	# Initialize target state if not already tracked
	if not _target_states.has(instance_id):
		_target_states[instance_id] = {
			"target": target,
			"in_fov": true,
			"visible": false,
			"illuminated": false,
			"light_level": 0.0,
			"confidence": 0.0,
			"position": target_position
		}
		
		# Immediately check visibility
		if raycast_component:
			_target_states[instance_id].visible = raycast_component.is_target_visible(target)
	else:
		# Update FOV state
		_target_states[instance_id].in_fov = true
		_target_states[instance_id].position = target_position

func _on_fov_target_lost(target: Node3D) -> void:
	var instance_id = target.get_instance_id()
	
	if _target_states.has(instance_id):
		_target_states[instance_id].in_fov = false

func _on_fov_target_updated(target: Node3D, position: Vector3) -> void:
	var instance_id = target.get_instance_id()
	
	if _target_states.has(instance_id):
		_target_states[instance_id].position = position

func _on_illumination_changed(is_lit: bool, intensity: float) -> void:
	# Apply illumination state to all targets
	# Note: this assumes one light detector for the whole recognition component
	for instance_id in _target_states:
		var state = _target_states[instance_id]
		state.illuminated = is_lit
		state.light_level = intensity

# Public API methods

## Returns the current recognition state for a target
func get_recognition_state(target: Node3D) -> Dictionary:
	var instance_id = target.get_instance_id()
	
	if _target_states.has(instance_id):
		return _target_states[instance_id].duplicate()
	
	return {}

## Returns true if the target is fully recognized
func is_target_recognized(target: Node3D) -> bool:
	var instance_id = target.get_instance_id()
	return _recognized_targets.has(instance_id)

## Returns all fully recognized targets
func get_recognized_targets() -> Array:
	return _recognized_targets.values()

## Returns targets that are partially detected but not fully recognized
func get_partially_detected_targets() -> Array:
	var result = []
	
	for instance_id in _target_states:
		if not _recognized_targets.has(instance_id):
			var state = _target_states[instance_id]
			if state.in_fov or state.visible:
				result.append(state.target)
	
	return result

## Returns the confidence value for a target
func get_target_confidence(target: Node3D) -> float:
	var instance_id = target.get_instance_id()
	
	if _target_states.has(instance_id):
		return _target_states[instance_id].confidence
	
	return 0.0

## Clears all tracked targets
func clear_targets() -> void:
	_target_states.clear()
	_recognized_targets.clear()
