extends TextureProgressBar

@export var stat_component: Node3D:
	set(new_component):
		if stat_component != null:
			disconnect_signals()
		stat_component = new_component
		connect_signals()
		update_bar()

@export var stat_name: String = "Stat"
@export var show_label: bool = true

var label_node: Label

func _ready():
	label_node = Label.new()
	label_node.name = "StatLabel"
	add_child(label_node)
	update_label()
	update_bar()

func connect_signals():
	if stat_component == null:
		return
	if stat_component.has_signal("health_changed"):
		stat_component.health_changed.connect(on_stat_changed)
	elif stat_component.has_signal("stamina_changed"):
		stat_component.stamina_changed.connect(on_stat_changed)
	elif stat_component.has_signal("hunger_changed"):
		stat_component.hunger_changed.connect(on_stat_changed)
	elif stat_component.has_signal("thirst_changed"):
		stat_component.thirst_changed.connect(on_stat_changed)
	elif stat_component.has_signal("battery_changed"):
		stat_component.battery_changed.connect(on_stat_changed)

func disconnect_signals():
	if stat_component == null:
		return
	if stat_component.has_signal("health_changed"):
		stat_component.health_changed.disconnect(on_stat_changed)
	elif stat_component.has_signal("stamina_changed"):
		stat_component.stamina_changed.disconnect(on_stat_changed)
	elif stat_component.has_signal("hunger_changed"):
		stat_component.hunger_changed.disconnect(on_stat_changed)
	elif stat_component.has_signal("thirst_changed"):
		stat_component.thirst_changed.disconnect(on_stat_changed)
	elif stat_component.has_signal("battery_changed"):
		stat_component.battery_changed.disconnect(on_stat_changed)

func on_stat_changed(_old_value: int, _new_value: int):
	update_bar()

func update_bar():
	if stat_component == null:
		return
	if stat_component.has_method("get_label"):
		var stat_data = stat_component.get_label()
		max_value = stat_data.max
		value = stat_data.current
		self.max_value = max_value
		self.value = value
	else:
		push_warning("Componente de estado no tiene el método 'get_label'.")

func update_label():
	if label_node:
		if show_label:
			label_node.text = "%s: %d/%d" % [stat_name, value, max_value]
		else:
			label_node.text = ""
