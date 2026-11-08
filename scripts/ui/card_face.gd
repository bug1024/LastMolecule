class_name CardFace
extends Control
## 骨白牌面、几何厚涂插画与实时效果行。阅读顺序：
##   ① 左上费用宝石 + 名称条（按角色上色：攻击红 / 防护蓝 / 技能绿 / 能力金 / 状态灰；名称过长自动缩字或换行）
##   ② 效果区：「图标 + 大号数字 + 两三个字」一行一条，实时数值变高显示绿色、变低显示红色
##   ③ 关键词与限制（消耗 / 无法打出 / AI 失误率）紧跟效果
##   ④ 插画区只放辅助信息：类型小标签、角色图标、稀有度宝石、AI 倍率
## 正常战斗手牌使用至少 12px 字号。右键（或长按）打开 CardDetail 看完整说明。
## 尺寸由 face_scale 决定（基准 180×250）。

const BASE := Vector2(180, 250)

const TYPE_COLOR := {
	"ai": UIKit.ACCENT_BLUE,
	"molecular": Color(0.6, 0.45, 0.98),
	"experiment": UIKit.GOLD,
	"clinical": UIKit.DANGER,
	"process": UIKit.ACCENT,
	"status": Color(0.5, 0.52, 0.58),
}
const ROLE_COLOR := {
	"attack": UIKit.DANGER,
	"defend": UIKit.ACCENT_BLUE,
	"skill": UIKit.ACCENT,
	"power": UIKit.GOLD,
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
var detail_enabled := true   # 右键 / 长按打开大图说明
var _art_layer: Control
var _name_label: Label
var _rows: Control
var _type_text := ""
var pick_style := false   # 奖励挑选用：选中时显示绿色描边与「✓ 已选」徽章（战斗手牌不用）
var _pick_mark: Control
var _ai_multiplier := -1.0   # 会失误的 AI 卡：当前威力倍率（插画右下角的小牌子），-1 表示不显示
var _time := 0.0
var _mods := {}
var _ai_info := {}
var _press_time := -1.0

const PICK_GREEN := UIKit.ACCENT
const MIN_FONT := 15   # 基准字号下限：0.9 倍时约 12.6px
const LONG_PRESS := 0.5
# 牌面布局（基准坐标）
const NAME_RECT := Rect2(6, 6, 168, 34)
const ART_RECT := Rect2(14, 44, 152, 76)   # 和 record.png 卡框里的插画窗口对齐
const BODY_RECT := Rect2(10, 126, 160, 116)


static func create(model: ResearchCard, scale_factor := 1.0, mods := {}, ai_info := {}) -> CardFace:
	var face := CardFace.new()
	face.face_scale = scale_factor
	face.card = model
	face._build()
	face.refresh(mods, ai_info)
	return face


func _build() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = BASE * face_scale
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = Vector2(size.x * 0.5, size.y)
	_art_layer = Control.new()
	_art_layer.position = ART_RECT.position * face_scale
	_art_layer.size = ART_RECT.size * face_scale
	_art_layer.clip_contents = true
	_art_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.draw.connect(func() -> void:
		var area := Rect2(Vector2.ZERO, _art_layer.size)
		_draw_art(area)
		_draw_art_inset(area)
		_draw_art_tags(area, _role_color()))
	add_child(_art_layer)
	_name_label = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_name_label.position = Vector2(NAME_RECT.position.x + 38, NAME_RECT.position.y) * face_scale
	_name_label.size = Vector2(NAME_RECT.size.x - 42, NAME_RECT.size.y) * face_scale
	_rows = Control.new()
	_rows.position = BODY_RECT.position * face_scale
	_rows.size = BODY_RECT.size * face_scale
	_rows.clip_contents = true
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)
	_pick_mark = Control.new()
	_pick_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_mark.size = size
	_pick_mark.draw.connect(_draw_pick_mark)
	add_child(_pick_mark)


