extends Label3D

@onready var parent = get_parent()

func _process(_delta: float) -> void:
	
	if parent && Global.debug:
		var label_data = parent.label
		if label_data:  
			self.text = "%s: %d / %d" % [label_data.name, label_data.current, label_data.max]			
	else: 
		self.text = ""
