extends Node
class_name HealthComponent

signal health_changed(old_value: int, new_value: int)
signal health_empty()
signal damaged(amount: int)
signal healed(amount: int)

@export var max_health: int = 100

var label = {
	"name" : "HEALTH",
	"current": 0,
	"max": max_health
}


var current_health: int:
	set(value):
		var old_value = current_health
		current_health = clamp(value, 0, max_health)
		if current_health != old_value:
			health_changed.emit(old_value, current_health)
			if current_health <= 0:
				health_empty.emit()
		label.current = value
	get:
		return current_health

func _ready():
	current_health = max_health
	

func take_damage(amount: int):
	if amount <= 0: return
	current_health -= amount
	damaged.emit(amount)

func heal(amount: int):
	if amount <= 0: return
	current_health += amount
	healed.emit(amount)

func reset_health():
	current_health = max_health
