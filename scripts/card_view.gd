class_name CardView
extends RefCounted
## 卡牌展示工具（选卡弹窗、奖励界面共用）。牌面本身见 CardFace。

const RARITY_COLOR := CardFace.RARITY_COLOR


## 生成可悬停高亮的牌面；scale_factor 相对基准尺寸 180×250
static func build(card: ResearchCard, scale_factor := 1.0, ai_info := {}) -> CardFace:
	var face := CardFace.create(card, scale_factor, {"ai_multiplier": float(ai_info.get("multiplier", 1.0))} if card.is_ai() else {}, ai_info)
	face.mouse_entered.connect(func() -> void: face.set_state(true, face.selected, face.dimmed))
	face.mouse_exited.connect(func() -> void: face.set_state(false, face.selected, face.dimmed))
	return face


static func label(text: String, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
