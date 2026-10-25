extends Control
## 研发管理界面（纯 UI 层）
## 订阅 GameLogic 的信号展示状态，转发玩家的决策（节点、事件选项、卡牌、战斗操作）。
## 状态变化时在对应指标旁播放浮动数字与闪烁动画，并配合音效 / 背景乐切换。
## 战斗结束后，奖励与里程碑弹窗会排队到玩家在战斗界面点击「继续」之后再显示。
## Esc 或右上角「菜单」打开游戏内菜单；一局结束显示结局画面。

@onready var _game_logic = $GameLogic
@onready var _card_popup = $CardPopup
@onready var _event_popup = $EventPopup
@onready var _battle_view: BattleView = $BattleView
@onready var _reward_popup = $RewardPopup
@onready var _map_screen = $MapScreen

@onready var _project_label: Label = %ProjectLabel
@onready var _stage_label: Label = %StageLabel
@onready var _funding_label: Label = %FundingLabel
@onready var _year_label: Label = %YearLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _success_label: Label = %SuccessLabel
@onready var _safety_label: Label = %SafetyLabel
@onready var _event_label: Label = %EventLabel
@onready var _advance_button: Button = %AdvanceButton
@onready var _challenge_label: Label = %ChallengeLabel
@onready var _challenge_button: Button = %ChallengeButton
@onready var _abilities_label: Label = %AbilitiesLabel
@onready var _float_layer: Control = %FloatLayer
@onready var _company_label: Label = %CompanyLabel
@onready var _help_button: Button = %HelpButton
@onready var _menu_button: Button = %MenuButton
@onready var _pipeline: PipelineView = %Pipeline
@onready var _molecule_art: MoleculeArt = %MoleculeArt
@onready var _competition_label: RichTextLabel = %CompetitionLabel

const EVENT_COLOR := {
	"positive": Color(0.31, 0.78, 0.55),
	"negative": Color(0.93, 0.42, 0.42),
	"neutral": Color(0.80, 0.84, 0.90),
}

var _float_slots := {}                     # 每个指标旁正在显示的浮动文字数
var _finished := false
var _after_battle: Array[Callable] = []   # 战斗结果展示期间排队的弹窗
var _pause_menu: PauseMenu
var _settings: SettingsPanel
var _help: HelpPanel
var _ending: EndingPanel
var _player_hud: PlayerHud

const OVERLAY_Z := 200


func _ready() -> void:
	if _game_logic == null:
		push_error("未找到 GameLogic 节点，UI 无法工作")
		set_process(false)
		return

	_game_logic.state_changed.connect(_on_state_changed)
	_game_logic.state_synced.connect(_on_state_synced)
	_game_logic.event_offered.connect(_on_event_offered)
	_game_logic.card_pick_offered.connect(_on_card_pick_offered)
	_game_logic.map_updated.connect(_on_map_updated)
	_game_logic.battle_resolved.connect(_on_battle_resolved)
	_game_logic.reward_offered.connect(_on_reward_offered)
	_game_logic.reward_claimed.connect(_on_reward_claimed)
	_game_logic.news_posted.connect(_on_news_posted)
	_game_logic.run_ended.connect(_on_run_ended)
	_advance_button.pressed.connect(_on_advance_pressed)
	_challenge_button.pressed.connect(_on_view_deck_pressed)

	_card_popup.card_selected.connect(_game_logic.select_card)
	_card_popup.cards_skipped.connect(func() -> void:
		if _card_popup.get_purpose() != "view":
			_game_logic.skip_cards())
	_event_popup.choice_selected.connect(_game_logic.resolve_event_choice)
	_battle_view.bind(_game_logic.get_battle_manager(), _game_logic)
	_battle_view.continue_pressed.connect(_flush_after_battle)
	_game_logic.player_leveled.connect(_battle_view.on_player_leveled)
	_player_hud = PlayerHud.new()
	var metrics: VBoxContainer = $Layout/VBox/Body/LeftPanel/VBox
	metrics.add_child(HSeparator.new())
	metrics.add_child(_player_hud)
	_battle_view.pile_requested.connect(func(cards: Array, title_key: String) -> void:
		_card_popup.show_cards(cards, "view", 0, 0, _game_logic.get_ai_info(), title_key))
	_reward_popup.reward_claimed.connect(_game_logic.claim_reward)
	_map_screen.bind(_game_logic)
	_map_screen.node_requested.connect(_game_logic.choose_node)
	_map_screen.close_requested.connect(func() -> void: _map_screen.visible = false)

	_build_overlays()
	# 战斗手牌用了 z_index（悬停的卡最高 50），弹窗与菜单必须整体压在它们之上
	for overlay in [_card_popup, _event_popup, _reward_popup, _ending, _pause_menu, _help, _settings]:
		overlay.z_index = OVERLAY_Z
	_style_buttons()
	_event_label.text = _company_intro()
	_on_state_synced(_game_logic.get_state())
	GameAudio.music("lab")
	if _game_logic.resumed:
		_event_label.text = tr("ui.resumed")
		_game_logic.replay_pending()
		if _game_logic.is_idle() and _game_logic.has_started_map():
			_map_screen.show_map()


