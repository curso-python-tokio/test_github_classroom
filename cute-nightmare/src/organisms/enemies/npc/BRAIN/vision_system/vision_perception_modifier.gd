# Aplica modificaciones a detección/memoria según estado visual
class_name VisionPerceptionModifier
extends Node

signal settings_updated()

@export_category("Target Recognition")
@export var target_recognition: TargetRecognitionComponent

@export_category("Debug")
@export var debug_enabled: bool = false

# References to other components
var _state_manager: VisionStateManager
var _eye_damage: EyeDamageController
var _blink_controller: BlinkController
var _original_settings: Dictionary = {}

func _ready() -> void:
	if is_instance_valid(target_recognition):
		_store_original_settings()

func initialize(state_manager: VisionStateManager, damage_controller: EyeDamageController, blink_controller: BlinkController) -> void:
	_state_manager = state_manager
	_eye_damage = damage_controller
	_blink_controller = blink_controller
	
	# Connect to signals
	if _state_manager:
		_state_manager.state_changed.connect(_on_vision_state_changed)
	
	if _eye_damage:
		_eye_damage.damage_changed.connect(_on_eye_damage_changed)
	
	if _blink_controller:
		_blink_controller.blink_started.connect(_on_blink_started)
		_blink_controller.blink_ended.connect(_on_blink_ended)
	
	# Initial update
	update_perception_modifiers()

func _store_original_settings() -> void:
	if not target_recognition:
		return
		
	_original_settings["detection_weights"] = target_recognition.detection_weights.duplicate()
	_original_settings["min_illumination"] = target_recognition.min_illumination
	_original_settings["recognition_threshold"] = target_recognition.recognition_threshold
	
	if debug_enabled:
		print_debug("VisionPerceptionModifier: Stored original recognition settings")

func _on_vision_state_changed(_old_state: int, _new_state: int) -> void:
	update_perception_modifiers()

func _on_eye_damage_changed(_old_value: float, _new_value: float) -> void:
	update_perception_modifiers()

func _on_blink_started() -> void:
	update_perception_modifiers()

func _on_blink_ended() -> void:
	update_perception_modifiers()

func update_perception_modifiers() -> void:
	if not target_recognition or not _original_settings.has("detection_weights"):
		return
	
	# Calculate how impaired vision is based on damage and state
	var impairment_factor = 0.0
	
	if _eye_damage:
		impairment_factor = _eye_damage.eye_damage
	
	if _blink_controller and _blink_controller.is_blinking:
		impairment_factor = 1.0
	elif _state_manager:
		match _state_manager.current_state:
			VisionStateManager.VisionState.BLIND:
				impairment_factor = 1.0
			VisionStateManager.VisionState.BLURRED:
				impairment_factor = max(impairment_factor, 0.5)
			VisionStateManager.VisionState.DAZZLED:
				impairment_factor = max(impairment_factor, 0.7)
			VisionStateManager.VisionState.OBSCURED:
				impairment_factor = max(impairment_factor, 0.4)
	
	# Modify detection weights
	var new_weights = _original_settings.detection_weights.duplicate()
	
	for factor in new_weights:
		new_weights[factor] *= (1.0 - impairment_factor * 0.7)
	
	# Special handling for different states
	if _state_manager and _state_manager.current_state == VisionStateManager.VisionState.DARK_ADAPTED:
		if new_weights.has(target_recognition.DetectionFactor.ILLUMINATION):
			new_weights[target_recognition.DetectionFactor.ILLUMINATION] *= 1.5
	
	# Re-normalize
	var total = 0.0
	for weight in new_weights.values():
		total += weight
	
	if total > 0:
		for factor in new_weights:
			new_weights[factor] /= total
	
	target_recognition.detection_weights = new_weights
	
	# Modify recognition threshold
	var threshold_modifier = 1.0
	
	if _state_manager:
		match _state_manager.current_state:
			VisionStateManager.VisionState.NORMAL:
				threshold_modifier = 1.0
			VisionStateManager.VisionState.BLURRED:
				threshold_modifier = 1.3
			VisionStateManager.VisionState.DARK_ADAPTED:
				threshold_modifier = 1.0
			VisionStateManager.VisionState.DAZZLED:
				threshold_modifier = 1.5
			VisionStateManager.VisionState.OBSCURED:
				threshold_modifier = 1.4
			VisionStateManager.VisionState.BLINKING:
				threshold_modifier = 1.1
				if _blink_controller and _blink_controller.is_blinking:
					threshold_modifier = 10.0
			VisionStateManager.VisionState.BLIND:
				threshold_modifier = 10.0
	
	var new_threshold = _original_settings.recognition_threshold * threshold_modifier
	
	if _eye_damage:
		new_threshold *= (1.0 + _eye_damage.eye_damage * 0.5)
		
	target_recognition.recognition_threshold = new_threshold
	
	settings_updated.emit()
	
	if debug_enabled:
		print_debug("Vision perception modifiers updated")
		print_debug("  - Impairment factor: ", impairment_factor)
		print_debug("  - New recognition threshold: ", new_threshold)

func get_confidence_modifier(state: int) -> float:
	# Return confidence modifier based on state
	match state:
		VisionStateManager.VisionState.NORMAL:
			return 1.0
		VisionStateManager.VisionState.BLURRED:
			return 0.7
		VisionStateManager.VisionState.DARK_ADAPTED:
			return 1.0
		VisionStateManager.VisionState.DAZZLED:
			return 0.5
		VisionStateManager.VisionState.OBSCURED:
			return 0.6
		VisionStateManager.VisionState.BLINKING:
			return 0.8
		VisionStateManager.VisionState.BLIND:
			return 0.0
	return 1.0

func apply_position_uncertainty(position: Vector3, multiplier: float = 1.0) -> Vector3:
	if not _state_manager:
		return position
		
	var uncertainty = _state_manager.get_position_uncertainty() * multiplier
	
	if _eye_damage:
		uncertainty *= (1.0 + _eye_damage.eye_damage)
	
	if uncertainty <= 0:
		return position
		
	return Vector3(
		position.x + randf_range(-uncertainty, uncertainty),
		position.y + randf_range(-uncertainty, uncertainty),
		position.z + randf_range(-uncertainty, uncertainty)
	)

func modify_confidence(confidence: float) -> float:
	if not _state_manager or not _eye_damage:
		return confidence
		
	var modified = confidence
	
	# Apply damage modifier
	modified *= (1.0 - _eye_damage.eye_damage * 0.5)
	
	# Apply state modifier
	modified *= get_confidence_modifier(_state_manager.current_state)
	
	# Apply blink modifier
	if _blink_controller and _blink_controller.is_blinking:
		modified *= 0.1
		
	return modified
