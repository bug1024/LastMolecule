class_name MoleculeView
extends Control
## 分子结构图：中间是六元环核心，周围是 7 个带类型的位点（data/molecule.json 的 sites 坐标），
## 片段画成带颜色的原子徽章并写上名字；带毒性警示的片段旁有警示标记。
## interactive 时可以点位点（site_clicked），选中的位点发光；编辑器和研发总览共用。
## compact 用于小图：位点缩小、不写名字。flash(prop) 让给这项属性加分的片段闪一下；flash_sites 让指定位点闪一下；
## hit / cheer / attack 是战斗里分子作为主角的反馈；face 打开时核心环上画一张会变表情的脸，
## form（1–5，随研发团队等级）让分子长出光晕、电子轨道与星光——分子在「进化」。

signal site_clicked(site_id: String)

var molecule: Molecule = null
var interactive := false
var selected := ""
var unit := 0.0
var _time := 0.0
var _hover := ""
var compact := false
var _flash := {}        # 属性 → 剩余闪光强度（1 → 0）
var _site_flash := {}   # 位点 → [剩余强度, 颜色]（被敌人攻击的片段闪红）
var _hit := 0.0         # 受击：抖动 + 泛红
var _cheer := 0.0       # 胜利：跳一跳、发光
var idle_bob := false   # 战斗中：轻轻浮动，像活着
var face := false       # 核心环上画脸（战斗、研发总览）；编辑器里写「核心」
var form := 1           # 进化形态 1–5
var mood := ""          # 持续表情：focus / sad；空为按 ratio 自动（idle / worried）
var ratio := 1.0        # 生命比例（低了会担心）
var _react := ""        # 短暂反应：hurt / happy / fierce
var _react_t := 0.0
var _blink := 0.0
var _next_blink := 2.5
var _glow_burst := 0.0  # 进化时的闪光
var _jolt := {}         # 位点 → [偏移, 速度]：受击时片段被震开再弹回

const SITE_R := 28.0
const TYPE_MARK := {"linker": "连", "ring": "环", "terminal": "端"}


func _ready() -> void:
	if interactive:
		mouse_filter = Control.MOUSE_FILTER_STOP
	elif tooltip_text.is_empty():
		mouse_filter = Control.MOUSE_FILTER_IGNORE


## 分子某项属性的效果生效：给这项属性加分的片段闪一下
func flash(prop: String) -> void:
	_flash[prop] = 1.0


## 指定位点闪一下（敌人专攻的结构弱点用红色）
func flash_sites(site_ids: Array, color := Color(1.0, 0.35, 0.3)) -> void:
	for id in site_ids:
		_site_flash[String(id)] = [1.0, color]


## 受击：抖动泛红、片段被震开再弹回、表情吃痛；strength 随伤害大小
func hit(strength := 1.0) -> void:
	_hit = 1.0
	react("hurt", 0.7)
	for site in Molecule.config().get("sites", []):
		var dir := Vector2.from_angle(randf() * TAU)
		_jolt[String(site.id)] = [Vector2.ZERO, dir * randf_range(260.0, 520.0) * clampf(strength, 0.4, 2.0)]


func cheer() -> void:
	_cheer = 1.0
	react("happy", 3.0)


## 出招：一瞬间的凶狠表情
func attack() -> void:
	react("fierce", 0.45)


func react(kind: String, duration := 0.8) -> void:
	_react = kind
	_react_t = duration


func set_mood(kind: String) -> void:
	mood = kind


func level_up() -> void:
	_glow_burst = 1.0
	react("happy", 2.0)


## 当前表情：短暂反应优先，其次持续表情，最后看生命
func expression() -> String:
	if _react_t > 0:
		return _react
	if not mood.is_empty():
		return mood
	return "worried" if ratio < 0.35 else "idle"


