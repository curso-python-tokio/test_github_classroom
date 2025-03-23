@tool
extends Node

## Utilidad para dibujar elementos de depuración en el espacio 3D
class_name DebugDraw

## Duración por defecto para los elementos de depuración (segundos)
const DEFAULT_DURATION: float = 0.0  # 0 = persistente hasta el próximo frame

## Nodo raíz para los elementos de depuración
static var _debug_root: Node3D = null

## Flag para habilitar/deshabilitar el dibujado
static var enabled: bool = true

## Diccionario para almacenar elementos persistentes
static var _persistent_elements: Dictionary = {}

## Object pools para reducir la creación/destrucción de nodos
static var _sphere_pool: Array[MeshInstance3D] = []
static var _line_pool: Array[MeshInstance3D] = []
static var _text_pool: Array[Label3D] = []

## Maximum pool size
static var _max_pool_size: int = 50

## Material cache para performance
static var _line_material: StandardMaterial3D = null
static var _sphere_materials: Dictionary = {}  # Cache by color
static var _sphere_meshes: Dictionary = {}     # Cache by radius

## Inicializar el sistema
static func initialize() -> void:
	if _debug_root == null:
		_debug_root = Node3D.new()
		_debug_root.name = "DebugDrawRoot"
		Engine.get_main_loop().root.call_deferred("add_child", _debug_root)
		_initialize_materials()

## Initialize shared materials
static func _initialize_materials() -> void:
	if _line_material == null:
		_line_material = StandardMaterial3D.new()
		_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_line_material.vertex_color_use_as_albedo = true
		_line_material.no_depth_test = true

## Get a sphere mesh from cache or create new one
static func _get_sphere_mesh(radius: float) -> SphereMesh:
	var radius_key = snapped(radius, 0.01)  # Round to reduce unique meshes
	
	if not _sphere_meshes.has(radius_key):
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = radius
		sphere_mesh.height = radius * 2.0
		_sphere_meshes[radius_key] = sphere_mesh
	
	return _sphere_meshes[radius_key]

## Get a material for spheres by color
static func _get_sphere_material(color: Color) -> StandardMaterial3D:
	var color_key = color.to_rgba32()
	
	if not _sphere_materials.has(color_key):
		var material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.no_depth_test = true
		_sphere_materials[color_key] = material
	
	return _sphere_materials[color_key]

## Get a mesh instance from pool or create new one
static func _get_mesh_instance(for_line: bool = false) -> MeshInstance3D:
	var pool = _line_pool if for_line else _sphere_pool
	
	if pool.size() > 0:
		return pool.pop_back()
	
	var mesh_instance = MeshInstance3D.new()
	return mesh_instance

## Get a label from pool or create new one
static func _get_label() -> Label3D:
	if _text_pool.size() > 0:
		return _text_pool.pop_back()
	
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	return label

## Return node to pool when done
static func _return_to_pool(node: Node) -> void:
	if not is_instance_valid(node):
		return
		
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	
	if node is MeshInstance3D:
		if node.mesh is ImmediateMesh:
			if _line_pool.size() < _max_pool_size:
				_line_pool.append(node)
			else:
				node.queue_free()
		else:
			if _sphere_pool.size() < _max_pool_size:
				_sphere_pool.append(node)
			else:
				node.queue_free()
	elif node is Label3D:
		if _text_pool.size() < _max_pool_size:
			_text_pool.append(node)
		else:
			node.queue_free()

