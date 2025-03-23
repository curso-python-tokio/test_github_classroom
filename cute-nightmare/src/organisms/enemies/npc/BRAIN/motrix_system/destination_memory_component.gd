# Componente para recordar y gestionar ubicaciones importantes
class_name DestinationMemoryComponent
extends Node

signal location_remembered(loc_name: String, position: Vector3)
signal location_forgotten(loc_name: String)
signal location_updated(loc_name: String, old_position: Vector3, new_position: Vector3)

@export_category("Configuration")
## Máximo número de ubicaciones a recordar
@export var max_locations: int = 20
## Estructura de datos para almacenar ubicaciones
@export var locations: Dictionary = {}
## Categorías de ubicaciones para organización
@export var location_categories: Dictionary = {
	"navigation": Color.GREEN,
	"interest": Color.YELLOW,
	"danger": Color.RED,
	"resource": Color.BLUE,
	"shelter": Color.PURPLE
}
## Límite de distancia para considerar misma ubicación
@export var same_location_threshold: float = 2.0

@export_category("Priority")
## Prioridad por defecto para nuevas ubicaciones
@export var default_priority: float = 0.5
## Reducir prioridad con el tiempo
@export var decay_priority: bool = true
## Factor de decaimiento de prioridad
@export var priority_decay_rate: float = 0.01
## Intervalo de tiempo para actualizar prioridades (segundos)
@export var priority_update_interval: float = 30.0

@export_category("Debug")
@export var debug_enabled: bool = false
@export var draw_remembered_locations: bool = false

# Variables internas
var _character: Node3D
var _movement_controller: MovementController
var _priority_timer: Timer

func _ready() -> void:
	_setup_timers()

func _process(_delta: float) -> void:
	if draw_remembered_locations:
		_draw_debug_locations()

func _setup_timers() -> void:
	# Timer para actualizar prioridades
	_priority_timer = Timer.new()
	_priority_timer.wait_time = priority_update_interval
	_priority_timer.one_shot = false
	_priority_timer.autostart = decay_priority
	_priority_timer.timeout.connect(_on_priority_timer)
	add_child(_priority_timer)

func initialize(controller: MovementController) -> void:
	_movement_controller = controller
	_character = controller.get_character()

func remember_location(loc_name: String, position: Vector3, 
					category: String = "navigation", priority: float = -1.0,
					metadata: Dictionary = {}) -> void:
	# Usar prioridad por defecto si no se especifica
	if priority < 0:
		priority = default_priority
	
	# Verificar si ya existe una ubicación con el mismo nombre
	if locations.has(loc_name):
		var old_position = locations[loc_name].position
		
		# Actualizar ubicación existente
		locations[loc_name].position = position
		locations[loc_name].last_updated = Time.get_ticks_msec() / 1000.0
		locations[loc_name].priority = priority
		
		# Actualizar metadatos si se proporcionan
		if not metadata.is_empty():
			for key in metadata:
				locations[loc_name].metadata[key] = metadata[key]
		
		# Emitir señal de actualización
		location_updated.emit(loc_name, old_position, position)
		
		if debug_enabled:
			print_debug("Location updated: ", loc_name, " at position: ", position)
	else:
		# Verificar límite de ubicaciones
		if locations.size() >= max_locations:
			_forget_lowest_priority_location()
		
		# Verificar si hay una ubicación existente en la misma posición
		var existing_at_position = _find_location_at_position(position)
		if existing_at_position:
			# Actualizar existente en vez de crear nueva
			var old_name = existing_at_position
			var _old_position = locations[old_name].position
			
			# Conservar prioridad más alta
			var old_priority = locations[old_name].priority
			priority = max(priority, old_priority)
			
			# Crear entrada actualizada
			locations.erase(old_name)
			
			if debug_enabled:
				print_debug("Merging location at position with existing: ", old_name, " -> ", loc_name)
		
		# Crear nueva entrada
		var category_color = location_categories.get(category, Color.WHITE)
		var current_time = Time.get_ticks_msec() / 1000.0
		
		locations[loc_name] = {
			"position": position,
			"category": category,
			"priority": priority,
			"created": current_time,
			"last_updated": current_time,
			"last_visited": 0.0,
			"visit_count": 0,
			"color": category_color,
			"metadata": metadata.duplicate()
		}
		
		# Emitir señal de nueva ubicación
		location_remembered.emit(loc_name, position)
		
		if debug_enabled:
			print_debug("New location remembered: ", loc_name, " at position: ", position)

func forget_location(loc_name: String) -> bool:
	if locations.has(loc_name):
		locations.erase(loc_name)
		location_forgotten.emit(loc_name)
		
		if debug_enabled:
			print_debug("Location forgotten: ", loc_name)
		
		return true
	
	return false

func has_location(loc_name: String) -> bool:
	return locations.has(loc_name)

func get_location(loc_name: String) -> Vector3:
	if locations.has(loc_name):
		return locations[loc_name].position
	
	return Vector3.ZERO

func get_location_data(loc_name: String) -> Dictionary:
	if locations.has(loc_name):
		return locations[loc_name].duplicate()
	
	return {}

func mark_location_visited(loc_name: String) -> void:
	if locations.has(loc_name):
		var current_time = Time.get_ticks_msec() / 1000.0
		locations[loc_name].last_visited = current_time
		locations[loc_name].visit_count += 1

func set_location_priority(loc_name: String, priority: float) -> void:
	if locations.has(loc_name):
		locations[loc_name].priority = clamp(priority, 0.0, 1.0)

