class_name UpgradeCeremony
extends Control
## 卡牌升级的强化演出：旧牌蓄能收缩 → 翻转变形 → 新牌带光落定，再逐条亮出变化。
## 全程约 1.3 秒；节奏短促，结果定格后保留缓慢的金色光芒，玩家随时可以点继续。

const FACE_SCALE := 1.25
const SIZE := Vector2(1060, 340)
const GREEN := Color(0.55, 1.0, 0.65)

var _old: CardFace
var _new: CardFace
var _overlay: Control
var _backdrop: Control    # 光芒画在弹窗面板上：牌列表外层会裁剪，光不能被切成一条直边
var _plates: VBoxContainer
var _charge := 0.0
var _burst := 0.0
var _rays := 0.0
var _sweep := -1.0
var _arrow := 0.0
var _time := 0.0


static func create(card: ResearchCard, backdrop_parent: Control) -> UpgradeCeremony:
	var node := UpgradeCeremony.new()
	node._backdrop = Control.new()
	node._backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node._backdrop.draw.connect(node._draw_backdrop)
	backdrop_parent.add_child(node._backdrop)
	backdrop_parent.move_child(node._backdrop, 0)
	node.tree_exiting.connect(node._backdrop.queue_free)
	node.custom_minimum_size = SIZE
	node.size = SIZE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node._build(card)
	return node


func _build(card: ResearchCard) -> void:
	var center := SIZE * 0.5
	var face_size := CardFace.BASE * FACE_SCALE
	_old = CardFace.create(card, FACE_SCALE)
	_new = CardFace.create(card.upgrade_preview, FACE_SCALE, {"compare_to": card})
	for face: CardFace in [_old, _new]:
		face.position = center - face_size * 0.5
		face.pivot_offset = face_size * 0.5
		add_child(face)
	_new.visible = false
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.size = SIZE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_plates = VBoxContainer.new()
	_plates.add_theme_constant_override("separation", 10)
	_plates.alignment = BoxContainer.ALIGNMENT_CENTER
	_plates.position = Vector2(center.x + face_size.x * 0.5 + 34, 0)
	_plates.size = Vector2(SIZE.x - (center.x + face_size.x * 0.5 + 34), SIZE.y)
	add_child(_plates)
	var lines := ResearchCard.upgrade_diff(card, card.upgrade_preview)
	if lines.is_empty():
		lines.append(tr("ui.upgrade.same"))
	for line in lines:
		var plate := _plate(line)
		plate.modulate.a = 0.0
		_plates.add_child(plate)


func _ready() -> void:
	_play()


