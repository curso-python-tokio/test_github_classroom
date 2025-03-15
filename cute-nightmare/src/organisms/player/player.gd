extends CharacterBody3D
class_name Player

# En el script del Character
func _ready():
	var detector = $PowerUpDetector
	detector.power_up_collected.connect(_on_power_up_collected)

func _on_power_up_collected(power_up: Node):
	print("PowerUp recolectado: ", power_up.name)
	# Aquí manejar aumento de estadísticas, efectos, etc.
