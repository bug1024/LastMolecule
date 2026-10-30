class_name MoleculeView
extends Control
## 分子结构图：中间是六元环核心，周围是 7 个带类型的位点（data/molecule.json 的 sites 坐标），
## 片段画成带颜色的原子徽章并写上名字；带毒性警示的片段旁有警示标记。
## interactive 时可以点位点（site_clicked），选中的位点发光；编辑器和研发总览共用。

signal site_clicked(site_id: String)

var molecule: Molecule = null
var interactive := false
var selected := ""
var unit := 0.0
var _time := 0.0
var _hover := ""

const SITE_R := 28.0
const TYPE_MARK := {"linker": "连", "ring": "环", "terminal": "端"}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE


func set_molecule(m: Molecule) -> void:
	molecule = m
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


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


func _site_at(pos: Vector2) -> String:
	for site in Molecule.config().get("sites", []):
		if site_center(site).distance_to(pos) <= SITE_R + 4:
			return String(site.id)
	return ""


func _draw() -> void:
	var cfg := Molecule.config()
	var center := size * Vector2(0.5, 0.52)
	var k := _scale()
	var bond := Color(0.7, 0.8, 0.9, 0.55)
	# 核心六元环
	var ring := PackedVector2Array()
	for i in 7:
		var a := PI / 6 + i * TAU / 6
		ring.append(center + Vector2(cos(a), sin(a)) * k * 0.82)
	draw_polyline(ring, Color(0.75, 0.85, 0.95, 0.85), 3.0, true)
	var inner := PackedVector2Array()
	for i in 7:
		var a := PI / 6 + i * TAU / 6
		inner.append(center + Vector2(cos(a), sin(a)) * k * 0.55)
	draw_polyline(inner, Color(0.75, 0.85, 0.95, 0.25), 2.0, true)
	var font := get_theme_default_font()
	var core_text := tr("mol.core")
	var tw := font.get_string_size(core_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, center + Vector2(-tw * 0.5, 5), core_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.9, 0.7))
	# 键：环上位点和连接位接在核心环上，末端位接在连接位上
	var by_id := {}
	for site in cfg.get("sites", []):
		by_id[String(site.id)] = site
	for site in cfg.get("sites", []):
		var c := site_center(site)
		var anchor: Vector2
		match String(site.type):
			"terminal":
				anchor = site_center(by_id["L1" if float(site.pos[0]) < 0 else "L2"])
			_:
				anchor = center + (c - center).normalized() * k * 0.82
		draw_line(anchor, c, bond, 3.0, true)
	# 位点
	for site in cfg.get("sites", []):
		var id := String(site.id)
		var c := site_center(site)
		var frag_id := String(molecule.sites.get(id, "")) if molecule != null else ""
		var is_sel := interactive and id == selected
		if is_sel:
			var pulse := 0.5 + 0.5 * sin(_time * 5.0)
			draw_circle(c, SITE_R + 8 + pulse * 3, Color(UIKit.ACCENT, 0.18))
			draw_arc(c, SITE_R + 6, 0, TAU, 40, Color(UIKit.ACCENT, 0.9), 2.5, true)
		elif interactive and id == _hover:
			draw_arc(c, SITE_R + 5, 0, TAU, 40, Color(1, 1, 1, 0.4), 1.5, true)
		if frag_id.is_empty():
			draw_circle(c, SITE_R, Color(0.06, 0.08, 0.11, 0.95))
			for d in 16:
				var a0 := d * TAU / 16.0
				draw_arc(c, SITE_R, a0, a0 + TAU / 32.0, 4, Color(0.6, 0.68, 0.76, 0.6), 1.5, true)
			var mark := String(TYPE_MARK.get(String(site.type), "?"))
			var mw := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, c + Vector2(-mw * 0.5, 6), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.68, 0.76, 0.8))
			continue
		var frag := Molecule.fragment(frag_id)
		var col := Color.from_string(String(frag.get("color", "#9fb4c8")), Color(0.6, 0.7, 0.8))
		draw_circle(c, SITE_R + 3, Color(col, 0.2))
		draw_circle(c, SITE_R, col.darkened(0.45))
		draw_arc(c, SITE_R, 0, TAU, 40, col.lightened(0.2), 2.5, true)
		var frag_name := tr("frag." + frag_id)
		var fs := 15 if frag_name.length() <= 3 else 12
		var nw := font.get_string_size(frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, c + Vector2(-nw * 0.5, fs * 0.36), frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.7))
		draw_string(font, c + Vector2(-nw * 0.5, fs * 0.36), frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if not String(frag.get("alert", "")).is_empty():
			_draw_alert(c + Vector2(SITE_R * 0.8, -SITE_R * 0.8))


func _draw_alert(p: Vector2) -> void:
	var tri := PackedVector2Array([p + Vector2(0, -9), p + Vector2(9, 7), p + Vector2(-9, 7)])
	draw_colored_polygon(tri, UIKit.GOLD)
	draw_line(p + Vector2(0, -3), p + Vector2(0, 2), Color(0.1, 0.08, 0.02), 2.0)
	draw_circle(p + Vector2(0, 4.5), 1.2, Color(0.1, 0.08, 0.02))
