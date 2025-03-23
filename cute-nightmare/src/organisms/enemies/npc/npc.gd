# In your character script
@onready var brain_system = $BrainSystem
@onready var vision_system = $VisionSystem
@onready var motrix_system = $MotrixSystem

func _ready():
	# Connect systems
	brain_system.vision_system = vision_system
	brain_system.motrix_system = motrix_system
	
	# Enable autonomous movement
	brain_system.autonomous_enabled = true
	
	# Start in wander state
	brain_system.set_state("wander")
