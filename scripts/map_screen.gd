class_name MapScreen
extends Control
## 研发地图界面（纯 UI 层）
## 左侧为当前阶段的分层分支地图（MapCanvas），右侧为本阶段 Boss 预告、竞品格局与 AI 数据面板。
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
var _side_label: RichTextLabel = null
var _boss_box: HBoxContainer = null


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
	_side_label = RichTextLabel.new()
	_side_label.bbcode_enabled = true
	_side_label.fit_content = true
	_side_label.custom_minimum_size = Vector2(340, 0)
	_side_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_label.add_theme_font_size_override("normal_font_size", 14)
	_side_label.add_theme_font_size_override("bold_font_size", 15)
	side.add_child(_side_label)
	_close_button.pressed.connect(func() -> void: close_requested.emit())


func show_map() -> void:
	visible = true
	refresh()


func refresh() -> void:
	if _game == null:
		return
	var s: ProjectState = _game.get_state()
	var map: ResearchMap = _game.get_map()
	_stage_label.text = tr("ui.stage_key_label") + tr("stage." + map.get_stage())
	_pos_label.text = tr("ui.map_progress") % [mini(s.research_progress, _game.get_progress_gate()), _game.get_progress_gate()]
	_funding_label.text = tr("ui.map_funding") % s.funding
	_year_label.text = tr("ui.year") % s.year
	_hint_label.text = tr("ui.map_hint_fast") if _game.fast_track else tr("ui.map_hint")
	var boss: Dictionary = _game.get_boss_info()
	var boss_title := tr("encounter." + String(boss.get("id", "")))
	_canvas.set_map(map.get_layers(), map.path, map.get_choices(), _game.is_idle(), boss_title)
	_fill_boss(boss, boss_title)
	_side_label.text = _side_text()


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
	_boss_box.add_child(col)


func _side_text() -> String:
	var lines: Array[String] = ["[b]" + tr("ui.competition_title") + "[/b]", competition_text()]
	var ai: Dictionary = _game.get_ai_info()
	lines.append("")
	lines.append("[b]" + tr("ui.ai_title") + "[/b]")
	lines.append(tr("ui.ai_line") % [ai.effective, tr("tier." + String(ai.tier)), ai.multiplier, ai.deviation])
	lines.append(tr("ui.data_line") % [ai.run_data, ai.company_data, ai.level, ai.run_process])
	if _game.rp2d > 0:
		lines.append(tr("ui.rp2d_line") % _game.rp2d)
	return "\n".join(lines)


## 竞品状态、终审门槛与最新动态（BBCode），主界面右栏也复用
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
	lines.append(tr("ui.final_bar") % [_game.get_final_efficacy_bar(), _game.get_final_safety_limit()])
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
