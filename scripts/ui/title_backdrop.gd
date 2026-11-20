class_name TitleBackdrop
extends Control
## 标题页的镜头层。后景：膜世界插画缓慢漂移，左侧压暗给标题和菜单留出安静的阅读面，
## 左上的光束落在主视觉身上；前景（front）：盖在主视觉之上的近景浮尘和四周暗角。
## 光和浮尘用加色混合画在子层里，暗部用普通混合画在自身。

var front := false
var focus := Vector2(0.7, 0.55)   # 主视觉在屏幕上的位置（比例），光束和光池都对准这里
var _time := 0.0
var _light: Control
var _motes: Array = []

static var _vignette: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_light = Control.new()
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = additive
	_light.draw.connect(_draw_light)
	add_child(_light)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7151 if front else 977
	for i in (14 if front else 46):
		_motes.append({
			"at": Vector2(rng.randf(), rng.randf()),
			"rise": rng.randf_range(0.004, 0.016) * (1.6 if front else 1.0),
			"phase": rng.randf() * TAU,
			"radius": rng.randf_range(9.0, 26.0) if front else rng.randf_range(1.6, 4.2),
			"alpha": rng.randf_range(0.04, 0.09) if front else rng.randf_range(0.25, 0.7),
			"warm": rng.randf() < 0.6,
		})
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta * (0.2 if GameSettings.reduce_motion else 1.0)
	_light.queue_redraw()
	if not front:
		queue_redraw()


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	if front:
		draw_texture_rect(_vignette_tex(), area.grow(2.0), false)
		return
	draw_rect(area, UIKit.INK)
	var texture := UIKit.art("painted-world")
	if texture:
		# 比画面略大一圈，在余量里缓慢漂移
		var cover := maxf(size.x / texture.get_width(), size.y / texture.get_height()) * 1.05
		var extent := texture.get_size() * cover
		var slack := (extent - size) * 0.45
		var drift := Vector2(sin(_time * 0.06), cos(_time * 0.045)) * slack
		draw_texture_rect(texture, Rect2((size - extent) * 0.5 + drift, extent), false)
	draw_rect(area, Color(0.05, 0.065, 0.12, 0.34))
	var ink := Color(0.025, 0.035, 0.075)
	var stops := [[0.0, 0.92], [0.22, 0.8], [0.42, 0.38], [0.62, 0.0]]
	for i in stops.size() - 1:
		_band(Rect2(size.x * stops[i][0], 0, size.x * (stops[i + 1][0] - stops[i][0]), size.y),
			Color(ink, stops[i][1]), Color(ink, stops[i + 1][1]), true)
	_band(Rect2(0, 0, size.x, size.y * 0.2), Color(ink, 0.55), Color(ink, 0.0), false)
	_band(Rect2(0, size.y * 0.7, size.x, size.y * 0.3), Color(ink, 0.0), Color(ink, 0.8), false)


func _band(rect: Rect2, from: Color, to: Color, horizontal: bool) -> void:
	var a := rect.position
	var b := rect.end
	draw_polygon(PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]),
		PackedColorArray([from, to, to, from] if horizontal else [from, from, to, to]))


func _draw_light() -> void:
	if not front:
		var target := focus * size
		Shading.glow(_light, target, size.x * 0.42, Color(0.36, 0.5, 0.82, 0.13))
		Shading.glow(_light, target + Vector2(0, size.y * 0.02), size.x * 0.25, Color(1.0, 0.76, 0.46, 0.2))
		var source := Vector2(size.x * 0.2, -size.y * 0.1)
		for i in 5:
			var sway := sin(_time * 0.13 + i * 1.7) * 0.012
			var reach := (target - source).rotated((i - 2) * 0.1 + sway) * 1.3
			var side := reach.normalized().orthogonal()
			var far := source + reach
			var near_half := 10.0
			var far_half := 64.0 + i * 16.0
			var strength := 0.075 + 0.03 * sin(_time * 0.4 + i * 2.1)
			var core := Color(1.0, 0.86, 0.62, strength)
			var tail := Color(1.0, 0.86, 0.62, strength * 0.12)
			var none := Color(1.0, 0.86, 0.62, 0.0)
			for dir in [-1.0, 1.0]:
				_light.draw_polygon(PackedVector2Array([source, far, far + side * far_half * dir, source + side * near_half * dir]),
					PackedColorArray([core, tail, none, none]))
	for mote in _motes:
		var at: Vector2 = mote.at
		var phase: float = mote.phase
		var x := fposmod(at.x + sin(_time * 0.3 + phase) * 0.012 + _time * 0.003, 1.0)
		var y := fposmod(at.y - _time * float(mote.rise), 1.0)
		var alpha: float = mote.alpha * (0.6 + 0.4 * sin(_time * 1.3 + phase * 3.0)) * sin(PI * y)
		if x < 0.36:
			alpha *= 0.35   # 菜单一侧保持安静
		var color := Color(1.0, 0.84, 0.58) if mote.warm else Color(0.6, 0.85, 0.9)
		Shading.glow(_light, Vector2(x, y) * size, mote.radius, Color(color, alpha))


static func _vignette_tex() -> Texture2D:
	if _vignette == null:
		var tex := GradientTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.2, 0.5)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
		g.colors = PackedColorArray([Color(0.01, 0.015, 0.04, 0.0), Color(0.01, 0.015, 0.04, 0.0), Color(0.01, 0.015, 0.04, 0.66)])
		tex.gradient = g
		_vignette = tex
	return _vignette
