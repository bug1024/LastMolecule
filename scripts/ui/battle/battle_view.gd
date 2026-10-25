class_name BattleView
extends Control
## 战斗画面（纯 UI 层），仿杀戮尖塔布局：左侧玩家烧瓶，右侧敌人与头顶意图，底部扇形手牌。
## 逻辑由 BattleManager 即时结算；本界面按事件列表依次播放动画（出牌飞行、受击闪白、
## 伤害数字、震屏、粒子、敌人前冲），播放期间锁定输入。
## 单体攻击在有多个敌人时需要再点击目标；右键或 Esc 取消。快捷键：E 结束回合，1–9 选牌。
## 氛围：生命低于 30% 时屏幕边缘泛红闪烁并有心跳声；Boss 战常驻暗红压迫边框，Boss 重击时闪红、踏地震屏。
## 每局第一场战斗显示一张图示小提示；战斗胜利后若团队升级，烧瓶会当场进化。

signal continue_pressed()
signal pile_requested(cards: Array, title_key: String)

const CARD_SCALE := 0.9
const HOVER_SCALE := 1.18
const STAGE_TINT := {
	"候选化合物发现": Color(0.35, 0.28, 0.6),
	"临床前研究": Color(0.3, 0.45, 0.2),
	"一期临床试验": Color(0.55, 0.22, 0.22),
	"二期临床试验": Color(0.2, 0.32, 0.6),
	"三期临床试验": Color(0.18, 0.45, 0.45),
}

var _manager: BattleManager
var _game = null
var _queue: Array = []
var _busy := false
var _ended := false
var _victory := false
var _battle_token := 0      # 每场战斗递增，防止上一场未完成的开场动画干扰新战斗

var _bg: MoleculeBackground
var _floor: Control
var _shake_root: Control
var _player: PlayerAvatar
var _player_bar: HealthBar
var _player_status: StatusRow
var _enemy_widgets: Array[EnemyWidget] = []
var _hand_root: Control
var _faces := {}            # ResearchCard → CardFace
var _hand_cards: Array = [] # 当前展示的手牌（按事件快照推进，可能落后于逻辑层）
var _hover_card: ResearchCard = null
var _selected: ResearchCard = null
var _hover_enemy := -1
var _energy_label: Label
var _energy_orb: Control
var _rule_label: Label               # 脱靶反噬：本回合还能放心打几张攻击牌 / 当前这张牌的反噬预告
var _draw_button: Button
var _discard_button: Button
var _end_button: Button
var _dose_button: Button
var _title: Label
var _kind_tag: Label
var _turn_label: Label
var _ai_label: Label
var _ai_next_label: Label
var _mechanic: RichTextLabel
var _fx: Control
var _arrow: Control
var _banner: Control
var _continue: Button
var _player_tag: Label
var _vignette_low: TextureRect
var _vignette_boss: TextureRect
var _flash_rect: ColorRect
var _tip: PanelContainer
var _is_boss := false
var _heart_timer := 0.0
var _time := 0.0
var _pending_level := 0
var _shown_player_hp := 100


func bind(manager: BattleManager, game) -> void:
	_manager = manager
	_game = game
	manager.battle_started.connect(_on_battle_started)
	manager.events_emitted.connect(_on_events)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


# ---------- 搭建 ----------

