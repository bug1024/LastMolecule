class_name MoleculeBackground
extends Control
## Painted membrane world; reading screens use a quiet ink wash over the same world.
@export var molecule_count := 0 # Legacy scene property retained for compatibility.
@export var top_color := Color("273449")
@export var bottom_color := Color("1c2336")
@export var line_color := Color("397b68")
@export var glow_color := Color("536781")
var battle := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	if battle:
		var scene := TextureRect.new()
		scene.texture = UIKit.art("painted-world")
		scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shader := ShaderMaterial.new()
		shader.shader = load("res://assets/shaders/battle_depth.gdshader")
		scene.material = shader
		add_child(scene)


func _draw() -> void:
	if battle:
		return
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, bottom_color)
	var texture := UIKit.art("painted-world")
	if texture:
		var cover := maxf(size.x / texture.get_width(), size.y / texture.get_height())
		var extent := texture.get_size() * cover
		draw_texture_rect(texture, Rect2((size - extent) * 0.5, extent), false)
	draw_rect(area, Color(0.07, 0.09, 0.15, 0.14 if battle else 0.65))
