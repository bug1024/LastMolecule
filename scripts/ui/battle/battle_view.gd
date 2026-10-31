class_name BattleView
extends Control
## 战斗画面（纯 UI 层），仿杀戮尖塔布局：左侧玩家烧瓶，右侧敌人与头顶意图，底部扇形手牌。
## 逻辑由 BattleManager 即时结算；本界面按事件列表依次播放动画（出牌飞行、受击闪白、
## 伤害数字、震屏、粒子、敌人前冲），播放期间锁定输入。
## 单体攻击在有多个敌人时需要再点击目标；右键或 Esc 取消。快捷键：E 结束回合，1–9 选牌。
## 氛围：生命低于 30% 时屏幕边缘泛红闪烁并有心跳声；Boss 战仅在敌人周围保留威胁刻度，Boss 重击时闪红、踏地震屏。
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
var _end_button: BattleHud.EndTurnButton
var _dose_button: Button
var _title: Label
var _kind_tag: Label
var _turn_badge: BattleHud.TurnBadge
var _ai_chip: BattleHud.AiChip
var _mechanic: RichTextLabel
var _mol: MoleculeView          # 设计了分子的项目：分子就是战场上的主角（代替烧瓶）；属性生效、被敌人针对时对应片段会闪
var _mol_tag: Label
var _strike_style := ""          # 最近一张牌的出招方式（命中特效跟着变）
var _strike_color := Color.WHITE  # 甩出的片段颜色（命中特效用）
var _fx: Control
var _arrow: Control
var _banner: Control
var _continue: Button
var _player_tag: Label
var _vignette_low: TextureRect
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
	_bg.molecule_count = 8
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
	_player_tag = UIKit.header("", 16, Color(0.68, 0.86, 0.82))
	_player_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_tag.add_theme_constant_override("outline_size", 2)
	_player_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_shake_root.add_child(_player_tag)
	_player_status = StatusRow.new()
	_shake_root.add_child(_player_status)
	_dose_button = UIKit.button("", "status_strength", "danger", Vector2(166, 44))
	_dose_button.add_theme_font_size_override("font_size", 13)
	_dose_button.pressed.connect(func() -> void:
		if not _busy:
			_manager.do_action("dose"))
	_shake_root.add_child(_dose_button)

	_title = UIKit.header("", 24)
	_title.position = Vector2(24, 12)
	add_child(_title)
	_kind_tag = UIKit.label("", UIKit.GOLD, 14)
	add_child(_kind_tag)
	_turn_badge = BattleHud.TurnBadge.new()
	add_child(_turn_badge)
	_ai_chip = BattleHud.AiChip.new()
	add_child(_ai_chip)
	_mechanic = UIKit.rich("", 14)
	_mechanic.custom_minimum_size = Vector2(560, 0)
	_mechanic.position = Vector2(24, 50)
	_mechanic.size = Vector2(560, 60)
	add_child(_mechanic)
	_mol = MoleculeView.new()
	_mol.idle_bob = true
	_mol.face = true
	_mol.tooltip_text = " "
	_mol.mouse_filter = Control.MOUSE_FILTER_PASS
	_mol.size = Vector2(460, 280)
	_shake_root.add_child(_mol)
	_mol_tag = UIKit.label("", Color(0.78, 0.68, 1.0), 13, true)
	_mol_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mol_tag.add_theme_constant_override("outline_size", 5)
	_mol_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_shake_root.add_child(_mol_tag)

	_energy_orb = Control.new()
	_energy_orb.size = Vector2(90, 90)
	_energy_orb.mouse_filter = Control.MOUSE_FILTER_PASS
	_energy_orb.tooltip_text = tr("battle.energy_tip")
	_energy_orb.draw.connect(_draw_energy)
	add_child(_energy_orb)
	_energy_label = UIKit.header("", 28)
	_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_energy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_energy_label.size = Vector2(90, 64)
	_energy_label.position.y = 22
	_energy_label.add_theme_constant_override("outline_size", 6)
	_energy_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_energy_orb.add_child(_energy_label)
	_rule_label = UIKit.label("", UIKit.GOLD, 14, true)
	_rule_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_rule_label.size = Vector2(560, 42)
	_rule_label.tooltip_text = tr("battle.rule_tip")
	_rule_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_rule_label)
	_draw_button = UIKit.button("", "ui_draw_pile", "normal", Vector2(110, 44))
	_draw_button.pressed.connect(func() -> void: pile_requested.emit(_sorted(_manager.draw_pile), "battle.pile.draw"))
	add_child(_draw_button)
	_discard_button = UIKit.button("", "ui_discard_pile", "normal", Vector2(110, 44))
	_discard_button.pressed.connect(func() -> void: pile_requested.emit(_manager.discard_pile.duplicate(), "battle.pile.discard"))
	add_child(_discard_button)
	for button in [_draw_button, _discard_button]:
		button.add_theme_stylebox_override("normal", UIKit.panel_style(Color("111d29"), Color("536574"), 6))
		button.add_theme_stylebox_override("hover", UIKit.panel_style(Color("182c35"), UIKit.ACCENT, 6))
	_end_button = BattleHud.EndTurnButton.new()
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
	_vignette_low = _make_vignette(Color(0.95, 0.05, 0.05))
	# 边缘遮罩只压在战场上，不盖住手牌和按钮
	move_child(_vignette_low, _shake_root.get_index() + 1)
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
	_player_tag.position = Vector2(w * 0.1 - 20, 348)
	_player_tag.size = Vector2(240, 24)
	_player_bar.position = Vector2(w * 0.1 + 6, 372)
	_player_bar.size = Vector2(190, 26)
	_player_status.position = Vector2(w * 0.1 + 14, 400)
	_dose_button.position = Vector2(20, h - 174)
	_mol.position = Vector2(w * 0.1 - 130, 96)
	_mol_tag.size = Vector2(_mol.size.x + 40, 44)
	_mol_tag.position = Vector2(_mol.position.x - 20, 440)
	_kind_tag.position = Vector2(24 + _title.get_combined_minimum_size().x + 14, 20)
	_turn_badge.position = Vector2(w * 0.5 - 75, 8)
	_turn_badge.size = _turn_badge.custom_minimum_size
	_ai_chip.position = Vector2(w - _ai_chip.custom_minimum_size.x - 20, 12)
	_energy_orb.position = Vector2(34, h - 284)
	_rule_label.position = Vector2(24, maxf(82.0, _mechanic.position.y + _mechanic.get_content_height() + 8.0))
	_draw_button.position = Vector2(24, h - 70)
	_discard_button.position = Vector2(w - maxf(110.0, _discard_button.get_combined_minimum_size().x) - 24, h - 70)
	_end_button.position = Vector2(w - 168, h - 290)
	_continue.position = Vector2(w * 0.5 - 120, h * 0.5 + 70)
	var n := _enemy_widgets.size()
	var span := w * 0.52
	for i in n:
		var ew := _enemy_widgets[i]
		var x := w * 0.42 + span * (i + 0.5) / n - EnemyWidget.SIZE.x * 0.5
		ew.position = Vector2(x, 96)
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
	var full := _manager != null and _manager.energy > 0
	var accent := UIKit.GOLD if full else UIKit.TEXT_DIM
	_energy_orb.draw_style_box(UIKit.panel_style(Color("111d29"), Color("536574"), 6), Rect2(Vector2.ZERO, _energy_orb.size))
	_energy_orb.draw_line(Vector2(12, 3), Vector2(78, 3), accent, 2.0)
	_energy_orb.draw_string(get_theme_default_font(), Vector2(16, 20), tr("battle.energy_title"), HORIZONTAL_ALIGNMENT_LEFT, 70, 12, accent)


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
	_title.text = tr("encounter." + String(encounter.get("id", kind))) if kind == "boss" else tr(_manager.enemies[0].name_key)
	if kind != "boss" and _manager.enemies.size() > 1:
		_title.text = tr("encounter.group") % [_title.text, _manager.enemies.size()]
	_kind_tag.text = tr("encounter.kind." + kind)
	_kind_tag.add_theme_color_override("font_color", {"boss": UIKit.DANGER, "elite": UIKit.GOLD}.get(kind, UIKit.TEXT_DIM))
	_bg.glow_color = STAGE_TINT.get(_game.state.stage, Color(0.2, 0.5, 0.5))
	var mech_lines: Array[String] = []
	for line in _manager.get_mechanic_lines():
		if String(line.get("key", "")).begins_with("mol.fx."):
			continue   # 分子效果放在分子小图的提示里，这里只留阶段考验等机制
		mech_lines.append(_fmt(line))
	if kind == "boss" and _game.rp2d > 0 and _game.state.stage == "二期临床试验":
		mech_lines.append(tr("mechanic.rp2d") % _game.rp2d)
	_mechanic.text = "\n".join(mech_lines.map(func(l: String) -> String: return "[color=#ffcf73]◆[/color] " + l))
	_mechanic.visible = not mech_lines.is_empty()
	var molecule: Molecule = _game.molecule
	_mol.visible = molecule != null
	_mol_tag.visible = false   # 分子效果放在悬停提示里，战场上不再堆文字
	_player.visible = molecule == null   # 有分子时，站在战场上的是分子本身
	if molecule != null:
		var lv: int = _game.get_player_level()
		_player_tag.text = tr("player.tag_mol") % [lv, tr("mol.level.%d" % lv)]
		_mol.form = lv
		_mol.set_mood("")
		_mol.ratio = float(_manager.player.hp) / _manager.player.max_hp
		_mol.set_molecule(molecule)
		var props := molecule.properties()
		_mol_tag.text = " ".join(Molecule.PROPS.map(func(p: String) -> String: return "%s%d" % [tr("prop." + p).left(1), int(props[p])])) \
			+ "\n" + _mol_summary(molecule.effects(_game.state.stage))
		var tips: Array = molecule.effects(_game.state.stage).lines.map(func(l: Dictionary) -> String: return _fmt(l))
		_mol.tooltip_text = tr("mol.battle_tip") + ("\n" + "\n".join(tips) if not tips.is_empty() else "")
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
## 分子效果的一行速览：「力量+1 · 破绽+1 · 首回合抽牌+1」
func _mol_summary(fx: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["strength", "start_block", "vulnerable_bonus", "poison_bonus", "enemy_poison", "first_draw", "first_energy", "clinical_cost"]:
		var v := int(fx.get(key, 0))
		if v != 0:
			parts.append(tr("mol.short." + key) % v)
	if int(fx.get("weak", 0)) > 0:
		parts.append(tr("mol.short.weak"))
	if bool(fx.get("offtarget", false)):
		parts.append(tr("mol.short.offtarget"))
	if parts.is_empty():
		return tr("mol.short.none")
	var rows: Array[String] = []
	for i in range(0, parts.size(), 2):
		rows.append(" · ".join(parts.slice(i, i + 2)))
	return "\n".join(rows)


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
			if String(ev.side) == "player" and _mol.visible:
				_shockwave(p, Color(0.5, 0.75, 1.0), 120.0, true)   # 护盾：一圈蓝光向内收拢
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
			_strike_style = ""   # 敌人回合里的伤害（中毒等）不沿用上一张牌的命中特效
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
		"exploit":
			# 敌人专攻分子结构弱点：被针对的片段闪红
			_mol.flash_sites(ev.sites)
			GameAudio.sfx("deviation")
			_float_text(tr("battle.fx.exploit." + String(ev.tag)), _mol.position + Vector2(_mol.size.x * 0.5, -6), Color(1.0, 0.45, 0.4), 20)
			await _wait(0.35)
		"mol":
			_mol.flash(String(ev.prop))
			if not bool(ev.get("start", false)):   # 开场时所有生效的片段一起亮，不逐个飘字
				_float_text(tr("prop." + String(ev.prop)), _mol.position + Vector2(_mol.size.x * 0.5, 10), Color(0.8, 0.7, 1.0), 16)
				await _wait(0.15)
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
			_mol.hit(amount / 10.0)   # 片段被震开再弹回，表情吃痛
			_shockwave(p, Color(1.0, 0.35, 0.3), 70.0 + minf(amount, 30) * 3.0)
			GameAudio.sfx("hurt")
			_screen_flash(0.18 + minf(amount, 30) * 0.01)
		else:
			_enemy_widgets[index].creature.hit()
			_impact(index, p, amount)
			GameAudio.sfx("hit_heavy" if amount >= 15 else "hit")
		_shake(3.0 + minf(amount, 30) * 0.4, 0.22)
	elif int(ev.blocked) > 0:
		_float_text(tr("battle.fx.blocked"), p + Vector2(0, -80), Color(0.5, 0.75, 1.0), 22)
		GameAudio.sfx("block")
	_set_bar(side, index, int(ev.hp), int(ev.block))
	await _wait(0.2 + (0.07 if amount >= 12 else 0.0))   # 重击多停一拍（顿帧感）


## 用事件里的数值更新血条（hp 为 -1 时保持当前显示）
func _set_bar(side: String, index: int, hp: int, block: int) -> void:
	if side == "player":
		var shown := hp if hp >= 0 else _player_bar.value
		_shown_player_hp = shown
		_player_bar.set_values(shown, _manager.player.max_hp, block)
		_player.ratio = float(shown) / _manager.player.max_hp
		_mol.ratio = _player.ratio
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


## 分子出招：卡牌化作光点飞进分子，再按卡牌的性质用不同方式打出去（见 _strike_style）；打自己的牌在分子周围亮一圈
func _molecule_cast(card: ResearchCard, face: CardFace, target: int, color: Color) -> void:
	var home := _player_point()
	face.z_index = 50
	face.set_state(true)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(face, "position", home - face.size * 0.5 + Vector2(30, -20), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(face, "scale", Vector2(0.25, 0.25), 0.16)
	tween.tween_property(face, "rotation", 0.0, 0.16)
	tween.chain().tween_property(face, "modulate:a", 0.0, 0.06)
	tween.chain().tween_callback(face.queue_free)
	_layout_hand()
	await _wait(0.16)
	_strike_style = _strike_style_for(card)
	if _strike_style == "self":
		_shockwave(home, color, 110.0, true)
		_burst(home, color, 12)
		await _wait(0.1)
		return
	_mol.attack()
	var targets: Array = [target] if target >= 0 else []
	if targets.is_empty():
		for i in _manager.enemies.size():
			if _manager.enemies[i].is_alive():
				targets.append(i)
	if targets.is_empty():
		return
	var muzzle := home + Vector2(60, -10)
	var to := _side_point("enemy", int(targets[0]))
	match _strike_style:
		"charge":
			await _strike_charge(to)
		"beam":
			_mol_recoil(10.0)
			for i in targets:
				_beam(muzzle, _side_point("enemy", int(i)), color, false)
			await _wait(0.12)
		"lock":
			await _crosshair(to, color)
			_mol_recoil(14.0)
			_beam(muzzle, to, Color(1.0, 0.95, 0.75), true)
			await _wait(0.08)
		"dose":
			_mol_recoil(8.0)
			for i in targets:
				_lob(muzzle, _side_point("enemy", int(i)), color, "drop")
			await _wait(0.3)
		"flask":
			_mol_recoil(8.0)
			for i in targets:
				_lob(muzzle, _side_point("enemy", int(i)), color, "flask")
			await _wait(0.3)
		"volley":
			var hits := 1
			for e in card.effects:
				hits = maxi(hits, int(e.get("times", 1)))
			for h in hits:
				_mol_recoil(6.0)
				_projectile(muzzle + Vector2(0, randf_range(-14, 14)), to + Vector2(randf_range(-18, 18), randf_range(-18, 18)), color, 0.6)
				await _wait(0.07)
			await _wait(0.1)
		"fragment":
			_mol_lean()
			for i in targets:
				_fragment_throw(_side_point("enemy", int(i)))
			await _wait(0.22)
		"wave":
			_mol_recoil(18.0)
			_sweep(home, color)
			await _wait(0.22)
		_:
			_mol_recoil(12.0)
			for i in targets:
				_projectile(muzzle, _side_point("enemy", int(i)), color)
			await _wait(0.2)


## 卡牌的出招方式：打全体＝扫荡波，多段＝连射，上破绽＝锁定精准光束，AI＝数据光束，
## 临床＝抛出药剂，实验＝掷出试剂瓶，分子设计牌＝甩出一个片段（重击才亲自冲撞）；只作用自己的牌为 self
func _strike_style_for(card: ResearchCard) -> String:
	if card.target == "self":
		return "self"
	if card.target == "all":
		return "wave"
	var hits := 1
	var vulnerable := false
	for e in card.effects:
		hits = maxi(hits, int(e.get("times", 1)))
		if String(e.get("op", "")) == "status" and String(e.get("id", "")) == "vulnerable":
			vulnerable = true
	if hits > 1:
		return "volley"
	if vulnerable:
		return "lock"
	match card.type:
		"ai":
			return "beam"
		"clinical":
			return "dose"
		"experiment":
			return "flask"
		"molecular":
			if card.kind != "attack":
				return "bolt"
			# 只有重击（基础伤害 ≥12）才让分子亲自冲撞，其余的分子设计攻击是甩出一个片段，分子基本不离开原位
			var base := 0
			for e in card.effects:
				if String(e.get("op", "")) == "damage":
					base = maxi(base, int(e.get("value", 0)))
			return "charge" if base >= 12 else "fragment"
	return "bolt"


## 分子后坐一下（射击类出招）
func _mol_recoil(amount: float) -> void:
	var origin := _mol.position
	var t := create_tween()
	t.tween_property(_mol, "position", origin + Vector2(-amount, 0), 0.05)
	t.tween_property(_mol, "position", origin, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 前倾一下（甩片段）：位移很小，视觉重心不跟着跑
func _mol_lean() -> void:
	var origin := _mol.position
	var t := create_tween()
	t.tween_property(_mol, "position", origin + Vector2(22, -4), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_mol, "position", origin, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


## 甩出片段：从分子上随机一个片段的位置飞出一颗同色的原子，旋转着砸向目标
func _fragment_throw(to: Vector2) -> void:
	var molecule: Molecule = _game.molecule
	var from := _player_point()
	var col := Color(0.8, 0.75, 1.0)
	if molecule != null and not molecule.sites.is_empty():
		var site_ids: Array = molecule.sites.keys()
		var site_id := String(site_ids[randi() % site_ids.size()])
		for site in Molecule.config().get("sites", []):
			if String(site.id) == site_id:
				from = _mol.position + _mol.site_center(site)
		col = Color.from_string(String(Molecule.fragment(String(molecule.sites[site_id])).get("color", "#c8b8ff")), col)
		_mol.flash_sites([site_id], col.lightened(0.3))
	_strike_color = col
	var atom := Control.new()
	atom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(atom)
	var trail: Array = []
	var state := [0.0]
	atom.draw.connect(func() -> void:
		for i in trail.size():
			var k := float(i + 1) / trail.size()
			atom.draw_circle(trail[i], 4.0 + 8.0 * k, Color(col, 0.08 + 0.25 * k))
		if trail.is_empty():
			return
		var p: Vector2 = trail.back()
		atom.draw_circle(p, 17.0, Color(col, 0.3))
		atom.draw_circle(p, 12.0, col.darkened(0.2))
		atom.draw_arc(p, 12.0, 0, TAU, 24, col.lightened(0.4), 2.5, true)
		var spin: float = state[0] * TAU * 2.0
		atom.draw_arc(p, 17.0, spin, spin + 1.2, 10, Color(1, 1, 1, 0.8), 2.0, true))
	var arc := Vector2(0, -minf(70.0, from.distance_to(to) * 0.15))
	var tween := atom.create_tween()
	tween.tween_method(func(t: float) -> void:
		state[0] = t
		trail.append(from.lerp(to, t) + arc * 4.0 * t * (1.0 - t))
		if trail.size() > 8:
			trail.pop_front()
		atom.queue_redraw(), 0.0, 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(atom.queue_free)


## 冲撞（只用于重击）：分子冲到敌人面前，撞上后再退回原位
func _strike_charge(to: Vector2) -> void:
	var origin := _mol.position
	var hit_pos := origin + Vector2(to.x - _player_point().x - 150.0, (to.y - _player_point().y) * 0.4)
	var dash := create_tween()
	dash.tween_property(_mol, "position", origin + Vector2(-24, 0), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	dash.tween_property(_mol, "position", hit_pos, 0.13).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	dash.tween_interval(0.16)
	dash.tween_property(_mol, "position", origin, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _wait(0.21)


## 光束：AI 是带锯齿和像素块的青色数据流；精准光束（precise）是一道又细又亮的直线
func _beam(from: Vector2, to: Vector2, color: Color, precise: bool) -> void:
	var ray := Control.new()
	ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(ray)
	var col := Color(1.0, 0.95, 0.75) if precise else Color(0.45, 0.95, 1.0)
	var seed_pts: Array = []
	var n := 14
	for i in n + 1:
		seed_pts.append(randf_range(-1.0, 1.0))
	var state := [0.0]
	ray.draw.connect(func() -> void:
		var t: float = state[0]
		var a := 1.0 - t
		var dir := (to - from).normalized()
		var normal := Vector2(-dir.y, dir.x)
		if precise:
			ray.draw_line(from, to, Color(col, 0.35 * a), 14.0 * a + 2.0, true)
			ray.draw_line(from, to, Color(1, 1, 1, a), 3.0, true)
			return
		var pts := PackedVector2Array()
		for i in n + 1:
			var p := from.lerp(to, float(i) / n)
			if i > 0 and i < n:
				p += normal * float(seed_pts[i]) * 14.0 * (0.4 + t)
			pts.append(p)
		ray.draw_polyline(pts, Color(col, 0.3 * a), 16.0 * a + 2.0, true)
		ray.draw_polyline(pts, Color(col.lightened(0.5), a), 3.0, true)
		for i in range(1, n, 2):   # 数据像素
			var q := from.lerp(to, float(i) / n) + normal * float(seed_pts[i]) * 26.0
			ray.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), Color(col, 0.8 * a)))
	var tween := ray.create_tween()
	tween.tween_method(func(t: float) -> void:
		state[0] = t
		ray.queue_redraw(), 0.0, 1.0, 0.32)
	tween.tween_callback(ray.queue_free)


## 锁定：准星从大到小收拢到目标上
func _crosshair(at: Vector2, color: Color) -> void:
	var mark := Control.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.position = at
	_fx.add_child(mark)
	var state := [0.0]
	mark.draw.connect(func() -> void:
		var t: float = state[0]
		var r := lerpf(90.0, 34.0, minf(1.0, t * 1.4))
		var col := Color(1.0, 0.85, 0.4, minf(1.0, t * 3.0) * (1.0 - maxf(0.0, t - 0.8) * 5.0))
		mark.draw_arc(Vector2.ZERO, r, 0, TAU, 40, col, 2.5, true)
		for k in 4:
			var d := Vector2.from_angle(k * PI / 2 + t * 1.5)
			mark.draw_line(d * (r - 12), d * (r + 14), col, 3.0, true)
		mark.draw_circle(Vector2.ZERO, 3.0, col))
	var tween := mark.create_tween()
	tween.tween_method(func(t: float) -> void:
		state[0] = t
		mark.queue_redraw(), 0.0, 1.0, 0.3)
	tween.tween_callback(mark.queue_free)
	await _wait(0.22)


## 抛物线投掷：drop＝一滴药剂（拖着小气泡），flask＝旋转的试剂瓶
func _lob(from: Vector2, to: Vector2, color: Color, shape: String) -> void:
	var item := Control.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(item)
	var state := [0.0]
	var arc := Vector2(0, -minf(130.0, from.distance_to(to) * 0.3))
	item.draw.connect(func() -> void:
		var t: float = state[0]
		var p := from.lerp(to, t) + arc * 4.0 * t * (1.0 - t)
		if shape == "drop":
			for k in 4:   # 拖尾的小气泡
				var tk := maxf(0.0, t - 0.06 * (k + 1))
				var q := from.lerp(to, tk) + arc * 4.0 * tk * (1.0 - tk)
				item.draw_circle(q, 4.0 - k * 0.7, Color(color.lightened(0.4), 0.6 - k * 0.12))
			var pts := PackedVector2Array()
			for k in 16:
				var a := k * TAU / 16.0
				var r := 11.0 * (1.0 + 0.6 * maxf(0.0, -sin(a)))
				pts.append(p + Vector2(cos(a) * 11.0, sin(a) * r * 0.9 - (6.0 if sin(a) < 0 else 0.0)))
			item.draw_colored_polygon(pts, color.lightened(0.15))
			item.draw_circle(p + Vector2(-4, -2), 3.0, Color(1, 1, 1, 0.8))
		else:
			item.draw_set_transform(p, t * TAU * 1.5, Vector2(1.7, 1.7))
			item.draw_rect(Rect2(-4, -18, 8, 10), Color(0.85, 0.92, 1.0, 0.9))
			item.draw_rect(Rect2(-6, -20, 12, 3), Color(0.85, 0.92, 1.0, 0.9))
			item.draw_circle(Vector2(0, 2), 11.0, Color(0.85, 0.92, 1.0, 0.9))
			item.draw_circle(Vector2(0, 4), 8.0, color.lightened(0.1))
			item.draw_circle(Vector2(-4, 0), 2.5, Color(1, 1, 1, 0.8))
			item.draw_set_transform(Vector2.ZERO))
	var tween := item.create_tween()
	tween.tween_method(func(t: float) -> void:
		state[0] = t
		item.queue_redraw(), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(item.queue_free)


## 扫荡波：一道弧形冲击波从分子横扫整个战场
func _sweep(from: Vector2, color: Color) -> void:
	var wave := Control.new()
	wave.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave.position = from
	_fx.add_child(wave)
	var state := [0.0]
	wave.draw.connect(func() -> void:
		var t: float = state[0]
		var r := lerpf(40.0, size.x, t)
		for k in 3:
			wave.draw_arc(Vector2.ZERO, r - k * 18.0, -0.7, 0.7, 40, Color(color.lightened(0.3), (1.0 - t) * (0.9 - k * 0.25)), 10.0 - k * 3.0, true))
	var tween := wave.create_tween()
	tween.tween_method(func(t: float) -> void:
		state[0] = t
		wave.queue_redraw(), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(wave.queue_free)


## 能量弹：带拖尾的光点沿一道弧线飞向目标（scale 越小越快越细，用于连射）
func _projectile(from: Vector2, to: Vector2, color: Color, scale_k := 1.0) -> void:
	var bolt := Control.new()
	bolt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(bolt)
	var trail: Array = []
	bolt.draw.connect(func() -> void:
		for i in trail.size():
			var t := float(i + 1) / trail.size()
			bolt.draw_circle(trail[i], (3.0 + 9.0 * t) * scale_k, Color(color.lightened(0.3), 0.12 + 0.35 * t))
		if not trail.is_empty():
			bolt.draw_circle(trail.back(), 16.0 * scale_k, Color(color, 0.35))
			bolt.draw_circle(trail.back(), 8.0 * scale_k, Color(1, 1, 1, 0.95)))
	var arc := Vector2(0, -minf(80.0, from.distance_to(to) * 0.18) * scale_k)
	var tween := bolt.create_tween()
	tween.tween_method(func(t: float) -> void:
		trail.append(from.lerp(to, t) + arc * 4.0 * t * (1.0 - t))
		if trail.size() > 9:
			trail.pop_front()
		bolt.queue_redraw(), 0.0, 1.0, 0.2 * (0.6 + 0.4 * scale_k)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(bolt.queue_free)


## 击中敌人：按出招方式换命中特效，伤害越高越猛；敌人都会被击退
func _impact(index: int, p: Vector2, amount: int) -> void:
	var color := _enemy_color(index).lightened(0.3)
	var heavy := minf(amount, 30)
	var knock := 10.0 + heavy * 0.8
	match _strike_style:
		"charge":   # 冲撞：大冲击波 + 震屏，击退更远
			_shockwave(p, Color(0.85, 0.8, 1.0), 90.0 + heavy * 5.0)
			_shockwave(p, Color(1, 1, 1), 50.0 + heavy * 2.0)
			_burst(p, Color(0.8, 0.75, 1.0), 18 + int(heavy))
			_shake(6.0 + heavy * 0.3, 0.2)
			knock *= 1.8
		"beam":     # 数据光束：青色电火花
			_burst(p, Color(0.45, 0.95, 1.0), 16 + int(heavy))
			_shockwave(p, Color(0.45, 0.95, 1.0), 50.0 + heavy * 2.0)
		"lock":     # 精准命中：金色准星一闪 + 斩痕
			_shockwave(p, Color(1.0, 0.85, 0.4), 70.0 + heavy * 3.0, true)
			_slash(p, Color(1.0, 0.9, 0.6), 90.0 + heavy * 3.0)
			_burst(p, Color(1.0, 0.85, 0.4), 12)
		"dose":     # 药剂：溅开一圈药液和气泡
			_splash(p, Color(0.55, 0.95, 0.5), 22 + int(heavy))
			_shockwave(p, Color(0.55, 0.95, 0.5), 60.0 + heavy * 2.0)
		"flask":    # 试剂瓶：玻璃碎片 + 彩色试剂
			_splash(p, Color(0.95, 0.75, 0.35), 16 + int(heavy))
			_burst(p, Color(0.9, 0.97, 1.0), 20)
			_slash(p, Color(0.9, 0.97, 1.0), 50.0)
		"fragment": # 片段砸中：片段颜色的冲击和碎屑
			_shockwave(p, _strike_color.lightened(0.3), 60.0 + heavy * 3.0)
			_burst(p, _strike_color, 12 + int(heavy))
		"volley":   # 连射：每段一个小冲击
			_shockwave(p, Color(1.0, 0.95, 0.8), 40.0 + heavy * 1.5)
			_burst(p, color, 6)
			knock *= 0.5
		_:
			_shockwave(p, Color(1.0, 0.95, 0.8), 60.0 + heavy * 4.0)
			_slash(p, Color(1.0, 0.97, 0.9), 70.0 + heavy * 3.0)
			_burst(p, color, 10 + int(heavy))
	var ew := _enemy_widgets[index]
	var origin := ew.position
	var kick := create_tween()
	kick.tween_property(ew, "position", origin + Vector2(knock, -4), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	kick.tween_property(ew, "position", origin, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 溅开的液滴：向四周飞、往下落的小圆点
func _splash(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 380.0
	p.gravity = Vector2(0, 900)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.texture = _spark_texture()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.lightened(0.3), 1.0))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	_fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## 扩散（或 inward 时收拢）的光环
func _shockwave(pos: Vector2, color: Color, radius: float, inward := false) -> void:
	var ring := Control.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = pos
	_fx.add_child(ring)
	var state := [0.0]
	ring.draw.connect(func() -> void:
		var t: float = state[0]
		var r := lerpf(radius, radius * 0.35, t) if inward else lerpf(12.0, radius, t)
		ring.draw_arc(Vector2.ZERO, r, 0, TAU, 56, Color(color, 1.0 - t), 2.0 + 8.0 * (1.0 - t), true)
		ring.draw_circle(Vector2.ZERO, r, Color(color, 0.12 * (1.0 - t))))
	var tween := ring.create_tween()
	tween.tween_method(func(t: float) -> void:
		state[0] = t
		ring.queue_redraw(), 0.0, 1.0, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ring.queue_free)


## 交叉斩痕：两道亮线一闪而过
func _slash(pos: Vector2, color: Color, length: float) -> void:
	var mark := Control.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.position = pos
	_fx.add_child(mark)
	var angle := randf_range(-0.4, 0.4)
	var state := [0.0]
	mark.draw.connect(func() -> void:
		var t: float = state[0]
		for a in [angle + 0.7, angle - 0.7]:
			var d := Vector2.from_angle(a) * length * 0.5 * minf(1.0, t * 3.0)
			mark.draw_line(-d, d, Color(color, 1.0 - t), 7.0 * (1.0 - t) + 1.0, true)
			mark.draw_line(-d * 0.9, d * 0.9, Color(1, 1, 1, 1.0 - t), 2.0, true))
	var tween := mark.create_tween()
	tween.tween_method(func(t: float) -> void:
		state[0] = t
		mark.queue_redraw(), 0.0, 1.0, 0.3)
	tween.tween_callback(mark.queue_free)


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
	var color: Color = CardFace.TYPE_COLOR.get(card.type, Color.WHITE)
	if _mol.visible:
		await _molecule_cast(card, face, target, color)
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
	var edge := (n - 1) * 0.5
	var fan_margin := maxf(40.0, edge * edge * 2.0 + absf(sin(deg_to_rad(edge * 3.0))) * card_w * 0.5 + 16.0)
	var base_y := size.y - CardFace.BASE.y * CARD_SCALE - fan_margin
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
			y = size.y - CardFace.BASE.y * CARD_SCALE * HOVER_SCALE - 40
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
		_mol.set_mood("focus" if on else "")
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
	# 没牌可打（能量用完或手里都打不出）时，结束回合按钮呼吸发光提示
	_end_button.prompt = _should_prompt_end()
	if _selected != null:
		_arrow.queue_redraw()
	var max_hp := _manager.player.max_hp if _manager and _manager.player else 100
	var low := float(_shown_player_hp) / max_hp <= 0.3 and not (_ended and not _victory)
	var target_low := (0.35 + 0.25 * sin(_time * 5.0)) if low else 0.0
	_vignette_low.modulate.a = move_toward(_vignette_low.modulate.a, target_low, delta * 3.0)
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
			if not _end_button.disabled:
				GameAudio.sfx("end_turn")   # 键盘结束回合也有和按钮一样的音效
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


func _should_prompt_end() -> bool:
	if _manager == null or _busy or _ended or not _manager.is_battle_active() or _end_button.disabled:
		return false
	for card in _manager.hand:
		if _manager.can_play(card):
			return false
	return true


func _refresh_top() -> void:
	_turn_badge.set_turn(maxi(1, _manager.turn))
	_ai_chip.refresh(_manager.get_ai_tier(), _manager.deviation_chance())
	_draw_button.text = tr("battle.draw_short") % _manager.draw_pile.size()
	_discard_button.text = tr("battle.discard_short") % _manager.discard_pile.size()
	_discard_button.position.x = size.x - maxf(110.0, _discard_button.get_combined_minimum_size().x) - 24
	_player.ratio = float(_manager.player.hp) / _manager.player.max_hp
	_mol.ratio = _player.ratio
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
		_mol.cheer()
		await _show_banner(tr("battle.banner.victory"), tr("battle.banner.victory_sub"), Color(0.5, 1.0, 0.7), 0.0, true)
		if _pending_level > 0:
			await _wait(0.6)
			await _play_level_up(_pending_level)
		_continue.text = tr("battle.claim")
	else:
		GameAudio.sting("lose")
		_player.set_mood("sad")
		_mol.set_mood("sad")
		await _show_banner(tr("battle.banner.defeat"), tr("battle.banner.defeat_sub"), Color(1.0, 0.45, 0.45), 0.0, true)
		_continue.text = tr("battle.continue")
	_continue.visible = true
	_end_button.disabled = true


# ---------- 特效 ----------

func _play_level_up(level: int) -> void:
	_pending_level = 0
	GameAudio.sfx("level_up")
	_player.level_up()
	_mol.level_up()
	_burst(_player_point(), Color(1.0, 0.85, 0.4), 50)
	if _mol.visible:   # 分子进化：放大一下，长出新形态（光晕 → 电子轨道 → 金色核心 → 星光）
		_mol.pivot_offset = _mol.size * 0.5
		var grow := create_tween()
		grow.tween_property(_mol, "scale", Vector2(1.2, 1.2), 0.25).set_trans(Tween.TRANS_BACK)
		grow.tween_callback(func() -> void: _mol.form = level)
		grow.tween_property(_mol, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tween := create_tween()
	tween.tween_property(_player, "scale", Vector2(1.25, 1.25), 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void: _player.form = level)
	tween.tween_property(_player, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_player.pivot_offset = _player.size * Vector2(0.5, 0.9)
	_player_tag.text = tr("player.tag_mol") % [level, tr("mol.level.%d" % level)] if _mol.visible \
		else tr("player.tag") % [level, tr("player.level.%d" % level)]
	var up_title := tr("player.level_up_mol") % [level, tr("mol.level.%d" % level)] if _mol.visible \
		else tr("player.level_up") % [level, tr("player.level.%d" % level)]
	await _show_banner(up_title, PlayerHud.bonus_text(_game.get_player_bonus()),
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
	if _mol.visible:
		return _mol.position + _mol.size * Vector2(0.5, 0.48)
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
