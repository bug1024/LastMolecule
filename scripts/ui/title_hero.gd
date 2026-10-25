class_name TitleHero
extends Control
## 标题页主视觉：被搁置的分子 LM-001 悬浮在光柱底座上，研发团队的烧瓶站在一旁仰望它。
## 跟主线进度联动：
##   未解锁 → 分子偏红、暗淡，标注「搁置中 · 研究证据 n / 2」；
##   已解锁 → 分子亮起，标注「可以重启了」；
##   主线完成 → 分子转绿，标注首次主线结局（获批路线为「已获批」，把答案留下为「研究已归档」）。
## 烧瓶形态随公司获批数进化（1 + 获批数，最多 5 级）。

var _molecule: MoleculeArt
var _avatar: PlayerAvatar
var _code: Label
var _status: Label
var _glow := Color(0.93, 0.42, 0.42)
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_molecule = MoleculeArt.new()
	_molecule.stage_index = 5
	add_child(_molecule)
	_avatar = PlayerAvatar.new()
	add_child(_avatar)
	_avatar.custom_minimum_size = Vector2(120, 144)
	_code = UIKit.header("LM-001", 30, UIKit.GOLD)
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.add_theme_constant_override("outline_size", 8)
	_code.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(_code)
	_status = UIKit.label("", UIKit.TEXT, 15)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	resized.connect(_layout)
	_layout.call_deferred()   # 锚点尺寸可能在 _ready 之前就算好了，错过 resized 信号
	refresh()


func refresh() -> void:
	var company := Company.new()
	company.load_save()
	var need := int(ProjectTypes.config().get("final_unlock_evidence", 2))
	if company.is_campaign_done():
		var ending := String(company.campaign.get("ending", ""))
		var archived := ending == "leave_answer"
		_glow = UIKit.ACCENT_BLUE if archived else UIKit.ACCENT   # 归档用冷静的蓝色，获批用绿色
		_molecule.health = 0.55 if archived else 1.0
		# 主动终止的主线结局（把答案留下）不是获批：显示为研究已归档
		_status.text = tr("hero.archived" if ending == "leave_answer" else "hero.done") % tr("campaign.%s.title" % ending)
		_status.add_theme_color_override("font_color", _glow.lightened(0.2))
	elif company.final_unlocked():
		_glow = UIKit.GOLD
		_molecule.health = 0.6
		_status.text = tr("hero.unlocked")
		_status.add_theme_color_override("font_color", UIKit.GOLD.lightened(0.2))
	else:
		_glow = UIKit.DANGER
		_molecule.health = 0.15
		_status.text = tr("hero.shelved") % [company.evidence.size(), need]
		_status.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	_avatar.form = 1 + company.approvals
	queue_redraw()


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w < 200 or h < 200:
		return
	var base_y := h - 70.0
	var mol := Vector2(minf(w * 0.8, 340), minf(h - 150, 290))
	_molecule.size = mol
	_molecule.position = Vector2(w * 0.58 - mol.x * 0.5, base_y - 40 - mol.y)
	_avatar.size = _avatar.custom_minimum_size
	_avatar.position = Vector2(w * 0.12, base_y - _avatar.size.y + 8)
	_code.position = Vector2(w * 0.58 - 120, base_y - 2)
	_code.size = Vector2(240, 36)
	_status.position = Vector2(w * 0.58 - 180, base_y + 34)
	_status.size = Vector2(360, 22)
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var base_y := h - 70.0
	var center := Vector2(w * 0.58, base_y - 40 - minf(h - 150, 290) * 0.5)
	var pulse := 0.5 + 0.5 * sin(_time * 1.3)
	for i in 12:
		draw_circle(center, 210.0 - i * 16.0, Color(_glow, 0.018 + 0.006 * pulse))
	# 光柱底座
	var base := Vector2(w * 0.58, base_y)
	var beam := PackedVector2Array([base + Vector2(-60, -30), base + Vector2(60, -30), base + Vector2(140, -330), base + Vector2(-140, -330)])
	draw_colored_polygon(beam, Color(_glow.lightened(0.3), 0.045 + 0.025 * pulse))
	draw_set_transform(base + Vector2(0, -12), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 92, Color(0.08, 0.11, 0.14))
	draw_arc(Vector2.ZERO, 92, 0, TAU, 64, Color(_glow, 0.7), 4.0, true)
	draw_circle(Vector2.ZERO, 60, Color(_glow, 0.12 + 0.08 * pulse))
	draw_set_transform(Vector2.ZERO)
	# 烧瓶脚下的光圈
	draw_set_transform(Vector2(w * 0.12 + 60, base_y + 6), 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, 56, Color(PlayerAvatar.GREEN, 0.12))
	draw_set_transform(Vector2.ZERO)