func _play() -> void:
	var face_size := CardFace.BASE * FACE_SCALE
	var tween := create_tween()
	GameAudio.sfx("level_up")
	tween.tween_method(func(v: float) -> void: _charge = v, 0.0, 1.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_old, "scale", Vector2(0.93, 0.93), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_old, "scale", Vector2(0.0, 1.0), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_transform)
	tween.tween_property(_new, "scale", Vector2(1.1, 1.1), 0.12).from(Vector2(0.0, 1.1)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_new, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)
	# 落定后：旧牌退到左边作为对照，新牌身上扫过一道光，变化逐条亮出
	var after := create_tween().set_parallel(true)
	var start := 0.42
	after.tween_method(func(v: float) -> void: _burst = v, 1.0, 0.0, 0.55).set_delay(start)
	after.tween_method(func(v: float) -> void: _rays = v, 0.0, 1.0, 0.3).set_delay(start)
	after.tween_method(func(v: float) -> void: _sweep = v, 0.0, 1.0, 0.5).set_delay(start + 0.2)
	after.tween_method(func(v: float) -> void: _arrow = v, 0.0, 1.0, 0.25).set_delay(start + 0.3)
	after.tween_property(_old, "scale", Vector2(0.62, 0.62), 0.32).from(Vector2(0.45, 0.45)).set_delay(start + 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var ghost_x := SIZE.x * 0.5 - face_size.x * 0.5 - face_size.x * 0.62 - 110
	after.tween_property(_old, "position:x", ghost_x, 0.32).set_delay(start + 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var i := 0
	for plate in _plates.get_children():
		var at := start + 0.34 + i * 0.09
		after.tween_property(plate, "modulate:a", 1.0, 0.12).set_delay(at)
		after.tween_property(plate, "position:x", 0.0, 0.22).from(26.0).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


func _transform() -> void:
	_old.visible = false
	_new.visible = true
	_new.scale = Vector2(0.0, 1.1)
	_charge = 0.0
	# 旧牌只隐藏一瞬，随后作为对照出现在左边
	var ghost := create_tween()
	ghost.tween_interval(0.2)
	ghost.tween_callback(func() -> void:
		_old.set_state(false, false, true)
		_old.visible = true)


## 「伤害 9 → 12」拆开排：新数字才是主角
func _plate(line: String) -> Control:
	var plate := PanelContainer.new()
	plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.12, 0.15, 0.95), Color(GREEN, 0.55), 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	var parts := line.split(" → ")
	if parts.size() == 2:
		var cut := parts[0].rfind(" ")
		row.add_child(UIKit.label(parts[0].substr(0, cut), UIKit.TEXT, 15))
		row.add_child(UIKit.label(parts[0].substr(cut + 1), UIKit.TEXT_DIM, 20))
		row.add_child(UIKit.label("→", GREEN, 18))
		row.add_child(UIKit.header(parts[1], 32, GREEN))
	else:
		row.add_child(UIKit.header(line, 18, GREEN))
	return plate


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	_overlay.queue_redraw()
	_backdrop.queue_redraw()


## 面板上、牌后面：蓄能时光点向中心收拢，落定后是缓慢转动的金色光芒
func _draw_backdrop() -> void:
	var c := global_position + SIZE * 0.5 - _backdrop.global_position
	if _charge > 0.0:
		Shading.glow(_backdrop, c, 230.0, Color(UIKit.GOLD, 0.4 * _charge))
		for i in 18:
			var a := i * TAU / 18.0 + _time * 1.4
			_backdrop.draw_circle(c + Vector2.from_angle(a) * lerpf(300.0, 70.0, _charge), 2.5 + 2.0 * _charge, Color(UIKit.GOLD.lightened(0.3), _charge))
	if _rays > 0.0:
		Shading.glow(_backdrop, c, 300.0, Color(UIKit.GOLD, 0.26 * _rays))
		for i in 12:
			var a := i * TAU / 12.0 + _time * 0.12
			var spread := 0.09
			var length := 270.0 + 22.0 * sin(_time * 1.3 + i)
			_backdrop.draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - spread) * length, c + Vector2.from_angle(a + spread) * length]),
				Color(UIKit.GOLD, 0.1 * _rays))
	if _burst > 0.0:
		_backdrop.draw_arc(c, lerpf(120.0, 420.0, 1.0 - _burst), 0, TAU, 64, Color(UIKit.GOLD.lightened(0.3), _burst), 2.0 + 7.0 * _burst, true)


## 新旧牌之间的箭头
func _draw() -> void:
	var c := SIZE * 0.5
	if _arrow > 0.0:
		var face_w := CardFace.BASE.x * FACE_SCALE
		var x := c.x - face_w * 0.5 - 22.0
		for i in 3:
			var p := Vector2(x + i * 13.0 - 26.0 + (1.0 - _arrow) * -14.0, c.y)
			draw_polyline(PackedVector2Array([p + Vector2(-6, -12), p + Vector2(6, 0), p + Vector2(-6, 12)]), Color(GREEN, _arrow * (0.45 + i * 0.27)), 3.0, true)


## 牌前面：变形瞬间的白光、扫过牌面的一道高光
func _draw_overlay() -> void:
	var c := SIZE * 0.5
	var rect := Rect2(c - CardFace.BASE * FACE_SCALE * 0.5, CardFace.BASE * FACE_SCALE)
	if _burst > 0.0:
		_overlay.draw_rect(rect, Color(1.0, 0.97, 0.82, _burst * _burst * 0.85))
	if _sweep >= 0.0 and _sweep < 1.0:
		var x := lerpf(rect.position.x - 60.0, rect.end.x + 60.0, _sweep)
		var band := PackedVector2Array([Vector2(x - 30, rect.position.y), Vector2(x + 18, rect.position.y), Vector2(x - 18, rect.end.y), Vector2(x - 66, rect.end.y)])
		var clip := Geometry2D.intersect_polygons(band, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
		for shape in clip:
			_overlay.draw_colored_polygon(shape, Color(1, 1, 1, 0.42))
