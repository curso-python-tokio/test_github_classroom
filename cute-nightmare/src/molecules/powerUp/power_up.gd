extends Area3D
class_name PowerUp

# -----------------------------
# Señales
# -----------------------------
signal collected(collector: Node)
signal collection_started()

# -----------------------------
# Configuración General
# -----------------------------
@export var rotation_speed: float = 2.0
@export var collection_duration: float = 0.3
@export var auto_collect: bool = true

# -----------------------------
# Nodos y Componentes Visuales
# -----------------------------
@export var mesh: MeshInstance3D
@export var collection_effect: GPUParticles3D
@export var pickup_sound: AudioStreamPlayer3D

# -----------------------------
# Configuración de Efectos Configurables
# -----------------------------
@export_group("Efectos Configurables")
@export var add_health: int = 0
@export var add_stamina: int = 0
@export var add_hunger: int = 0
@export var add_thirst: int = 0

# -----------------------------
# Configuración de Feedback Visual
# -----------------------------
@export_group("Feedback Visual")
@export var active_material: Material
@export var inactive_material: Material
@export var collect_effect: GPUParticles3D

# -----------------------------
# Configuración de Reactivación y Uso
# -----------------------------
@export var one_time_use: bool = true  # Si es true, se elimina después de usar
@export var respawn_time: float = 5.0    # Tiempo para reactivarse (si no es one_time_use)

# -----------------------------
# Referencias a Componentes Externos
# -----------------------------
@export_group("Componentes")
@export var status_component_path: NodePath  # Ruta a un componente (por ejemplo, HealthComponent) del recolector (opcional)

# -----------------------------
# Variables Internas y Nodos
# -----------------------------
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var timer: Timer = get_node_or_null("Timer")

var is_collected: bool = false
var is_active: bool = true

# -----------------------------
# Inicialización
# -----------------------------
func _ready() -> void:
	# Crear el Timer si no existe
	if not timer:
		timer = Timer.new()
		timer.name = "Timer"
		timer.one_shot = true
		timer.wait_time = respawn_time
		add_child(timer)
	
	timer.timeout.connect(_on_respawn_timer_timeout)
	
	# Conectar la señal de detección para colección automática
	if auto_collect:
		body_entered.connect(_on_body_entered)
	# Verificar que exista el CollisionShape3D
	if not collision_shape:
		push_warning("PowerUp necesita un CollisionShape3D como hijo.")
	
	_update_visual_state()

# -----------------------------
# Proceso Visual
# -----------------------------
func _process(delta: float) -> void:
	if not is_collected:
		# Rotación continua para efecto visual
		rotate_y(rotation_speed * delta)

# -----------------------------
# Detección y Recolección
# -----------------------------
func _on_body_entered(body: Node) -> void:
	# Se asume que el recolector está en el grupo "Player"
	if body.is_in_group("Player"):
		collect(body)


func collect(collector: Node) -> void:
	if is_collected:
		return
	
	is_collected = true
	collection_started.emit()
	
	# Desactivar colisiones
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Efectos visuales y de sonido
	if collection_effect:
		collection_effect.emitting = true
	if pickup_sound:
		pickup_sound.play()
	
	# Buscar componentes automáticamente
	var health_component = _find_component(collector, "HealthComponent")
	var stamina_component = _find_component(collector, "StaminaComponent")
	var hunger_component = _find_component(collector, "HungerComponent")
	var thirst_component = _find_component(collector, "ThirstComponent")
	
	# Aplicar efectos a los componentes encontrados
	if add_health != 0 && health_component && health_component.has_method("heal"):
		health_component.heal(add_health)
	
	if add_stamina != 0 && stamina_component && stamina_component.has_method("recover_stamina"):
		stamina_component.recover_stamina(add_stamina)
	
	if add_hunger != 0 && hunger_component && hunger_component.has_method("recover_hunger"):
		hunger_component.recover_hunger(add_hunger)
	
	if add_thirst != 0 && thirst_component && thirst_component.has_method("recover_thirst"):
		thirst_component.recover_thirst(add_thirst)
	
	# Animación de recolección
	var tween = create_tween()
	tween.parallel().tween_property(mesh, "scale", Vector3.ZERO, collection_duration)
	tween.parallel().tween_property(mesh, "position:y", mesh.position.y + 0.5, collection_duration)
	
	await tween.finished
	collected.emit(collector)
	
	# Gestión de estado post-recolección
	if one_time_use:
		queue_free()
	else:
		disable_trigger()

func _find_component(collector: Node, component_class: String) -> Node:
	# Busca recursivamente el primer nodo con la clase especificada
	var components = collector.find_children("*", component_class, true, false)
	return components[0] if components.size() > 0 else null


# Permite disparar la colección de forma manual
func trigger_collection(collector: Node) -> void:
	collect(collector)

# -----------------------------
# Feedback y Estado Visual
# -----------------------------
func _play_feedback() -> void:
	if collect_effect:
		collect_effect.emitting = true
	var tween = create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE * 1.2, 0.1)
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.1)

func disable_trigger() -> void:
	is_active = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	_update_visual_state()
	if respawn_time > 0:
		timer.start(respawn_time)

func enable_trigger() -> void:
	is_active = true
	if collision_shape:
		collision_shape.disabled = false
	_update_visual_state()

func _update_visual_state() -> void:
	if mesh:
		if is_active and active_material:
			mesh.material_override = active_material
		elif inactive_material:
			mesh.material_override = inactive_material

func _on_respawn_timer_timeout() -> void:
	enable_trigger()

# Método para aplicar efectos manualmente (si se desea disparar la colección desde otro script)
func apply_effects_manually(target: Node) -> void:
	if not is_active:
		return
	_on_body_entered(target.get_parent())

func reset_trigger() -> void:
	enable_trigger()
	timer.stop()
