class_name HubView
extends Control
## 研发总览的「实验室场景」：取代原来的三栏面板，减少企业软件感。
##   背景：实验室后墙（货架、瓶罐）、按阶段着色的灯光、实验台；
##   主体：烧瓶研发团队站在实验台上，候选分子悬浮在分析仪上方（MoleculeArt）；
##   左上：RPG 式状态栏（生命条 + 资金 / 年份 / 疗效 / 前期研究）；
##   右上：AI / 研发能力 / 竞争格局三张可展开卡片，默认只显示一行摘要；
##   实验台正面：团队铭牌、消息条、「进入研发地图 / 查看牌库」按钮。
## 只负责展示；rd_ui 调 refresh(game) 刷新，并用这里的控件做飘字锚点。

var stage_label: Label
var molecule_art: MoleculeArt
var avatar: PlayerAvatar
var hp_label: Label
var hp_bar: ProgressBar
var funding_label: Label
var year_label: Label
var efficacy_label: Label
var efficacy_bar: ProgressBar
var progress_label: Label
var progress_bar: ProgressBar
var event_label: Label
var advance_button: Button
var challenge_button: Button
var goal_card: InfoCard
var ai_card: InfoCard
var abilities_card: InfoCard
var competition_card: InfoCard

var _team_label: Label
var _xp_bar: ProgressBar
var _bonus_label: Label
var _status_panel: PanelContainer
var _cards: VBoxContainer
var _bench_panel: Control
var _tint := Color(0.35, 0.28, 0.6)
var _time := 0.0
var _props: Array = []   # 后墙货架上的瓶罐 [x 比例, 货架层, 宽, 高, 颜色]

const BENCH_FROM_BOTTOM := 176.0
const STATUS_W := 330.0
const CARDS_W := 300.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var palette := [Color(0.45, 0.75, 1.0), Color(0.35, 0.95, 0.6), Color(0.95, 0.72, 0.35), Color(0.6, 0.48, 0.95), Color(0.93, 0.45, 0.45)]
	for shelf in 2:
		var x := 0.04
		while x < 0.96:
			var w := rng.randf_range(0.012, 0.024)
			_props.append([x, shelf, w, rng.randf_range(18, 44), palette[rng.randi_range(0, palette.size() - 1)]])
			x += w + rng.randf_range(0.008, 0.05)
	_build()
	resized.connect(_layout)


