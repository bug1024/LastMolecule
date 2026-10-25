class_name CardPopup
extends Control
## 选卡弹窗（纯 UI 层）：加入牌库 / 购买 / 删除 / 升级 / 查看牌库。
## 由 rd_ui 注入候选卡牌，玩家点击后通过 card_selected 回传；查看模式只读。

signal card_selected(card: ResearchCard)
signal cards_skipped()

@onready var _title_label: Label = $Center/Margin/VBox/TitleLabel
@onready var _hint_label: Label = $Center/Margin/VBox/HintLabel
@onready var _card_row: HFlowContainer = %CardRow
@onready var _skip_button: Button = %SkipButton

var _purpose := ""
var _cost := 0
var _funding := 0
var _pending_upgrade: ResearchCard = null


func _ready() -> void:
	_skip_button.pressed.connect(_on_skip_pressed)


## purpose：add / buy / remove / upgrade / view；cost 为每次选择的资金花费
## title_key 可覆盖标题（如战斗中查看抽牌堆 / 弃牌堆）
func show_cards(cards: Array, purpose: String, cost: int, funding: int, ai_info: Dictionary, title_key := "") -> void:
	_purpose = purpose
	_cost = cost
	_funding = funding
	_title_label.text = tr(title_key if not title_key.is_empty() else "ui.pick.%s.title" % purpose)
	if purpose == "view":
		_hint_label.text = tr("ui.pick.view.hint") % cards.size() + "  ·  " + _composition(cards)
	else:
		_hint_label.text = tr("ui.pick.%s.hint" % purpose) + (tr("ui.pick.cost") % cost if cost > 0 else "")
	_hint_label.text += "  ·  " + tr("ui.card_detail.tip")
	_skip_button.text = tr("ui.pick.%s.skip" % purpose)
	for child in _card_row.get_children():
		child.queue_free()
	var card_scale := 1.15 if cards.size() <= 4 else 0.95
	if purpose == "upgrade":
		card_scale = 1.0 if cards.size() <= 4 else 0.85
	for card in cards:
		if purpose == "upgrade" and card.upgrade_preview != null:
			_card_row.add_child(_upgrade_option(card, card_scale, ai_info))
			continue
		var face := CardView.build(card, card_scale, ai_info)
		if purpose != "view":
			face.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			face.gui_input.connect(_on_panel_input.bind(card))
		if cost > funding:
			face.set_state(false, false, true)
		_card_row.add_child(face)
	visible = true


## 牌组构成：各类型张数 + 主要套路，例如「分子设计 5 · 实验验证 4 · 套路：分子快攻」
func _composition(cards: Array) -> String:
	var counts := {}
	for card in cards:
		if card.type != "status":
			counts[card.type] = int(counts.get(card.type, 0)) + 1
	var parts: Array[String] = []
	for t in ["molecular", "experiment", "clinical", "ai", "process"]:
		if counts.has(t):
			parts.append("%s %d" % [tr("card.type." + t), counts[t]])
	parts.append(tr("build.label") % tr("build." + ResearchCard.deck_build(cards)))
	return " · ".join(parts)


## 升级候选：直接展示「升级后」的牌面（变大的数字是绿色），下面列出前后对比和会一起升级的张数
func _upgrade_option(card: ResearchCard, card_scale: float, ai_info: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mods := {"compare_to": card}
	if card.is_ai():
		mods["ai_multiplier"] = 1.0
	# AI 卡按基础数值比较，所以不显示当前倍率小牌子
	var face := CardFace.create(card.upgrade_preview, card_scale, mods, {} if card.is_ai() else ai_info)
	face.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	face.mouse_entered.connect(func() -> void: face.set_state(true, false, face.dimmed))
	face.mouse_exited.connect(func() -> void: face.set_state(false, false, face.dimmed))
	face.gui_input.connect(_on_panel_input.bind(card))
	if _cost > _funding:
		face.set_state(false, false, true)
	box.add_child(face)
	var diff := ResearchCard.upgrade_diff(card, card.upgrade_preview)
	var lines := UIKit.label("\n".join(diff) if not diff.is_empty() else tr("ui.upgrade.same"), Color(0.55, 1.0, 0.65), 14, true)
	lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.custom_minimum_size = Vector2(CardFace.BASE.x * card_scale, 0)
	box.add_child(lines)
	if card.copies > 1:
		var copies := UIKit.label(tr("ui.upgrade.copies") % card.copies, UIKit.TEXT_DIM, 13, true)
		copies.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		copies.custom_minimum_size = Vector2(CardFace.BASE.x * card_scale, 0)
		box.add_child(copies)
	return box


func _on_panel_input(event: InputEvent, card: ResearchCard) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not visible or _purpose == "view" or _cost > _funding:
			return
		if _purpose == "upgrade" and card.upgrade_preview != null:
			_show_upgrade_result(card)
			return
		visible = false
		card_selected.emit(card)


## 升级完成：单独展示升级后的卡、前后对比，点「继续」后才回到游戏
func _show_upgrade_result(card: ResearchCard) -> void:
	GameAudio.sfx("level_up")
	for child in _card_row.get_children():
		child.queue_free()
	_title_label.text = tr("ui.upgrade.done_title")
	_hint_label.text = tr("ui.upgrade.done_hint") % [card.copies, tr(card.name)]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.custom_minimum_size = Vector2(1100, 0)
	var old_face := CardFace.create(card, 0.9)
	old_face.set_state(false, false, true)
	row.add_child(old_face)
	row.add_child(UIKit.header("➜", 48, Color(0.55, 1.0, 0.65)))
	var new_face := CardFace.create(card.upgrade_preview, 1.25, {"compare_to": card})
	new_face.set_state(true, false)
	row.add_child(new_face)
	var diff := UIKit.label("\n".join(ResearchCard.upgrade_diff(card, card.upgrade_preview)), Color(0.55, 1.0, 0.65), 20, true)
	diff.custom_minimum_size = Vector2(240, 0)
	row.add_child(diff)
	_card_row.add_child(row)
	new_face.pivot_offset = new_face.custom_minimum_size * 0.5
	new_face.scale = Vector2(0.7, 0.7)
	create_tween().tween_property(new_face, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_skip_button.text = tr("ui.upgrade.continue")
	_purpose = "upgrade_done"
	_pending_upgrade = card


func _on_skip_pressed() -> void:
	visible = false
	if _purpose == "upgrade_done":
		_purpose = "upgrade"
		var card := _pending_upgrade
		_pending_upgrade = null
		card_selected.emit(card)
		return
	cards_skipped.emit()


func get_purpose() -> String:
	return _purpose
