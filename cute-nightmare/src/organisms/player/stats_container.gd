extends Node
class_name StatusEffectComponent

# Enumerados para configuración
enum EffectType { INSTANT, OVER_TIME, DURATION }
enum AttributeTarget { HEALTH, STAMINA, HUNGER, THIRST }

# Configuración de efectos
@export_group("Component References")
@export var health_component: HealthComponent
@export var stamina_component: StaminaComponent
@export var hunger_component: HungerComponent
@export var thirst_component: ThirstComponent

@export_group("Effect Configuration")
@export var effects: Array[Dictionary] = []

# Señales
signal effect_applied(effect_name: String)
signal effect_removed(effect_name: String)
signal effect_updated(effect_name: String, remaining_time: float)

var active_effects: Dictionary = {}

func _ready():
	# Inicializar efectos preconfigurados
	for effect in effects:
		register_effect(effect)

func _process(delta):
	# Actualizar efectos con duración
	for effect_name in active_effects.keys():
		var effect_data = active_effects[effect_name]
		
		if effect_data["type"] == EffectType.OVER_TIME:
			effect_data["timer"] += delta
			if effect_data["timer"] >= effect_data["interval"]:
				_apply_effect(effect_data)
				effect_data["timer"] = 0.0
				effect_data["duration"] -= effect_data["interval"]
				
		elif effect_data["type"] == EffectType.DURATION:
			effect_data["remaining_time"] -= delta
			effect_updated.emit(effect_name, effect_data["remaining_time"])
			
			if effect_data["remaining_time"] <= 0:
				remove_effect(effect_name)

func register_effect(effect: Dictionary):
	effects.append(effect)

func apply_effect(effect_name: String):
	var effect = _get_effect_config(effect_name)
	if not effect:
		push_warning("Effect not found: ", effect_name)
		return
	
	match effect["type"]:
		EffectType.INSTANT:
			_apply_effect(effect)
		
		EffectType.OVER_TIME, EffectType.DURATION:
			if active_effects.has(effect_name):
				# Resetear si ya está activo
				remove_effect(effect_name)
			
			var effect_data = effect.duplicate()
			effect_data["remaining_time"] = effect_data["duration"]
			active_effects[effect_name] = effect_data
			
	effect_applied.emit(effect_name)

func remove_effect(effect_name: String):
	if active_effects.erase(effect_name):
		effect_removed.emit(effect_name)
		
		# Aplicar efecto inverso si está configurado
		var effect = _get_effect_config(effect_name)
		if effect.has("revert_on_remove") && effect["revert_on_remove"]:
			_apply_effect(effect, true)

func _get_effect_config(effect_name: String) -> Dictionary:
	for effect in effects:
		if effect["name"] == effect_name:
			return effect
	return {}

func _apply_effect(effect: Dictionary, is_revert: bool = false):
	var multiplier = -1 if is_revert else 1
	var amount = effect["amount"] * multiplier
	var target_component = _get_target_component(effect["target"])
	
	if not target_component:
		return
	
	match effect["operation"]:
		"add":
			_modify_attribute(target_component, amount)
		"multiply":
			_scale_attribute(target_component, amount)

func _get_target_component(target: AttributeTarget) -> Node:
	match target:
		AttributeTarget.HEALTH: return health_component
		AttributeTarget.STAMINA: return stamina_component
		AttributeTarget.HUNGER: return hunger_component
		AttributeTarget.THIRST: return thirst_component
	return null

func _modify_attribute(component: Node, amount: int):
	if component is HealthComponent:
		if amount > 0: component.heal(amount)
		else: component.take_damage(-amount)
	elif component is StaminaComponent:
		if amount > 0: component.recover_stamina(amount)
		else: component.use_stamina(-amount)
	elif component is HungerComponent:
		if amount > 0: component.recover_hunger(amount)
		else: component.use_hunger(-amount)
	elif component is ThirstComponent:
		if amount > 0: component.recover_thirst(amount)
		else: component.use_thirst(-amount)

func _scale_attribute(component: Node, multiplier: float):
	# Para efectos de porcentaje (ej: aumentar salud máxima un 20%)
	if component is HealthComponent:
		component.max_health = int(component.max_health * multiplier)
		component.current_health = min(component.current_health, component.max_health)
	elif component is StaminaComponent:
		component.max_stamina = int(component.max_stamina * multiplier)
		component.current_stamina = min(component.current_stamina, component.max_stamina)
	
