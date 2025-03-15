extends CheckButton

@export var bus_name: String
var bus_index: int

func _ready() -> void:
	bus_index = AudioServer.get_bus_index(bus_name)
	
func _toggled(_toggled_on: bool) -> void:
	AudioServer.set_bus_mute(bus_index, not AudioServer.is_bus_mute(bus_index))
	