func _build() -> void:
	_bg = MoleculeBackground.new()
	_bg.molecule_count = 14
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_floor = Control.new()
	_floor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor.draw.connect(_draw_floor)
	add_child(_floor)
	_shake_root = Control.new()
	_shake_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shake_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shake_root)

	_player = PlayerAvatar.new()
	_shake_root.add_child(_player)
	_player_bar = HealthBar.new()
	_player_bar.is_player = true
	_shake_root.add_child(_player_bar)
	_player_tag = UIKit.header("", 16, PlayerAvatar.GREEN)
	_player_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_tag.add_theme_constant_override("outline_size", 6)
	_player_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_shake_root.add_child(_player_tag)
	_player_status = StatusRow.new()
	_shake_root.add_child(_player_status)
	_dose_button = UIKit.button("", "status_strength", "danger", Vector2(200, 44))
	_dose_button.pressed.connect(func() -> void:
		if not _busy:
			_manager.do_action("dose"))
	_shake_root.add_child(_dose_button)

	_title = UIKit.header("", 24)
	_title.position = Vector2(24, 12)
	add_child(_title)
	_kind_tag = UIKit.label("", UIKit.GOLD, 14)
	add_child(_kind_tag)
	_turn_label = UIKit.header("", 18, UIKit.TEXT_DIM)
	add_child(_turn_label)
	_ai_label = UIKit.label("", UIKit.ACCENT_BLUE, 14)
	_ai_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_ai_label)
	_ai_next_label = UIKit.label("", Color(0.75, 0.88, 1.0), 13)
	_ai_next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_ai_next_label)
	_mechanic = UIKit.rich("", 14)
	_mechanic.custom_minimum_size = Vector2(560, 0)
	_mechanic.position = Vector2(24, 50)
	_mechanic.size = Vector2(560, 60)
	add_child(_mechanic)

	_energy_orb = Control.new()
	_energy_orb.size = Vector2(90, 90)
	_energy_orb.mouse_filter = Control.MOUSE_FILTER_PASS
	_energy_orb.tooltip_text = tr("battle.energy_tip")
	_energy_orb.draw.connect(_draw_energy)
	add_child(_energy_orb)
	_energy_label = UIKit.header("", 28)
	_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_energy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_energy_label.size = Vector2(90, 90)
	_energy_label.add_theme_constant_override("outline_size", 6)
	_energy_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_energy_orb.add_child(_energy_label)
	_rule_label = UIKit.label("", UIKit.GOLD, 14, true)
	_rule_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule_label.size = Vector2(150, 62)
	_rule_label.tooltip_text = tr("battle.rule_tip")
	_rule_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_rule_label)
	_draw_button = UIKit.button("", "ui_draw_pile", "normal", Vector2(110, 44))
	_draw_button.pressed.connect(func() -> void: pile_requested.emit(_sorted(_manager.draw_pile), "battle.pile.draw"))
	add_child(_draw_button)
	_discard_button = UIKit.button("", "ui_discard_pile", "normal", Vector2(110, 44))
	_discard_button.pressed.connect(func() -> void: pile_requested.emit(_manager.discard_pile.duplicate(), "battle.pile.discard"))
	add_child(_discard_button)
	_end_button = UIKit.button(tr("ui.end_turn"), "", "primary", Vector2(180, 60))
	_end_button.add_theme_font_size_override("font_size", 20)
	_end_button.set_meta("sfx", "turn")
	_end_button.pressed.connect(_on_end_turn)
	add_child(_end_button)

	_hand_root = Control.new()
	_hand_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand_root)
	_arrow = Control.new()
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	_vignette_boss = _make_vignette(Color(0.35, 0.0, 0.02))
	_vignette_low = _make_vignette(Color(0.95, 0.05, 0.05))
	# 边缘遮罩只压在战场上，不盖住手牌和按钮
	move_child(_vignette_boss, _shake_root.get_index() + 1)
	move_child(_vignette_low, _shake_root.get_index() + 2)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 0.1, 0.05, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_banner = Control.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_continue = UIKit.button("", "ui_play", "primary", Vector2(240, 56))
	_continue.add_theme_font_size_override("font_size", 20)
	_continue.visible = false
	_continue.pressed.connect(func() -> void:
		visible = false
		GameAudio.music("lab")
		continue_pressed.emit())
	add_child(_continue)
	resized.connect(_layout)


## 屏幕边缘渐变遮罩（中心透明、四周着色）
func _make_vignette(color: Color) -> TextureRect:
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.0), Color(color, 1.0)])
	tex.gradient = g
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	add_child(rect)
	return rect


func _layout() -> void:
	var w := size.x
	var h := size.y
	_player.size = _player.custom_minimum_size
	_player.size = Vector2(200, 240)
	_player.position = Vector2(w * 0.1, 140)
	_player_tag.position = Vector2(w * 0.1 - 20, 362)
	_player_tag.size = Vector2(240, 24)
	_player_bar.position = Vector2(w * 0.1 + 6, 388)
	_player_bar.size = Vector2(190, 26)
	_player_status.position = Vector2(w * 0.1 + 14, 418)
	_dose_button.position = Vector2(w * 0.1 - 6, 102)
	_kind_tag.position = Vector2(24 + _title.get_combined_minimum_size().x + 14, 20)
	_turn_label.position = Vector2(w * 0.5 - 60, 16)
	_ai_label.position = Vector2(w - 424, 18)
	_ai_label.size = Vector2(400, 20)
	_ai_next_label.position = Vector2(w - 424, 40)
	_ai_next_label.size = Vector2(400, 18)
	_energy_orb.position = Vector2(34, h - 250)
	_rule_label.position = Vector2(4, h - 156)
	_draw_button.position = Vector2(24, h - 70)
	_discard_button.position = Vector2(w - 134, h - 70)
	_end_button.position = Vector2(w - 214, h - 250)
	_continue.position = Vector2(w * 0.5 - 120, h * 0.5 + 70)
	var n := _enemy_widgets.size()
	var span := w * 0.52
	for i in n:
		var ew := _enemy_widgets[i]
		var x := w * 0.42 + span * (i + 0.5) / n - EnemyWidget.SIZE.x * 0.5
		ew.position = Vector2(x, 96 + (16 if n > 1 and i % 2 == 1 else 0))
	_layout_hand(true)
	_floor.queue_redraw()


func _draw_floor() -> void:
	var w := _floor.size.x
	var y := 420.0
	var tint: Color = STAGE_TINT.get(_game.state.stage if _game else "", Color(0.3, 0.4, 0.5))
	for i in 10:
		var r := Vector2(w * 0.55 - i * 30, 70 - i * 6)
		var pts := PackedVector2Array()
		for k in 40:
			var a := TAU * k / 40.0
			pts.append(Vector2(w * 0.5, y) + Vector2(cos(a) * r.x, sin(a) * r.y))
		_floor.draw_colored_polygon(pts, Color(tint, 0.035))
	_floor.draw_line(Vector2(0, y), Vector2(w, y), Color(tint.lightened(0.4), 0.12), 2.0)


