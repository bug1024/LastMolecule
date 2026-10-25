class_name CardFace
extends Control
## 卡牌牌面（纯展示），设计目标是「小朋友也一眼看懂」：
##   边框与名称条按角色上色（攻击红 / 防护蓝 / 技能绿 / 能力金 / 状态灰），右上角有角色徽章；
##   效果用「图标 + 大号数字 + 两三个字」一行一条展示，实时数值变高显示绿色、变低显示红色；
##   左上角是大号费用宝石；插画区按卡牌类型程序绘制。
## 尺寸由 face_scale 决定（基准 180×250）。

const BASE := Vector2(180, 250)

const TYPE_COLOR := {
	"ai": Color(0.29, 0.63, 1.0),
	"molecular": Color(0.6, 0.45, 0.98),
	"experiment": Color(0.95, 0.72, 0.3),
	"clinical": Color(0.95, 0.44, 0.44),
	"process": Color(0.4, 0.82, 0.75),
	"status": Color(0.5, 0.52, 0.58),
}
const ROLE_COLOR := {
	"attack": Color(0.92, 0.32, 0.3),
	"defend": Color(0.3, 0.58, 0.98),
	"skill": Color(0.3, 0.78, 0.5),
	"power": Color(0.98, 0.74, 0.25),
	"status": Color(0.48, 0.5, 0.56),
}
const ROLE_ICON := {
	"attack": "intent_attack",
	"defend": "intent_defend",
	"skill": "role_skill",
	"power": "role_power",
	"status": "intent_debuff",
}
const RARITY_COLOR := {
	"common": Color(0.62, 0.68, 0.76),
	"rare": Color(0.4, 0.72, 1.0),
	"epic": Color(0.98, 0.78, 0.35),
}

var card: ResearchCard = null
var face_scale := 1.0
var hovered := false
var selected := false
var dimmed := false
var _name_label: Label
var _role_label: Label
var _rows: VBoxContainer
var _foot: Label
var pick_style := false   # 奖励挑选用：选中时显示绿色描边与「✓ 已选」徽章（战斗手牌不用）
var _pick_mark: Control
var _ai_multiplier := -1.0   # 会失误的 AI 卡：当前威力倍率（插画右下角的小牌子），-1 表示不显示
var _time := 0.0

const PICK_GREEN := Color(0.35, 0.95, 0.55)


static func create(model: ResearchCard, scale_factor := 1.0, mods := {}, ai_info := {}) -> CardFace:
	var face := CardFace.new()
	face.face_scale = scale_factor
	face.card = model
	face._build()
	face.refresh(mods, ai_info)
	return face


func _build() -> void:
	custom_minimum_size = BASE * face_scale
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = Vector2(size.x * 0.5, size.y)
	_name_label = _label(16, HORIZONTAL_ALIGNMENT_CENTER)
	_name_label.position = Vector2(36, 9) * face_scale
	_name_label.size = Vector2(108, 26) * face_scale
	_role_label = _label(14, HORIZONTAL_ALIGNMENT_CENTER)
	_role_label.position = Vector2(10, 102) * face_scale
	_role_label.size = Vector2(BASE.x - 20, 20) * face_scale
	_rows = VBoxContainer.new()
	_rows.position = Vector2(12, 126) * face_scale
	_rows.size = Vector2(BASE.x - 24, 100) * face_scale
	_rows.add_theme_constant_override("separation", int(2 * face_scale))
	_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)
	_foot = _label(11, HORIZONTAL_ALIGNMENT_CENTER)
	_foot.position = Vector2(8, 228) * face_scale
	_foot.size = Vector2(BASE.x - 16, 16) * face_scale
	_pick_mark = Control.new()
	_pick_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_mark.size = size
	_pick_mark.draw.connect(_draw_pick_mark)
	add_child(_pick_mark)


func _label(font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(font_size * face_scale))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", int(4 * face_scale))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	add_child(l)
	return l