func _label(font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", _px(font_size))
	l.add_theme_color_override("font_outline_color", UIKit.TEXT)
	l.add_theme_constant_override("outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


static func _bold_font() -> Font:
	var theme := ThemeDB.get_project_theme()
	if theme and theme.has_font("font", &"NumberLabel"):
		return theme.get_font("font", &"NumberLabel")   # 数字单独一套窄体字
	return ThemeDB.fallback_font


func _px(base_size: float) -> int:
	return maxi(1, int(round(base_size * face_scale)))


## Fit both dimensions against the actual font in use, in rendered pixels.
func _fit(text: String, font: Font, width: float, height: float, preferred: int, floor_size: int) -> int:
	for fs in range(preferred, floor_size - 1, -1):
		if font.get_height(fs) <= height and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
			return fs
	return floor_size


## mods 见 ResearchCard.effect_rows；ai_info 为 {multiplier, deviation, need_data...}（AI 卡显示倍率与失误率）
func refresh(mods := {}, ai_info := {}) -> void:
	if card == null:
		return
	_mods = mods
	_ai_info = ai_info
	_set_name(tr(card.name) + ("+" if card.upgraded else ""))
	_name_label.add_theme_color_override("font_color", Color("28634c") if card.upgraded else UIKit.INK)
	_type_text = tr(card.type_name if not card.type_name.is_empty() else "card.type." + card.type)
	_layout_effects(card.effect_rows(mods), _notes(ai_info))
	_ai_multiplier = float(ai_info.get("multiplier", 1.0)) if card.can_deviate() and not ai_info.is_empty() else -1.0
	tooltip_text = ""
	queue_redraw()
	_art_layer.queue_redraw()


func _set_name(text: String) -> void:
	_name_label.text = text
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var fs := _fit(text, _name_label.get_theme_default_font(), _name_label.size.x - _px(4),
		_name_label.size.y, _px(18), _px(MIN_FONT))
	_name_label.add_theme_font_size_override("font_size", fs)
	_name_label.size = Vector2(NAME_RECT.size.x - 42, NAME_RECT.size.y) * face_scale


## 效果下方的限制说明：关键词（消耗 / 无法打出…）+ AI 失误率
func _notes(ai_info: Dictionary) -> Array:
	var notes: Array = []
	for word in card.keywords().split(" · ", false):
		notes.append({"text": word, "color": Color(0.95, 0.82, 0.55)})
	if card.is_ai():
		if card.reliable:
			notes.append({"text": tr("cardtext.reliable"), "color": Color(0.6, 0.85, 1.0)})
		elif card.can_deviate() and not ai_info.is_empty():
			notes.append({"text": tr("cardtext.miss") % int(ai_info.get("deviation", 15)), "color": Color(0.6, 0.85, 1.0)})
	return notes


## AI 卡底部一行：现在的威力，以及离下一档还差多少数据（大图说明里用）
static func ai_foot(ai_info: Dictionary) -> String:
	var mult := String.num(float(ai_info.get("multiplier", 1.0)), 2)
	var need := int(ai_info.get("need_data", -1))
	if need < 0:
		return TranslationServer.translate("cardtext.ai_max") % [mult, int(ai_info.get("deviation", 15))]
	return TranslationServer.translate("cardtext.ai_next") % [mult, need, String.num(float(ai_info.get("next_multiplier", 1.0)), 2)]


func _layout_effects(effects: Array, notes: Array) -> void:
	for child in _rows.get_children():
		# A hover or target change can refresh several times before the next frame.
		_rows.remove_child(child)
		child.queue_free()
	var gap := _px(3)
	var count := effects.size() + notes.size()
	var note_height := _px(22)
	var effect_budget := _rows.size.y - notes.size() * note_height - maxi(0, count - 1) * gap
	var row_height := minf(_px(37), floorf(effect_budget / maxi(1, effects.size())))
	var stack_height := effects.size() * row_height + notes.size() * note_height + maxi(0, count - 1) * gap
	var y := floorf((_rows.size.y - stack_height) * 0.5)
	for row in effects:
		var line := _make_row(row, Vector2(_rows.size.x, row_height))
		line.position.y = y
		_rows.add_child(line)
		y += row_height + gap
	for note in notes:
		var note_width := _rows.size.x - _px(6)
		var font := get_theme_default_font()
		var fs := _fit(String(note.text), font, note_width, note_height, _px(15), _px(MIN_FONT))
		var label := _effect_label(String(note.text), Color(note.color).darkened(0.55), font, fs)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(label)
		label.set_deferred("size", Vector2(note_width, note_height))
		label.position = Vector2(_px(3), y)
		y += note_height + gap


func _effect_label(text: String, ink: Color, font: Font, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", ink)
	label.add_theme_constant_override("outline_size", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	return label


func _make_row(row: Dictionary, bounds: Vector2) -> Control:
	var line := Control.new()
	line.size = bounds
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gap := _px(4)
	var inset := _px(6)
	var icon_size := minf(_px(24), bounds.y - _px(4))
	var number_text := String(row.number)
	var caption := String(row.text)
	var number_font := _bold_font()
	var text_font := get_theme_default_font()
	var width := bounds.x - inset * 2 - icon_size - gap
	var caption_min := minf(width, ceilf(text_font.get_string_size(caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _px(MIN_FONT)).x))
	var number_width := 0.0
	var number_size := _px(30)
	if not number_text.is_empty():
		var number_budget := maxf(width * 0.34, width - caption_min - gap)
		number_size = _fit(number_text, number_font, number_budget, bounds.y, _px(30), _px(MIN_FONT))
		number_width = ceilf(number_font.get_string_size(number_text, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size).x) + 1
		width -= number_width + gap
	var caption_size := _fit(caption, text_font, width, bounds.y, _px(17), _px(MIN_FONT))
	var caption_width := minf(width, ceilf(text_font.get_string_size(caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x) + 1)
	var occupied := icon_size + gap + caption_width
	if not number_text.is_empty():
		occupied += number_width + gap
	var x := floorf((bounds.x - occupied) * 0.5)
	var icon_name := String(row.icon)
	var icon_ink := Color(row.color).darkened(0.18 if icon_name == "intent_attack" else 0.42)
	var icon := UIKit.icon_rect(icon_name, icon_size, icon_ink)
	icon.size = Vector2.ONE * icon_size
	icon.position = Vector2(x, (bounds.y - icon_size) * 0.5)
	line.add_child(icon)
	x += icon_size + gap
	if not number_text.is_empty():
		var change := int(row.get("change", 0))
		var ink := Color("28634c") if change > 0 else (Color("a43f38") if change < 0 else UIKit.INK)
		var number := _effect_label(number_text, ink, number_font, number_size)
		number.position.x = x
		line.add_child(number)
		number.set_deferred("size", Vector2(number_width, bounds.y))
		x += number_width + gap
	var text := _effect_label(caption, UIKit.INK, text_font, caption_size)
	text.position.x = x
	line.add_child(text)
	text.set_deferred("size", Vector2(caption_width, bounds.y))
	return line


## 右键 / 长按：打开大图说明（战斗里左键已被出牌占用，所以只靠右键）
func _gui_input(event: InputEvent) -> void:
	if not detail_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			open_detail()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_press_time = 0.0 if mb.pressed else -1.0
	elif event is InputEventMouseMotion and _press_time >= 0.0 and (event as InputEventMouseMotion).relative.length() > 6:
		_press_time = -1.0


func open_detail() -> void:
	_press_time = -1.0
	CardDetail.open(self, card, _mods, _ai_info)


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
	_pick_mark.draw_style_box(_box(Color(0.055, 0.075, 0.11), Color(0.055, 0.075, 0.11), 17, 0), pill.grow(3 * k))
	_pick_mark.draw_style_box(_box(PICK_GREEN.darkened(0.15 * pulse), PICK_GREEN.lightened(0.4), 17, 2), pill)
	var tick := PackedVector2Array([c + Vector2(-34, 0) * k, c + Vector2(-27, 7) * k, c + Vector2(-15, -7) * k])
	_pick_mark.draw_polyline(tick, Color(0.055, 0.075, 0.11), 4.0 * k, true)
	var font := get_theme_default_font()
	var fs := int(17 * k)
	var text := tr("ui.picked")
	_pick_mark.draw_string(font, c + Vector2(-10 * k, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.055, 0.075, 0.11))


func _role_color() -> Color:
	return ROLE_COLOR.get(card.role(), Color.GRAY) if card else Color.GRAY


func _type_color() -> Color:
	if card == null:
		return Color.GRAY
	# 片段牌用它在分子上那个片段的颜色，特性卡用金色：整手分子牌不再是一片紫
	if card.id.begins_with("frag_"):
		var frag := Molecule.fragment(card.id.trim_prefix("frag_"))
		return Color.from_string(String(frag.get("color", "#9fb4c8")), Color(0.6, 0.7, 0.8))
	if card.id.begins_with("sig_"):
		return UIKit.GOLD
	return TYPE_COLOR.get(card.type, Color(0.6, 0.6, 0.6))


func _process(delta: float) -> void:
	if _press_time >= 0.0:
		_press_time += delta
		if _press_time >= LONG_PRESS:
			open_detail()
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
	var rect := Rect2(Vector2.ZERO, BASE * k)
	if selected and pick_style:
		for i in 2:
			draw_style_box(_box(Color(0, 0, 0, 0), Color(PICK_GREEN, 0.55 - i * 0.09), 14 + i * 3, 3), rect.grow((i + 1) * 3 * k))
	elif hovered or selected:
		var glow := Color(role_color.lightened(0.35), 0.35 + 0.15 * sin(_time * 5.0))
		for i in 1:
			draw_style_box(_box(Color(0, 0, 0, 0), glow, 14 + i * 2, 2), rect.grow((i + 1) * 2 * k))
	PaintedArt.frame(self, rect, UIKit.PAPER, UIKit.GOLD.darkened(0.25), 1.5 * k)
	var header := Rect2(NAME_RECT.position * k, NAME_RECT.size * k)
	draw_style_box(_box(role_color.lerp(UIKit.PAPER, 0.70), Color(role_color, 0.6), 2, 1), header)
	if card.upgraded:
		_draw_upgrade_mark(rect, k)
	var body := Rect2(BODY_RECT.position * k, BODY_RECT.size * k)
	# 正文区就是卡面本身的纸，不再盖一块平涂的色块；只留一道刻线分隔
	draw_line(body.position + Vector2(6 * k, 0), Vector2(body.end.x - 6 * k, body.position.y), Color(UIKit.INK, 0.3), k, true)
	draw_line(body.position + Vector2(6 * k, k), Vector2(body.end.x - 6 * k, body.position.y + k), Color(1, 1, 1, 0.3), k, true)
	# 左上角费用宝石
	if not card.unplayable:
		var font: Font = get_theme_font("font", &"NumberLabel")
		var orb := Vector2(24, 23) * k
		var gem := PackedVector2Array()
		for j in 6:
			gem.append(orb + Vector2.from_angle(PI / 6 + j * TAU / 6) * 19 * k)
		draw_colored_polygon(gem, UIKit.DANGER.darkened(0.2) if card.damaged else Color("397b68"))   # 受损的片段卡：费用宝石变红
		gem.append(gem[0])
		draw_polyline(gem, UIKit.PAPER, 2 * k, true)
		var fs := _px(30)
		var text := str(card.cost)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := orb + Vector2(-w * 0.5, fs * 0.36)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color(0.055, 0.075, 0.11))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.TEXT)


## 升级过的卡：内圈一道金线，顶边嵌一颗金色菱形，缩小成手牌也认得出
func _draw_upgrade_mark(rect: Rect2, k: float) -> void:
	var line := PaintedArt.contour(rect.grow(-3.5 * k), 12)
	line.append(line[0])
	draw_polyline(line, Color(UIKit.GOLD, 0.95), maxf(1.0, 1.5 * k), true)
	var c := Vector2(rect.size.x * 0.5, 2.0 * k)
	var diamond := PackedVector2Array([c + Vector2(0, -7) * k, c + Vector2(8, 0) * k, c + Vector2(0, 7) * k, c + Vector2(-8, 0) * k])
	draw_colored_polygon(diamond, UIKit.GOLD)
	diamond.append(diamond[0])
	draw_polyline(diamond, UIKit.INK, maxf(1.0, k), true)


## 插画上的小标记：左下类型、右上角色图标、左上稀有度宝石、右下 AI 倍率
func _draw_art_tags(art: Rect2, role_color: Color) -> void:
	var k := face_scale
	var font := get_theme_default_font()
	var fs := _px(MIN_FONT)
	var type_color := _type_color()
	var tw := font.get_string_size(_type_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tag := Rect2(Vector2(3 * k, art.size.y - fs - 8 * k), Vector2(minf(tw + 10 * k, art.size.x - 6 * k), fs + 5 * k))
	_art_layer.draw_style_box(_box(type_color.darkened(0.7), type_color, 3, 1), tag)
	_art_layer.draw_string(font, tag.position + Vector2(5 * k, fs), _type_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, type_color.lightened(0.35))
	var badge := Vector2(art.size.x - 14 * k, 14 * k)
	_art_layer.draw_circle(badge, 12 * k, role_color.darkened(0.65))
	_art_layer.draw_arc(badge, 12 * k, 0, TAU, 32, role_color, k, true)
	var role_icon := UIKit.icon(String(ROLE_ICON.get(card.role(), "role_skill")))
	if role_icon:
		_art_layer.draw_texture_rect(role_icon, Rect2(badge - Vector2(8, 8) * k, Vector2(16, 16) * k), false, Color.WHITE)
	if card.rarity != "common":
		var c := Vector2(10, 10) * k
		var gem := PackedVector2Array([c + Vector2(0, -5) * k, c + Vector2(5, 0) * k, c + Vector2(0, 5) * k, c + Vector2(-5, 0) * k])
		_art_layer.draw_colored_polygon(gem, RARITY_COLOR.get(card.rarity, Color.WHITE))
	if _ai_multiplier >= 0.0:
		_draw_ai_chip(art)


## 插画右下角「AI ×0.5」小牌子：低档红、中档蓝、高档金
func _draw_ai_chip(art: Rect2) -> void:
	var k := face_scale
	var col := UIKit.DANGER if _ai_multiplier < 1.0 else (UIKit.ACCENT_BLUE if _ai_multiplier <= 1.0 else UIKit.GOLD)
	var text := "AI ×" + String.num(_ai_multiplier, 2)
	var font := get_theme_default_font()
	var fs := _px(MIN_FONT)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12 * k
	var h := fs + 6 * k
	var pill := Rect2(art.end - Vector2(w + 3 * k, h + 25 * k), Vector2(w, h))
	_art_layer.draw_style_box(_box(Color(Color(0.055, 0.075, 0.11), 0.92), col, 8, 2), pill)
	_art_layer.draw_string(font, pill.position + Vector2(6 * k, h * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.25))


## 插画：先按卡牌的作用挑图（攻击＝结合、护盾＝防护、AI＝推理……），再按卡牌 id 取不同的局部取景、
## 左右翻转，让同类型的牌也各长各样，手牌里不会排一排一模一样的图
## Positive destination sizes are required. Mirror the canvas transform, not the destination rectangle.
static func art_region(card_id: String, cell: int, area: Rect2, texture_size: Vector2) -> Dictionary:
	var cell_size := texture_size / Vector2(3, 2)
	var h := absi(hash(card_id))
	var zoom := 0.62 + float(h % 23) / 100.0
	var aspect := area.size.x / maxf(area.size.y, 1.0)
	var region_size := Vector2(cell_size.x * zoom, minf(cell_size.x * zoom / aspect, cell_size.y))
	var slack := cell_size - region_size
	var offset := Vector2(float((h / 23) % 100) / 100.0, float((h / 2300) % 100) / 100.0) * slack
	return {"source": Rect2(Vector2(cell % 3, cell / 3) * cell_size + offset, region_size), "destination": area.abs(), "mirrored": (h / 7) % 2 == 1}


const CARD_SHEETS := {
	"geometric-cards-a": [
		"mol_hit", "mol_target", "mol_analog", "mol_scaffold", "mol_selectivity",
		"mol_broad", "mol_prodrug", "mol_multivalent", "mol_sar", "mol_covalent",
		"exp_assay", "exp_tox_screen", "exp_organoid", "exp_controls", "exp_hts",
		"exp_glp", "exp_biomarker", "exp_counter", "exp_stable_platform", "exp_safety_net",
		"exp_replicate", "clin_dosing", "clin_protocol", "clin_site", "clin_monitor",
	],
	"geometric-cards-b": [
		"clin_combo", "clin_endpoint", "clin_network", "ai_screen", "ai_tox_predict",
		"ai_design", "ai_governance", "ai_intel", "ai_structure", "ai_generate",
		"ai_stratify", "ai_agent", "ai_lead_opt", "ai_mlops", "proc_sop",
		"proc_qbd", "proc_lims", "proc_platform", "proc_formulation", "proc_review",
		"sig_stacking", "sig_balance", "sig_shield", "noise", "ae_card",
	],
}


# The hand-painted sheet seams are measured, not inferred from nominal grid dimensions.
const CARD_SHEET_ROWS := {
	"geometric-cards-a": [0, 216, 433, 641, 851, 1086],
	"geometric-cards-b": [0, 204, 409, 614, 819, 1086],
}


static func illustrated_tile(sheet: String, cell: int) -> Rect2:
	var tile := PaintedArt.atlas_region(sheet, cell, 5, 5)
	if not tile.has_area():
		return tile
	var rows: Array = CARD_SHEET_ROWS[sheet]
	var row := cell / 5
	tile.position.y = rows[row]
	tile.size.y = rows[row + 1] - rows[row]
	return tile.grow(-6)


func _draw_art(art: Rect2) -> void:
	if card.id.begins_with("frag_"):
		_draw_fragment_portrait(art)
		return
	for sheet in CARD_SHEETS:
		var cell: int = CARD_SHEETS[sheet].find(card.id)
		if cell < 0:
			continue
		if PaintedArt.cover(_art_layer, sheet, art, illustrated_tile(sheet, cell)):
			return
	var tex := UIKit.art("painted-cards")
	if tex == null:
		return
	var geometry := art_region(card.id, _art_cell(), art, tex.get_size())
	if geometry.mirrored:
		_art_layer.draw_set_transform(Vector2(art.position.x * 2 + art.size.x, 0), 0, Vector2(-1, 1))
	_art_layer.draw_texture_rect_region(tex, geometry.destination, geometry.source)
	_art_layer.draw_set_transform(Vector2.ZERO)


## Fragment portraits share the arena's painted planes and the live molecule's materials.
func _draw_fragment_portrait(art: Rect2) -> void:
	var frag_id := card.id.trim_prefix("frag_")
	var ground := UIKit.art("geometric-ground")
	_art_layer.draw_rect(art, Color("263148"))
	if ground:
		var backdrop := Rect2(Vector2(ground.get_width() * 0.21, ground.get_height() * 0.61),
			ground.get_size() * Vector2(0.55, 0.33))
		PaintedArt.cover(_art_layer, "geometric-ground", art, backdrop, Color(0.62, 0.70, 0.84))
	var c := art.get_center() + Vector2(0, -art.size.y * 0.06)
	# 片段图的尺寸按分子骨架单位给；放大到占满插画的大半高度
	var unit := art.size.y * 0.42
	var bounds := MoleculeSpecimen.bounds(frag_id, c, unit)
	unit *= minf(art.size.y * 0.78 / maxf(bounds.size.y, 1.0), art.size.x * 0.6 / maxf(bounds.size.x, 1.0))
	MoleculeSpecimen.draw_fragment(_art_layer, frag_id, c, unit)


## 插画嵌在卡面里，不是贴在上面
func _draw_art_inset(art: Rect2) -> void:
	UIKit.inset(_art_layer, art, 7.0 * face_scale)


func _art_cell() -> int:
	# Mechanism first: assay apparatus, structural polarity, and shield-driven counterattack.
	match card.id:
		"exp_assay": return 3
		"sig_balance": return 2
		"exp_counter": return 1
	var ops: Array = card.effects.map(func(e: Dictionary) -> String: return String(e.get("op", "")))
	if card.type == "ai":
		return 5
	if card.kind != "attack" and (ops.has("block") or ops.has("double_block")) and not ops.has("damage"):
		return 1
	match card.type:
		"clinical":
			return 4
		"experiment":
			return 3
		"molecular":
			return 0 if card.kind == "attack" else 2
		"process":
			return 4 if ops.has("formulate") else 2
	return 2


func _box(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(width * face_scale))
	sb.set_corner_radius_all(int(mini(radius, 4) * face_scale))
	sb.anti_aliasing = true
	return sb