func _draw_energy() -> void:
	var c := _energy_orb.size * 0.5
	var full := _manager != null and _manager.energy > 0
	var color := Color(0.98, 0.72, 0.3) if full else Color(0.4, 0.4, 0.45)
	for i in 6:
		_energy_orb.draw_circle(c, 44 - i * 2, Color(color, 0.05))
	_energy_orb.draw_circle(c, 34, color.darkened(0.55))
	_energy_orb.draw_circle(c, 30, color.darkened(0.15))
	_energy_orb.draw_circle(c + Vector2(-9, -10), 10, Color(1, 1, 1, 0.25))
	_energy_orb.draw_arc(c, 34, 0, TAU, 48, color.lightened(0.3), 3.0, true)


# ---------- 战斗开始 ----------

func _on_battle_started(encounter: Dictionary) -> void:
	_battle_token += 1
	var token := _battle_token
	_ended = false
	_victory = false
	_queue.clear()
	_busy = true
	_selected = null
	_hover_card = null
	_continue.visible = false
	for child in _fx.get_children() + _banner.get_children() + _hand_root.get_children():
		child.queue_free()
	_faces.clear()
	_hand_cards.clear()
	for ew in _enemy_widgets:
		ew.queue_free()
	_enemy_widgets.clear()
	for i in _manager.enemies.size():
		var ew := EnemyWidget.new()
		ew.setup(_manager.enemies[i], i)
		ew.pressed.connect(_on_enemy_pressed)
		ew.hovered.connect(func(idx: int, on: bool) -> void:
			_hover_enemy = idx if on else (-1 if _hover_enemy == idx else _hover_enemy)
			_refresh_faces()
			_refresh_energy())
		_shake_root.add_child(ew)
		_enemy_widgets.append(ew)
	var kind := String(encounter.get("kind", "fight"))
	_is_boss = kind == "boss"
	_pending_level = 0
	_player.form = _game.get_player_level()
	_player.set_mood("")
	_player_tag.text = tr("player.tag") % [_game.get_player_level(), tr("player.level.%d" % _game.get_player_level())]
	_shown_player_hp = _manager.player.hp
	_title.text = tr("encounter." + String(encounter.get("id", kind))) if kind == "boss" else tr("enemy." + String(_manager.enemies[0].id))
	if kind != "boss" and _manager.enemies.size() > 1:
		_title.text = tr("encounter.group") % [_title.text, _manager.enemies.size()]
	_kind_tag.text = tr("encounter.kind." + kind)
	_kind_tag.add_theme_color_override("font_color", {"boss": UIKit.DANGER, "elite": UIKit.GOLD}.get(kind, UIKit.TEXT_DIM))
	_bg.glow_color = STAGE_TINT.get(_game.state.stage, Color(0.2, 0.5, 0.5))
	var mech_lines: Array[String] = []
	for line in _manager.get_mechanic_lines():
		mech_lines.append(_fmt(line))
	if kind == "boss" and _game.rp2d > 0 and _game.state.stage == "二期临床试验":
		mech_lines.append(tr("mechanic.rp2d") % _game.rp2d)
	_mechanic.text = "\n".join(mech_lines.map(func(l: String) -> String: return "[color=#ffcf73]◆[/color] " + l))
	_mechanic.visible = not mech_lines.is_empty()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	_layout()
	_refresh_all(true)
	# 最终 Boss（LM-001）用专属曲：LM-001 主题的战斗版
	GameAudio.music("boss_final" if String(encounter.get("id", "")) == "boss_final" else ("boss" if kind == "boss" else "battle"))
	await _intro_banner(kind)
	if token != _battle_token:
		return
	if _game.battles_fought == 0:
		_show_tip()
	_busy = false
	_run_queue()