## mods 见 ResearchCard.effect_rows；ai_info 为 {multiplier, deviation}（AI 卡显示倍率与偏差）
func refresh(mods := {}, ai_info := {}) -> void:
	if card == null:
		return
	var role_color := _role_color()
	_name_label.text = tr(card.name) + ("+" if card.upgraded else "")
	_name_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7) if card.upgraded else Color(1, 1, 1))
	_role_label.text = "%s · %s" % [tr("role." + card.role()), tr(card.type_name if not card.type_name.is_empty() else "card.type." + card.type)]
	_role_label.add_theme_color_override("font_color", role_color.lightened(0.35))
	for child in _rows.get_children():
		child.queue_free()
	for row in card.effect_rows(mods):
		_rows.add_child(_make_row(row))
	var foot := card.keywords()
	_foot.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	if card.is_ai():
		if card.reliable:
			foot = tr("cardtext.reliable")
		elif not ai_info.is_empty():
			foot = ai_foot(ai_info)
		_foot.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	_foot.text = foot
	_ai_multiplier = float(ai_info.get("multiplier", 1.0)) if card.can_deviate() and not ai_info.is_empty() else -1.0
	tooltip_text = tr("cardtext.deviation_tip") % card.describe_deviation() if card.can_deviate() and not card.deviation.is_empty() else ""
	queue_redraw()


## AI 卡底部一行：现在的威力，以及离下一档还差多少数据
static func ai_foot(ai_info: Dictionary) -> String:
	var mult := String.num(float(ai_info.get("multiplier", 1.0)), 2)
	var need := int(ai_info.get("need_data", -1))
	if need < 0:
		return TranslationServer.translate("cardtext.ai_max") % [mult, int(ai_info.get("deviation", 15))]
	return TranslationServer.translate("cardtext.ai_next") % [mult, need, String.num(float(ai_info.get("next_multiplier", 1.0)), 2)]


func _make_row(row: Dictionary) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(4 * face_scale))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(UIKit.icon_rect(String(row.icon), 24 * face_scale, row.color))
	if not String(row.number).is_empty():
		var number := Label.new()
		number.text = String(row.number)
		number.theme_type_variation = &"HeaderLabel"
		number.add_theme_font_size_override("font_size", int(24 * face_scale))
		var change := int(row.get("change", 0))
		var color: Color = Color(0.45, 1.0, 0.55) if change > 0 else (Color(1.0, 0.45, 0.4) if change < 0 else Color(1, 0.96, 0.85))
		number.add_theme_color_override("font_color", color)
		number.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		number.add_theme_constant_override("outline_size", int(5 * face_scale))
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(number)
	var text := Label.new()
	text.text = String(row.text)
	text.add_theme_font_size_override("font_size", int(13 * face_scale))
	text.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	text.add_theme_constant_override("outline_size", int(3 * face_scale))
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)
	return box


func set_state(is_hovered: bool, is_selected := false, is_dimmed := false) -> void:
	hovered = is_hovered
	selected = is_selected
	dimmed = is_dimmed
	modulate = Color(0.55, 0.55, 0.6) if dimmed else Color.WHITE
	queue_redraw()
	if _pick_mark:
		_pick_mark.queue_redraw()


## 选中标记：画在所有文字之上——绿色粗描边 + 底部「✓ 已选」徽章
func _draw_pick_mark() -> void:
	if not (selected and pick_style):
		return
	var k := face_scale
	var rect := Rect2(Vector2.ZERO, BASE * k)
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	_pick_mark.draw_style_box(_box(Color(PICK_GREEN, 0.08), PICK_GREEN, 12, 5), rect)
	var c := Vector2(BASE.x * 0.5, BASE.y - 4) * k
	var pill := Rect2(c - Vector2(46, 17) * k, Vector2(92, 34) * k)
	_pick_mark.draw_style_box(_box(Color(0.05, 0.06, 0.09), Color(0.05, 0.06, 0.09), 17, 0), pill.grow(3 * k))
	_pick_mark.draw_style_box(_box(PICK_GREEN.darkened(0.15 * pulse), PICK_GREEN.lightened(0.4), 17, 2), pill)
	var tick := PackedVector2Array([c + Vector2(-34, 0) * k, c + Vector2(-27, 7) * k, c + Vector2(-15, -7) * k])
	_pick_mark.draw_polyline(tick, Color(0.04, 0.2, 0.08), 4.0 * k, true)
	var font := get_theme_default_font()
	var fs := int(17 * k)
	var text := tr("ui.picked")
	_pick_mark.draw_string(font, c + Vector2(-10 * k, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.04, 0.2, 0.08))