func _build_overlays() -> void:
	_help = HelpPanel.new()
	_settings = SettingsPanel.new()
	_settings.locale_changed.connect(_on_locale_changed)
	_pause_menu = PauseMenu.new()
	_pause_menu.help_requested.connect(func() -> void: _help.open())
	_pause_menu.settings_requested.connect(func() -> void: _settings.open())
	_ending = EndingPanel.new()
	_ending.restart_requested.connect(func() -> void:
		RunSave.new_project_type = _game_logic.project_type   # 「再来一局」沿用同类项目，换类型回标题选
		SceneRouter.restart_scene())
	for overlay in [_ending, _pause_menu, _help, _settings]:
		add_child(overlay)
	_help_button.pressed.connect(func() -> void: _help.open())
	_menu_button.pressed.connect(func() -> void: _pause_menu.open())


func _style_buttons() -> void:
	var primary := UIKit.button("", "", "primary")
	for state_name in ["normal", "hover", "pressed"]:
		_advance_button.add_theme_stylebox_override(state_name, primary.get_theme_stylebox(state_name))
	primary.free()
	_advance_button.icon = UIKit.icon("node_research")
	_advance_button.set_meta("sfx", "open")
	_challenge_button.text = tr("ui.view_deck")
	_help_button.text = tr("title.help")
	_menu_button.text = tr("pause.menu")


func _on_locale_changed() -> void:
	for node in [_help, _pause_menu]:
		node.rebuild()
	_style_buttons()
	_on_state_synced(_game_logic.get_state())
	_map_screen.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _finished:
		return
	get_viewport().set_input_as_handled()
	if _map_screen.visible:
		_map_screen.visible = false
	else:
		_pause_menu.open()


func _company_intro() -> String:
	var company: Company = _game_logic.company
	if company.runs == 0:
		return tr("ui.event_default")
	return tr("ui.company_intro") % [company.runs, company.approvals, company.data, company.process_level()]


func _on_advance_pressed() -> void:
	if _finished:
		SceneRouter.restart_scene()
		return
	_map_screen.show_map()


func _on_view_deck_pressed() -> void:
	if not _game_logic.is_idle():
		return
	_card_popup.show_cards(_game_logic.build_deck(), "view", 0, 0, _game_logic.get_ai_info())


func _on_map_updated() -> void:
	if _map_screen.visible:
		_map_screen.refresh()


# ---------- 状态展示 ----------

