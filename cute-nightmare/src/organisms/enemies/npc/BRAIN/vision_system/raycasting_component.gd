# Component to verify line-of-sight visibility to targets
class_name RaycastComponent
extends Node3D

## Signal emitted when a target becomes visible
signal target_visible(target: Node3D, position: Vector3)
## Signal emitted when a target is no longer visible
signal target_lost(target: Node3D)
## Signal emitted when a visible target's position is updated
signal target_updated(target: Node3D, position: Vector3)

@export_category("Configuration")
## Collision mask for raycasting
@export var collision_mask: int = 1
@export_group("Debug", "debug_")
## Show debug information
@export var debug_enabled: bool = false

var _space_state: PhysicsDirectSpaceState3D
var _visible_targets: Dictionary = {}  # {int: {object: Node3D, position: Vector3}}

func _ready() -> void:
	# Initialize the space state
	_space_state = get_world_3d().direct_space_state

func _physics_process(_delta: float) -> void:
	# Update the space state each physics frame
	_space_state = get_world_3d().direct_space_state
	
	if debug_enabled && Global.debug:
		_update_debug_info()

func is_target_visible(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	
	var origin: Vector3 = global_position
	var target_position: Vector3 = target.global_position
	
	# Configure the raycast query
	var query := PhysicsRayQueryParameters3D.create(origin, target_position)
	query.collision_mask = collision_mask
	
	# Exclude the owner from collision detection
	if owner is CollisionObject3D:
		query.exclude = [owner]
	
	# Perform the raycast
	var result := _space_state.intersect_ray(query)
	
	# Target is visible if there's no collision or the collision is with the target itself
	var target_is_visible: bool = result.is_empty() or result.collider == target
	var instance_id: int = target.get_instance_id()
	
	if target_is_visible:
		if not _visible_targets.has(instance_id):
			var target_data = {
				"object": target,
				"position": target_position
			}
			_visible_targets[instance_id] = target_data
			target_visible.emit(target, target_position)
			
			if debug_enabled && Global.debug:
				print_debug("Target became visible: %s" % target.name)
		else:
			# Update the position if needed
			var target_data = _visible_targets[instance_id]
			if target_data["position"] != target_position:
				target_data["position"] = target_position
				target_updated.emit(target, target_position)
	elif _visible_targets.has(instance_id):
		_visible_targets.erase(instance_id)
		target_lost.emit(target)
		
		if debug_enabled && Global.debug:
			print_debug("Target lost visibility: %s" % target.name)
	
	return target_is_visible

func check_visibility_for_targets(targets: Array) -> void:
	for target_data in targets:
		if target_data is Dictionary and target_data.has("object"):
			var target: Node3D = target_data["object"]
			if target is Node3D:
				is_target_visible(target)

func get_visible_targets() -> Array:
	return _visible_targets.values()

func get_target_position(target: Node3D) -> Vector3:
	return _visible_targets.get(target.get_instance_id(), {}).get("position", Vector3.ZERO)

func has_visible_target(target: Node3D) -> bool:
	return _visible_targets.has(target.get_instance_id())

func clear_visible_targets() -> void:
	_visible_targets.clear()

func _update_debug_info() -> void:
	var to_remove: Array = []
	
	for instance_id in _visible_targets:
		var target_data = _visible_targets[instance_id]
		var target: Node3D = target_data["object"]
		
		if is_instance_valid(target):
			print_debug("Visible target: %s | Position: %s" % [target.name, target_data["position"]])
		else:
			to_remove.append(instance_id)
	
	for instance_id in to_remove:
		_visible_targets.erase(instance_id)