func _role_color() -> Color:
	return ROLE_COLOR.get(card.role(), Color.GRAY) if card else Color.GRAY


func _type_color() -> Color:
	return TYPE_COLOR.get(card.type, Color(0.6, 0.6, 0.6)) if card else Color.GRAY


func _process(delta: float) -> void:
	if hovered or selected:
		_time += delta
		queue_redraw()
		if selected and _pick_mark:
			_pick_mark.queue_redraw()


func _draw() -> void:
	if card == null:
		return
	var k := face_scale
	var role_color := _role_color()
	var rarity: Color = RARITY_COLOR.get(card.rarity, RARITY_COLOR.common)
	var rect := Rect2(Vector2.ZERO, BASE * k)
	if selected and pick_style:
		for i in 5:
			draw_style_box(_box(Color(0, 0, 0, 0), Color(PICK_GREEN, 0.55 - i * 0.09), 14 + i * 3, 3), rect.grow((i + 1) * 3 * k))
	elif hovered or selected:
		var glow := Color(role_color.lightened(0.35), 0.35 + 0.15 * sin(_time * 5.0))
		for i in 4:
			draw_style_box(_box(Color(0, 0, 0, 0), glow, 14 + i * 2, 2), rect.grow((i + 1) * 2 * k))
	# 外框：角色色粗边 + 稀有度细内框
	draw_style_box(_box(role_color.lerp(Color(0.05, 0.06, 0.09), 0.8), role_color, 12, 4), rect)
	draw_style_box(_box(Color(0, 0, 0, 0), Color(rarity, 0.7), 9, 1), rect.grow(-5 * k))
	# 名称条
	draw_style_box(_box(role_color.darkened(0.25), role_color.lightened(0.2), 8, 1),
		Rect2(Vector2(30, 8) * k, Vector2(120, 28) * k))
	# 插画区
	var art := Rect2(Vector2(12, 40) * k, Vector2(BASE.x - 24, 60) * k)
	_draw_art(art, _type_color())
	if _ai_multiplier >= 0.0:
		_draw_ai_chip(art)
	draw_style_box(_box(Color(0, 0, 0, 0), role_color.darkened(0.1), 6, 2), art)
	# 效果区底板
	draw_style_box(_box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 8, 0), Rect2(Vector2(10, 124) * k, Vector2(BASE.x - 20, 104) * k))
	var font := get_theme_default_font()
	# 右上角角色徽章
	var badge := Vector2(BASE.x - 18, 20) * k
	draw_circle(badge, 18 * k, Color(0.05, 0.06, 0.09))
	draw_circle(badge, 15.5 * k, role_color)
	draw_arc(badge, 15.5 * k, 0, TAU, 32, role_color.lightened(0.5), 2.0 * k, true)
	var role_icon := UIKit.icon(String(ROLE_ICON.get(card.role(), "role_skill")))
	if role_icon:
		var s := 22 * k
		draw_texture_rect(role_icon, Rect2(badge - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color.WHITE)
	# 左上角费用宝石
	if not card.unplayable:
		var orb := Vector2(20, 20) * k
		draw_circle(orb, 20 * k, Color(0.05, 0.06, 0.09))
		draw_circle(orb, 17 * k, Color(0.98, 0.72, 0.25))
		draw_circle(orb, 13 * k, Color(0.92, 0.55, 0.15))
		draw_circle(orb + Vector2(-5, -5) * k, 6 * k, Color(1, 1, 1, 0.3))
		var fs := int(26 * k)
		var text := str(card.cost)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := orb + Vector2(-w * 0.5, fs * 0.36)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(6 * k), Color(0.2, 0.08, 0.0))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## 插画右下角「AI ×0.5」小牌子：低档红、中档蓝、高档金
