class_name MoleculeView
extends Control
## Live scaffold with pre-rendered chemical fragments: shared by battle, hub and editor.
## Site identity, picking, pocket hints and property flashes remain tied to the actual molecule.
## Reactions use local charge light and bond motion; the core has no face or instrument disk.

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
var face := false       # Enable ambient evolution/reaction light in battle and hub.
var form := 1           # 进化形态 1–5
var mood := ""          # 持续反应：focus / sad；空为按 ratio 自动（idle / worried）
var ratio := 1.0        # 生命比例（低了会担心）
var _react := ""        # 短暂反应：hurt / happy / fierce
var _react_t := 0.0
var _glow_burst := 0.0  # 进化时的闪光
var _jolt := {}         # 位点 → [偏移, 速度]：受击时片段被震开再弹回
var _offset := Vector2.ZERO   # 本帧整体位移（抖动 / 浮动 / 跳跃）

const SITE_R := 28.0
const TYPE_MARK := {"linker": "连", "ring": "环", "terminal": "端"}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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


## 受击：抖动泛红、片段被震开再弹回；strength 随伤害大小
func hit(strength := 1.0) -> void:
	_hit = 1.0
	react("hurt", 0.7)
	for site in Molecule.config().get("sites", []):
		var dir := Vector2.from_angle(randf() * TAU)
		_jolt[String(site.id)] = [Vector2.ZERO, dir * randf_range(260.0, 520.0) * clampf(strength, 0.4, 2.0)]


func cheer() -> void:
	_cheer = 1.0
	react("happy", 3.0)


## 出招：一瞬间的局部电荷辉光
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


## 当前反应：短暂反馈优先，其次持续状态，最后看生命
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
	if compact:
		return maxf(7.0, _scale() * 0.36)
	return minf(SITE_R, _scale() * (0.62 if interactive else 0.44))


func _scale() -> float:
	return unit if unit > 0 else minf(size.x / 8.0, size.y / 4.9)


func site_center(site: Dictionary) -> Vector2:
	var p: Array = site.get("pos", [0, 0])
	var projected := Vector2(float(p[0]) + float(p[1]) * 0.12, float(p[1]) * 0.88)
	return size * Vector2(0.5, 0.48) + projected * _scale()


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
	var nearest := ""
	var distance := INF
	for site in Molecule.config().get("sites", []):
		var center := site_center(site)
		var id := String(site.id)
		var frag_id := String(molecule.sites.get(id, "")) if molecule != null else ""
		var inside := center.distance_to(pos) <= _site_r() + 4
		if not frag_id.is_empty():
			inside = inside or MoleculeSpecimen.bounds(frag_id, center, _scale()).grow(4).has_point(pos)
		if inside and center.distance_squared_to(pos) < distance:
			nearest = id
			distance = center.distance_squared_to(pos)
	return nearest


