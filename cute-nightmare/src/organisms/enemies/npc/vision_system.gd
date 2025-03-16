# Facade para el sistema de visión completo
class_name VisionSystem
extends Node3D

signal target_detected(target: Node3D, position: Vector3)
signal target_lost(target: Node3D)
signal target_remembered(target: Node3D, memory_data: Dictionary)
signal target_forgotten(target: Node3D)
signal vision_state_changed(old_state: int, new_state: int)
signal eye_damage_changed(old_value: float, new_value: float)
signal blink_started()
signal blink_ended()

@export_category("Vision Components")
## Manejo de estados de visión
@export var state_manager: VisionStateManager
## Controlador de parpadeo
@export var blink_controller: BlinkController
## Controlador de daño ocular
@export var eye_damage_controller: EyeDamageController
## Componente de campo de visión
@export var fov_component: FieldOfViewComponent
## Componente de raycast para verificar línea de visión
@export var raycast_component: RaycastComponent
## Detector de luz
@export var light_detector: PixelLightDetector
## Componente de reconocimiento de objetivos
@export var target_recognition: TargetRecognitionComponent
## Componente de memoria visual
@export var memory_vision: MemoryVisionComponent
## Modificador de percepción visual
@export var perception_modifier: VisionPerceptionModifier

@export_category("Configuration")
## Gestionar automáticamente estados visuales basados en iluminación
@export var auto_manage_light_states: bool = true
## Usar memoria al procesar objetivos
@export var use_memory: bool = true

@export_category("Debug")
## Mostrar información de depuración
@export var debug_enabled: bool = false

func _ready() -> void:
	# Inicializar componentes en el orden correcto
	_initialize_components()
	# Conectar señales
	_connect_signals()

func _initialize_components() -> void:
	# Inicializar componentes en orden de dependencia
	
	# Primero inicializar el state manager (central)
	if state_manager:
		state_manager.initialize(self)
	
	# Inicializar el controlador de daño
	if eye_damage_controller:
		eye_damage_controller.initialize(self, state_manager)
	
	# Inicializar el controlador de parpadeo
	if blink_controller:
		blink_controller.initialize(state_manager)
	
	# Inicializar componentes de reconocimiento de targets
	if target_recognition:
		# Asegurar que tiene referencias a sus componentes dependientes
		if not target_recognition.fov_component and fov_component:
			target_recognition.fov_component = fov_component
		
		if not target_recognition.raycast_component and raycast_component:
			target_recognition.raycast_component = raycast_component
		
		if not target_recognition.light_detector and light_detector:
			target_recognition.light_detector = light_detector
	
	# Inicializar componente de memoria
	if memory_vision:
		if not memory_vision.target_recognition and target_recognition:
			memory_vision.target_recognition = target_recognition
	
	# Inicializar modificador de percepción
	if perception_modifier:
		if not perception_modifier.target_recognition and target_recognition:
			perception_modifier.target_recognition = target_recognition
		
		perception_modifier.initialize(state_manager, eye_damage_controller, blink_controller)

func _connect_signals() -> void:
	# Conectar señales del state manager
	if state_manager:
		if not state_manager.state_changed.is_connected(self._on_vision_state_changed):
			state_manager.state_changed.connect(self._on_vision_state_changed)
	
	# Conectar señales del controlador de daño
	if eye_damage_controller:
		if not eye_damage_controller.damage_changed.is_connected(self._on_eye_damage_changed):
			eye_damage_controller.damage_changed.connect(self._on_eye_damage_changed)
	
	# Conectar señales del controlador de parpadeo
	if blink_controller:
		if not blink_controller.blink_started.is_connected(self._on_blink_started):
			blink_controller.blink_started.connect(self._on_blink_started)
		
		if not blink_controller.blink_ended.is_connected(self._on_blink_ended):
			blink_controller.blink_ended.connect(self._on_blink_ended)
	
	# Conectar señales del detector de luz
	if light_detector and auto_manage_light_states:
		if not light_detector.illumination_changed.is_connected(self._on_illumination_changed):
			light_detector.illumination_changed.connect(self._on_illumination_changed)
	
	# Conectar señales del target recognition
	if target_recognition:
		if not target_recognition.target_recognized.is_connected(self._on_target_recognized):
			target_recognition.target_recognized.connect(self._on_target_recognized)
		
		if not target_recognition.target_lost.is_connected(self._on_target_lost):
			target_recognition.target_lost.connect(self._on_target_lost)
	
	# Conectar señales del memory vision
	if memory_vision:
		if not memory_vision.target_remembered.is_connected(self._on_target_remembered):
			memory_vision.target_remembered.connect(self._on_target_remembered)
		
		if not memory_vision.target_forgotten.is_connected(self._on_target_forgotten):
			memory_vision.target_forgotten.connect(self._on_target_forgotten)

