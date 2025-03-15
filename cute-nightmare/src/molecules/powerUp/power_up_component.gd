extends Node3D
class_name PowerUpComponent

# Configuraciones para efectos. Puedes asignar estos valores desde el editor.
@export var heal_amount: int = 0
@export var stamina_boost: int = 0
@export var hunger_recovery: int = 0
@export var thirst_recovery: int = 0

func apply_effects(target: Node) -> void:
	# Aplica curación si se ha configurado y el target tiene HealthComponent o método heal
	if heal_amount > 0 and target.has_method("heal"):
		target.heal(heal_amount)
		
	# Aplica aumento de stamina (suponiendo que usar un valor negativo incremente la stamina)
	if stamina_boost > 0 and target.has_method("use_stamina"):
		# Aquí podrías definir un método específico para recuperar stamina en lugar de "use_stamina"
		if target.has_method("recover_stamina"):
			target.recover_stamina(stamina_boost)
			
	# Aplica recuperación de hambre
	if hunger_recovery > 0 and target.has_method("recover_hunger"):
		target.recover_hunger(hunger_recovery)
		
	# Aplica recuperación de sed
	if thirst_recovery > 0 and target.has_method("recover_thirst"):
		target.recover_thirst(thirst_recovery)