func _build() -> void:
	stage_label = UIKit.header("", 28, Color(0.75, 0.95, 1.0))
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.add_theme_constant_override("outline_size", 8)
	stage_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(stage_label)

	molecule_art = MoleculeArt.new()
	add_child(molecule_art)
	avatar = PlayerAvatar.new()
	add_child(avatar)
	avatar.custom_minimum_size = Vector2(170, 204)

	_status_panel = _glass_panel()
	add_child(_status_panel)
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 6)
	_status_panel.add_child(status)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	hp_row.tooltip_text = tr("ui.hp_tip")
	hp_row.mouse_filter = Control.MOUSE_FILTER_PASS
	hp_row.add_child(UIKit.icon_rect("ui_heart", 22, UIKit.DANGER))
	hp_bar = _bar(170, 16)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(hp_bar)
	hp_label = UIKit.header("", 17)
	hp_row.add_child(hp_label)
	status.add_child(hp_row)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	status.add_child(grid)
	funding_label = _chip(grid, "stat_funding", UIKit.GOLD, "")
	year_label = _chip(grid, "stat_year", UIKit.TEXT, "")
	var eff := _bar_chip(grid, "stat_efficacy", UIKit.ACCENT)
	efficacy_label = eff[0]
	efficacy_bar = eff[1]
	var prog := _bar_chip(grid, "stat_progress", UIKit.ACCENT_BLUE)
	progress_label = prog[0]
	progress_bar = prog[1]

	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 6)
	add_child(_cards)
	goal_card = InfoCard.new("outcome_approved", "goal.title", UIKit.ACCENT)
	goal_card.pin()
	_cards.add_child(goal_card)
	ai_card = InfoCard.new("type_ai", "ui.hub_ai", UIKit.ACCENT_BLUE)
	abilities_card = InfoCard.new("role_power", "ui.hub_abilities", Color(0.75, 0.55, 1.0))
	competition_card = InfoCard.new("node_event", "ui.competition_title", UIKit.GOLD)
	for card in [ai_card, abilities_card, competition_card]:
		_cards.add_child(card)

	# 实验台正面：左边团队铭牌，中间消息，下面按钮
	_bench_panel = Control.new()
	_bench_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_bench_panel)
	var plate := VBoxContainer.new()
	plate.name = "Plate"
	plate.add_theme_constant_override("separation", 3)
	_bench_panel.add_child(plate)
	_team_label = UIKit.header("", 15, PlayerAvatar.GREEN)
	plate.add_child(_team_label)
	_xp_bar = _bar(200, 10)
	plate.add_child(_xp_bar)
	_bonus_label = UIKit.label("", UIKit.TEXT_DIM, 12, true)
	_bonus_label.custom_minimum_size = Vector2(220, 0)
	plate.add_child(_bonus_label)
	# 消息条：放进 CenterContainer，由容器按最小尺寸居中排版（自动换行的 Label 自己定尺寸不可靠）
	var msg := CenterContainer.new()
	msg.name = "Message"
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bench_panel.add_child(msg)
	event_label = UIKit.label("", UIKit.TEXT, 15, true)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_child(event_label)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_bench_panel.add_child(buttons)
	advance_button = UIKit.button(tr("ui.enter_map"), "node_research", "primary", Vector2(260, 52))
	advance_button.add_theme_font_size_override("font_size", 20)
	advance_button.set_meta("sfx", "open")
	buttons.add_child(advance_button)
	challenge_button = UIKit.button(tr("ui.view_deck"), "ui_deck", "normal", Vector2(170, 52))
	challenge_button.add_theme_font_size_override("font_size", 17)
	buttons.add_child(challenge_button)


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w < 600 or h < 300:
		return   # 尚未排版到真实尺寸：零宽度时自动换行文字会撑出很高的最小尺寸，之后缩不回来
	var bench_y := h - BENCH_FROM_BOTTOM
	stage_label.position = Vector2(STATUS_W + 20, 14)
	stage_label.size = Vector2(w - STATUS_W - CARDS_W - 40, 40)
	_status_panel.position = Vector2(14, 14)
	_status_panel.size = Vector2(STATUS_W, 0)
	_cards.position = Vector2(w - CARDS_W - 14, 14)
	_cards.size = Vector2(CARDS_W, 0)
	avatar.size = avatar.custom_minimum_size
	avatar.position = Vector2(w * 0.3 - avatar.size.x * 0.5, bench_y - avatar.size.y + 12)
	var mol := Vector2(minf(300, w * 0.26), minf(240, bench_y - 70))
	molecule_art.size = mol
	molecule_art.position = Vector2(w * 0.56 - mol.x * 0.5, bench_y - 58 - mol.y)
	_bench_panel.position = Vector2(0, bench_y + 14)
	_bench_panel.size = Vector2(w, h - bench_y - 14)
	var plate: Control = _bench_panel.get_node("Plate")
	plate.position = Vector2(w * 0.3 - 110, 6)
	plate.size = Vector2(220, 0)
	var msg_w := (w - CARDS_W - 28) - (w * 0.3 + 130)   # 右侧卡片列可能伸到台面，消息不压到它
	var msg: Control = _bench_panel.get_node("Message")
	event_label.custom_minimum_size = Vector2(msg_w, 0)
	msg.position = Vector2(w * 0.3 + 130, 4)
	# 文字最小高度要等定宽后下一帧才更新；立即设尺寸会被旧的（零宽度时的）最小高度撑大
	msg.set_deferred("size", Vector2(msg_w, 64))
	var buttons: Control = _bench_panel.get_node("Buttons")
	buttons.size = Vector2(w, 52)
	buttons.position = Vector2(0, _bench_panel.size.y - 64)
	queue_redraw()


## 终审目标卡：每个条件一行，达标打勾、不达标写差多少；标题后汇总「n/m 达标」
static func fill_goal_card(card: InfoCard, items: Array) -> void:
	var t := TranslationServer
	var lines: Array[String] = []
	var met := 0
	for item in items:
		var ok := bool(item.ok)
		met += 1 if ok else 0
		var need := ("< %d" % int(item.need)) if item.id == "safety" else str(int(item.need))
		var mark := "[color=#5ad99a]✓[/color]" if ok else "[color=#ff8a80]%s[/color]" % (t.translate("goal.gap") % int(item.gap))
		lines.append("%s　[b]%d[/b] / %s　%s" % [t.translate("goal." + String(item.id)), int(item.current), need, mark])
	card.set_title_suffix(t.translate("goal.summary") % [met, items.size()])
	card.set_content("", "\n".join(lines))