## 每局第一场战斗：图示说明卡牌颜色与敌人意图
func _show_tip() -> void:
	if _tip != null:
		_tip.queue_free()
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.08, 0.12, 0.98), UIKit.GOLD, 14))
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.z_index = 100
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(holder)
	holder.add_child(_tip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_tip.add_child(box)
	box.add_child(UIKit.header(tr("tutorial.title"), 20, UIKit.GOLD))
	var body := UIKit.rich(tr("tutorial.body"), 16)
	body.custom_minimum_size = Vector2(430, 0)
	box.add_child(body)
	var ok := UIKit.button(tr("tutorial.ok"), "", "primary", Vector2(140, 40))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(func() -> void:
		dim.queue_free()
		_tip = null)
	box.add_child(ok)
	add_child(dim)


func _intro_banner(kind: String) -> void:
	var title := _title.text
	var sub := tr("encounter.kind." + kind)
	var color: Color = {"boss": UIKit.DANGER, "elite": UIKit.GOLD}.get(kind, Color.WHITE)
	if kind == "boss":
		GameAudio.sfx("boss")
		_shake(14.0, 0.6)
		await _show_banner(sub, title, color, 1.7, true)
	else:
		await _show_banner(sub, title, color, 0.9, false)


# ---------- 事件播放 ----------

func _on_events(events: Array) -> void:
	_queue.append_array(events)
	if not _busy:
		_run_queue()


func _run_queue() -> void:
	if _busy:
		return
	_busy = true
	_update_controls()
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await _play(ev)
	_busy = false
	_refresh_all()
	if _ended:
		_show_end()


func _play(ev: Dictionary) -> void:
	match String(ev.t):
		"card":
			var played: ResearchCard = ev.card
			GameAudio.sfx("zap" if played.is_ai() else ("slash" if played.kind == "attack" else "card_play"))
			await _animate_card_out(played, int(ev.get("target", -1)))
		"deviation":
			GameAudio.sfx("deviation")
			_float_text(tr("battle.fx.deviation"), _player_point() + Vector2(0, -150), Color(0.95, 0.45, 0.95), 26)
			_shake(6.0, 0.25)
			await _wait(0.4)
		"damage":
			await _play_damage(ev)
		"block":
			var p := _side_point(String(ev.side), int(ev.index))
			_float_text(tr("battle.fx.block") % int(ev.amount), p + Vector2(0, -40), Color(0.5, 0.75, 1.0), 22)
			_set_bar(String(ev.side), int(ev.index), -1, int(ev.block))
			GameAudio.sfx("block")
			await _wait(0.16)
		"status":
			var id := String(ev.id)
			var p := _side_point(String(ev.side), int(ev.index))
			if id == "cleanse":
				_float_text(tr("battle.fx.cleanse"), p + Vector2(0, -60), Color(0.6, 1.0, 0.8), 20)
			else:
				var bad := Combatant.DEBUFFS.has(id)
				_float_text("%s %+d" % [tr("status." + id), int(ev.amount)], p + Vector2(0, -60),
					Color(0.95, 0.5, 0.55) if bad else Color(0.5, 0.95, 0.6), 18)
				GameAudio.sfx("debuff" if bad else "buff")
			_refresh_statuses()
			await _wait(0.16)
		"data":
			_float_text(tr("battle.fx.data") % int(ev.amount), _player_point() + Vector2(70, -110), Color(0.55, 0.8, 1.0), 18)
			_refresh_top()
			await _wait(0.08)
		"draw":
			_sync_hand(ev.get("hand", []))
			if int(ev.count) > 0:
				GameAudio.sfx("card_draw")
				await _wait(0.22)
		"energy":
			_energy_label.text = "%d/%d" % [int(ev.energy), _manager.max_energy]
			_energy_orb.queue_redraw()
		"add_card":
			_float_text(tr("battle.fx.add_card") % [int(ev.count), tr("card." + String(ev.id))], Vector2(size.x * 0.5, size.y * 0.5),
				Color(0.95, 0.6, 0.6), 22)
			GameAudio.sfx("deviation")
			await _wait(0.45)
		"enemy_turn":
			await _show_banner(tr("battle.banner.enemy_turn"), "", Color(1.0, 0.55, 0.5), 0.4, false)
		"enemy_move":
			await _play_enemy_move(int(ev.index), ev.move)
		"turn":
			_refresh_intents()
			if int(ev.turn) > 1:
				await _show_banner(tr("battle.banner.your_turn"), tr("battle.turn") % int(ev.turn), Color(0.5, 0.95, 0.7), 0.4, false)
		"death":
			await _play_death(String(ev.side), int(ev.index))
		"mechanic":
			_float_text(_fmt(ev), Vector2(size.x * 0.5, 150), Color(1.0, 0.82, 0.45), 20)
			await _wait(0.55)
		"ai_tier":
			var tier: Dictionary = ev.tier
			var up := bool(ev.up)
			GameAudio.sfx("level_up" if up else "deviation")
			_refresh_top()
			_refresh_faces()
			await _show_banner(tr("battle.ai_tier_up" if up else "battle.ai_tier_down"),
				tr("battle.ai_tier_sub") % [String.num(float(tier.get("multiplier", 1.0)), 2), _manager.deviation_chance()],
				Color(1.0, 0.85, 0.35) if up else Color(0.95, 0.5, 0.45), 0.9, false)
		"end":
			_ended = true
			_victory = bool(ev.victory)


func _play_damage(ev: Dictionary) -> void:
	var side := String(ev.side)
	var index := int(ev.index)
	var amount := int(ev.amount)
	var p := _side_point(side, index)
	if amount > 0:
		_float_text("-%d" % amount, p + Vector2(randf_range(-30, 30), -80), Color(1.0, 0.35, 0.3), 30 + mini(amount, 30))
		_burst(p, Color(1.0, 0.4, 0.35) if side == "player" else _enemy_color(index), 12 + mini(amount, 20))
		if side == "player":
			_player.hit()
			GameAudio.sfx("hurt")
			_screen_flash(0.18 + minf(amount, 30) * 0.01)
		else:
			_enemy_widgets[index].creature.hit()
			GameAudio.sfx("hit_heavy" if amount >= 15 else "hit")
		_shake(3.0 + minf(amount, 30) * 0.4, 0.22)
	elif int(ev.blocked) > 0:
		_float_text(tr("battle.fx.blocked"), p + Vector2(0, -80), Color(0.5, 0.75, 1.0), 22)
		GameAudio.sfx("block")
	_set_bar(side, index, int(ev.hp), int(ev.block))
	await _wait(0.2)


## 用事件里的数值更新血条（hp 为 -1 时保持当前显示）
func _set_bar(side: String, index: int, hp: int, block: int) -> void:
	if side == "player":
		var shown := hp if hp >= 0 else _player_bar.value
		_shown_player_hp = shown
		_player_bar.set_values(shown, _manager.player.max_hp, block)
		_player.ratio = float(shown) / _manager.player.max_hp
		_player.shield = block
	elif index < _enemy_widgets.size():
		var bar := _enemy_widgets[index].bar
		bar.set_values(hp if hp >= 0 else bar.value, _manager.enemies[index].max_hp, block)
		if hp >= 0:
			_enemy_widgets[index].creature.hp_ratio = float(hp) / maxf(1.0, _manager.enemies[index].max_hp)


func _play_enemy_move(index: int, move: Dictionary) -> void:
	if index >= _enemy_widgets.size():
		return
	var ew := _enemy_widgets[index]
	_float_text(tr("move." + String(move.get("id", ""))), ew.position + Vector2(EnemyWidget.SIZE.x * 0.5, 70), Color(1, 0.9, 0.7), 20)
	var origin := ew.position
	var tween := create_tween()
	var enemy: Enemy = _manager.enemies[index]
	if int(move.get("damage", 0)) > 0 and (enemy.is_boss or enemy.is_elite):
		GameAudio.sfx("boss_stomp")
		_shake(10.0 if enemy.is_boss else 6.0, 0.35)
	if int(move.get("damage", 0)) > 0:
		tween.tween_property(ew, "position", origin + Vector2(-110 if enemy.is_boss else -70, 10), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(ew, "position", origin, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(ew, "scale", Vector2(1.08, 1.08), 0.12)
		tween.tween_property(ew, "scale", Vector2.ONE, 0.15)
	await _wait(0.14)


func _play_death(side: String, index: int) -> void:
	if side == "player":
		_shake(16.0, 0.6)
		await _wait(0.5)
		return
	var ew := _enemy_widgets[index]
	GameAudio.sfx("enemy_die")
	_burst(_side_point(side, index), _enemy_color(index), 40)
	var tween := create_tween()
	tween.tween_property(ew.creature, "dying", 1.0, 0.6)
	tween.parallel().tween_property(ew, "modulate:a", 0.0, 0.7).set_delay(0.2)
	await _wait(0.35)


func _animate_card_out(card: ResearchCard, target: int) -> void:
	var face: CardFace = _faces.get(card)
	_faces.erase(card)
	_hand_cards.erase(card)
	_selected = null
	_arrow.queue_redraw()
	if face == null:
		return
	var dest := _side_point("enemy", target) if target >= 0 else Vector2(size.x * 0.5, size.y * 0.42)
	face.z_index = 50
	face.set_state(true)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(face, "position", dest - face.size * 0.5, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(face, "scale", Vector2(0.6, 0.6), 0.2)
	tween.tween_property(face, "rotation", 0.0, 0.2)
	tween.chain().tween_property(face, "modulate:a", 0.0, 0.1)
	tween.chain().tween_callback(face.queue_free)
	_layout_hand()
	await _wait(0.2)
	_burst(dest, CardFace.TYPE_COLOR.get(card.type, Color.WHITE), 10)


# ---------- 手牌 ----------

func _sync_hand(cards = null) -> void:
	if cards != null:
		_hand_cards = (cards as Array).duplicate()
	for card in _faces.keys():
		if not _hand_cards.has(card):
			var face: CardFace = _faces[card]
			_faces.erase(card)
			var tween := create_tween().set_parallel(true)
			tween.tween_property(face, "position", _discard_button.position + Vector2(20, -60), 0.25).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(face, "scale", Vector2(0.2, 0.2), 0.25)
			tween.chain().tween_callback(face.queue_free)
	for card in _hand_cards:
		if _faces.has(card):
			continue
		var face := CardFace.create(card, CARD_SCALE)
		face.position = _draw_button.position + Vector2(0, -40)
		face.scale = Vector2(0.3, 0.3)
		face.mouse_entered.connect(_on_card_hover.bind(card, true))
		face.mouse_exited.connect(_on_card_hover.bind(card, false))
		face.gui_input.connect(_on_card_input.bind(card))
		_hand_root.add_child(face)
		_faces[card] = face
	_refresh_faces()
	_layout_hand()


func _layout_hand(instant := false) -> void:
	var cards: Array = _hand_cards.filter(func(c: ResearchCard) -> bool: return _faces.has(c))
	var n := cards.size()
	if n == 0:
		return
	var card_w := CardFace.BASE.x * CARD_SCALE
	var spacing := minf(card_w * 0.95, 820.0 / n)
	var center_x := size.x * 0.5
	var base_y := size.y - CardFace.BASE.y * CARD_SCALE - 14   # 留出余量，扇形两端的牌底部关键词也不出屏
	var hover_i := cards.find(_hover_card if _selected == null else _selected)
	for i in n:
		var face: CardFace = _faces[cards[i]]
		var offset := i - (n - 1) * 0.5
		var x := center_x + offset * spacing - card_w * 0.5
		var y := base_y + absf(offset) * absf(offset) * 2.0
		var rot := deg_to_rad(offset * 3.0)
		var s := Vector2.ONE
		if hover_i >= 0 and i != hover_i:
			x += 30.0 * signf(i - hover_i) / maxf(1.0, absf(i - hover_i))
		if i == hover_i:
			y = size.y - CardFace.BASE.y * CARD_SCALE * HOVER_SCALE - 12
			rot = 0.0
			s = Vector2(HOVER_SCALE, HOVER_SCALE)
			face.z_index = 20
		else:
			face.z_index = i
		face.pivot_offset = Vector2(face.size.x * 0.5, face.size.y)
		if instant:
			face.position = Vector2(x, y)
			face.rotation = rot
			face.scale = s
		else:
			var tween := face.create_tween().set_parallel(true)
			tween.tween_property(face, "position", Vector2(x, y), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(face, "rotation", rot, 0.16)
			tween.tween_property(face, "scale", s, 0.16)


func _on_card_hover(card: ResearchCard, on: bool) -> void:
	if on:
		_hover_card = card
	elif _hover_card == card:
		_hover_card = null
	if _selected == null:
		_refresh_faces()
		_layout_hand()
	_refresh_energy()


func _on_card_input(event: InputEvent, card: ResearchCard) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		# 有选中目标时右键是取消；否则交给牌面打开大图说明
		if _selected != null:
			_cancel_target()
			accept_event()
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_try_card(card)


func _try_card(card: ResearchCard) -> void:
	if _busy or _ended:
		return
	if _selected == card:
		_cancel_target()
		return
	if not _manager.can_play(card):
		GameAudio.sfx("error")
		var reason := "battle.fx.unplayable" if card.unplayable else "battle.fx.no_energy"
		_float_text(tr(reason), _faces[card].position + Vector2(70, -10), Color(1, 0.5, 0.45), 18)
		var face: CardFace = _faces[card]
		var tween := create_tween()
		for i in 3:
			tween.tween_property(face, "rotation", 0.08, 0.04)
			tween.tween_property(face, "rotation", -0.08, 0.04)
		tween.tween_property(face, "rotation", 0.0, 0.04)
		return
	if card.needs_target() and _manager.alive_enemies().size() > 1:
		_selected = card
		_set_targeting(true)
		_layout_hand()
		return
	_manager.play_card(card, _manager._resolve_target(-1))


func _on_enemy_pressed(index: int) -> void:
	if _selected == null or _busy:
		return
	if not _manager.enemies[index].is_alive():
		return
	var card := _selected
	_set_targeting(false)
	_manager.play_card(card, index)


func _cancel_target() -> void:
	if _selected == null:
		return
	_selected = null
	_set_targeting(false)
	_layout_hand()


func _set_targeting(on: bool) -> void:
	if _player and _player.mood != "sad":
		_player.set_mood("focus" if on else "")   # 选目标时烧瓶专注地看着
	for ew in _enemy_widgets:
		ew.targetable = on and _manager.enemies[ew.index].is_alive()
	_arrow.queue_redraw()


func _draw_arrow() -> void:
	if _selected == null or not _faces.has(_selected):
		return
	var face: CardFace = _faces[_selected]
	var from := face.position + Vector2(face.size.x * 0.5, 0)
	var to := _arrow.get_local_mouse_position()
	var mid := (from + to) * 0.5 + Vector2(0, -160)
	var pts := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	var color := Color(1, 0.85, 0.3) if _hover_enemy >= 0 else Color(1, 1, 1, 0.7)
	for i in range(0, pts.size() - 1, 2):
		_arrow.draw_line(pts[i], pts[i + 1], color, 6.0, true)
	var dir := (pts[-1] - pts[-2]).normalized()
	_arrow.draw_colored_polygon(PackedVector2Array([to + dir * 14, to + dir.orthogonal() * 12 - dir * 6, to - dir.orthogonal() * 12 - dir * 6]), color)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _selected != null:
		_arrow.queue_redraw()
	var max_hp := _manager.player.max_hp if _manager and _manager.player else 100
	var low := float(_shown_player_hp) / max_hp <= 0.3 and not (_ended and not _victory)
	var target_low := (0.35 + 0.25 * sin(_time * 5.0)) if low else 0.0
	_vignette_low.modulate.a = move_toward(_vignette_low.modulate.a, target_low, delta * 3.0)
	var target_boss := (0.55 + 0.12 * sin(_time * 1.6)) if _is_boss and not _ended else 0.0
	_vignette_boss.modulate.a = move_toward(_vignette_boss.modulate.a, target_boss, delta * 1.5)
	if low and not _ended:
		_heart_timer -= delta
		if _heart_timer <= 0.0:
			_heart_timer = 1.1
			GameAudio.sfx("heartbeat")


func _screen_flash(strength: float) -> void:
	_flash_rect.color.a = strength
	create_tween().tween_property(_flash_rect, "color:a", 0.0, 0.35)


## 由 rd_ui 转发：本场胜利后团队升级，在胜利横幅后播放进化
func on_player_leveled(level: int) -> void:
	_pending_level = level


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _ended:
		return
	if _selected != null and (event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)):
		_cancel_target()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_E:
			_on_end_turn()
			get_viewport().set_input_as_handled()
		elif key >= KEY_1 and key <= KEY_9:
			var i := key - KEY_1
			if i < _hand_cards.size():
				_try_card(_hand_cards[i])
				get_viewport().set_input_as_handled()


func _on_end_turn() -> void:
	if _busy or _ended or not _manager.is_battle_active():
		return
	_cancel_target()
	_manager.end_turn()


# ---------- 刷新 ----------

func _refresh_all(instant := false) -> void:
	_player_bar.set_values(_manager.player.hp, _manager.player.max_hp, _manager.player.block, instant)
	for ew in _enemy_widgets:
		var e: Enemy = _manager.enemies[ew.index]
		ew.bar.set_values(e.hp, e.max_hp, e.block, instant)
	_refresh_statuses()
	_refresh_intents()
	_refresh_energy()
	_refresh_top()
	_sync_hand(_manager.hand)
	_update_controls()


func _refresh_statuses() -> void:
	_player_status.set_statuses(_manager.player.statuses)
	for ew in _enemy_widgets:
		ew.statuses.set_statuses(_manager.enemies[ew.index].statuses)


func _refresh_intents() -> void:
	for ew in _enemy_widgets:
		var e: Enemy = _manager.enemies[ew.index]
		ew.show_intent(e, _manager.intent_damage(e))


func _refresh_energy() -> void:
	_energy_label.text = "%d/%d" % [_manager.energy, _manager.max_energy]
	_energy_orb.queue_redraw()
	var left := _manager.safe_attacks_left()
	_rule_label.visible = left >= 0
	var card := _selected if _selected != null else _hover_card
	var lines := backfire_lines(_manager.backfire_preview(card, _hover_enemy)) if card != null and card.kind == "attack" else []
	if not lines.is_empty():
		_rule_label.text = "\n".join(lines)
		_rule_label.add_theme_color_override("font_color", UIKit.DANGER.lightened(0.15) if lines.size() > 1 or not lines[0].begins_with("✓") else UIKit.ACCENT.lightened(0.2))
		return
	_rule_label.text = tr("battle.rule_left") % left if left > 0 else tr("battle.rule_none")
	_rule_label.add_theme_color_override("font_color", UIKit.GOLD if left > 0 else UIKit.DANGER.lightened(0.15))


## 反噬预告文字：「项目脱靶 -5」「破绽目标：项目规则豁免」「Boss 反噬 -4」；什么都不会发生时为「✓ 这张不会反噬」
static func backfire_lines(preview: Dictionary) -> Array:
	var t := TranslationServer
	var lines: Array = []
	if bool(preview.get("exempt", false)):
		lines.append(t.translate("battle.backfire.exempt"))
	if int(preview.get("project", 0)) > 0:
		lines.append(t.translate("battle.backfire.project") % int(preview.project))
	if int(preview.get("boss", 0)) > 0:
		lines.append(t.translate("battle.backfire.boss") % int(preview.boss))
	if lines.is_empty() or (lines.size() == 1 and bool(preview.get("exempt", false))):
		lines.push_front(t.translate("battle.backfire.safe"))
	return lines


## 「再 +6 数据（或 +1 流程）→ AI 威力 ×1」/「AI 已满档」
static func ai_next_text(tier: Dictionary) -> String:
	var t := TranslationServer
	var need := int(tier.get("need_data", -1))
	if need < 0:
		return t.translate("battle.ai_max")
	var key := "battle.ai_next_or_process" if bool(tier.get("process_helps", false)) else "battle.ai_next"
	return t.translate(key) % [need, String.num(float(tier.get("next_multiplier", 1.0)), 2)]


func _refresh_top() -> void:
	_turn_label.text = tr("battle.turn") % maxi(1, _manager.turn)
	var tier := _manager.get_ai_tier()
	_ai_label.text = tr("battle.ai_chip") % [int(tier.get("effective", 0)), tr("tier." + String(tier.get("id", "mid"))),
		float(tier.get("multiplier", 1.0)), _manager.deviation_chance()]
	_ai_next_label.text = ai_next_text(tier)
	_draw_button.text = str(_manager.draw_pile.size())
	_discard_button.text = str(_manager.discard_pile.size())
	_player.ratio = float(_manager.player.hp) / _manager.player.max_hp
	_player.shield = _manager.player.block
	var actions := _manager.get_actions()
	_dose_button.visible = not actions.is_empty()
	if not actions.is_empty():
		_dose_button.text = tr(String(actions[0].label_key)) % actions[0].args
		_dose_button.disabled = not bool(actions[0].enabled)
		_dose_button.tooltip_text = tr("battle.action.dose.tip")


func _refresh_faces() -> void:
	if _manager == null:
		return
	var target := _hover_enemy if _hover_enemy >= 0 else -1
	var mods := {
		"damage": func(v: int) -> int: return _manager.preview_damage(v, target),
		"block": _manager.preview_block,
		"ai_multiplier": _manager.ai_multiplier(),
	}
	var ai := _manager.ai_card_info()
	for card in _faces:
		var face: CardFace = _faces[card]
		face.refresh(mods if card.is_ai() else {"damage": mods.damage, "block": mods.block}, ai)
		face.set_state(card == _hover_card or card == _selected, card == _selected, not _manager.can_play(card) and not _busy)


func _update_controls() -> void:
	var can_act := not _busy and not _ended and _manager != null and _manager.is_battle_active()
	_end_button.disabled = not can_act
	_hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for card in _faces:
		(_faces[card] as CardFace).mouse_filter = Control.MOUSE_FILTER_STOP if can_act else Control.MOUSE_FILTER_IGNORE
	_refresh_faces()


# ---------- 结束 ----------

func _show_end() -> void:
	_set_targeting(false)
	for card in _faces:
		(_faces[card] as CardFace).queue_free()
	_faces.clear()
	_hand_cards.clear()
	if _victory:
		GameAudio.sting("win")
		_player.set_mood("")
		_player.react("happy", 3.0)
		await _show_banner(tr("battle.banner.victory"), tr("battle.banner.victory_sub"), Color(0.5, 1.0, 0.7), 0.0, true)
		if _pending_level > 0:
			await _wait(0.6)
			await _play_level_up(_pending_level)
		_continue.text = tr("battle.claim")
	else:
		GameAudio.sting("lose")
		_player.set_mood("sad")
		await _show_banner(tr("battle.banner.defeat"), tr("battle.banner.defeat_sub"), Color(1.0, 0.45, 0.45), 0.0, true)
		_continue.text = tr("battle.continue")
	_continue.visible = true
	_end_button.disabled = true


# ---------- 特效 ----------

func _play_level_up(level: int) -> void:
	_pending_level = 0
	GameAudio.sfx("level_up")
	_player.level_up()
	_burst(_player_point(), Color(1.0, 0.85, 0.4), 50)
	var tween := create_tween()
	tween.tween_property(_player, "scale", Vector2(1.25, 1.25), 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void: _player.form = level)
	tween.tween_property(_player, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_player.pivot_offset = _player.size * Vector2(0.5, 0.9)
	_player_tag.text = tr("player.tag") % [level, tr("player.level.%d" % level)]
	await _show_banner(tr("player.level_up") % [level, tr("player.level.%d" % level)], PlayerHud.bonus_text(_game.get_player_bonus()),
		Color(1.0, 0.85, 0.4), 1.2, true)


func _show_banner(text: String, sub: String, color: Color, hold: float, big: bool) -> void:
	for child in _banner.get_children():
		child.queue_free()
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.62)
	strip.size = Vector2(size.x, 150 if big else 96)
	strip.position = Vector2(0, size.y * 0.42 - strip.size.y * 0.5)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(strip)
	var label := UIKit.header(text, 48 if big else 32, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(size.x, 60)
	label.position = Vector2(0, strip.position.y + (18 if big else 12))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_child(label)
	if not sub.is_empty():
		var sub_label := UIKit.label(sub, Color(1, 1, 1, 0.85), 20 if big else 16)
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.size = Vector2(size.x, 30)
		sub_label.position = Vector2(0, label.position.y + (66 if big else 44))
		_banner.add_child(sub_label)
	_banner.modulate.a = 0.0
	label.pivot_offset = Vector2(size.x * 0.5, 30)
	label.scale = Vector2(1.4, 1.4)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_banner, "modulate:a", 1.0, 0.15)
	tween.tween_property(label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	if hold <= 0.0:
		return
	await _wait(hold)
	var out := create_tween()
	out.tween_property(_banner, "modulate:a", 0.0, 0.2)
	await out.finished


func _float_text(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	var label := UIKit.header(text, font_size, color)
	label.add_theme_constant_override("outline_size", 7)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(label)
	var w := label.get_combined_minimum_size()
	label.position = pos - w * 0.5
	label.pivot_offset = w * 0.5
	label.scale = Vector2(0.5, 0.5)
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.08)
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 50, 0.9).set_delay(0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)


func _burst(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(4, amount)
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.color = color
	p.texture = _spark_texture()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.lightened(0.4), 1.0))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	_fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


static var _spark: Texture2D


## 圆形柔光粒子贴图（运行时生成一次）
static func _spark_texture() -> Texture2D:
	if _spark == null:
		var tex := GradientTexture2D.new()
		tex.width = 24
		tex.height = 24
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		tex.gradient = g
		_spark = tex
	return _spark


func _shake(strength: float, duration: float) -> void:
	var tween := create_tween()
	var steps := int(duration / 0.04)
	for i in steps:
		var falloff := 1.0 - float(i) / steps
		tween.tween_property(_shake_root, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * falloff, 0.04)
	tween.tween_property(_shake_root, "position", Vector2.ZERO, 0.04)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ---------- 工具 ----------

func _side_point(side: String, index: int) -> Vector2:
	if side == "player" or index < 0 or index >= _enemy_widgets.size():
		return _player_point()
	var ew := _enemy_widgets[index]
	return ew.position + ew.creature.position + ew.creature.size * Vector2(0.5, 0.55)


func _player_point() -> Vector2:
	return _player.position + _player.size * Vector2(0.5, 0.6)


func _enemy_color(index: int) -> Color:
	return _enemy_widgets[index].creature.color if index < _enemy_widgets.size() else Color.WHITE


func _fmt(line: Dictionary) -> String:
	var args: Array = []
	for a in line.get("args", []):
		args.append(tr(a) if a is String else a)
	var text := tr(String(line.get("key", "")))
	return text % args if not args.is_empty() else text


func _sorted(cards: Array) -> Array:
	var copy := cards.duplicate()
	copy.sort_custom(func(a: ResearchCard, b: ResearchCard) -> bool: return a.id < b.id)
	return copy
