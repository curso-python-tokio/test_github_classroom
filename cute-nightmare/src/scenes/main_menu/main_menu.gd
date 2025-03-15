extends Control

@export var escala_zoom = 1.1  # Factor de escala al hacer zoom
@export var duracion_zoom = 0.1 # Duración de la animación de zoom

@onready var play_button = $GridContainer/play
@onready var exit_button = $GridContainer/exit
@onready var settings_button = $GridContainer/settings

var play_original_scale: Vector2
var exit_original_scale: Vector2
var settings_original_scale: Vector2

func _ready():
	play_original_scale = play_button.scale
	exit_original_scale = exit_button.scale
	settings_original_scale = settings_button.scale

	# Establecer el punto de anclaje al centro de cada botón
	play_button.pivot_offset = play_button.size / 2
	exit_button.pivot_offset = exit_button.size / 2
	settings_button.pivot_offset = settings_button.size / 2

func _on_play_mouse_entered() -> void:
	var tween = create_tween()
	tween.tween_property(play_button, "scale", play_original_scale * escala_zoom, duracion_zoom)

func _on_play_mouse_exited() -> void:
	var tween = create_tween()
	tween.tween_property(play_button, "scale", play_original_scale, duracion_zoom)

func _on_exit_mouse_entered() -> void:
	var tween = create_tween()
	tween.tween_property(exit_button, "scale", exit_original_scale * escala_zoom, duracion_zoom)

func _on_exit_mouse_exited() -> void:
	var tween = create_tween()
	tween.tween_property(exit_button, "scale", exit_original_scale, duracion_zoom)

func _on_settings_mouse_entered() -> void:
	var tween = create_tween()
	tween.tween_property(settings_button, "scale", settings_original_scale * escala_zoom, duracion_zoom)

func _on_settings_mouse_exited() -> void:
	var tween = create_tween()
	tween.tween_property(settings_button, "scale", settings_original_scale, duracion_zoom)

func _on_settings_pressed() -> void:
	pass # Replace with function body.

func _on_play_pressed() -> void:
	pass # Replace with function body.

func _on_exit_pressed() -> void:
	pass # Replace with function body.