func _on_state_synced(state) -> void:
	_project_label.text = tr(_game_logic.get_project_name())
	_stage_label.text = tr("stage." + state.stage)
	var stages: Array = _game_logic.get_stages()
	_pipeline.set_stages(stages, maxi(stages.find(state.stage), 0))
	_molecule_art.stage_index = maxi(stages.find(state.stage), 0)
	_molecule_art.health = clampf(0.5 + (state.efficacy - state.safety_risk) / 120.0, 0.0, 1.0)
	var company: Company = _game_logic.company
	_company_label.text = tr("ui.hub_company") % [company.runs + 1, company.process_level()]
	_competition_label.text = _map_screen.competition_text()
	if _player_hud:
		_player_hud.refresh(_game_logic)
	_funding_label.text = tr("ui.hub_funding") % state.funding
	_year_label.text = tr("ui.year") % state.year
	_progress_bar.max_value = _game_logic.get_progress_gate()
	_progress_bar.value = mini(state.research_progress, _game_logic.get_progress_gate())
	_success_label.text = tr("ui.efficacy_value") % [state.efficacy, _game_logic.get_final_efficacy_bar()]
	_safety_label.text = tr("ui.safety_value") % [state.safety_risk, _game_logic.get_final_safety_limit()]
	var ai: Dictionary = _game_logic.get_ai_info()
	_challenge_label.text = tr("ui.hub_ai_detail") % [ai.effective, tr("tier." + String(ai.tier)), ai.multiplier, ai.deviation,
		ai.run_data, ai.company_data, ai.level] + "\n" + BattleView.ai_next_text(ai)
	_refresh_abilities(state)


func _on_state_changed(deltas: Dictionary) -> void:
	for key in deltas:
		var value = deltas[key]
		match key:
			"funding":
				_spawn_float(tr("ui.float_funding") % value, _delta_color(value), _funding_label)
				_flash(_funding_label)
			"year":
				_spawn_float(tr("ui.float_year") % value, Color(0.8, 0.84, 0.9), _year_label)
				_flash(_year_label)
			"research_progress":
				_spawn_float(tr("ui.float_progress") % value, _delta_color(value), _progress_bar)
				_flash(_progress_bar)
			"efficacy":
				_spawn_float(tr("ui.float_efficacy") % value, _delta_color(value), _success_label)
				_flash(_success_label)
			"safety_risk":
				# 风险上升为负向，颜色取反
				_spawn_float(tr("ui.float_safety") % value, _delta_color(-int(value)), _safety_label)
				_flash(_safety_label)
			"data":
				_spawn_float(tr("ui.float_data") % value, Color(0.55, 0.78, 1.0), _challenge_label)
				_flash(_challenge_label)
			"stage":
				_spawn_float(tr("ui.stage_enter") % tr("stage." + String(value)), Color(0.45, 0.85, 0.95), _stage_label)
				_flash(_stage_label)
				GameAudio.sfx("stage")
	_play_delta_sound(deltas)


## 资金 / 疗效增加或安全风险下降算好消息，反之算坏消息
func _play_delta_sound(deltas: Dictionary) -> void:
	if deltas.has("stage"):
		return
	var score := int(deltas.get("funding", 0)) + int(deltas.get("efficacy", 0)) - int(deltas.get("safety_risk", 0))
	if score > 0:
		GameAudio.sfx("gain")
	elif score < 0:
		GameAudio.sfx("loss")


func _delta_color(value: int) -> Color:
	return Color(0.31, 0.78, 0.55) if value > 0 else Color(0.93, 0.42, 0.42)


func _flash(control: Control) -> void:
	var tween := create_tween()
	tween.tween_property(control, "modulate", Color(1.0, 0.9, 0.35), 0.12)
	tween.tween_property(control, "modulate", Color(1, 1, 1), 0.35)


## anchor 为浮字出现位置旁的控件；为空时显示在顶部中央（新闻等）
func _spawn_float(text: String, color: Color, anchor: Control = null) -> void:
	var label := CardView.label(text, color, 16)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	_float_layer.add_child(label)
	if _overlay_open():
		anchor = null   # 弹窗打开时指标被遮住，改在顶部居中提示
	var slot_key: Variant = anchor if anchor != null else "top"
	var slot := int(_float_slots.get(slot_key, 0))
	_float_slots[slot_key] = slot + 1
	var origin: Vector2
	if anchor != null and anchor.is_visible_in_tree():
		var rect := anchor.get_global_rect()
		origin = Vector2(rect.end.x + 12, rect.position.y) - _float_layer.global_position
	else:
		origin = Vector2(size.x * 0.5 - label.get_combined_minimum_size().x * 0.5, 4)
	origin.y += slot * 22
	label.position = origin
	label.pivot_offset = label.get_combined_minimum_size() * 0.5
	label.scale = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.6 if anchor != null else 1.6)
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "position:y", origin.y - 26.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void:
		_float_slots[slot_key] = maxi(int(_float_slots.get(slot_key, 1)) - 1, 0)
		label.queue_free())


