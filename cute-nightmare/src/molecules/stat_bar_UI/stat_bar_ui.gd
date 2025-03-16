extends Control

# QUESIIIIII ALCI QUE ESTA NO ES LA MEJOR MANEEEEEEERA QUE LO SE PERO NO RECUERDO LA OTRA YA LO BUSCAREEEEEEEEEEE
@onready var health_component = get_node("../../Node3D/Player/StatusContainer/HealthComponent")
@onready var stamina_component = get_node("../../Node3D/Player/StatusContainer/StaminaComponent")
@onready var hunger_component = get_node("../../Node3D/Player/StatusContainer/HungerComponent")
@onready var thirst_component = get_node("../../Node3D/Player/StatusContainer/ThirstComponent")
@onready var battery_component = get_node("../../Node3D/Player/Skin/Armature/Flashlight")

@onready var health_stat_bar = $VBoxLeft2/HealthBar
@onready var stamina_stat_bar = $VBoxLeft2/StaminaBar
@onready var hunger_stat_bar = $VBoxRight/HungerBar
@onready var thirst_stat_bar = $VBoxRight/ThirstBar
@onready var battery_stat_bar = $VBoxRight/BatteryBar

func _ready():
	if health_component:
		health_stat_bar.stat_component = health_component
		health_stat_bar.update_bar()
	else:
		print("Health Component no encontrado.")

	if stamina_component:
		stamina_stat_bar.stat_component = stamina_component
		stamina_stat_bar.update_bar()
	else:
		print("Stamina Component no encontrado.")

	if hunger_component:
		hunger_stat_bar.stat_component = hunger_component
		hunger_stat_bar.update_bar()
	else:
		print("Hunger Component no encontrado.")

	if thirst_component:
		thirst_stat_bar.stat_component = thirst_component
		thirst_stat_bar.update_bar()
	else:
		print("Thirst Component no encontrado.")
	
	if battery_component:
		battery_stat_bar.stat_component = battery_component
		battery_stat_bar.update_bar()
	else:
		print("Battery Component no encontrado.")
