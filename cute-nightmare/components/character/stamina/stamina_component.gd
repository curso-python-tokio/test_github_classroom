extends Node
class_name StaminaComponent

signal stamina_changed(old_value: int, new_value: int)
signal stamina_empty()
signal stamina_depleted(amount: int)
signal stamina_recovered(amount: int)

@export var max_stamina: int = 100

var label = {
	"name" : "STAMINA",
	"current": 0,
	"max": max_stamina
}

var current_stamina: int:
	set(value):
		var old_value = current_stamina
		current_stamina = clamp(value, 0, max_stamina)
		if current_stamina != old_value:
			stamina_changed.emit(old_value, current_stamina)
			if current_stamina <= 0:
				stamina_empty.emit()
		label.current = value
	get:
		return current_stamina

func _ready():
	current_stamina = max_stamina

func use_stamina(amount: int):
	if amount <= 0: return
	current_stamina -= amount
	stamina_depleted.emit(amount)

func recover_stamina(amount: int):
	if amount <= 0: return
	current_stamina += amount
	stamina_recovered.emit(amount)

func reset_stamina():
	current_stamina = max_stamina
