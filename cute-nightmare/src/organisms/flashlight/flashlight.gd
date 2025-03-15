extends Node3D
class_name BatteryComponent

# Señales
signal battery_changed(old_value: int, new_value: int)
signal battery_empty()
signal battery_increased(amount: int)
signal battery_decreased(amount: int)

# Configuración exportada
@export var max_battery: int = 100
@export var battery_decay_rate: float = 2.0  # Batería consumida por segundo
@export var low_battery_threshold: int = 20  # Nivel para efectos de batería baja

# Referencias
@onready var spotlight: SpotLight3D = $CSGCylinder3D/SpotLight3D

# Estado interno
var current_battery: int:
	set(value):
		var old_value = current_battery
		current_battery = clamp(value, 0, max_battery)
		
		battery_changed.emit(old_value, current_battery)
		if current_battery < old_value: battery_decreased.emit(old_value - current_battery)
		if current_battery > old_value: battery_increased.emit(current_battery - old_value)
		
		if current_battery <= 0:
			battery_empty.emit()
			turn_off()
		
		_update_light()
		label.current = current_battery
	get:
		return current_battery

var is_active: bool = true
var _battery_decay_timer: Timer

var label = {
	"name" : "FLASHLIGHT_BATTERY - Press F",
	"current": 0,
	"max": max_battery
}

func _ready():
	current_battery = max_battery
	_setup_decay_timer()
	_update_light()
	
func _input(event):  
	if event.is_action_pressed("toggle_flashlight"):
		toggle()

func _setup_decay_timer():
	_battery_decay_timer = Timer.new()
	_battery_decay_timer.wait_time = 1.0
	_battery_decay_timer.autostart = true
	_battery_decay_timer.timeout.connect(_on_battery_decay)
	add_child(_battery_decay_timer)

func _on_battery_decay():
	if is_active and current_battery > 0:
		current_battery -= int(battery_decay_rate)

func _update_light():
	spotlight.visible = is_active && current_battery > 0
	spotlight.light_energy = clamp(current_battery / float(max_battery), 0.1, 1.0)

# API pública
func toggle():
	if current_battery > 0:
		is_active = !is_active
		_update_light()

func turn_off():
	if is_active:
		is_active = false
		_update_light()

func recharge(amount: int):
	current_battery += amount
	if current_battery > 0 && !is_active:
		toggle()

func get_battery_percent() -> float:
	return current_battery / float(max_battery)

func has_low_battery() -> bool:
	return current_battery <= low_battery_threshold
