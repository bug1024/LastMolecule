class_name EventPopup
extends Control
## 事件 / 节点决策 / 里程碑弹窗（纯 UI 层）：标题区（类型图标 + 标签 + 标题 + 说明）+ 一列选项卡片。
## 内容完全来自 game 组装的事件数据；玩家选择后通过 choice_selected 信号回传。
## 支持 desc_args / label_args（字符串参数会先经 tr() 翻译）与选项的 tag_key、desc_key、desc_text（已拼好的文字）。

signal choice_selected(event_id: String, choice_index: int)

@onready var _tag: Label = %TagLabel
@onready var _title: Label = %TitleLabel
@onready var _desc: Label = %DescLabel
@onready var _choices_box: VBoxContainer = %ChoicesBox

var _event_id: String = ""


const EVENT_ICONS := {"research": "node_research", "partner": "node_partner", "platform": "node_platform",
	"fast_track": "node_fast_track", "milestone": "node_milestone", "final_review": "outcome_approved", "route": "logo"}

const EVENT_SCENES := {
	"data_quality": 0, "unexpected_signal": 0, "tox_result": 0,
	"biomarker_found": 1, "research": 1, "conference": 1, "platform": 1,
	"funding_strain": 2, "partner": 2, "partnership": 2, "talent_bid": 2,
	"regulatory_hint": 3, "final_review": 3, "fast_track": 3,
}
const SCENE_INKS := [Color("f0947f"), Color("92d7b9"), Color("edc280"), Color("c5b1e9")]

var _header_icon: TextureRect
var _scene_header: HBoxContainer
var _scene_text: VBoxContainer
var _scene_picture: Control
var _scene_index := -1


func show_event(event: Dictionary, is_gate: bool, state: ProjectState) -> void:
	_event_id = String(event.get("id", ""))
	_ensure_header_icon()
	_layout_header()
	_header_icon.texture = UIKit.icon(String(EVENT_ICONS.get(_event_id, "node_event")))
	_header_icon.modulate = Color(0.45, 0.85, 0.95) if is_gate else Color(0.95, 0.72, 0.30)
	_title.text = tr(String(event.get("title_key", "event.default_title")))
	var tag_key := "ui.gate_tag" if is_gate else "ui.event_tag"
	if _scene_index >= 0 and not is_gate:
		tag_key = "event.scene.%d" % _scene_index
	_tag.text = tr(String(event.get("tag_key", tag_key)))
	var accent: Color = SCENE_INKS[_scene_index] if _scene_index >= 0 else _header_icon.modulate
	_tag.add_theme_color_override("font_color", accent)
	_desc.text = _format(String(event.get("desc_key", "")), event.get("desc_args", []))
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()
	var choices: Array = event.get("choices", [])
	for i in choices.size():
		_choices_box.add_child(_build_choice(choices[i], i, state))
	visible = true


## 标题上方的大图标（按事件类型），第一次显示时插到标签前面；面板也加宽以容纳选项卡片
func _ensure_header_icon() -> void:
	if _header_icon != null:
		return
	_header_icon = TextureRect.new()
	_header_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_header_icon.custom_minimum_size = Vector2(36, 36)
	_header_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tag.get_parent().add_child(_header_icon)
	_tag.get_parent().move_child(_header_icon, 0)
	($Center/Panel as Control).custom_minimum_size = Vector2(640, 0)
	_desc.custom_minimum_size = Vector2(0, 0)
	_choices_box.add_theme_constant_override("separation", 8)
	(_tag.get_parent() as VBoxContainer).add_theme_constant_override("separation", 8)


func _layout_header() -> void:
	var column := _choices_box.get_parent() as VBoxContainer
	if _scene_header == null:
		_scene_header = HBoxContainer.new()
		_scene_header.add_theme_constant_override("separation", 18)
		column.add_child(_scene_header)
		column.move_child(_scene_header, 0)
		_scene_picture = Control.new()
		_scene_picture.custom_minimum_size = Vector2(230, 144)
		_scene_picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_scene_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scene_picture.draw.connect(_draw_scene)
		_scene_header.add_child(_scene_picture)
		_scene_text = VBoxContainer.new()
		_scene_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scene_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_scene_text.add_theme_constant_override("separation", 5)
		_scene_header.add_child(_scene_text)
	var cell := int(EVENT_SCENES.get(_event_id, -1))
	_scene_index = cell if UIKit.art("event-scenes") != null else -1
	var illustrated := _scene_index >= 0
	var alignment := HORIZONTAL_ALIGNMENT_LEFT if illustrated else HORIZONTAL_ALIGNMENT_CENTER
	var target := _scene_text if illustrated else column
	for label in [_tag, _title, _desc]:
		if label.get_parent() != target:
			label.reparent(target, false)
		label.horizontal_alignment = alignment
	if not illustrated:
		column.move_child(_header_icon, 1)
		column.move_child(_tag, 2)
		column.move_child(_title, 3)
		column.move_child(_desc, 5)
	_header_icon.visible = not illustrated
	_scene_header.visible = illustrated
	(column.get_node("HSep") as Control).visible = not illustrated
	($Center/Panel as Control).custom_minimum_size.x = 756 if illustrated else 640
	_desc.custom_minimum_size.y = 0 if illustrated else 54
	_scene_picture.queue_redraw()


