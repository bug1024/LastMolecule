class_name CardDetail
extends CanvasLayer
## 卡牌大图说明：右键（或长按）任意牌面打开。
## 左边是放大的牌面，右边是完整文字说明、限制、AI 威力与失误后果；点任意处或按 Esc 关闭。

const LAYER := 60
const FACE_SCALE := 1.6

static var _current: CardDetail = null


static func open(source: Control, card: ResearchCard, mods := {}, ai_info := {}) -> void:
	if card == null or not source.is_inside_tree():
		return
	close_current()
	var detail := CardDetail.new()
	detail.layer = LAYER
	source.get_tree().root.add_child(detail)
	detail._build(card, mods, ai_info)
	_current = detail
	GameAudio.sfx("click")


static func close_current() -> void:
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null


func _build(card: ResearchCard, mods: Dictionary, ai_info: Dictionary) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_input)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	var face := CardFace.create(card, FACE_SCALE, mods, ai_info)
	face.detail_enabled = false
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(face)
	row.add_child(_text_panel(card, mods, ai_info))


func _text_panel(card: ResearchCard, mods: Dictionary, ai_info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style())
	panel.custom_minimum_size = Vector2(420, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var role_color: Color = CardFace.ROLE_COLOR.get(card.role(), Color.GRAY)
	box.add_child(UIKit.header(tr(card.name) + ("+" if card.upgraded else ""), 28, Color(0.6, 1.0, 0.7) if card.upgraded else Color(0.95, 0.97, 1.0)))
	var type_name := tr(card.type_name if not card.type_name.is_empty() else "card.type." + card.type)
	var sub := "%s · %s · %s" % [tr("role." + card.role()), type_name, tr("rarity." + card.rarity)]
	if not card.unplayable:
		sub += " · " + tr("ui.card_detail.cost") % card.cost
	box.add_child(UIKit.label(sub, role_color.lightened(0.35), 17))
	box.add_child(HSeparator.new())
	box.add_child(UIKit.label(card.describe(mods), UIKit.TEXT, 20, true))
	if card.is_ai():
		box.add_child(HSeparator.new())
		if card.reliable:
			box.add_child(UIKit.label(tr("cardtext.reliable"), UIKit.ACCENT_BLUE, 17, true))
		elif not ai_info.is_empty():
			box.add_child(UIKit.label(CardFace.ai_foot(ai_info), UIKit.ACCENT_BLUE, 17, true))
		if card.can_deviate() and not card.deviation.is_empty():
			box.add_child(UIKit.label(tr("cardtext.deviation_tip") % card.describe_deviation(), UIKit.DANGER.lightened(0.2), 17, true))
	var hint := UIKit.label(tr("ui.card_detail.close"), UIKit.TEXT_DIM, 14)
	box.add_child(hint)
	for child in box.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		get_viewport().set_input_as_handled()
		close_current()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_current()
