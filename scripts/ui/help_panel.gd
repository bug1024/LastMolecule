class_name HelpPanel
extends ModalPanel
## 玩法说明：像一本小手册——左侧是带图标的章节目录，右侧是当前章节的「书页」（大标题 + 正文）。
## 章节：快速上手、目标、研发地图、阶段试验、卡牌与 AI、立项决策、术语；正文是翻译表里的 BBCode（help.<id>）。

const PAGES := ["quick", "goal", "map", "battles", "cards", "decisions", "glossary"]
const ICONS := {"quick": "ui_play", "goal": "outcome_approved", "map": "node_milestone", "battles": "node_boss",
	"cards": "ui_deck", "decisions": "node_event", "glossary": "ui_help"}

var _nav: VBoxContainer
var _page_icon: TextureRect
var _page_title: Label
var _page_text: RichTextLabel
var _scroll: ScrollContainer
var _current := "quick"


func _init() -> void:
	super._init()
	title_key = "help.title"
	subtitle_key = "help.subtitle"
	icon_name = "ui_help"
	accent = UIKit.ACCENT
	panel_width = 980


func _build(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	_nav = VBoxContainer.new()
	_nav.custom_minimum_size = Vector2(200, 0)
	_nav.add_theme_constant_override("separation", 6)
	row.add_child(_nav)
	var page := PanelContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UIKit.panel_style(Color(0.05, 0.075, 0.1, 0.92), Color(accent, 0.25), 14)
	sb.border_width_left = 4
	sb.border_color = Color(accent, 0.25)
	sb.set_content_margin_all(20)
	page.add_theme_stylebox_override("panel", sb)
	row.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_page_icon = TextureRect.new()
	_page_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page_icon.custom_minimum_size = Vector2(30, 30)
	_page_icon.modulate = accent.lightened(0.2)
	head.add_child(_page_icon)
	_page_title = UIKit.header("", 24, Color(0.93, 0.97, 0.98))
	head.add_child(_page_title)
	col.add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 430)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_page_text = UIKit.rich("", 16)
	_page_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_text.add_theme_constant_override("line_separation", 7)
	_scroll.add_child(_page_text)
	for id in PAGES:
		_nav.add_child(_nav_button(id))
	_show(_current)


func _nav_button(id: String) -> Button:
	var btn := Button.new()
	btn.name = id
	btn.text = tr("help.tab." + id)
	btn.icon = UIKit.icon(ICONS[id])
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_constant_override("icon_max_width", 18)
	btn.add_theme_constant_override("h_separation", 10)
	btn.custom_minimum_size = Vector2(200, 42)
	btn.add_theme_font_size_override("font_size", 16)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func() -> void:
		GameAudio.sfx("card_draw")
		_show(id))
	return btn


func _show(id: String) -> void:
	_current = id
	_page_icon.texture = UIKit.icon(ICONS[id])
	_page_title.text = tr("help.tab." + id)
	_page_text.text = tr("help." + id)
	_scroll.scroll_vertical = 0
	for btn in _nav.get_children():
		var on: bool = btn.name == id
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(accent, 0.2) if on else Color(0, 0, 0, 0)
		sb.border_color = Color(accent, 0.85)
		sb.border_width_left = 3 if on else 0
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 14
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = Color(accent, 0.28 if on else 0.1)
		for state_name in ["normal", "focus"]:
			btn.add_theme_stylebox_override(state_name, sb)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		var color := Color(0.95, 1.0, 0.97) if on else Color(0.7, 0.76, 0.82)
		for key in ["font_color", "font_focus_color"]:
			btn.add_theme_color_override(key, color)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("icon_normal_color", accent.lightened(0.2) if on else Color(0.55, 0.62, 0.7))
