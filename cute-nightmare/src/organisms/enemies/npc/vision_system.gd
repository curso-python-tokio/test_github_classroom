extends Node3D
class_name VisionSystem

@onready var field_of_view: FieldOfViewComponent = $FieldOfViewComponent
@onready var raycast: RaycastComponent = $RaycastComponet

var current_target: Node3D = null
var last_known_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Conectar señales del FieldOfViewComponent
	field_of_view.target_detected.connect(_on_target_detected)
	field_of_view.target_lost.connect(_on_target_lost)
	field_of_view.target_updated.connect(_on_target_updated)
	
	# Conectar señales del RaycastComponent
	raycast.target_visible.connect(_on_target_visible)
	raycast.target_lost.connect(_on_target_lost_visibility)
	raycast.target_updated.connect(_on_target_visibility_updated)

func _physics_process(delta: float) -> void:
	# Verificar la visibilidad de los objetivos detectados por el campo de visión
	var detected_targets = field_of_view.get_detected_targets()
	raycast.check_visibility_for_targets(detected_targets)

# Callbacks para FieldOfViewComponent
func _on_target_detected(target: Node3D, position: Vector3) -> void:
	print("Target detected: %s" % target.name)
	
	# Verificar si es un objetivo válido para este animal
	if _is_valid_target(target):
		# Verificar si es visible con el raycast
		raycast.is_target_visible(target)

func _on_target_lost(target: Node3D) -> void:
	print("Target lost from field of view: %s" % target.name)
	
	# Si el objetivo que se perdió es el objetivo actual, cambiamos de estado
	if target == current_target:
		# Si sabemos la última posición, podemos investigar
		last_known_position = field_of_view.get_target_position(target)

func _on_target_updated(target: Node3D, new_position: Vector3) -> void:
	# El objetivo se movió, actualizamos su posición
	if target == current_target:
		last_known_position = new_position

# Callbacks para RaycastComponent
func _on_target_visible(target: Node3D, position: Vector3) -> void:
	print("Target visible: %s" % target.name)
	
	# Si es un objetivo válido, lo perseguimos o huimos
	if _is_valid_target(target):
		current_target = target
		last_known_position = position


func _on_target_lost_visibility(target: Node3D) -> void:
	pass
	

func _on_target_visibility_updated(target: Node3D, position: Vector3) -> void:
	# El objetivo visible se movió
	if target == current_target:
		last_known_position = position

func _is_valid_target(target: Node3D) -> bool:
	# Lógica para determinar si un objetivo es relevante
	# Por ejemplo, verificar si es comida, presa o depredador
	return true  # Implementar según tus necesidades
