extends Node3D
class_name HungerComponent

signal hunger_changed(old_value: int, new_value: int)
signal hunger_empty()
signal hunger_increased(amount: int)
signal hunger_decreased(amount: int)

@export var max_hunger: int = 100
@export var hunger_decay_rate: float = 1.0  # Hambre que se reduce por segundo
@export var health_component: HealthComponent
@export var hunger_damage: int = 5         # Daño por segundo cuando el hambre es 0
@export var damage_interval: float = 1.0   # Intervalo de daño en segundos

var label = {
	"name" : "HUNGER",
	"current": 0,
	"max": max_hunger
}

var current_hunger: int:
	set(value):
		var old_value = current_hunger
		current_hunger = clamp(value, 0, max_hunger)
		if current_hunger != old_value:
			hunger_changed.emit(old_value, current_hunger)
			if current_hunger <= 0:
				hunger_empty.emit()
		label.current = current_hunger
	get:
		return current_hunger

var _hunger_damage_timer: float = 0.0  # Temporizador para el daño continuo

func _ready():
	current_hunger = max_hunger
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_hunger_decay_timeout)
	add_child(timer)

func _process(delta):
	if current_hunger <= 0:
		_hunger_damage_timer += delta
		# Aplica daño cada [damage_interval] segundos
		if _hunger_damage_timer >= damage_interval:
			_apply_hunger_damage()
			_hunger_damage_timer = 0.0
	else:
		_hunger_damage_timer = 0.0  # Reinicia el temporizador si se recupera hambre

func _on_hunger_decay_timeout():
	use_hunger(hunger_decay_rate)

func use_hunger(amount: float):
	if amount <= 0: return
	current_hunger -= int(amount)
	hunger_decreased.emit(int(amount))

func recover_hunger(amount: int):
	if amount <= 0: return
	current_hunger += amount
	hunger_increased.emit(amount)

func reset_hunger():
	current_hunger = max_hunger

func _apply_hunger_damage():
	if health_component:
		health_component.take_damage(hunger_damage)
	else:
		push_warning("HealthComponent no asignado en HungerComponent.")

func get_label():
	return label