func set_molecule(m: Molecule) -> void:
	molecule = m
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		for prop in _flash.keys():
			_flash[prop] = float(_flash[prop]) - delta * 0.9
			if float(_flash[prop]) <= 0.0:
				_flash.erase(prop)
		for id in _site_flash.keys():
			_site_flash[id][0] = float(_site_flash[id][0]) - delta * 0.8
			if float(_site_flash[id][0]) <= 0.0:
				_site_flash.erase(id)
		_hit = maxf(0.0, _hit - delta * 2.5)
		_cheer = maxf(0.0, _cheer - delta * 0.35)
		_glow_burst = maxf(0.0, _glow_burst - delta * 0.6)
		_react_t = maxf(0.0, _react_t - delta)
		_next_blink -= delta
		if _next_blink <= 0:
			_blink = 0.14
			_next_blink = randf_range(2.0, 4.5)
		_blink = maxf(0.0, _blink - delta)
		for id in _jolt.keys():   # 阻尼弹簧：片段被震开后弹回原位
			var j: Array = _jolt[id]
			var v: Vector2 = j[1] + (-j[0] * 260.0 - j[1] * 14.0) * delta
			j[0] = (j[0] as Vector2) + v * delta
			j[1] = v
			if (j[0] as Vector2).length() < 0.2 and v.length() < 2.0:
				_jolt.erase(id)
		self_modulate = Color(1, 1 - 0.45 * _hit, 1 - 0.45 * _hit)
		queue_redraw()


func _site_r() -> float:
	return maxf(7.0, _scale() * 0.36) if compact else minf(SITE_R, _scale() * 0.62)


func _scale() -> float:
	return unit if unit > 0 else minf(size.x / 7.2, size.y / 3.9)


func site_center(site: Dictionary) -> Vector2:
	var p: Array = site.get("pos", [0, 0])
	return size * Vector2(0.5, 0.52) + Vector2(float(p[0]), float(p[1])) * _scale()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		var hit := _site_at((event as InputEventMouseMotion).position)
		if hit != _hover:
			_hover = hit
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hit.is_empty() else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _site_at((event as InputEventMouseButton).position)
		if not hit.is_empty():
			GameAudio.sfx("click")
			site_clicked.emit(hit)


## 画图用的位点位置：叠加受击时的弹开偏移
func _pos(site: Dictionary) -> Vector2:
	var j: Array = _jolt.get(String(site.id), [])
	return site_center(site) + (j[0] if not j.is_empty() else Vector2.ZERO)


func _site_at(pos: Vector2) -> String:
	for site in Molecule.config().get("sites", []):
		if site_center(site).distance_to(pos) <= _site_r() + 4:
			return String(site.id)
	return ""


