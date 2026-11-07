class_name MoleculeBackground
extends Control
## Painted membrane world; reading screens use a quiet ink wash over the same world.
@export var molecule_count := 0 # Legacy scene property retained for compatibility.
@export var top_color := Color("273449")
@export var bottom_color := Color("1c2336")
@export var line_color := Color("397b68")
@export var glow_color := Color("536781")
var battle := false
var lab := false          # 研发总览：观察室，不是战场；glow_color 跟随研发阶段


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	if battle:
		var scene := TextureRect.new()
		var arena := UIKit.art("geometric-arena")
		if arena:
			scene.texture = arena
			scene.modulate = Color(0.66, 0.71, 0.83)
		else:
			scene.texture = UIKit.art("painted-world")
			var shader := ShaderMaterial.new()
			shader.shader = preload("res://assets/shaders/battle_depth.gdshader")
			scene.material = shader
		scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scene)


func _draw() -> void:
	if battle:
		return
	if lab:
		_draw_lab()
		return
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, bottom_color)
	var texture := UIKit.art("painted-world")
	if texture:
		var cover := maxf(size.x / texture.get_width(), size.y / texture.get_height())
		var extent := texture.get_size() * cover
		draw_texture_rect(texture, Rect2((size - extent) * 0.5, extent), false)
	draw_rect(area, Color(0.07, 0.09, 0.15, 0.34))


## 观察室：深色舱壁 + 暗纹六边形墙板 + 顶部打下来的阶段色光。不用世界插画，一眼和战场区分开
func _draw_lab() -> void:
	var w := size.x
	var h := size.y
	var top := Color(0.085, 0.10, 0.165)
	var low := Color(0.04, 0.05, 0.09)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), PackedColorArray([top, top, low, low]))
	var center := Vector2(w * 0.5, h * 0.48)
	var tile := 46.0
	var row := 0
	var y := 0.0
	while y < h * 0.8:
		var x := (tile * 0.87) if row % 2 == 1 else 0.0
		while x < w + tile:
			var c := Vector2(x, y)
			var fade := clampf(1.0 - c.distance_to(center) / (w * 0.62), 0.0, 1.0)
			if fade > 0.0:
				var hex := PackedVector2Array()
				for i in 7:
					hex.append(c + Vector2.from_angle(PI / 6 + i * TAU / 6) * (tile - 3.0))
				draw_polyline(hex, Color(glow_color.lightened(0.35), 0.11 * fade), 1.5, true)
			x += tile * 1.74
		y += tile * 1.5
		row += 1
	# 地面：一条柔和的墙脚线，地板向观察台汇聚
	var floor_y := h * 0.76
	draw_polygon(PackedVector2Array([Vector2(0, floor_y), Vector2(w, floor_y), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0.055, 0.065, 0.11), Color(0.055, 0.065, 0.11), Color(0.025, 0.03, 0.06), Color(0.025, 0.03, 0.06)]))
	draw_line(Vector2(0, floor_y), Vector2(w, floor_y), Color(glow_color.lightened(0.3), 0.28), 1.5, true)
	for i in range(-6, 7):
		draw_line(Vector2(w * 0.5 + i * 34.0, floor_y), Vector2(w * 0.5 + i * 190.0, h), Color(glow_color.lightened(0.3), 0.07), 1.0, true)
	Shading.glow(self, Vector2(w * 0.5, h * 0.42), w * 0.42, Color(glow_color.lightened(0.15), 0.34))