func _draw_scene() -> void:
	if _scene_index < 0:
		return
	var area := Rect2(Vector2.ZERO, _scene_picture.size)
	PaintedArt.cover(_scene_picture, "event-scenes", area,
		PaintedArt.atlas_region("event-scenes", _scene_index, 2, 2).grow(-2))
	UIKit.inset(_scene_picture, area, 9.0)
	_scene_picture.draw_line(area.end - Vector2(area.size.x, 1), area.end - Vector2(0, 1),
		SCENE_INKS[_scene_index], 2.0, true)


func _format(key: String, args: Array) -> String:
	if key.is_empty():
		return ""
	if args.is_empty():
		return tr(key)
	var translated: Array = []
	for a in args:
		translated.append(tr(a) if a is String else a)
	return tr(key) % translated


## 选项卡片：左边图标徽章，中间「标签 + 标题 + 说明」，下面一排效果小标签（收益绿、代价红、中性灰）；
## 条件不满足时整张卡变暗并写明还差什么。
func _build_choice(choice: Dictionary, index: int, state: ProjectState) -> Control:
	var requires: Dictionary = choice.get("requires", {})
	var enabled := state == null or state.can_meet(requires)
	var accent := _choice_color(choice)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_style(accent, false, enabled))
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	# 圆形图标徽章（直接画圆，避免样式框的内边距把它撑成椭圆）
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(40, 40)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_tex := UIKit.icon(_choice_icon(choice))
	badge.draw.connect(func() -> void:
		var c := badge.size * 0.5
		badge.draw_circle(c, 20, Color(accent, 0.18))
		badge.draw_arc(c, 19, 0, TAU, 40, Color(accent, 0.65), 1.5, true)
		if icon_tex:
			badge.draw_texture_rect(icon_tex, Rect2(c - Vector2(11, 11), Vector2(22, 22)), false, accent.lightened(0.3)))
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	if choice.has("tag_key"):
		var tag := UIKit.label(tr(String(choice.tag_key)), accent.lightened(0.3), 12)
		var pill := PanelContainer.new()
		var sb := UIKit.filled(Color(accent, 0.15), Color(accent, 0.5), 8)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		pill.add_theme_stylebox_override("panel", sb)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pill.add_child(tag)
		title_row.add_child(pill)
	title_row.add_child(UIKit.header(_format(String(choice.get("label_key", "ui.choose_default")), choice.get("label_args", [])), 17))
	col.add_child(title_row)
	var desc_key := String(choice.get("desc_key", ""))
	if desc_key != "" and tr(desc_key) != desc_key:
		col.add_child(UIKit.label(tr(desc_key), UIKit.TEXT_DIM, 14, true))
	if not String(choice.get("desc_text", "")).is_empty():   # 逻辑层已拼好的动态说明（如片段属性、下一阶段考验）
		col.add_child(UIKit.label(String(choice.desc_text), Color(0.78, 0.7, 1.0), 14, true))
	var chips := effect_chips(choice.get("effects", {}))
	if not chips.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 4)
		for chip in chips:
			flow.add_child(_chip(String(chip.text), chip.color))
		col.add_child(flow)
	if not enabled:
		col.add_child(UIKit.label("🔒 " + _requires_text(requires), UIKit.DANGER.lightened(0.15), 13, true))
	for node in card.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if enabled:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_entered.connect(func() -> void:
			card.add_theme_stylebox_override("panel", _card_style(accent, true, true))
			GameAudio.sfx("hover"))
		card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", _card_style(accent, false, true)))
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				GameAudio.sfx("click")
				_on_choice_pressed(index))
	else:
		card.modulate = Color(1, 1, 1, 0.55)
	return card