func _draw() -> void:
	var cfg := Molecule.config()
	var center := size * Vector2(0.5, 0.52)
	var k := _scale()
	var bond := Color(0.7, 0.8, 0.9, 0.55)
	var offset := Vector2(sin(_time * 70.0) * 6.0 * _hit, 0)
	if idle_bob:
		offset.y += sin(_time * 2.0) * 3.0
	offset.y -= absf(sin(_time * 9.0)) * 10.0 * _cheer
	draw_set_transform(offset)
	if _cheer > 0:
		draw_circle(center, k * 1.9, Color(0.55, 1.0, 0.75, 0.16 * _cheer))
	if face and not compact:
		_draw_form(center, k)
	# 核心六元环
	var ring := PackedVector2Array()
	for i in 7:
		var a := PI / 6 + i * TAU / 6
		ring.append(center + Vector2(cos(a), sin(a)) * k * 0.82)
	draw_polyline(ring, Color(0.75, 0.85, 0.95, 0.85), 2.0 if compact else 3.0, true)
	var inner := PackedVector2Array()
	for i in 7:
		var a := PI / 6 + i * TAU / 6
		inner.append(center + Vector2(cos(a), sin(a)) * k * 0.55)
	draw_polyline(inner, Color(0.75, 0.85, 0.95, 0.25), 2.0, true)
	var font := get_theme_default_font()
	if face and not compact:
		_draw_face(center, k)
	elif not compact:
		var core_text := tr("mol.core")
		var tw := font.get_string_size(core_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, center + Vector2(-tw * 0.5, 5), core_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.7))
	# 键：环上位点和连接位接在核心环上，末端位接在连接位上
	var by_id := {}
	for site in cfg.get("sites", []):
		by_id[String(site.id)] = site
	for site in cfg.get("sites", []):
		var c := _pos(site)
		var anchor: Vector2
		match String(site.type):
			"terminal":
				anchor = _pos(by_id["L1" if float(site.pos[0]) < 0 else "L2"])
			_:
				anchor = center + (c - center).normalized() * k * 0.82
		draw_line(anchor, c, bond, 2.0 if compact else 3.0, true)
	# 位点
	var r := _site_r()
	for site in cfg.get("sites", []):
		var id := String(site.id)
		var c := _pos(site)
		var frag_id := String(molecule.sites.get(id, "")) if molecule != null else ""
		var is_sel := interactive and id == selected
		if is_sel:
			var pulse := 0.5 + 0.5 * sin(_time * 5.0)
			draw_circle(c, r + 8 + pulse * 3, Color(UIKit.ACCENT, 0.18))
			draw_arc(c, r + 6, 0, TAU, 40, Color(UIKit.ACCENT, 0.9), 2.5, true)
		elif interactive and id == _hover:
			draw_arc(c, r + 5, 0, TAU, 40, Color(1, 1, 1, 0.4), 1.5, true)
		if frag_id.is_empty():
			draw_circle(c, r, Color(0.06, 0.08, 0.11, 0.95))
			for d in 16:
				var a0 := d * TAU / 16.0
				draw_arc(c, r, a0, a0 + TAU / 32.0, 4, Color(0.6, 0.68, 0.76, 0.6), 1.5, true)
			if compact:
				continue
			var mark := String(TYPE_MARK.get(String(site.type), "?"))
			var mw := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, c + Vector2(-mw * 0.5, 6), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.68, 0.76, 0.8))
			continue
		var frag := Molecule.fragment(frag_id)
		var col := Color.from_string(String(frag.get("color", "#9fb4c8")), Color(0.6, 0.7, 0.8))
		draw_circle(c, r + 3, Color(col, 0.2))
		draw_circle(c, r, col.darkened(0.45))
		draw_arc(c, r, 0, TAU, 40, col.lightened(0.2), 2.5, true)
		for prop in _flash:   # 效果生效时，给这项属性加分的片段外圈发亮
			if int(frag.get("fx", {}).get(prop, 0)) > 0:
				var f := float(_flash[prop])
				draw_circle(c, r + 4 + (1.0 - f) * 10, Color(col.lightened(0.4), 0.45 * f))
				draw_arc(c, r + 3, 0, TAU, 32, Color(1, 1, 1, f), 2.5, true)
		if _site_flash.has(id):
			var sf: Array = _site_flash[id]
			var t := float(sf[0])
			draw_circle(c, r + 5 + (1.0 - t) * 14, Color(sf[1], 0.5 * t))
			draw_arc(c, r + 3, 0, TAU, 32, Color(sf[1], t), 3.0, true)
		if compact:
			if not String(frag.get("alert", "")).is_empty():
				_draw_alert(c + Vector2(r * 0.9, -r * 0.9), 0.6)
			continue
		var frag_name := tr("frag." + frag_id)
		var fs := roundi((15.0 if frag_name.length() <= 3 else 12.0) * r / SITE_R)
		var nw := font.get_string_size(frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, c + Vector2(-nw * 0.5, fs * 0.36), frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.7))
		draw_string(font, c + Vector2(-nw * 0.5, fs * 0.36), frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if not String(frag.get("alert", "")).is_empty():
			_draw_alert(c + Vector2(r * 0.8, -r * 0.8))
	_draw_pocket(font)


## 靶点口袋热点：位点外一圈虚线（绿＝想要的标签，红＝空间冲突），下方写提示；命中时实线发亮
func _draw_pocket(font: Font) -> void:
	if molecule == null or molecule.disease.is_empty() or compact:
		return
	var r := _site_r()
	var by_site := {}
	for fit in molecule.pocket_fits():
		var list: Array = by_site.get(String(fit.site), [])
		list.append(fit)
		by_site[String(fit.site)] = list
	for site in Molecule.config().get("sites", []):
		var fits: Array = by_site.get(String(site.id), [])
		if fits.is_empty():
			continue
		var c := _pos(site)
		var y := r + 13.0
		for fit in fits:
			var want: bool = fit.has("want")
			var hit: bool = bool(fit.hit)
			var col := (Color(0.45, 0.95, 0.6) if want else Color(1.0, 0.45, 0.4))
			var rr := r + (7.0 if want else 11.0)
			if hit:
				draw_arc(c, rr, 0, TAU, 40, Color(col, 0.95), 2.5, true)
			else:
				for d in 12:
					var a0 := d * TAU / 12.0
					draw_arc(c, rr, a0, a0 + TAU / 24.0, 4, Color(col, 0.55), 1.5, true)
			var label := tr("pocket.%s.%s" % ["want" if want else "avoid", String(fit.get("want", fit.get("avoid", "")))])
			var fs := 11
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, c + Vector2(-w * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
			draw_string(font, c + Vector2(-w * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col if (hit == want) else Color(col, 0.75))
			y += 13.0


## 进化形态：2 光晕，3 电子轨道，4 第二条轨道 + 金色核心，5 闪烁的星光
func _draw_form(center: Vector2, k: float) -> void:
	var colors := [Color(0.5, 0.95, 0.7), Color(0.5, 0.95, 0.7), Color(0.45, 0.85, 1.0), Color(0.6, 0.75, 1.0), Color(1.0, 0.85, 0.4), Color(1.0, 0.7, 0.95)]
	var col: Color = colors[clampi(form, 1, 5)]
	if _glow_burst > 0:
		draw_circle(center, k * (2.0 + (1.0 - _glow_burst) * 2.5), Color(1.0, 0.9, 0.5, 0.35 * _glow_burst))
	if form >= 2:
		var pulse := 0.5 + 0.5 * sin(_time * 2.2)
		for i in 4:
			draw_circle(center, k * (1.3 + i * 0.35 + pulse * 0.1), Color(col, 0.05))
	if form >= 3:
		_draw_orbit(center, Vector2(k * 3.3, k * 1.25), 0.25, 3, col, 1.0)
	if form >= 4:
		_draw_orbit(center, Vector2(k * 2.9, k * 1.5), -0.45, 2, Color(1.0, 0.85, 0.4), -1.3)
		draw_arc(center, k * 0.95, 0, TAU, 48, Color(1.0, 0.85, 0.4, 0.55), 2.0, true)
	if form >= 5:
		for i in 7:
			var a := i * TAU / 7.0 + _time * 0.3
			var p := center + Vector2(cos(a) * k * 3.6, sin(a) * k * 1.9)
			var tw := 0.5 + 0.5 * sin(_time * 4.0 + i * 1.7)
			_draw_star(p, 3.0 + tw * 4.0, Color(1.0, 0.95, 0.7, 0.4 + 0.6 * tw))


func _draw_orbit(center: Vector2, radii: Vector2, tilt: float, electrons: int, col: Color, speed: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := i * TAU / 48.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(tilt))
	draw_polyline(pts, Color(col, 0.22), 1.5, true)
	for e in electrons:
		var a := _time * speed + e * TAU / electrons
		var p := center + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(tilt)
		draw_circle(p, 6.0, Color(col, 0.25))
		draw_circle(p, 3.2, col.lightened(0.3))


func _draw_star(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := i * TAU / 8.0 - PI / 2
		pts.append(p + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.35))
	draw_colored_polygon(pts, col)


## 核心环上的脸：idle / worried / hurt / happy / fierce / focus / sad；会眨眼
func _draw_face(center: Vector2, size_k: float) -> void:
	var k := size_k * 1.7                  # 脸撑满核心六元环
	var e := k * 0.17                      # 两眼的水平间距（半）
	var eye_y := center.y - k * 0.08
	var ink := Color(0.08, 0.1, 0.14)
	var white := Color(0.95, 0.98, 1.0)
	var mouth := Vector2(center.x, center.y + k * 0.2)
	var kind := expression()
	draw_circle(center, size_k * 0.78, Color(0.6, 0.8, 1.0, 0.12))   # 脸的底色
	var blink := _blink > 0 and kind in ["idle", "worried", "focus"]
	for side in [-1, 1]:
		var c := Vector2(center.x + side * e, eye_y)
		match kind:
			"hurt":   # > <
				draw_line(c + Vector2(-k * 0.07 * side, -k * 0.06), c + Vector2(k * 0.06 * side, 0), white, 2.5, true)
				draw_line(c + Vector2(k * 0.06 * side, 0), c + Vector2(-k * 0.07 * side, k * 0.06), white, 2.5, true)
			"happy":   # ^ ^
				draw_arc(c + Vector2(0, k * 0.03), k * 0.07, PI * 1.1, PI * 1.9, 10, white, 2.5, true)
			"sad":
				draw_arc(c, k * 0.06, PI * 0.1, PI * 0.9, 10, white, 2.5, true)
			_:
				if blink:
					draw_line(c - Vector2(k * 0.06, 0), c + Vector2(k * 0.06, 0), white, 2.5, true)
				else:
					var h := k * (0.05 if kind in ["focus", "fierce"] else 0.085)
					_ellipse(c, Vector2(k * 0.065, h), white)
					_ellipse(c + Vector2(k * 0.01, h * 0.15), Vector2(k * 0.035, minf(h, k * 0.05)), ink)
					draw_circle(c + Vector2(-k * 0.015, -h * 0.35), k * 0.015, white)
		# 眉毛：担心向上皱、凶狠向下压
		match kind:
			"worried", "sad":
				draw_line(c + Vector2(-k * 0.07, -k * 0.12 + side * k * 0.03), c + Vector2(k * 0.07, -k * 0.12 - side * k * 0.03), white, 2.0, true)
			"fierce":
				draw_line(c + Vector2(-k * 0.07, -k * 0.13 - side * k * 0.04), c + Vector2(k * 0.07, -k * 0.13 + side * k * 0.04), white, 2.5, true)
	match kind:
		"happy":
			draw_arc(mouth, k * 0.11, PI * 0.1, PI * 0.9, 14, white, 3.0, true)
			for side in [-1, 1]:
				draw_circle(Vector2(center.x + side * k * 0.3, mouth.y - k * 0.04), k * 0.05, Color(1.0, 0.55, 0.6, 0.45))
		"hurt":
			_ellipse(mouth + Vector2(0, k * 0.02), Vector2(k * 0.05, k * 0.06), ink)
		"fierce":
			draw_line(mouth + Vector2(-k * 0.08, 0), mouth + Vector2(k * 0.08, -k * 0.01), white, 3.0, true)
		"worried":
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(mouth + Vector2(-k * 0.09 + i * k * 0.03, sin(i * 1.6) * k * 0.015))
			draw_polyline(pts, white, 2.0, true)
		"sad":
			draw_arc(mouth + Vector2(0, k * 0.1), k * 0.09, PI * 1.15, PI * 1.85, 12, white, 2.5, true)
			draw_circle(Vector2(center.x + e + k * 0.02, eye_y + k * 0.12 + fmod(_time * 0.3, 0.1) * k), k * 0.025, Color(0.6, 0.85, 1.0))
		"focus":
			draw_line(mouth + Vector2(-k * 0.05, 0), mouth + Vector2(k * 0.05, 0), white, 2.5, true)
		_:
			draw_arc(mouth, k * 0.08, PI * 0.2, PI * 0.8, 12, white, 2.5, true)


func _ellipse(c: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := i * TAU / 20.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)


func _draw_alert(p: Vector2, k := 1.0) -> void:
	var tri := PackedVector2Array([p + Vector2(0, -9) * k, p + Vector2(9, 7) * k, p + Vector2(-9, 7) * k])
	draw_colored_polygon(tri, UIKit.GOLD)
	draw_line(p + Vector2(0, -3) * k, p + Vector2(0, 2) * k, Color(0.1, 0.08, 0.02), 2.0 * k)
	draw_circle(p + Vector2(0, 4.5) * k, 1.2 * k, Color(0.1, 0.08, 0.02))
