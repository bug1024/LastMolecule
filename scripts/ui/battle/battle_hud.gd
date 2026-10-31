class_name BattleHud
extends RefCounted
## 战斗界面顶部与右下角的 HUD 小部件：
##   TurnBadge  回合徽章——六边形里的大号回合数 + 「回合」字样，换回合时弹一下；
##   AiChip     AI 状态卡——档位名 + 威力倍率 + 失误率，下方一条到下一档的进度条；
##   EndTurnButton  圆形结束回合按钮——沙漏图标 + 「E」键帽，悬停放大、按下回弹带专属音效，没牌可打时外圈光环提示。


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
		var c := Vector2(30, size.y * 0.5)
		var r := 24.0 * (1.0 + 0.18 * _pop)
		var pts := PackedVector2Array()
		for k in 7:
			var a := PI / 6 + k * TAU / 6
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(0.05, 0.08, 0.1, 0.92))
		draw_polyline(pts, Color(UIKit.ACCENT, 0.9), 2.0, true)
		if _pop > 0.0:
			draw_circle(c, r + 10 * _pop, Color(UIKit.ACCENT, 0.18 * _pop))
		var bold: Font = ThemeDB.get_project_theme().get_font("font", &"HeaderLabel") if ThemeDB.get_project_theme() else get_theme_default_font()
		var text := str(turn)
		var fs := 24
		var w := bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(bold, c + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
		draw_string(bold, c + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var font := get_theme_default_font()
		draw_string(font, Vector2(64, size.y * 0.5 - 2), tr("battle.turn_word"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.TEXT_DIM)
		draw_string(font, Vector2(64, size.y * 0.5 + 16), "ROUND", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UIKit.ACCENT, 0.7))


class AiChip extends PanelContainer:
	var _tier_label: Label
	var _power: Label
	var _miss: Label
	var _bar: ProgressBar
	var _next: Label
	var _icon: TextureRect

	func _init() -> void:
		custom_minimum_size = Vector2(290, 0)
		mouse_filter = Control.MOUSE_FILTER_PASS
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		_icon = UIKit.icon_rect("type_ai", 22, UIKit.ACCENT_BLUE)
		row.add_child(_icon)
		_tier_label = UIKit.header("", 17)
		row.add_child(_tier_label)
		_power = UIKit.header("", 17, Color.WHITE)
		row.add_child(_power)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		_miss = UIKit.label("", UIKit.TEXT_DIM, 13)
		row.add_child(_miss)
		_bar = ProgressBar.new()
		_bar.custom_minimum_size = Vector2(0, 6)
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
		var sb := UIKit.panel_style(Color(0.04, 0.06, 0.09, 0.72), Color(0.3, 0.4, 0.5, 0.45), 12)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		add_theme_stylebox_override("panel", sb)
		_icon.self_modulate = UIKit.ACCENT_BLUE
		_tier_label.text = "AI · " + tr("tier." + id)
		_tier_label.add_theme_color_override("font_color", color.lightened(0.2))
		_power.text = "×" + String.num(float(tier.get("multiplier", 1.0)), 2)
		_miss.text = tr("battle.ai_miss") % miss
		var effective := int(tier.get("effective", 0))
		var need := int(tier.get("need_data", -1))
		_bar.max_value = 1.0
		_bar.step = 0.001
		_bar.value = 1.0 if need < 0 else clampf(float(effective) / maxf(1.0, float(tier.get("max", effective + need))), 0.0, 1.0)
		_bar.add_theme_stylebox_override("fill", UIKit.filled(bar_color, bar_color, 3))
		_bar.add_theme_stylebox_override("background", UIKit.filled(Color(0.12, 0.15, 0.2), Color(0.12, 0.15, 0.2), 3))
		_next.text = BattleView.ai_next_text(tier)
		tooltip_text = tr("battle.ai_chip") % [effective, tr("tier." + id), float(tier.get("multiplier", 1.0)), miss]


## 结束回合：圆形按钮——深绿底 + 亮绿圆环 + 中间沙漏图标与「结束回合」，底部「E」键帽；
## 悬停变亮放大、按下回弹并播放专属音效 end_turn；没牌可打时（prompt）外圈有扩散的光环提示。
class EndTurnButton extends Button:
	const D := 112.0
	var prompt := false
	var _time := 0.0
	var _icon_tex: Texture2D

	func _init() -> void:
		text = ""
		custom_minimum_size = Vector2(D, D)
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
		var c := size * 0.5
		var r := D * 0.5 - 6
		var on := not disabled
		var accent: Color = UIKit.ACCENT if on else Color(0.4, 0.45, 0.5)
		var hover := on and is_hovered()
		if on and prompt:
			# 提示：两圈向外扩散的光环
			for k in 2:
				var t := fmod(_time * 0.8 + k * 0.5, 1.0)
				draw_arc(c, r + 4 + t * 14, 0, TAU, 48, Color(accent, 0.5 * (1.0 - t)), 3.0, true)
		draw_circle(c, r + 4, Color(accent, 0.12 if not hover else 0.22))
		draw_circle(c, r, accent.darkened(0.62 if not hover else 0.5))
		draw_circle(c + Vector2(0, -r * 0.25), r * 0.7, Color(accent, 0.08))   # 上半部高光
		draw_arc(c, r, 0, TAU, 64, accent.lightened(0.3 if hover else 0.1), 3.0, true)
		draw_arc(c, r - 7, 0, TAU, 64, Color(accent, 0.25), 1.0, true)
		var ink := Color(0.95, 1.0, 0.97) if on else Color(0.62, 0.66, 0.7)
		if _icon_tex:
			draw_texture_rect(_icon_tex, Rect2(c + Vector2(-13, -34), Vector2(26, 26)), false, ink)
		var font := get_theme_default_font()
		var label := TranslationServer.translate("ui.end_turn")
		var fs := 16
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var cap := Rect2(c + Vector2(-10, 22), Vector2(20, 18))
		draw_rect(cap, Color(0, 0, 0, 0.3))
		draw_rect(cap, Color(ink, 0.5), false, 1.0)
		draw_string(font, cap.position + Vector2(6, 14), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(ink, 0.85))