func _physics_process(_delta: float) -> void:
	# Procesar visión y memoria en cada frame físico
	if target_recognition and memory_vision and use_memory:
		# Actualizar memoria con objetivos reconocidos
		for target in target_recognition.get_recognized_targets():
			var state = target_recognition.get_recognition_state(target)
			if state.has("position"):
				memory_vision.remember_target(target, state.position, true)

func _on_vision_state_changed(old_state: int, new_state: int) -> void:
	# Re-emitir la señal
	vision_state_changed.emit(old_state, new_state)
	
	if debug_enabled:
		print_debug("VisionSystem: Vision state changed: ", old_state, " -> ", new_state)

func _on_eye_damage_changed(old_value: float, new_value: float) -> void:
	# Re-emitir la señal
	eye_damage_changed.emit(old_value, new_value)
	
	if debug_enabled:
		print_debug("VisionSystem: Eye damage changed: ", old_value, " -> ", new_value)

func _on_blink_started() -> void:
	# Re-emitir la señal
	blink_started.emit()
	
	if debug_enabled:
		print_debug("VisionSystem: Blink started")

func _on_blink_ended() -> void:
	# Re-emitir la señal
	blink_ended.emit()
	
	if debug_enabled:
		print_debug("VisionSystem: Blink ended")

func _on_illumination_changed(_is_lit: bool, intensity: float) -> void:
	if auto_manage_light_states and state_manager:
		# Gestionar transiciones de estado basadas en niveles de luz
		var current_light_level = light_detector.get_light_intensity()
		var old_level = current_light_level
		
		# Actualizar el state manager con el cambio de iluminación
		state_manager.react_to_light_change(intensity, old_level)
		
		if debug_enabled:
			print_debug("VisionSystem: Light level changed: ", old_level, " -> ", intensity)

func _on_target_recognized(target: Node3D, confidence: float) -> void:
	var target_position = Vector3.ZERO
	
	if target_recognition:
		var state = target_recognition.get_recognition_state(target)
		if state.has("position"):
			target_position = state.position
	
	# Re-emitir la señal con posición incluida
	target_detected.emit(target, target_position)
	
	if debug_enabled:
		print_debug("VisionSystem: Target detected: ", target.name, " (confidence: ", confidence, ")")

func _on_target_lost(target: Node3D) -> void:
	# Re-emitir la señal
	target_lost.emit(target)
	
	if debug_enabled:
		print_debug("VisionSystem: Target lost: ", target.name)

func _on_target_remembered(target: Node3D, memory_data: Dictionary) -> void:
	# Re-emitir la señal
	target_remembered.emit(target, memory_data)
	
	if debug_enabled:
		print_debug("VisionSystem: Target remembered: ", target.name)

func _on_target_forgotten(target: Node3D) -> void:
	# Re-emitir la señal
	target_forgotten.emit(target)
	
	if debug_enabled:
		print_debug("VisionSystem: Target forgotten: ", target.name)

# API pública para interactuar con el sistema de visión

## Establecer estado de visión (con duración opcional)
func set_vision_state(state: VisionStateManager.VisionState, duration: float = 0.0) -> void:
	if state_manager:
		state_manager.set_state(state, duration)

