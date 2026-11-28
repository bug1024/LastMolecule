class_name MoleculeBackground
extends Control
## Painted membrane world; reading screens use a quiet ink wash over the same world.
@export var molecule_count := 0 # Legacy scene property retained for compatibility.
@export var top_color := Color("273449")
@export var bottom_color := Color("1c2336")
@export var line_color := Color("397b68")
@export var glow_color := Color("536781"):
	set(value):
		glow_color = value
		_apply_battle_tint()
		if _atmos:
			_atmos.queue_redraw()
		queue_redraw()
var battle := false
var lab := false          # 研发总览：观察室，不是战场；glow_color 跟随研发阶段
var _scene: TextureRect
var _atmos: Control
var _time := 0.0
var _motes: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	if battle:
		_scene = TextureRect.new()
		var arena := UIKit.art("geometric-arena")
		if arena:
			_scene.texture = arena
		else:
			_scene.texture = UIKit.art("geometric-title")
			var shader := ShaderMaterial.new()
			shader.shader = preload("res://assets/shaders/battle_depth.gdshader")
			_scene.material = shader
		_scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# 战斗镜头会推动这一层：四周留出余量
		_scene.offset_left = -24
		_scene.offset_top = -24
		_scene.offset_right = 24
		_scene.offset_bottom = 24
		_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_scene)
		_apply_battle_tint()
		_setup_atmosphere()


func _setup_atmosphere() -> void:
	_atmos = Control.new()
	_atmos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmos.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_atmos.material = additive
	_atmos.draw.connect(_draw_atmosphere)
	add_child(_atmos)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4129
	for i in 22:
		_motes.append({
			"at": Vector2(rng.randf(), rng.randf_range(0.06, 0.54)),
			"rise": rng.randf_range(0.003, 0.011),
			"phase": rng.randf() * TAU,
			"radius": rng.randf_range(1.6, 3.8),
			"alpha": rng.randf_range(0.14, 0.34),
			"warm": rng.randf() < 0.55,
		})


func _apply_battle_tint() -> void:
	if _scene == null or _scene.material != null:
		return
	var base := Color(0.64, 0.70, 0.82)
	var accent := glow_color.lightened(0.28)
	_scene.modulate = base.lerp(accent, 0.24)


func _process(delta: float) -> void:
	if not battle or _atmos == null or not is_visible_in_tree():
		return
	_time += delta * (0.2 if GameSettings.reduce_motion else 1.0)
	_atmos.queue_redraw()


## 战斗远景的左上主光束与稀疏微粒：只停留在上半战场，绝不侵入底部手牌阅读区
func _draw_atmosphere() -> void:
	if size.x < 100.0 or size.y < 100.0:
		return
	var stage_light := glow_color.lightened(0.32)
	var warm := Color(1.0, 0.88, 0.66).lerp(stage_light, 0.24)
	Shading.glow(_atmos, Vector2(size.x * 0.22, size.y * 0.14), size.x * 0.38, Color(warm, 0.075))
	Shading.glow(_atmos, Vector2(size.x * 0.54, size.y * 0.34), size.x * 0.42, Color(stage_light, 0.085))
	var source := Vector2(size.x * 0.12, -size.y * 0.12)
	var target := Vector2(size.x * 0.46, size.y * 0.56)
	for i in 4:
		var sway := sin(_time * 0.14 + i * 1.6) * 0.014
		var reach := (target - source).rotated((i - 1.5) * 0.13 + sway) * 1.18
		var side := reach.normalized().orthogonal()
		var far := source + reach
		var near_half := 12.0
		var far_half := 72.0 + i * 20.0
		var strength := 0.034 + 0.011 * sin(_time * 0.36 + i * 2.0)
		var core := Color(warm, strength)
		var tail := Color(warm, strength * 0.08)
		var none := Color(warm, 0.0)
		for dir in [-1.0, 1.0]:
			_atmos.draw_polygon(PackedVector2Array([source, far, far + side * far_half * dir, source + side * near_half * dir]),
				PackedColorArray([core, tail, none, none]))
	if BattleDirector.lite():
		return
	for mote in _motes:
		var at: Vector2 = mote.at
		var phase: float = mote.phase
		var x := fposmod(at.x + sin(_time * 0.26 + phase) * 0.01 + _time * 0.0025, 1.0)
		var y := 0.06 + fposmod(at.y - 0.06 - _time * float(mote.rise), 0.48)
		var edge_fade := sin(clampf((y - 0.06) / 0.48, 0.0, 1.0) * PI)
		var alpha: float = float(mote.alpha) * (0.65 + 0.35 * sin(_time * 1.2 + phase * 2.4)) * edge_fade
		var color := Color(1.0, 0.87, 0.62) if bool(mote.warm) else stage_light.lightened(0.25)
		Shading.glow(_atmos, Vector2(x, y) * size, float(mote.radius), Color(color, alpha))


func _draw() -> void:
	if battle:
		return
	if lab:
		_draw_lab()
		return
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, bottom_color)
	var texture := UIKit.art("geometric-title")
	if texture == null:
		texture = UIKit.art("geometric-arena")
	if texture:
		var cover := maxf(size.x / texture.get_width(), size.y / texture.get_height())
		var extent := texture.get_size() * cover
		draw_texture_rect(texture, Rect2((size - extent) * 0.5, extent), false)
	draw_rect(area, Color(0.07, 0.09, 0.15, 0.34))


## 观察室：低饱和几何膜壁 + 阶段色左上柔光 + 沉静墨蓝前景，与几何厚涂角色和战斗世界统一材质
func _draw_lab() -> void:
	var w := size.x
	var h := size.y
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, Color(0.045, 0.055, 0.095))
	var arena := UIKit.art("geometric-arena")
	if arena:
		var cover := maxf(w / arena.get_width(), h / arena.get_height())
		var extent := arena.get_size() * cover
		var tint := Color(0.30, 0.34, 0.46).lerp(glow_color.lightened(0.18), 0.24)
		draw_texture_rect(arena, Rect2((size - extent) * 0.5, extent), false, tint)
	# 顶部与底部柔暗压边：让四周面板安静退后，中央留出标本观察窗的呼吸空间
	var top := Color(0.04, 0.05, 0.095, 0.72)
	var mid := Color(0.045, 0.055, 0.10, 0.42)
	var low := Color(0.03, 0.038, 0.075, 0.90)
	var split := h * 0.66
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, split), Vector2(0, split)]),
		PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, split), Vector2(w, split), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([mid, mid, low, low]))
	# 左上方柔和阶段光晕：和场景、控件共用同一光向
	Shading.glow(self, Vector2(w * 0.38, h * 0.28), w * 0.44, Color(glow_color.lightened(0.24), 0.22))
	Shading.glow(self, Vector2(w * 0.50, h * 0.46), w * 0.32, Color(1.0, 0.90, 0.72, 0.07))
