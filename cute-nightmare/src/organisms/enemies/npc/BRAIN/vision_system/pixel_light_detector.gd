# Ultra-efficient light detector using shader-based optimization and shared resources
class_name PixelLightDetector
extends Node3D

signal illumination_changed(is_lit: bool, intensity: float)

@export_category("Configuration")
## Minimum light intensity to be considered lit
@export var min_intensity_threshold: float = 0.1
## Base interval between checks
@export var update_interval: float = 0.2
## Whether to skip checks when off-screen
@export var skip_offscreen: bool = true
## Grid size for caching light data (lower = more precision, higher = less cache entries)
@export_range(1.0, 100.0, 1.0) var grid_size: float = 10.0
## Size of detector's sampling area
@export_range(0.01, 1.0, 0.01) var detector_size: float = 0.1
## Size of region of interest in pixels (NxN)
@export_range(1, 9, 2) var roi_size: int = 3
## Threshold for significant change to emit signal
@export_range(0.01, 0.5, 0.01) var change_threshold: float = 0.05

@export_group("Debug", "debug_")
## Show debug information
@export var debug_enabled: bool = false

# Static shared resources
static var _shader: Shader
static var _probe_mesh: Mesh
static var _detectors = []
static var _light_data = {}
static var _max_cache_entries: int = 500
static var _is_initialized: bool = false

# Instance variables
var _is_lit: bool = false
var _light_intensity: float = 0.0
var _update_timer: Timer
var _visibility_notifier: VisibleOnScreenNotifier3D
var _is_visible: bool = false
var _probe_instance: MeshInstance3D
var _shader_material: ShaderMaterial

# Initialize shared resources
static func _initialize_shared_resources() -> void:
	if _is_initialized:
		return
	
	# Create shared shader
	_shader = Shader.new()
	_shader.code = """
		shader_type spatial;
		render_mode unshaded;
		
		uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
		
		void vertex() {
			// Make invisible but keep in place for sampling
			VERTEX *= 0.0;
		}
		
		void fragment() {
			// Sample screen directly at this position
			vec4 color = texture(screen_texture, SCREEN_UV);
			
			// Calculate perceptual luminance
			float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
			
			// Output luminance to be visible in framebuffer
			ALBEDO = vec3(luminance);
			ALPHA = 0.0; // Invisible
		}
	"""
	
	# Create shared mesh
	_probe_mesh = SphereMesh.new()
	_probe_mesh.radius = 0.01
	_probe_mesh.height = 0.02
	
	_is_initialized = true

func _ready() -> void:
	# Initialize shared resources
	_initialize_shared_resources()
	
	# Create visibility notifier for culling
	_visibility_notifier = VisibleOnScreenNotifier3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3.ONE * detector_size
	_visibility_notifier.aabb = box.get_debug_mesh().get_aabb()
	add_child(_visibility_notifier)
	_visibility_notifier.screen_entered.connect(_on_became_visible)
	_visibility_notifier.screen_exited.connect(_on_became_invisible)
	
	# Create light probe with shared shader
	_setup_shader_probe()
	
	# Setup update timer
	_update_timer = Timer.new()
	_update_timer.wait_time = update_interval
	_update_timer.one_shot = false
	_update_timer.timeout.connect(_on_update_timer)
	add_child(_update_timer)
	_update_timer.start()
	
	# Register this detector
	_detectors.append(self)

func _setup_shader_probe() -> void:
	# Create mesh instance with shared mesh
	_probe_instance = MeshInstance3D.new()
	_probe_instance.mesh = _probe_mesh
	add_child(_probe_instance)
	
	# Create material using shared shader
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = _shader
	
	_probe_instance.material_override = _shader_material
	_probe_instance.visible = false

func _on_became_visible() -> void:
	_is_visible = true

func _on_became_invisible() -> void:
	_is_visible = false

func _on_update_timer() -> void:
	# Skip if culling enabled and not visible
	if skip_offscreen and not _is_visible:
		return
	
	# Get cached data if available for this frame
	var frame_id = Engine.get_frames_drawn()
	
	# Use grid_size to determine cache position key (lower resolution grid)
	var grid_pos = Vector3(
		floor(global_position.x / grid_size),
		floor(global_position.y / grid_size),
		floor(global_position.z / grid_size)
	)
	var pos_key = str(grid_pos) # Using string instead of Vector3i to be more GC friendly
	
	if _light_data.has(pos_key) and _light_data[pos_key].frame_id == frame_id:
		# Use cached data
		var brightness = _light_data[pos_key].brightness
		_update_light_state(brightness)
		return
	
	# Make probe visible for sampling
	_probe_instance.visible = true
	
	# Request frame callback to capture light after rendering
	RenderingServer.request_frame_drawn_callback(self._sample_light.bind(pos_key))