func get_nearest_location(position: Vector3, category: String = "") -> Dictionary:
	var nearest_name = ""
	var nearest_distance = 999999.0
	
	for loc_name in locations:
		var loc_data = locations[loc_name]
		
		# Filtrar por categoría si se especifica
		if category != "" and loc_data.category != category:
			continue
		
		var distance = position.distance_to(loc_data.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_name = loc_name
	
	if nearest_name != "":
		return {
			"name": nearest_name,
			"position": locations[nearest_name].position,
			"distance": nearest_distance,
			"data": locations[nearest_name].duplicate()
		}
	
	return {}

func get_locations_by_category(category: String) -> Array:
	var result = []
	
	for loc_name in locations:
		if locations[loc_name].category == category:
			result.append({
				"name": loc_name,
				"position": locations[loc_name].position,
				"data": locations[loc_name].duplicate()
			})
	
	return result

func get_locations_in_radius(position: Vector3, radius: float, category: String = "") -> Array:
	var result = []
	
	for loc_name in locations:
		var loc_data = locations[loc_name]
		
		# Filtrar por categoría si se especifica
		if category != "" and loc_data.category != category:
			continue
		
		var distance = position.distance_to(loc_data.position)
		if distance <= radius:
			result.append({
				"name": loc_name,
				"position": loc_data.position,
				"distance": distance,
				"data": loc_data.duplicate()
			})
	
	return result

func clear_all_locations() -> void:
	var location_names = locations.keys()
	
	for loc_name in location_names:
		forget_location(loc_name)
	
	if debug_enabled:
		print_debug("All locations cleared")

func merge_nearby_locations(threshold: float = -1.0) -> int:
	if threshold < 0:
		threshold = same_location_threshold
	
	var merged_count = 0
	var locations_to_check = locations.keys()
	
	# Comparar cada ubicación con las demás
	while locations_to_check.size() > 0:
		var loc_name = locations_to_check[0]
		locations_to_check.remove_at(0)
		
		if not locations.has(loc_name):
			continue
		
		var loc_position = locations[loc_name].position
		var loc_priority = locations[loc_name].priority
		
		var nearby_locs = []
		
		# Encontrar ubicaciones cercanas
		for other_name in locations_to_check:
			if not locations.has(other_name):
				continue
			
			var other_position = locations[other_name].position
			var distance = loc_position.distance_to(other_position)
			
			if distance <= threshold:
				nearby_locs.append(other_name)
		
		# Fusionar ubicaciones cercanas
		for nearby_name in nearby_locs:
			if not locations.has(nearby_name):
				continue
			
			# Mantener el nombre con mayor prioridad
			var nearby_priority = locations[nearby_name].priority
			var keep_name = loc_name
			var forget_name = nearby_name
			
			if nearby_priority > loc_priority:
				keep_name = nearby_name
				forget_name = loc_name
			
			# Actualizar posición como promedio
			var avg_position = (locations[loc_name].position + locations[nearby_name].position) / 2.0
			remember_location(keep_name, avg_position, 
				locations[keep_name].category, 
				max(loc_priority, nearby_priority),
				locations[keep_name].metadata)
			
			# Olvidar la otra ubicación
			if forget_location(forget_name):
				merged_count += 1
				
				if debug_enabled:
					print_debug("Merged locations: ", forget_name, " into ", keep_name)
			
			# Si olvidamos la ubicación actual, salir del bucle
			if forget_name == loc_name:
				break
	
	return merged_count

func add_location_metadata(loc_name: String, key: String, value: Variant) -> bool:
	if locations.has(loc_name):
		locations[loc_name].metadata[key] = value
		return true
	
	return false

func get_location_metadata(loc_name: String, key: String, default_value: Variant = null) -> Variant:
	if locations.has(loc_name) and locations[loc_name].metadata.has(key):
		return locations[loc_name].metadata[key]
	
	return default_value

func _find_location_at_position(position: Vector3) -> String:
	for loc_name in locations:
		var loc_position = locations[loc_name].position
		var distance = position.distance_to(loc_position)
		
		if distance <= same_location_threshold:
			return loc_name
	
	return ""

func _forget_lowest_priority_location() -> void:
	var lowest_priority = 999.0
	var lowest_name = ""
	
	for loc_name in locations:
		var priority = locations[loc_name].priority
		if priority < lowest_priority:
			lowest_priority = priority
			lowest_name = loc_name
	
	if lowest_name != "":
		forget_location(lowest_name)

func _on_priority_timer() -> void:
	if not decay_priority:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	
	for loc_name in locations:
		var loc_data = locations[loc_name]
		var time_since_update = current_time - loc_data.last_updated
		
		# Reducir prioridad basada en tiempo transcurrido
		if time_since_update > priority_update_interval:
			var decay = priority_decay_rate * (time_since_update / priority_update_interval)
			loc_data.priority = max(0.1, loc_data.priority - decay)
			
			if debug_enabled and decay > 0.01:
				print_debug("Location priority decayed: ", loc_name, " new priority: ", loc_data.priority)

func _draw_debug_locations() -> void:
	if not Engine.is_editor_hint() and not debug_enabled:
		return
	
	for loc_name in locations:
		var loc_data = locations[loc_name]
		var position = loc_data.position
		var color = loc_data.color
		
		# Dibujar esfera en la posición
		DebugDraw.draw_sphere(position, 0.5, color)
		
		# Dibujar texto con el nombre
		var text_pos = position + Vector3(0, 1.5, 0)
		DebugDraw.draw_string_3d(text_pos, loc_name, color)
