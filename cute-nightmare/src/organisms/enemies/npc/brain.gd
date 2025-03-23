extends Node3D
class_name BRAIN
# In your character script
@onready var brain_system = $BrainSystem
@onready var vision_system = $VisionSystem
@onready var motrix_system = $MotrixSystem

@export_category("Debug")
@export var debug_enabled: bool = false

# In your NPC controller script
func _ready():
	# Initialize the systems
	setup_autonomous_behavior()
	
func setup_autonomous_behavior():
	# Get references to all systems
	var vision = $VisionSystem
	var motrix = $MotrixSystem
	var brain = $BrainSystem
	var state_manager = $BrainSystem/AIStateManager
	
	# Ensure all required components exist
	if not vision or not motrix or not brain or not state_manager:
		print("ERROR: Missing required systems!")
		return
	
	# Connect systems
	brain.vision_system = vision
	brain.motrix_system = motrix
	brain.state_manager = state_manager
	
	# Make sure states are assigned in state_manager
	
	# Enable autonomous movement
	brain.autonomous_enabled = true
	brain.default_state = "idle"
	
	if debug_enabled:
		print_debug("NPC autonomous behavior initialized!")