func _draw_ai_chip(art: Rect2) -> void:
	var k := face_scale
	var col := Color(0.95, 0.4, 0.38) if _ai_multiplier < 1.0 else (Color(0.4, 0.7, 1.0) if _ai_multiplier <= 1.0 else Color(1.0, 0.8, 0.3))
	var text := "AI ×" + String.num(_ai_multiplier, 2)
	var font := get_theme_default_font()
	var fs := int(14 * k)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12 * k
	var pill := Rect2(art.end - Vector2(w + 4 * k, 22 * k), Vector2(w, 19 * k))
	draw_style_box(_box(Color(0.04, 0.05, 0.08, 0.92), col, 9, 2), pill)
	draw_string(font, pill.position + Vector2(6 * k, 14.5 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.25))


func _draw_art(art: Rect2, accent: Color) -> void:
	var top := accent.darkened(0.15)
	var bottom := accent.darkened(0.7)
	draw_polygon(PackedVector2Array([art.position, Vector2(art.end.x, art.position.y), art.end, Vector2(art.position.x, art.end.y)]),
		PackedColorArray([top, top.darkened(0.2), bottom, bottom]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(card.id)
	var k := face_scale
	var line := Color(1, 1, 1, 0.18)
	match card.type:
		"molecular":
			for i in 3:
				var c := art.position + Vector2(rng.randf_range(0.15, 0.85) * art.size.x, rng.randf_range(0.25, 0.75) * art.size.y)
				var r := rng.randf_range(9, 15) * k
				var pts := PackedVector2Array()
				for j in 7:
					pts.append(c + Vector2(cos(PI / 6 + j * TAU / 6), sin(PI / 6 + j * TAU / 6)) * r)
				draw_polyline(pts, line, 2.0 * k, true)
		"experiment":
			for i in 14:
				var p := art.position + Vector2(rng.randf() * art.size.x, rng.randf() * art.size.y)
				draw_circle(p, rng.randf_range(2, 5) * k, Color(1, 1, 1, 0.12))
		"clinical":
			var pts := PackedVector2Array()
			for i in 24:
				var x := art.position.x + art.size.x * i / 23.0
				var y := art.get_center().y + (rng.randf_range(-1, 1) * 15 * k if i % 5 == 2 else rng.randf_range(-3, 3) * k)
				pts.append(Vector2(x, y))
			draw_polyline(pts, Color(1, 1, 1, 0.25), 2.0 * k, true)
		"ai":
			var nodes: Array[Vector2] = []
			for i in 9:
				nodes.append(art.position + Vector2((0.15 + 0.35 * (i / 3)) * art.size.x, (0.2 + 0.3 * (i % 3)) * art.size.y))
			for i in 6:
				for j in 3:
					draw_line(nodes[i], nodes[3 * (i / 3 + 1) + j], line, 1.0 * k, true)
			for n in nodes:
				draw_circle(n, 3 * k, Color(1, 1, 1, 0.3))
		"process":
			for i in 3:
				var c := art.position + Vector2((0.2 + 0.3 * i) * art.size.x, art.size.y * 0.5 + rng.randf_range(-6, 6) * k)
				draw_arc(c, 12 * k, 0, TAU, 16, line, 3.0 * k, true)
		_:
			for i in 6:
				var a := Vector2(rng.randf() * art.size.x, rng.randf() * art.size.y) + art.position
				draw_line(a, a + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)) * k, Color(1, 1, 1, 0.2), 2.0 * k)
	var icon := UIKit.icon("type_" + card.type if card.type != "status" else "intent_debuff")
	if icon:
		var s := art.size.y * 0.8
		draw_texture_rect(icon, Rect2(art.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, 0.92))


func _box(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(width * face_scale))
	sb.set_corner_radius_all(int(radius * face_scale))
	sb.anti_aliasing = true
	return sb