func _draw() -> void:
	var cfg := Molecule.config()
	var center := size * Vector2(0.5, 0.48)
	var k := _scale()
	var offset := Vector2(sin(_time * 70.0) * 6.0 * _hit, 0)
	if idle_bob:
		offset.y += sin(_time * 2.0) * 3.0
	offset.y -= absf(sin(_time * 9.0)) * 10.0 * _cheer
	_offset = offset
	draw_set_transform(offset)
	if _cheer > 0:
		Shading.glow(self, center, k * 2.6, Color(0.55, 1.0, 0.75, 0.3 * _cheer))
	if face and not compact:
		_draw_form(center, k)
	var font := get_theme_default_font()
	var bw := maxf(1.2, k * 0.065)
	var bond_col := Color(0.64, 0.72, 0.78)
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
				anchor = center + (c - center).normalized() * Vector2(k * 0.64, k * 0.42)
		var filled := molecule != null and molecule.sites.has(String(site.id))
		Shading.bond(self, anchor, c, bw * (1.0 if filled else 0.6), Color(bond_col, 1.0 if filled else 0.35))
	MoleculeSpecimen.draw_fragment(self, "core", center, k)
	# 位点：绘制对应化学片段；名字只在编辑器里写
	var r := _site_r()
	for site in cfg.get("sites", []):
		var id := String(site.id)
		var c := _pos(site)
		var frag_id := String(molecule.sites.get(id, "")) if molecule != null else ""
		var is_sel := interactive and id == selected
		if is_sel:
			var pulse := 0.5 + 0.5 * sin(_time * 5.0)
			Shading.glow(self, c, r + 16 + pulse * 4, Color(UIKit.ACCENT, 0.4))
			draw_arc(c, r + 6, 0, TAU, 40, Color(UIKit.ACCENT, 0.9), 2.5, true)
		elif interactive and id == _hover:
			draw_arc(c, r + 5, 0, TAU, 40, Color(1, 1, 1, 0.4), 1.5, true)
		if frag_id.is_empty():
			if not interactive:
				MoleculeSpecimen.draw_fragment(self, "hydrogen", c, k)   # 空位：只留一个小氢原子似的点
				continue
			draw_circle(c, r, Color(0.06, 0.08, 0.11, 0.95))
			for d in 16:
				var a0 := d * TAU / 16.0
				draw_arc(c, r, a0, a0 + TAU / 32.0, 4, Color(0.6, 0.68, 0.76, 0.6), 1.5, true)
			var mark := String(TYPE_MARK.get(String(site.type), "?"))
			var mw := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, c + Vector2(-mw * 0.5, 6), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.68, 0.76, 0.8))
			continue
		var frag := Molecule.fragment(frag_id)
		var col := Color.from_string(String(frag.get("color", "#9fb4c8")), Color(0.6, 0.7, 0.8))
		for prop in _flash:   # 效果生效时，给这项属性加分的片段发亮
			if int(frag.get("fx", {}).get(prop, 0)) > 0:
				var f := float(_flash[prop])
				Shading.glow(self, c, r * (1.6 + (1.0 - f) * 0.8), Color(col.lightened(0.4), 0.7 * f))
		if _site_flash.has(id):
			var sf: Array = _site_flash[id]
			var t := float(sf[0])
			Shading.glow(self, c, r * (1.7 + (1.0 - t) * 0.9), Color(sf[1], 0.8 * t))
			draw_arc(c, r + 3, 0, TAU, 32, Color(sf[1], t), 2.5, true)
		MoleculeSpecimen.draw_fragment(self, frag_id, c, k)
		if not String(frag.get("alert", "")).is_empty():
			_draw_alert(c + Vector2(r * 0.85, -r * 0.85), 0.6 if compact else (1.0 if interactive else 0.75))
		if not interactive:
			continue
		var frag_name := tr("frag." + frag_id)
		var fs := 12
		var label_y := -MoleculeSpecimen.bounds(frag_id, c, k).size.y * 0.5 - 7.0
		var nw := font.get_string_size(frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, c + Vector2(-nw * 0.5, label_y), frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.75))
		draw_string(font, c + Vector2(-nw * 0.5, label_y), frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if interactive:
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


## Local electronic-density light keeps the structure, rather than a face, expressive.
func _draw_form(center: Vector2, k: float) -> void:
	var col := Color(0.25, 0.66, 0.75)
	if ratio < 0.35:
		col = Color(0.8, 0.38, 0.25)
	var reaction := maxf(_glow_burst, _react_t * 0.3)
	if _react == "hurt" and _react_t > 0:
		col = Color(0.9, 0.25, 0.22)
	var strength := 0.035 * mini(form, 5) + reaction * 0.12
	Shading.glow(self, center, k * 2.3, Color(col, strength))
	if reaction > 0.02:
		for site in Molecule.config().get("sites", []):
			if molecule != null and molecule.sites.has(String(site.id)):
				Shading.glow(self, _pos(site), k * 0.5, Color(col, reaction * 0.2))


func _draw_alert(p: Vector2, k := 1.0) -> void:
	var tri := PackedVector2Array([p + Vector2(0, -9) * k, p + Vector2(9, 7) * k, p + Vector2(-9, 7) * k])
	draw_colored_polygon(tri, UIKit.GOLD)
	draw_line(p + Vector2(0, -3) * k, p + Vector2(0, 2) * k, Color(0.1, 0.08, 0.02), 2.0 * k)
	draw_circle(p + Vector2(0, 4.5) * k, 1.2 * k, Color(0.1, 0.08, 0.02))