func _sample_light(pos_key: String) -> void:
	# Hide probe after sampling
	_probe_instance.visible = false
	
	var vp = get_viewport()
	if not vp:
		return
		
	var camera = vp.get_camera_3d()
	if not camera:
		return
	
	# Check if in front of camera
	var to_detector = global_position - camera.global_position
	var forward = -camera.global_transform.basis.z
	if to_detector.dot(forward) <= 0:
		return
	
	# Get screen position
	var screen_pos = camera.unproject_position(global_position)
	var screen_size = vp.get_visible_rect().size
	
	# Check if on screen
	if screen_pos.x < 0 or screen_pos.x >= screen_size.x or screen_pos.y < 0 or screen_pos.y >= screen_size.y:
		return
	
	# Get Region of Interest - configurable NxN pixels around point for better accuracy
	var img = vp.get_texture().get_image()
	var pixel_x = int(screen_pos.x)
	var pixel_y = int(screen_pos.y)
	
	# Calculate half-size (for ROI of 3, half_size is 1)
	var half_size = float(roi_size) / 2.0
	
	# Create ROI rect
	var roi_rect = Rect2i(
		max(0, pixel_x - half_size),
		max(0, pixel_y - half_size),
		min(roi_size, img.get_width() - pixel_x + half_size),
		min(roi_size, img.get_height() - pixel_y + half_size)
	)
	
	# Get region (faster than sampling full image)
	var roi = img.get_region(roi_rect)
	
	# Calculate brightness
	var total_luminance = 0.0
	var pixel_count = 0
	
	for y in range(roi.get_height()):
		for x in range(roi.get_width()):
			var color = roi.get_pixel(x, y)
			var luminance = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
			total_luminance += luminance
			pixel_count += 1
	
	var avg_brightness = total_luminance / max(1, pixel_count)
	
	# Manage cache size
	if _light_data.size() >= _max_cache_entries:
		# Clear older entries when exceeding max size
		var oldest_frame = Engine.get_frames_drawn()
		var oldest_key = ""
		
		# Find oldest entry
		for key in _light_data:
			if _light_data[key].frame_id < oldest_frame:
				oldest_frame = _light_data[key].frame_id
				oldest_key = key
		
		# Remove oldest entry
		if oldest_key != "":
			_light_data.erase(oldest_key)
	
	# Cache result for this frame
	_light_data[pos_key] = {
		"frame_id": Engine.get_frames_drawn(),
		"brightness": avg_brightness
	}
	
	# Update state
	_update_light_state(avg_brightness)

func _update_light_state(brightness: float) -> void:
	var was_lit = _is_lit
	_is_lit = brightness > min_intensity_threshold
	
	# Only emit signal if there's a significant change
	if was_lit != _is_lit or abs(_light_intensity - brightness) > change_threshold:
		_light_intensity = brightness
		illumination_changed.emit(_is_lit, brightness)
		
		if debug_enabled:
			print_debug("Light: ", _is_lit, " | Intensity: ", brightness)

func is_illuminated() -> bool:
	return _is_lit

func get_light_intensity() -> float:
	return _light_intensity

func _exit_tree() -> void:
	# Remove from static list
	var idx = _detectors.find(self)
	if idx >= 0:
		_detectors.remove_at(idx)

# Process all detectors efficiently
static func process_all_detectors(scene_tree: SceneTree) -> void:
	# Process by batch (1/4 each frame)
	var frame_id = Engine.get_frames_drawn()
	var batch_index = frame_id % 4
	
	for i in range(_detectors.size()):
		if i % 4 == batch_index:
			_detectors[i]._on_update_timer()

# Set maximum cache size
static func set_max_cache_size(size: int) -> void:
	_max_cache_entries = max(10, size)
	
	# Trim cache if needed
	if _light_data.size() > _max_cache_entries:
		var keys_to_remove = _light_data.size() - _max_cache_entries
		var keys = _light_data.keys()
		keys.sort_custom(func(a, b): return _light_data[a].frame_id < _light_data[b].frame_id)
		
		for i in range(keys_to_remove):
			_light_data.erase(keys[i])

# Clear all cached light data
static func clear_cache() -> void:
	_light_data.clear()
