extends Area3D
class_name Area3DPowerUpDetector

# Configuración
@export var power_up_mask: int = 2  # Capa 2 por defecto para power-ups
@onready var detection_shape: CollisionShape3D = $CollisionShape3D

# Señales
signal power_up_collected(power_up: Node)
signal power_up_entered(power_up: Node)
signal power_up_exited(power_up: Node)

func _ready():

	# Configurar máscaras de colisión
	collision_mask = power_up_mask
	collision_layer = 0  # No somos detectables por otros
	
	# Conectar señales
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _create_default_collision_shape():
	# Crear forma esférica por defecto
	var new_shape = CollisionShape3D.new()
	new_shape.shape = SphereShape3D.new()
	new_shape.name = "DefaultDetectionShape"
	add_child(new_shape)
	detection_shape = new_shape

func _on_body_entered(body: Node):
	_handle_power_up(body, true)
	if Global.debug:
		print("Player Power Up: body entered")

func _on_area_entered(area: Area3D):
	_handle_power_up(area, true)
	if Global.debug:
		print("Player Power Up: area entered")

func _on_body_exited(body: Node):
	_handle_power_up(body, false)
	if Global.debug:
		print("Player Power Up: body exited")
		
func _on_area_exited(area: Area3D):
	_handle_power_up(area, false)
	if Global.debug:
		print("Player Power Up: area exited")
		
func _handle_power_up(node: Node, entered: bool):
	if node.is_in_group("power_up"):
		if entered:
			power_up_entered.emit(node)
			_collect_power_up(node)
		else:
			power_up_exited.emit(node)
	

func _collect_power_up(power_up: Node):
	power_up_collected.emit(power_up)
	
	# Lógica básica de recolección (personalizar según necesidades)
	if power_up.has_method("collect"):
		power_up.call("collect", get_parent())  # Pasar el character como parámetro
