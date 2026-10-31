class_name CreditsPanel
extends ModalPanel
## 制作名单：电影片尾式排版——居中的 Logo 与片名，职务（右对齐、暗色）和名字（左对齐、亮色）分两列，
## 分隔处用小分子图标，最后是献词。

const ROLES := ["design", "codev", "engine", "art", "music"]


func _init() -> void:
	super._init()
	title_key = "credits.title"
	icon_name = "ui_music"
	accent = UIKit.GOLD
	panel_width = 640


func _build(box: VBoxContainer) -> void:
	box.add_theme_constant_override("separation", 10)
	var logo := TextureRect.new()
	logo.texture = UIKit.icon("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(72, 72)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(logo)
	var game_title := UIKit.header(tr("ui.title"), 32, UIKit.INK)
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(game_title)
	var english := UIKit.label("THE LAST MOLECULE", UIKit.ACCENT, 14)
	english.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(english)
	var sub := UIKit.label(tr("ui.subtitle"), UIKit.TEXT_DIM, 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(_divider())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for role in ROLES:
		var key := UIKit.label(tr("credits.role." + role), Color(accent.lightened(0.1), 0.85), 15)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.custom_minimum_size = Vector2(150, 0)
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(key)
		var value := UIKit.label(tr("credits.name." + role), UIKit.TEXT, 16, true)
		value.custom_minimum_size = Vector2(360, 0)
		grid.add_child(value)
	box.add_child(grid)
	box.add_child(_divider())
	var dedication := UIKit.label(tr("credits.dedication"), Color(UIKit.TEXT_DIM, 0.95), 15)
	dedication.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(dedication)


## 分隔：两侧渐隐的细线，中间一个小六边形分子
func _divider() -> Control:
	var d := Control.new()
	d.custom_minimum_size = Vector2(0, 22)
	d.draw.connect(func() -> void:
		var c := Vector2(d.size.x * 0.5, 11)
		for side in [-1, 1]:
			for i in 12:
				var x0: float = c.x + side * (18 + i * 14)
				d.draw_line(Vector2(x0, c.y), Vector2(x0 + side * 12, c.y), Color(accent, 0.5 * (1.0 - i / 12.0)), 1.0)
		var pts := PackedVector2Array()
		for k in 7:
			var a := PI / 6 + k * TAU / 6
			pts.append(c + Vector2(cos(a), sin(a)) * 8)
		d.draw_polyline(pts, Color(accent, 0.9), 1.5, true)
		d.draw_circle(c, 2.5, accent))
	return d