## 状态全部从 game 读：rd_ui 在状态同步时调用（竞争格局的摘要与全文由地图界面生成后传入）
func refresh(game, competition_summary: String, competition_text: String) -> void:
	var state: ProjectState = game.get_state()
	stage_label.text = tr("stage." + state.stage)
	_tint = BattleView.STAGE_TINT.get(state.stage, Color(0.2, 0.5, 0.5))
	var stages: Array = game.get_stages()
	molecule_art.stage_index = maxi(stages.find(state.stage), 0)
	molecule_art.health = clampf(0.5 + (state.efficacy - state.safety_risk) / 120.0, 0.0, 1.0)
	var hp := maxi(0, 100 - state.safety_risk)
	hp_bar.value = hp
	hp_label.text = tr("ui.hp_value") % hp
	var hp_color: Color = UIKit.ACCENT if hp > 60 else (UIKit.GOLD if hp > 30 else UIKit.DANGER)
	_style_bar(hp_bar, hp_color)
	hp_label.add_theme_color_override("font_color", hp_color.lightened(0.2))
	hp_label.get_parent().tooltip_text = tr("ui.hp_tip") + "\n" + tr("hub.safety_tip") % [state.safety_risk, game.get_final_safety_limit()]
	funding_label.text = tr("hub.funding") % state.funding
	year_label.text = tr("ui.year") % state.year
	var bar := game.get_final_efficacy_bar() as int
	efficacy_label.text = tr("hub.efficacy") % [state.efficacy, bar]
	efficacy_bar.max_value = maxi(bar, 1)
	efficacy_bar.value = mini(state.efficacy, bar)
	efficacy_label.get_parent().get_parent().tooltip_text = tr("hub.efficacy_tip") % bar
	var gate := game.get_progress_gate() as int
	progress_label.text = tr("hub.research") % [mini(state.research_progress, gate), gate]
	progress_bar.max_value = maxi(gate, 1)
	progress_bar.value = mini(state.research_progress, gate)
	progress_label.get_parent().get_parent().tooltip_text = tr("hub.research_tip") % gate
	# 团队铭牌
	var level: int = game.get_player_level()
	avatar.form = level
	avatar.ratio = float(hp) / 100.0
	var next: int = game.get_next_level_xp()
	_team_label.text = tr("player.tag") % [level, tr("player.level.%d" % level)]
	_xp_bar.max_value = maxi(next, 1) if next > 0 else 1
	_xp_bar.value = game.player_xp if next > 0 else 1
	_xp_bar.tooltip_text = tr("player.xp") % [game.player_xp, next] if next > 0 else tr("player.max")
	_bonus_label.text = PlayerHud.bonus_text(game.get_player_bonus())
	# 右侧三张卡片
	var ai: Dictionary = game.get_ai_info()
	ai_card.set_content(tr("hub.ai_summary") % [tr("tier." + String(ai.tier)), ai.multiplier, ai.deviation],
		tr("ui.hub_ai_detail") % [ai.effective, tr("tier." + String(ai.tier)), ai.multiplier, ai.deviation,
			ai.run_data, ai.company_data, ai.level] + "\n" + BattleView.ai_next_text(ai))
	var names: Array[String] = []
	for ability_id in state.abilities:
		names.append("· " + tr(String(game.get_ability_by_id(String(ability_id)).get("name_key", String(ability_id)))))
	abilities_card.set_content(tr("hub.abilities_summary") % names.size() if not names.is_empty() else tr("hub.abilities_empty"),
		"\n".join(names) if not names.is_empty() else tr("ui.hub_abilities_none"))
	competition_card.set_content(competition_summary, competition_text)
	fill_goal_card(goal_card, game.get_final_checklist())
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var bench_y := h - BENCH_FROM_BOTTOM
	var rect := Rect2(Vector2.ZERO, size)
	# 后墙：深色渐变 + 阶段色灯光
	draw_style_box(UIKit.filled(Color(0.05, 0.08, 0.11, 0.96), Color(0.2, 0.28, 0.34), 14), rect)
	var pulse := 0.5 + 0.5 * sin(_time * 1.2)
	var light := Vector2(w * 0.56, bench_y - 150)
	for i in 10:
		draw_circle(light, (330.0 - i * 28.0), Color(_tint.lightened(0.2), 0.022 + 0.006 * pulse))
	# 货架与瓶罐
	for shelf in 2:
		var y := bench_y - 200.0 + shelf * 92.0
		if y < 70:
			continue
		draw_rect(Rect2(w * 0.03, y, w * 0.94, 4), Color(0.25, 0.32, 0.38, 0.55))
		for prop in _props:
			if int(prop[1]) != shelf:
				continue
			var px: float = float(prop[0]) * w
			if px > w * 0.42 and px < w * 0.7:
				continue   # 分子周围留空
			var pw: float = float(prop[2]) * w
			var ph: float = prop[3]
			var c: Color = prop[4]
			draw_rect(Rect2(px, y - ph, pw, ph), Color(c, 0.16))
			draw_rect(Rect2(px, y - ph * 0.45, pw, ph * 0.45), Color(c, 0.22))
			draw_rect(Rect2(px + pw * 0.3, y - ph - 6, pw * 0.4, 6), Color(c, 0.18))
	# 分析仪：分子下方的底座与向上的光柱
	var base := Vector2(w * 0.56, bench_y)
	var beam := PackedVector2Array([base + Vector2(-70, -40), base + Vector2(70, -40), base + Vector2(150, -300), base + Vector2(-150, -300)])
	draw_colored_polygon(beam, Color(_tint.lightened(0.4), 0.05 + 0.03 * pulse))
	draw_style_box(UIKit.filled(Color(0.12, 0.16, 0.2), Color(_tint.lightened(0.3), 0.8), 10), Rect2(base + Vector2(-90, -44), Vector2(180, 44)))
	draw_rect(Rect2(base + Vector2(-60, -30), Vector2(120, 6)), Color(_tint.lightened(0.5), 0.6 + 0.3 * pulse))
	# 实验台：台面高光 + 正面
	draw_rect(Rect2(0, bench_y, w, 14), Color(0.32, 0.4, 0.46))
	draw_rect(Rect2(0, bench_y + 14, w, h - bench_y - 14), Color(0.09, 0.12, 0.15))
	draw_line(Vector2(0, bench_y), Vector2(w, bench_y), Color(0.6, 0.72, 0.8, 0.6), 2.0)
	for x in range(1, 6):
		draw_line(Vector2(w * x / 6.0, bench_y + 14), Vector2(w * x / 6.0, h), Color(0, 0, 0, 0.25), 2.0)
	# 台面小道具：右侧试管架与烧杯
	var rack := Vector2(w * 0.8, bench_y)
	if w > 900:
		for i in 4:
			var tube := Rect2(rack + Vector2(i * 16 - 32, -46), Vector2(9, 40))
			draw_rect(tube, Color(0.7, 0.85, 0.95, 0.25))
			draw_rect(Rect2(tube.position + Vector2(0, 22), Vector2(9, 18)), Color([UIKit.ACCENT, UIKit.ACCENT_BLUE, UIKit.GOLD, UIKit.DANGER][i], 0.55))
		draw_rect(Rect2(rack + Vector2(-40, -18), Vector2(78, 6)), Color(0.4, 0.48, 0.55))
	# 阴影：烧瓶脚下
	var feet := Vector2(w * 0.3, bench_y + 4)
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 70, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)


func _glass_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0.04, 0.06, 0.09, 0.78), Color(0.3, 0.4, 0.46, 0.6), 12)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _bar(width: float, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(width, height)
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_bar(b, UIKit.ACCENT)
	return b


func _style_bar(b: ProgressBar, color: Color) -> void:
	b.add_theme_stylebox_override("fill", UIKit.filled(color, color, 4))
	b.add_theme_stylebox_override("background", UIKit.filled(Color(0.1, 0.12, 0.16), Color(0.25, 0.3, 0.36), 4))


func _chip(grid: GridContainer, icon_name: String, color: Color, text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(UIKit.icon_rect(icon_name, 18, color))
	var label := UIKit.label(text, color.lightened(0.15), 15)
	row.add_child(label)
	grid.add_child(row)
	return label


## 带小进度条的指标（疗效对终审门槛、前期研究对 Boss 削弱上限）
func _bar_chip(grid: GridContainer, icon_name: String, color: Color) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(UIKit.icon_rect(icon_name, 18, color))
	var label := UIKit.label("", color.lightened(0.15), 14)
	row.add_child(label)
	col.add_child(row)
	var b := _bar(140, 6)
	_style_bar(b, color)
	col.add_child(b)
	grid.add_child(col)
	return [label, b]
