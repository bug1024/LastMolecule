class_name RewardPopup
extends Control
## 挑战胜利后的奖励界面（纯 UI 层）
## 由 rd_ui 注入 game._offer_reward 组装的奖励字典：
##   { kind: fight/elite/boss, resources: {...}, cards: [卡牌定义], abilities: [能力定义] }
## 没有候选能力时（普通战斗）隐藏能力区。
## 玩家在候选卡牌与候选研发能力中各选一项后确认，经 reward_claimed 信号回传。
## 弹窗不持有任何业务数据——全部来自 reward 字典（数据驱动）。

signal reward_claimed(card_id: String, ability_id: String)

@onready var _research_label: Label = %ResearchLabel
@onready var _resources_label: Label = %ResourcesLabel
@onready var _card_row: HBoxContainer = %CardRow
@onready var _ability_row: HBoxContainer = %AbilityRow
@onready var _hint_label: Label = %HintLabel
@onready var _confirm_button: Button = %ConfirmButton

const PANEL_BG := UIKit.PAPER
const TEXT_DIM := UIKit.TEXT_DIM
const TEXT_GOOD := UIKit.ACCENT
const TEXT_WARN := UIKit.DANGER
const TEXT_GOLD := UIKit.GOLD

var _selected_card_id := ""
var _selected_ability_id := ""
var _card_count := 0
var _ability_count := 0


func _ready() -> void:
	UIKit.decorate_panel($Center/Panel)
	_confirm_button.pressed.connect(_on_confirm_pressed)


## 渲染奖励界面：研发成果、获得资源、候选卡牌、候选研发能力
func show_reward(reward: Dictionary) -> void:
	_selected_card_id = ""
	_selected_ability_id = ""
	_research_label.text = tr("ui.reward_kind." + String(reward.get("kind", "fight")))
	_resources_label.text = ProjectState.format_effects(reward.get("resources", {}))
	_build_cards(reward.get("cards", []))
	_build_abilities(reward.get("abilities", []))
	var has_abilities: bool = not (reward.get("abilities", []) as Array).is_empty()
	_ability_row.visible = has_abilities
	$Center/Panel/Margin/VBox/Scroll/Content/AbilitiesTitle.visible = has_abilities
	$Center/Panel/Margin/VBox/Scroll/Content/Sep2.visible = has_abilities
	_update_confirm()
	visible = true


# ---------- 渲染 ----------

func _build_cards(cards: Array) -> void:
	_clear(_card_row)
	_card_count = cards.size()
	if _card_count == 0:
		_card_row.add_child(_make_empty_label(tr("ui.reward_no_cards")))
		return
	for card in cards:
		var fits: Array = card.get("mol_fit", [])
		if fits.is_empty():
			_card_row.add_child(_build_card_panel(card))
			continue
		# 契合分子强项的卡：卡下方标注，让「这张卡和我的分子合不合」一眼可见
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(_build_card_panel(card))
		var names: Array = fits.map(func(p: String) -> String: return tr("prop." + p))
		var tag := _make_label("⬡ " + tr("mol.fit") % "、".join(names), Color(0.75, 0.6, 1.0), 13)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tag)
		_card_row.add_child(col)


func _build_abilities(abilities: Array) -> void:
	_clear(_ability_row)
	_ability_count = abilities.size()
	if _ability_count == 0:
		_ability_row.add_child(_make_empty_label(tr("ui.reward_no_abilities")))
		return
	for ability in abilities:
		_ability_row.add_child(_build_ability_panel(ability))


func _build_card_panel(card: Dictionary) -> Control:
	var model := ResearchCard.from_dict(card)
	model.type_name = String(card.get("type_name", ""))
	var face := CardFace.create(model, 1.15)
	face.set_meta("card_id", String(card.get("id", "")))
	face.set_meta("name", tr(model.name))
	face.pick_style = true
	face.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	face.gui_input.connect(_on_card_input.bind(card))
	face.mouse_entered.connect(func() -> void: face.set_state(true, face.selected, face.dimmed))
	face.mouse_exited.connect(func() -> void: face.set_state(false, face.selected, face.dimmed))
	return face


func _build_ability_panel(ability: Dictionary) -> Control:
	var rarity := String(ability.get("rarity", "common"))
	var accent: Color = CardView.RARITY_COLOR.get(rarity, CardView.RARITY_COLOR["common"])
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 110)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.set_meta("ability_id", String(ability.get("id", "")))
	panel.set_meta("name", tr(String(ability.get("name_key", ""))))
	panel.set_meta("rarity", rarity)
	panel.gui_input.connect(_on_ability_input.bind(ability))
	panel.mouse_entered.connect(_on_ability_hover.bind(panel, accent, true))
	panel.mouse_exited.connect(_on_ability_hover.bind(panel, accent, false))
	_refresh_panel(panel, accent, false)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _make_label(tr(String(ability.get("name_key", ""))), accent, 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var mark := _make_label("✓ " + tr("ui.picked"), CardFace.PICK_GREEN, 15)
	mark.name = "PickMark"
	mark.visible = false
	head.add_child(mark)
	vbox.add_child(head)
	var desc := _make_label(tr(String(ability.get("desc_key", ""))), TEXT_DIM, 13)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc)
	return panel


