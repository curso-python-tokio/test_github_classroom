# Component to detect objects within a field of view
class_name FieldOfViewComponent
extends Area3D

## Signal emitted when a new target is detected
signal target_detected(target: Node3D, position: Vector3)

## Signal emitted when a target is lost from view
signal target_lost(target: Node3D)

## Signal emitted when a target's position is updated
signal target_updated(target: Node3D, new_position: Vector3)

@export_category("Configuration")
@export_group("Debug", "debug_")
## Show debug information
@export var debug_enabled: bool = false

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _detected_targets: Dictionary = {}  # {int: {object: Node3D, position: Vector3}}

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _physics_process(_delta: float) -> void:
	if debug_enabled && Global.debug:
		_update_debug_info()

func get_detected_targets() -> Array:
	return _detected_targets.values()

func get_target_position(target: Node3D) -> Vector3:
	return _detected_targets.get(target.get_instance_id(), {}).get("position", Vector3.ZERO)
	
func has_target(target: Node3D) -> bool:
	return _detected_targets.has(target.get_instance_id())

func _on_body_entered(body: Node3D) -> void:
	if _is_valid_target(body):
		var instance_id = body.get_instance_id()
		var target_data = {
			"object": body,
			"position": body.global_position
		}
		
		_detected_targets[instance_id] = target_data
		target_detected.emit(body, body.global_position)

func _on_body_exited(body: Node3D) -> void:
	var instance_id = body.get_instance_id()
	if _detected_targets.erase(instance_id):
		target_lost.emit(body)

func _is_valid_target(body: Node3D) -> bool:
	return body != owner
	

func _update_debug_info() -> void:
	var to_remove: Array = []
	
	for instance_id in _detected_targets:
		var target_data = _detected_targets[instance_id]
		var target: Node3D = target_data["object"]
		
		if is_instance_valid(target):
			var new_position = target.global_position
			if new_position != target_data["position"]:
				target_data["position"] = new_position
				target_updated.emit(target, new_position)
				
			print_debug("Target: %s | Position: %s" % [target.name, new_position])
		else:
			to_remove.append(instance_id)
	
	for instance_id in to_remove:
		_detected_targets.erase(instance_id)