## Aplicar daño ocular
func apply_eye_damage(damage_amount: float) -> void:
	if eye_damage_controller:
		eye_damage_controller.apply_damage(damage_amount)

## Ejecutar un parpadeo único
func blink_once() -> void:
	if blink_controller:
		blink_controller.blink_once()

## Iniciar estado de parpadeo constante
func start_blinking(frequency: float = -1.0) -> void:
	if blink_controller:
		blink_controller.start_blinking_state(frequency)

## Detener el parpadeo
func stop_blinking() -> void:
	if blink_controller:
		blink_controller.stop_blinking_state()

## Reaccionar a un irritante (humo, polvo, etc.)
func react_to_irritant(intensity: float) -> void:
	if blink_controller:
		blink_controller.react_to_irritant(intensity)

## Comprobar si un objetivo está en el campo de visión
func is_target_in_fov(target: Node3D) -> bool:
	if fov_component:
		return fov_component.has_target(target)
	return false

## Comprobar si un objetivo es visible (línea de visión)
func is_target_visible(target: Node3D) -> bool:
	if raycast_component:
		return raycast_component.is_target_visible(target)
	return false

## Comprobar si un objetivo es reconocido completamente
func is_target_recognized(target: Node3D) -> bool:
	if target_recognition:
		return target_recognition.is_target_recognized(target)
	return false

## Comprobar si un objetivo está en la memoria
func is_target_remembered(target: Node3D) -> bool:
	if memory_vision:
		return memory_vision.is_target_remembered(target)
	return false

## Obtener todos los objetivos detectados actualmente
func get_detected_targets() -> Array:
	if target_recognition:
		return target_recognition.get_recognized_targets()
	return []

## Obtener todos los objetivos en memoria
func get_remembered_targets() -> Array:
	if memory_vision:
		return memory_vision.get_remembered_targets()
	return []

## Obtener nivel de iluminación actual
func get_light_level() -> float:
	if light_detector:
		return light_detector.get_light_intensity()
	return 0.0

## Obtener nivel de daño ocular
func get_eye_damage() -> float:
	if eye_damage_controller:
		return eye_damage_controller.eye_damage
	return 0.0

## Obtener el estado visual actual
func get_vision_state() -> int:
	if state_manager:
		return state_manager.current_state
	return VisionStateManager.VisionState.NORMAL

## Obtener el nombre del estado visual actual
func get_vision_state_name() -> String:
	if state_manager:
		return state_manager.get_state_name()
	return "Normal"

## Comprobar si la percepción está completamente bloqueada
func is_perception_blocked() -> bool:
	if state_manager:
		return state_manager.is_perception_blocked()
	return false

## Obtener la última posición conocida de un objetivo
func get_target_last_position(target: Node3D) -> Vector3:
	if memory_vision and memory_vision.is_target_remembered(target):
		return memory_vision.get_last_position(target)
	return Vector3.ZERO

## Obtener el tiempo desde la última vez que se vio un objetivo
func get_time_since_target_seen(target: Node3D) -> float:
	if memory_vision:
		return memory_vision.get_time_since_last_seen(target)
	return -1.0

## Limpiar todas las memorias de objetivos
func clear_all_memories() -> void:
	if memory_vision:
		memory_vision.clear_all_memories()

## Olvidar un objetivo específico
func forget_target(target: Node3D) -> void:
	if memory_vision:
		memory_vision.forget_target_manually(target)

## Activar/desactivar el parpadeo natural
func set_natural_blinking(enabled: bool) -> void:
	if blink_controller:
		blink_controller.set_natural_blinking(enabled)

## Activar/desactivar la curación automática de daño ocular
func set_auto_healing(enabled: bool) -> void:
	if eye_damage_controller:
		eye_damage_controller.auto_healing_enabled = enabled

## Resetear daño ocular a cero
func reset_eye_damage() -> void:
	if eye_damage_controller:
		eye_damage_controller.reset_damage()
