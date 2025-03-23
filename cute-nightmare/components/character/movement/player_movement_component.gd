extends Node3D
class_name MovementComponent

@export var max_speed: float = 5.0
@export var acceleration: float = 15.0
@export var rotation_speed: float = 8.0
@export var stopping_distance: float = 0.2
@export var camera: Camera3D
@export var controlled_body: CharacterBody3D
@export var rotation_pivot: Node3D  # Armature/Mesh para rotación

# Parámetros de gravedad
@export var gravity_enabled: bool = true
@export var gravity_strength: float = 9.8
@export var terminal_velocity: float = 50.0

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

var target_position: Vector3
var is_moving: bool = false
var current_speed: float = 0.0
var vertical_velocity: float = 0.0
var last_good_position: Vector3 = Vector3.ZERO

func _ready():
	# Verificaciones básicas
	assert(controlled_body != null, "Asignar CharacterBody3D en el editor")
	assert(rotation_pivot != null, "Asignar nodo de rotación en el editor")
	
	# Configuración del agente de navegación
	if navigation_agent:
		navigation_agent.path_desired_distance = 0.5
		navigation_agent.target_desired_distance = stopping_distance
		navigation_agent.max_speed = max_speed
		# Importante: usar avoidance puede causar problemas con la malla de navegación
		navigation_agent.avoidance_enabled = false
	
	# Guardar posición inicial como segura
	last_good_position = controlled_body.global_position
	
	# IMPORTANTE: Corrección del escalado para JoltPhysics
	# Esta corrección debe aplicarse en una función _enter_tree() o similar en el nodo principal
	# NO es recomendable hacerlo aquí, pero como solución temporal puede funcionar
	if controlled_body:
		# Aseguramos que el CharacterBody3D tenga escala uniforme
		var avg_scale = (controlled_body.scale.x + controlled_body.scale.y + controlled_body.scale.z) / 3.0
		controlled_body.scale = Vector3(avg_scale, avg_scale, avg_scale)
		
		# Recursivamente uniformamos escalas de hijos
		_normalize_scales_recursive(controlled_body)

# Función recursiva para normalizar escalas
func _normalize_scales_recursive(node):
	for child in node.get_children():
		if child is CollisionShape3D:
			var avg_scale = (child.scale.x + child.scale.y + child.scale.z) / 3.0
			child.scale = Vector3(avg_scale, avg_scale, avg_scale)
		_normalize_scales_recursive(child)

func _physics_process(delta):
	# PASO 1: Aplicamos gravedad manual
	if gravity_enabled:
		if controlled_body.is_on_floor():
			vertical_velocity = -0.1  # Pequeña fuerza hacia abajo
		else:
			vertical_velocity = clamp(vertical_velocity - gravity_strength * delta, -terminal_velocity, terminal_velocity)
	
	# PASO 2: Manejo de movimiento básico 
	if is_moving and navigation_agent:
		if navigation_agent.is_navigation_finished():
			# Llegamos al destino
			controlled_body.velocity.x = 0
			controlled_body.velocity.z = 0
			is_moving = false
		else:
			# Obtenemos siguiente punto (con manejo de errores)
			var target
			if navigation_agent.get_target_position() != Vector3.ZERO:
				target = navigation_agent.get_next_path_position()
			else:
				target = target_position
				
			# Calculamos dirección SOLO en plano XZ
			var direction = Vector3(
				target.x - controlled_body.global_position.x,
				0, 
				target.z - controlled_body.global_position.z
			)
			
			# Verificamos que la dirección no sea cero antes de normalizar
			if direction.length_squared() > 0.001:
				direction = direction.normalized()
			else:
				direction = Vector3.FORWARD  # Dirección predeterminada
			
			# Calculamos velocidad con aceleración suave
			current_speed = move_toward(current_speed, max_speed, acceleration * delta)
			
			# Aplicamos velocidad horizontal
			controlled_body.velocity.x = direction.x * current_speed
			controlled_body.velocity.z = direction.z * current_speed
			
			# Actualizamos rotación
			_update_simple_rotation(delta, direction)
	else:
		# Si no nos estamos moviendo, detenemos velocidad horizontal
		controlled_body.velocity.x = 0
		controlled_body.velocity.z = 0
	
	# PASO 3: Aplicamos gravedad
	controlled_body.velocity.y = vertical_velocity
	
	# PASO FINAL: Mover el personaje con el método integrado
	var previous_position = controlled_body.global_position
	controlled_body.move_and_slide()
	
	# Guardamos posición buena si nos movimos con éxito
	if controlled_body.global_position.distance_to(previous_position) > 0.01:
		last_good_position = controlled_body.global_position

# Versión simplificada de la rotación
func _update_simple_rotation(delta, direction):
	if direction.length_squared() > 0.01:
		var target_angle = atan2(direction.x, direction.z)
		rotation_pivot.rotation.y = lerp_angle(
			rotation_pivot.rotation.y,
			target_angle,
			rotation_speed * delta
		)

# Manejador de input simplificado con mejor manejo de errores
func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = _get_simple_mouse_position()
		if mouse_pos != Vector3.ZERO:
			set_target_position(mouse_pos)

# Obtener posición del mouse en Y=0
func _get_simple_mouse_position() -> Vector3:
	if !camera:
		return Vector3.ZERO
	
	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	
	# Plano simple en Y=0
	var plane = Plane(Vector3.UP, 0)
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	
	var intersection = plane.intersects_ray(from, dir * 1000.0)
	return intersection if intersection else Vector3.ZERO

# Función para establecer destino con mejor manejo de errores
func set_target_position(custom_position: Vector3):
	if navigation_agent and custom_position != Vector3.ZERO:
		target_position = custom_position
		
		# Ajustamos Y al nivel del personaje para evitar problemas de navegación
		var safe_position = custom_position
		safe_position.y = controlled_body.global_position.y
		
		# Configuramos la navegación
		navigation_agent.target_position = safe_position
		is_moving = true

# Función simple para saltar
func jump(jump_force: float = 10.0):
	if controlled_body.is_on_floor():
		vertical_velocity = jump_force

# Función de emergencia para salir de situaciones atascadas
func teleport_to_safe_position():
	if last_good_position != Vector3.ZERO:
		controlled_body.global_position = last_good_position
		vertical_velocity = 0.0