func _overlay_open() -> bool:
	for popup in [_card_popup, _event_popup, _battle_view, _reward_popup, _map_screen]:
		if popup.visible:
			return true
	return false


func _set_message(text: String, tone: String) -> void:
	_event_label.text = text
	_event_label.add_theme_color_override("font_color", EVENT_COLOR[tone])


# ---------- 决策弹窗 ----------

## 战斗结果仍在展示时，后续弹窗排队等待「继续」
func _show_or_queue(callable: Callable) -> void:
	if _battle_view.visible:
		_after_battle.append(callable)
	else:
		callable.call()


func _flush_after_battle() -> void:
	if not _finished:
		GameAudio.music("lab")
	var queued := _after_battle.duplicate()
	_after_battle.clear()
	for callable in queued:
		callable.call()


func _on_event_offered(event: Dictionary, is_gate: bool) -> void:
	_show_or_queue(func() -> void:
		GameAudio.sfx("open")
		_event_popup.show_event(event, is_gate, _game_logic.get_state()))


func _on_card_pick_offered(cards: Array, purpose: String) -> void:
	GameAudio.sfx("card_draw")
	_card_popup.show_cards(cards, purpose, _game_logic.get_pick_cost(), _game_logic.get_state().funding, _game_logic.get_ai_info())


func _on_battle_resolved(victory: bool, effects: Dictionary) -> void:
	_set_message(tr("ui.challenge_win" if victory else "ui.challenge_fail") % ProjectState.format_effects(effects),
		"positive" if victory else "negative")


func _on_reward_offered(reward: Dictionary) -> void:
	_show_or_queue(func() -> void:
		GameAudio.sfx("gain")
		_reward_popup.show_reward(reward))


func _on_reward_claimed() -> void:
	_reward_popup.visible = false


func _on_news_posted(items: Array) -> void:
	for item in items:
		var args: Array = []
		for a in item.get("args", []):
			args.append(tr(a) if a is String else a)
		_spawn_float(tr(String(item.key)) % args, Color(0.95, 0.8, 0.4))
	_on_state_synced(_game_logic.get_state())


func _refresh_abilities(state) -> void:
	if state.abilities.is_empty():
		_abilities_label.text = tr("ui.hub_abilities_none")
		return
	var names: Array[String] = []
	for ability_id in state.abilities:
		var ability: Dictionary = _game_logic.get_ability_by_id(String(ability_id))
		names.append("· " + tr(String(ability.get("name_key", String(ability_id)))))
	_abilities_label.text = "\n".join(names)


func _on_run_ended(outcome: String, reason_key: String, summary: Dictionary) -> void:
	_finished = true
	_after_battle.clear()
	for popup in [_card_popup, _event_popup, _reward_popup, _map_screen]:
		popup.visible = false
	var text := tr(reason_key) + "\n" + tr("ui.run_summary") % [summary.data_saved, summary.level_before, summary.level_after]
	if int(summary.funding_carry) > 0:
		text += tr("ui.run_carry") % summary.funding_carry
	_set_message(text, "positive" if outcome == "approved" else ("neutral" if outcome == "terminated" else "negative"))
	_advance_button.disabled = false
	_advance_button.text = tr("ui.restart")
	_advance_button.icon = UIKit.icon("ui_play")
	_challenge_button.disabled = true
	# 战斗中落败时，先让玩家看完战斗结果，点「继续」后再显示结局
	_show_or_queue(func() -> void:
		GameAudio.music("")
		GameAudio.sting(outcome)
		_ending.show_ending(outcome, reason_key, summary, _game_logic.get_state()))