func _make_empty_label(text: String) -> Label:
	var label := _make_label(text, TEXT_DIM, 14)
	label.custom_minimum_size = Vector2(220, 60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UIKit.ink(color))
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _clear(row: Container) -> void:
	for child in row.get_children():
		child.queue_free()


# ---------- 选择与确认 ----------

func _on_card_input(event: InputEvent, card: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_card(String(card.get("id", "")))


func _on_ability_input(event: InputEvent, ability: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_ability(String(ability.get("id", "")))


## 再点一次已选的卡可取消；选中后其余候选变暗
func _select_card(card_id: String) -> void:
	_selected_card_id = "" if card_id == _selected_card_id else card_id
	GameAudio.sfx("card_draw" if not _selected_card_id.is_empty() else "click")
	for child in _card_row.find_children("*", "CardFace", true, false):
		if child is CardFace:
			var picked := String(child.get_meta("card_id")) == _selected_card_id
			child.set_state(picked, picked, not picked and not _selected_card_id.is_empty())
	_update_confirm()


func _select_ability(ability_id: String) -> void:
	if ability_id == _selected_ability_id:
		return
	_selected_ability_id = ability_id
	GameAudio.sfx("gain")
	_refresh_selection(_ability_row, "ability_id", ability_id)


func _refresh_selection(row: Container, meta_key: String, selected_id: String) -> void:
	for child in row.get_children():
		if not (child is PanelContainer) or not child.has_meta(meta_key):
			continue
		var rarity := String(child.get_meta("rarity"))
		var accent: Color = CardView.RARITY_COLOR.get(rarity, CardView.RARITY_COLOR["common"])
		var picked := String(child.get_meta(meta_key)) == selected_id
		_refresh_panel(child, accent, picked)
		child.modulate = Color.WHITE if picked or selected_id.is_empty() else Color(0.55, 0.55, 0.6)
		var mark := child.find_child("PickMark", true, false)
		if mark:
			mark.visible = picked
	_update_confirm()


func _on_ability_hover(panel: Control, accent: Color, hovered: bool) -> void:
	if String(panel.get_meta("ability_id", "")) == _selected_ability_id:
		return
	_refresh_panel(panel, accent, hovered)


func _refresh_panel(panel: Control, accent: Color, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.lerp(PANEL_BG, 0.8) if not selected else CardFace.PICK_GREEN.lerp(PANEL_BG, 0.75)
	sb.set_border_width_all(4 if selected else 2)
	sb.set_corner_radius_all(10)
	sb.border_color = CardFace.PICK_GREEN if selected else accent.darkened(0.25)
	if selected:
		sb.shadow_color = Color(CardFace.PICK_GREEN, 0.35)
		sb.shadow_size = 10
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)


func _update_confirm() -> void:
	# 某项候选为空（无需选择）或已选中时，该项即视为满足
	var card_ok := true   # 卡牌可以跳过
	var ability_ok: bool = _ability_count == 0 or _selected_ability_id != ""
	_confirm_button.disabled = not (card_ok and ability_ok)
	# 按钮文字直接说出会拿到什么，避免「不知道选没选中」
	var picks: Array[String] = []
	if not _selected_card_id.is_empty():
		picks.append(_picked_name(_card_row, "card_id", _selected_card_id))
	if not _selected_ability_id.is_empty():
		picks.append(_picked_name(_ability_row, "ability_id", _selected_ability_id))
	if not ability_ok:
		_confirm_button.text = tr("ui.reward_need_ability")
	elif picks.is_empty():
		_confirm_button.text = tr("ui.reward_skip_card")
	else:
		_confirm_button.text = tr("ui.reward_take") % "」「".join(picks)
	if picks.is_empty():
		_hint_label.text = tr("ui.reward_choose_hint")
		_hint_label.add_theme_color_override("font_color", TEXT_DIM)
	else:
		_hint_label.text = tr("ui.reward_picked") % "、".join(picks)
		_hint_label.add_theme_color_override("font_color", CardFace.PICK_GREEN)


func _picked_name(row: Container, meta_key: String, id: String) -> String:
	for child in row.get_children() + row.find_children("*", "CardFace", true, false):
		if child.has_meta(meta_key) and String(child.get_meta(meta_key)) == id:
			return String(child.get_meta("name", id))
	return id


func _on_confirm_pressed() -> void:
	if _confirm_button.disabled:
		return
	visible = false
	reward_claimed.emit(_selected_card_id, _selected_ability_id)
