class_name MapScreen
extends Control
## 研发地图界面（纯 UI 层）
## 左侧为当前阶段的研发路线图（MapCanvas，从左往右推进），右侧为本阶段 Boss 预告，
## 竞争格局与 AI 数据收进可展开的小卡片（InfoCard）。
## 点击可前往的节点发出 node_requested，由 rd_ui 转发给 GameLogic。

signal node_requested(index: int)
signal close_requested()

@onready var _panel: PanelContainer = $Center/Panel
@onready var _stage_label: Label = %StageLabel
@onready var _pos_label: Label = %PosLabel
@onready var _funding_label: Label = %FundingLabel
@onready var _year_label: Label = %YearLabel
@onready var _node_list: VBoxContainer = %NodeList
@onready var _hint_label: Label = %HintLabel
@onready var _advance_button: Button = %AdvanceButton
@onready var _close_button: Button = %CloseButton

var _game = null
var _canvas: MapCanvas = null
var _goal_card: InfoCard = null
var _competition_card: InfoCard = null
var _ai_card: InfoCard = null
var _boss_box: HBoxContainer = null
var _hp_label: Label = null          # 顶栏生命值：生命 = 100 - 安全风险
var _hp_bar: ProgressBar = null
var _research_bar: ProgressBar = null   # 标题区的前期研究进度条


## 由 rd_ui 注入 GameLogic 并构建地图画布与侧栏
func bind(game) -> void:
	_game = game
	_panel.custom_minimum_size = Vector2(1180, 0)
	_advance_button.visible = false
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	_node_list.add_child(body)
	_canvas = MapCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.node_pressed.connect(func(index: int) -> void: node_requested.emit(index))
	body.add_child(_canvas)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	body.add_child(side)
	var boss_panel := PanelContainer.new()
	boss_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.16, 0.06, 0.08, 0.9), Color(0.93, 0.35, 0.4, 0.7), 12))
	_boss_box = HBoxContainer.new()
	_boss_box.add_theme_constant_override("separation", 10)
	boss_panel.add_child(_boss_box)
	side.add_child(boss_panel)
	side.custom_minimum_size = Vector2(320, 0)
	_goal_card = InfoCard.new("outcome_approved", "goal.title", UIKit.ACCENT)
	_goal_card.pin()
	side.add_child(_goal_card)
	_competition_card = InfoCard.new("node_event", "ui.competition_title", UIKit.GOLD)
	_ai_card = InfoCard.new("type_ai", "ui.ai_title", UIKit.ACCENT_BLUE)
	side.add_child(_competition_card)
	side.add_child(_ai_card)
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	_build_hp(_funding_label.get_parent())
	_build_header()


## 顶部标题区改成「研发地图 · 阶段名」一行 + 带进度条的前期研究小标签
func _build_header() -> void:
	var header: HBoxContainer = _close_button.get_parent()
	_stage_label.get_parent().remove_child(_stage_label)
	header.add_child(_stage_label)
	header.move_child(_stage_label, 1)
	_stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_label.theme_type_variation = &"HeaderLabel"
	_stage_label.add_theme_font_size_override("font_size", 22)
	(header.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var parent := _pos_label.get_parent()
	var index := _pos_label.get_index()
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 8)
	chip.tooltip_text = tr("hub.research_tip") % 30
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.add_child(UIKit.icon_rect("stat_progress", 18, UIKit.ACCENT_BLUE))
	_research_bar = ProgressBar.new()
	_research_bar.custom_minimum_size = Vector2(180, 8)
	_research_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_research_bar.show_percentage = false
	_research_bar.add_theme_stylebox_override("fill", UIKit.filled(UIKit.ACCENT_BLUE, UIKit.ACCENT_BLUE, 4))
	_research_bar.add_theme_stylebox_override("background", UIKit.filled(Color(0.1, 0.12, 0.16), Color(0.25, 0.3, 0.36), 4))
	chip.add_child(_research_bar)
	parent.remove_child(_pos_label)
	chip.add_child(_pos_label)
	parent.add_child(chip)
	parent.move_child(chip, index)


## 顶栏最前面加「♥ 生命 80/100」和血条：地图上选路时也能看到还剩多少血
func _build_hp(row: Control) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.tooltip_text = tr("ui.hp_tip")
	box.add_child(UIKit.icon_rect("ui_heart", 20, UIKit.DANGER))
	_hp_label = UIKit.label("", UIKit.TEXT, 16)
	box.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(150, 14)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.show_percentage = false
	_hp_bar.max_value = 100
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_hp_bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	box.add_child(gap)
	row.add_child(box)
	row.move_child(box, 0)


func show_map() -> void:
	visible = true
	refresh()