## 效果小标签：[{text, color}]。资金 / 疗效 / 进度 / 数据增加和安全风险下降是收益（绿），反之是代价（红）；
## 年份增加算时间代价（金）；重置、进入阶段为中性（灰）
static func effect_chips(effects: Dictionary) -> Array:
	var t := TranslationServer
	var chips: Array = []
	var labels := {"research_progress": "fx.research_progress", "efficacy": "fx.efficacy", "safety_risk": "fx.safety_risk",
		"funding": "fx.funding", "year": "fx.year", "data": "fx.data"}
	for field in ["efficacy", "safety_risk", "funding", "research_progress", "data", "year"]:
		var v := int(effects.get(field, 0))
		if v == 0:
			continue
		var good := v < 0 if field == "safety_risk" else v > 0
		var color: Color = UIKit.GOLD if field == "year" else (UIKit.ACCENT if good else UIKit.DANGER)
		chips.append({"text": "%s %s%d" % [t.translate(labels[field]), "+" if v > 0 else "", v], "color": color})
	for key in effects:
		if String(key).begins_with("set_"):
			var field := String(key).trim_prefix("set_")
			chips.append({"text": t.translate("fx.reset") % [t.translate(labels.get(field, field)), int(effects[key])], "color": UIKit.TEXT_DIM})
	if effects.has("stage"):
		chips.append({"text": t.translate("fx.enter_stage") % t.translate("stage." + String(effects.stage)), "color": UIKit.ACCENT_BLUE})
	return chips


func _chip(text: String, color: Color) -> Control:
	var pill := PanelContainer.new()
	var sb := UIKit.filled(Color(color, 0.14), Color(color, 0.55), 10)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", sb)
	pill.add_child(UIKit.label(text, color.lightened(0.25), 13))
	return pill


func _card_style(accent: Color, hover: bool, enabled: bool) -> StyleBox:
	if _scene_index >= 0:
		var row := StyleBoxFlat.new()
		row.bg_color = Color("181e2b").lerp(accent, 0.13 if hover else 0.04)
		row.border_color = Color(accent, 0.85 if hover else 0.55)
		row.border_width_left = 3
		row.set_content_margin_all(5)
		return row
	var sb := UIKit.panel_style(Color(0.07, 0.09, 0.13, 0.95) if not hover else accent.lerp(Color(0.07, 0.09, 0.13), 0.82),
		Color(accent, 0.9 if hover else (0.45 if enabled else 0.2)), 12)
	sb.set_border_width_all(2 if hover else 1)
	if hover:
		sb.shadow_color = Color(accent, 0.3)
		sb.shadow_size = 10
	return sb


## 选项的图标：按动作类型；没有动作的按主要效果
func _choice_icon(choice: Dictionary) -> String:
	var icons := {"card_reward": "node_research", "buy": "ui_deck", "remove": "ui_discard_pile", "upgrade": "ui_plus",
		"process": "type_process", "fast_track": "node_fast_track", "continue": "ui_play", "final_review": "node_research",
		"submit": "outcome_approved", "terminate": "outcome_terminated", "decide": "role_skill", "route": "logo"}
	var action := String(choice.get("action", ""))
	if icons.has(action):
		return icons[action]
	var fx: Dictionary = choice.get("effects", {})
	if int(fx.get("safety_risk", 0)) < 0:
		return "ui_heart"
	if int(fx.get("funding", 0)) > 0:
		return "stat_funding"
	if int(fx.get("efficacy", 0)) > 0:
		return "stat_efficacy"
	if fx.is_empty():
		return "ui_back"
	return "node_event"


func _choice_color(choice: Dictionary) -> Color:
	match String(choice.get("action", "")):
		"terminate":
			return UIKit.GOLD
		"submit", "continue":
			return UIKit.ACCENT
		"decide", "route":
			return Color(0.75, 0.55, 1.0)
	var fx: Dictionary = choice.get("effects", {})
	if fx.is_empty() and String(choice.get("action", "")).is_empty():
		return Color(0.55, 0.62, 0.72)
	return SCENE_INKS[_scene_index] if _scene_index >= 0 else UIKit.ACCENT_BLUE


func _requires_text(requires: Dictionary) -> String:
	var parts: Array[String] = []
	if requires.has("funding_min"):
		parts.append(tr("req.funding_min") % int(requires.funding_min))
	if requires.has("efficacy_min"):
		parts.append(tr("req.efficacy_min") % int(requires.efficacy_min))
	if requires.has("safety_risk_below"):
		parts.append(tr("req.safety_risk_below") % int(requires.safety_risk_below))
	if requires.has("data_min"):
		parts.append(tr("req.data_min") % int(requires.data_min))
	if bool(requires.get("battle_won", false)):
		parts.append(tr("req.battle_won"))
	return tr("ui.requires") % "，".join(parts)


func _on_choice_pressed(index: int) -> void:
	visible = false
	choice_selected.emit(_event_id, index)
