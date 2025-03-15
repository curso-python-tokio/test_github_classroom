extends Node3D
class_name ThirstComponent

signal thirst_changed(old_value: int, new_value: int)
signal thirst_empty()
signal thirst_increased(amount: int)
signal thirst_decreased(amount: int)

@export var max_thirst: int = 100
@export var thirst_decay_rate: float = 1.0  # Sed que se reduce por segundo
@export var health_component: HealthComponent  # Referencia al HealthComponent
@export var thirst_damage: int = 5          # Daño por segundo cuando la sed es 0
@export var damage_interval: float = 1.0    # Intervalo de daño en segundos

var label = {
	"name" : "THIRST",
	"current": 0,
	"max": max_thirst
}

var current_thirst: int:
	set(value):
		var old_value = current_thirst
		current_thirst = clamp(value, 0, max_thirst)
		if current_thirst != old_value:
			thirst_changed.emit(old_value, current_thirst)
			if current_thirst <= 0:
				thirst_empty.emit()
		label.current = current_thirst
	get:
		return current_thirst

var _thirst_damage_timer: float = 0.0  # Temporizador para el daño continuo

func _ready():
	current_thirst = max_thirst
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_thirst_decay_timeout)
	add_child(timer)

func _process(delta):
	if current_thirst <= 0:
		_thirst_damage_timer += delta
		# Aplica daño cada [damage_interval] segundos
		if _thirst_damage_timer >= damage_interval:
			_apply_thirst_damage()
			_thirst_damage_timer = 0.0
	else:
		_thirst_damage_timer = 0.0  # Reinicia si se recupera sed

func _on_thirst_decay_timeout():
	use_thirst(thirst_decay_rate)

func use_thirst(amount: float):
	if amount <= 0: return
	current_thirst -= int(amount)
	thirst_decreased.emit(int(amount))

func recover_thirst(amount: int):
	if amount <= 0: return
	current_thirst += amount
	thirst_increased.emit(amount)

func reset_thirst():
	current_thirst = max_thirst

func _apply_thirst_damage():
	if health_component:
		health_component.take_damage(thirst_damage)
	else:
		push_warning("HealthComponent no asignado en ThirstComponent.")