## Dibujar una línea 3D
static func draw_line_3d(start: Vector3, end: Vector3, color: Color = Color.WHITE, 
						duration: float = DEFAULT_DURATION, _line_width: float = 1.0) -> void:
	if not enabled or not _debug_root:
		initialize()
		
	if not _debug_root:
		return
		
	var mesh_instance = _get_mesh_instance(true)
	var im: ImmediateMesh
	
	if mesh_instance.mesh == null or not (mesh_instance.mesh is ImmediateMesh):
		im = ImmediateMesh.new()
		mesh_instance.mesh = im
	else:
		im = mesh_instance.mesh as ImmediateMesh
	
	mesh_instance.material_override = _line_material
	
	# Set transform before adding to scene
	var midpoint = (start + end) / 2
	var transform = Transform3D()
	transform.origin = midpoint
	mesh_instance.transform = transform
	
	# Add to scene tree first
	_debug_root.add_child(mesh_instance)
	
	# Configure mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	
	im.surface_set_color(color)
	im.surface_add_vertex(start - midpoint)  # Relative to midpoint
	im.surface_set_color(color)
	im.surface_add_vertex(end - midpoint)    # Relative to midpoint
	
	im.surface_end()
	
	if duration > 0.0001:
		var timer = _debug_root.get_tree().create_timer(duration)
		timer.timeout.connect(func(): 
			if is_instance_valid(mesh_instance):
				_return_to_pool(mesh_instance)
		)

## Dibujar una esfera 3D
static func draw_sphere(pos: Vector3, radius: float = 0.1, 
					color: Color = Color.WHITE, duration: float = DEFAULT_DURATION) -> void:
	if not enabled:
		initialize()
		
	if not _debug_root:
		return
	
	var mesh_instance = _get_mesh_instance(false)
	
	# Configure mesh and material (use cached versions)
	mesh_instance.mesh = _get_sphere_mesh(radius)
	mesh_instance.material_override = _get_sphere_material(color)
	
	# Set transform before adding to scene tree
	var transform = Transform3D()
	transform.origin = pos
	mesh_instance.transform = transform
	
	# Add to scene tree
	_debug_root.add_child(mesh_instance)
	
	if duration > 0.0001:
		var timer = _debug_root.get_tree().create_timer(duration)
		timer.timeout.connect(func(): 
			if is_instance_valid(mesh_instance):
				_return_to_pool(mesh_instance)
		)

## Dibujar texto 3D
static func draw_string_3d(pos: Vector3, text: String, 
						color: Color = Color.WHITE, duration: float = DEFAULT_DURATION,
						scale: float = 1.0) -> void:
	if not enabled:
		initialize()
		
	if not _debug_root:
		return
	
	var label = _get_label()
	label.text = text
	label.font_size = 18
	label.modulate = color
	label.pixel_size = 0.005 * scale
	
	# Set transform before adding to scene tree
	var transform = Transform3D()
	transform.origin = pos
	label.transform = transform
	
	# Add to scene tree
	_debug_root.add_child(label)
	
	if duration > 0.0001:
		var timer = _debug_root.get_tree().create_timer(duration)
		timer.timeout.connect(func(): 
			if is_instance_valid(label):
				_return_to_pool(label)
		)

## Limpiar todos los elementos de depuración
static func clear() -> void:
	if not _debug_root:
		return
		
	for child in _debug_root.get_children():
		_return_to_pool(child)
	
	_persistent_elements.clear()

## Añadir un elemento persistente con ID
static func add_persistent(id: String, 
						draw_function: Callable, 
						params: Array) -> void:
	_persistent_elements[id] = {
		"draw_function": draw_function,
		"params": params
	}
	
	# Dibujar inmediatamente
	draw_function.callv(params)

## Eliminar un elemento persistente
static func remove_persistent(id: String) -> void:
	if _persistent_elements.has(id):
		_persistent_elements.erase(id)

## Actualizar todos los elementos persistentes
static func update_persistent() -> void:
	if not enabled:
		return
		
	# Actualizar cada elemento persistente
	for id in _persistent_elements:
		var element = _persistent_elements[id]
		element.draw_function.callv(element.params)
		
# Static variable for process timing
static var _last_process_time: int = 0
static var _process_interval: int = 500  # Process every 500ms for better performance

func _process(_delta: float) -> void:
	# Skip processing if disabled
	if not enabled or not _debug_root:
		return
		
	# Reduce update frequency for better performance
	var current_time = Time.get_ticks_msec()
	if current_time - _last_process_time < _process_interval:
		return
	
	_last_process_time = current_time
	
	# Clear non-pooled nodes
	var children_to_remove = []
	for child in _debug_root.get_children():
		children_to_remove.append(child)
	
	# Remove children
	for child in children_to_remove:
		_return_to_pool(child)
	
	# Redraw persistent elements
	update_persistent()
