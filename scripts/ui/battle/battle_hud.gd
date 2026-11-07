class_name BattleHud
extends RefCounted
## 战斗界面顶部与右下角的 HUD 小部件：
##   TurnBadge  回合徽章——六边形里的大号回合数 + 「回合」字样，换回合时弹一下；
##   AiChip     AI 状态卡——档位名 + 威力倍率 + 失误率，下方一条到下一档的进度条；
##   EndTurnButton  仪器面板式结束回合按钮——沙漏图标 + 「E」键帽，悬停放大、按下回弹带专属音效，没牌可打时外圈光环提示。


class TurnBadge extends Control:
	var turn := 1
	var _pop := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(150, 54)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_turn(value: int) -> void:
		if value != turn:
			_pop = 1.0
		turn = value
		queue_redraw()

	func _process(delta: float) -> void:
		if _pop > 0.0:
			_pop = maxf(0.0, _pop - delta * 2.5)
			queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var label := tr("battle.turn_word") + " " + str(turn)
		draw_string(font,Vector2(8,25),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,UIKit.TEXT_DIM)


class AiChip extends PanelContainer:
	var _tier_label: Label
	var _power: Label
	var _miss: Label
	var _bar: ProgressBar
	var _next: Label
	var _icon: TextureRect

	func _init() -> void:
		custom_minimum_size = Vector2(190, 0)
		mouse_filter = Control.MOUSE_FILTER_PASS
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		_icon = UIKit.icon_rect("type_ai", 16, UIKit.ACCENT_BLUE)
		row.add_child(_icon)
		_tier_label = UIKit.header("", 14)
		row.add_child(_tier_label)
		_power = UIKit.header("", 14, UIKit.TEXT_DIM)
		row.add_child(_power)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		_miss = UIKit.label("", UIKit.TEXT_DIM, 13)
		row.add_child(_miss)
		_bar = ProgressBar.new()
		_bar.custom_minimum_size = Vector2(0, 3)
		_bar.show_percentage = false
		col.add_child(_bar)
		_next = UIKit.label("", Color(0.7, 0.82, 0.95), 12)
		col.add_child(_next)
		for node in find_children("*", "Control", true, false):
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	## tier 为 BattleManager.get_ai_tier()（含 effective / max / need_data …），miss 为当前失误率
	func refresh(tier: Dictionary, miss: int) -> void:
		var id := String(tier.get("id", "mid"))
		# 档位只改文字颜色（低档灰蓝、中档蓝、高档金）；进度条统一用代表「数据」的蓝色，不用红色，以免和敌人混淆
		var color: Color = {"low": Color(0.62, 0.7, 0.8), "mid": UIKit.ACCENT_BLUE, "high": UIKit.GOLD}.get(id, UIKit.ACCENT_BLUE)
		var bar_color: Color = UIKit.ACCENT_BLUE
		var sb := BattleHud.quiet_style(Color(0,0,0,0),Color(0,0,0,0))
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		add_theme_stylebox_override("panel",sb)

		_icon.self_modulate = UIKit.ACCENT_BLUE
		_tier_label.text = "AI"
		_tier_label.add_theme_color_override("font_color", color.lightened(0.2))
		_power.text = "×" + String.num(float(tier.get("multiplier", 1.0)), 2)
		_miss.text = tr("battle.ai_miss") % miss
		var effective := int(tier.get("effective", 0))
		var need := int(tier.get("need_data", -1))
		_bar.max_value = 1.0
		_bar.step = 0.001
		_bar.value = 1.0 if need < 0 else clampf(float(effective) / maxf(1.0, float(tier.get("max", effective + need))), 0.0, 1.0)
		_bar.add_theme_stylebox_override("fill", UIKit.meter_style(bar_color, bar_color, 3))
		_bar.add_theme_stylebox_override("background", UIKit.meter_style(Color(0.12, 0.15, 0.2), Color(0.12, 0.15, 0.2), 3))
		_next.text = BattleView.ai_next_text(tier)
		_next.visible = false
		_miss.visible = false
		tooltip_text = tr("battle.ai_chip") % [effective, tr("tier." + id), float(tier.get("multiplier", 1.0)), miss] + "\n" + _next.text


## 结束回合：深色仪器面板、金属边框、绿色提示线，底部保留「E」键帽；
## 悬停变亮放大、按下回弹并播放专属音效 end_turn；没牌可打时（prompt）顶部提示线呼吸发亮。
class EndTurnButton extends Button:
	const D := 112.0
	var prompt := false
	var _time := 0.0
	var _icon_tex: Texture2D

	func _init() -> void:
		text = ""
		custom_minimum_size = Vector2(166, 60)
		size = custom_minimum_size
		pivot_offset = size * 0.5
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = TranslationServer.translate("ui.end_turn") + "（E）"
		set_meta("sfx", "end_turn")
		_icon_tex = UIKit.icon("stat_year")
		var empty := StyleBoxEmpty.new()
		for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state_name, empty)
		mouse_entered.connect(func() -> void:
			if not disabled:
				create_tween().tween_property(self, "scale", Vector2(1.06, 1.06), 0.1))
		mouse_exited.connect(func() -> void: create_tween().tween_property(self, "scale", Vector2.ONE, 0.12))
		button_down.connect(func() -> void: create_tween().tween_property(self, "scale", Vector2(0.92, 0.92), 0.06))
		button_up.connect(func() -> void:
			create_tween().tween_property(self, "scale", Vector2(1.06, 1.06) if is_hovered() else Vector2.ONE, 0.18) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var on := not disabled
		BattleHud.quiet_style(UIKit.ACCENT.darkened(0.65) if on else UIKit.INK,Color(UIKit.GOLD,0.65 if is_hovered() and on else 0.3)).draw(get_canvas_item(),Rect2(Vector2.ZERO,size))
		var ink := UIKit.PAPER if on else UIKit.TEXT_DIM
		var font := get_theme_font("font", &"HeaderLabel")
		var label := TranslationServer.translate("ui.end_turn")
		var fs := 18
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - 28 - w) * 0.5, size.y * 0.5 + 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var cap := Rect2(Vector2(size.x - 34, size.y * 0.5 - 11), Vector2(20, 22))
		draw_rect(cap, Color(0.06, 0.08, 0.13, 0.6))
		draw_rect(cap, Color(ink, 0.6), false, 1.0)
		draw_string(get_theme_default_font(), cap.position + Vector2(5, 16), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
		if on and prompt:
			var a := 0.4 + 0.3 * sin(_time * 3.0)
			draw_line(Vector2(25, size.y - 9), Vector2(size.x - 25, size.y - 9), Color(UIKit.GOLD, a), 2, true)


static func quiet_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	return style