func refresh() -> void:
	if _game == null:
		return
	var s: ProjectState = _game.get_state()
	var map: ResearchMap = _game.get_map()
	_stage_label.text = "· " + tr("stage." + map.get_stage())
	_stage_label.add_theme_color_override("font_color", BattleView.STAGE_TINT.get(s.stage, Color(0.5, 0.7, 0.8)).lightened(0.45))
	_research_bar.max_value = maxi(_game.get_progress_gate(), 1)
	_research_bar.value = mini(s.research_progress, _game.get_progress_gate())
	_pos_label.text = tr("ui.map_progress") % [mini(s.research_progress, _game.get_progress_gate()), _game.get_progress_gate()]
	_funding_label.text = tr("ui.map_funding") % s.funding
	var hp := maxi(0, 100 - s.safety_risk)
	_hp_label.text = tr("ui.hp_value") % hp
	_hp_bar.value = hp
	var hp_color: Color = UIKit.ACCENT if hp > 60 else (UIKit.GOLD if hp > 30 else UIKit.DANGER)
	_hp_label.add_theme_color_override("font_color", hp_color.lightened(0.15))
	_hp_bar.add_theme_stylebox_override("fill", UIKit.filled(hp_color, hp_color, 4))
	_hp_bar.add_theme_stylebox_override("background", UIKit.filled(Color(0.1, 0.12, 0.16), Color(0.25, 0.3, 0.36), 4))
	_canvas.rest_heal = _game.get_rest_heal()
	_canvas.tint = BattleView.STAGE_TINT.get(s.stage, Color(0.2, 0.5, 0.5))
	_year_label.text = tr("ui.year") % s.year
	_hint_label.text = tr("ui.map_hint_fast") if _game.fast_track else tr("ui.map_hint")
	var boss: Dictionary = _game.get_boss_info()
	var boss_title := tr("encounter." + String(boss.get("id", "")))
	_canvas.set_map(map.get_layers(), map.path, map.get_choices(), _game.is_idle(), boss_title)
	_fill_boss(boss, boss_title)
	_competition_card.set_content(competition_summary(), competition_text())
	HubView.fill_goal_card(_goal_card, _game.get_final_checklist())
	var ai: Dictionary = _game.get_ai_info()
	_ai_card.set_content(tr("hub.ai_summary") % [tr("tier." + String(ai.tier)), ai.multiplier, ai.deviation], _ai_text(ai))


## Boss 预告：形象、名称、专属机制与前期研究的削弱幅度
func _fill_boss(boss: Dictionary, title: String) -> void:
	for child in _boss_box.get_children():
		child.queue_free()
	var defs: Array = JsonData.load_dict(BattleManager.ENEMIES_PATH).get("enemies", [])
	var first := String((boss.get("enemies", [""]) as Array)[0])
	for def in defs:
		if String(def.id) == first:
			var view := CreatureView.new()
			view.setup(def, true)
			view.radius = 30.0
			view.custom_minimum_size = Vector2(96, 96)
			_boss_box.add_child(view)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.label(tr("map.boss_preview"), UIKit.DANGER, 13))
	col.add_child(UIKit.header(title, 19, Color(1, 0.88, 0.85)))
	var desc := UIKit.label(tr("encounter." + String(boss.get("id", "")) + ".desc"), UIKit.TEXT, 13, true)
	desc.custom_minimum_size = Vector2(220, 0)
	col.add_child(desc)
	var cut := roundi((1.0 - float(boss.get("hp_scale", 1.0))) * 100)
	col.add_child(UIKit.label(tr("map.boss_cut") % cut if cut >= 0 else tr("map.boss_buff") % -cut,
		UIKit.ACCENT if cut > 0 else UIKit.TEXT_DIM, 13, true))
	if _game.rp2d > 0 and _game.state.stage == "二期临床试验":
		col.add_child(UIKit.label(tr("ui.rp2d_line") % _game.rp2d, UIKit.GOLD, 13, true))
	_boss_box.add_child(col)


func _ai_text(ai: Dictionary) -> String:
	return "\n".join([tr("ui.ai_line") % [ai.effective, tr("tier." + String(ai.tier)), ai.multiplier, ai.deviation],
		tr("ui.data_line") % [ai.run_data, ai.company_data, ai.level, ai.run_process], BattleView.ai_next_text(ai)])


## 竞品状态、终审门槛与最新动态（BBCode），主界面右栏也复用
## 竞争格局一行摘要：终审门槛被抬高时按来源说明（竞品获批 / 新机制，多个来源再给出合计）；
## 否则是跑得最快的在研竞品
func competition_summary() -> String:
	if _game == null:
		return ""
	var comp: Competition = _game.competition
	var sources: Array = comp.bar_sources()
	if not sources.is_empty():
		var parts: Array[String] = []
		for src in sources:
			if String(src.kind) == "approved":
				parts.append(tr("comp.src_approved") % [_short_name(String(src.name_key)), int(src.amount)])
			else:
				parts.append(tr("comp.src_mechanism") % int(src.amount))
		var text := " · ".join(parts)
		if sources.size() > 1:
			text += tr("comp.src_total") % comp.efficacy_bar_bonus
		return text
	var leader: Dictionary = {}
	for c in comp.competitors:
		if String(c.status) == "active" and (leader.is_empty() or int(c.stage) > int(leader.stage)):
			leader = c
	if leader.is_empty():
		return tr("comp.none")
	return tr("comp.leader") % [_short_name(String(leader.name_key)), tr("stage_index." + str(leader.stage))]


## 摘要里用短名「竞品 A」（去掉括号里的类型说明，展开后再看全名）
func _short_name(key: String) -> String:
	var full := tr(key)
	for mark in ["（", " ("]:
		if full.contains(mark):
			return full.left(full.find(mark))
	return full


func competition_text() -> String:
	if _game == null:
		return ""
	var comp: Competition = _game.competition
	var lines: Array[String] = []
	for c in comp.competitors:
		var status := String(c.status)
		var text := "%s：%s" % [tr(String(c.name_key)), tr("stage_index." + str(c.stage)) if status == "active" else tr("competitor.status." + status)]
		if comp.intel_revealed and status == "active":
			text += tr("ui.competitor_forecast") % comp.forecast_years(c)
		lines.append("· " + text)
	if comp.finance_mod != 0:
		lines.append(tr("ui.finance_mod") % comp.finance_mod)
	if not comp.news.is_empty():
		lines.append("")
		lines.append("[b]" + tr("ui.news_title") + "[/b]")
		for item in comp.news.slice(0, 3):
			lines.append("[color=#c8b26a]· " + _format_line(item) + "[/color]")
	return "\n".join(lines)


func _format_line(item: Dictionary) -> String:
	var args: Array = []
	for a in item.get("args", []):
		args.append(tr(a) if a is String else a)
	return tr(String(item.get("key", ""))) % args
