class_name TitleHero
extends Control
## 标题页主视觉：被搁置的分子 LM-001，用和战斗、观察室同一个几何厚涂分子角色（MoleculeView），带待机的生命节奏。
## 跟主线进度联动：
##   未解锁 → 分子暗淡、失去光泽，标注「搁置中 · 研究证据 n / 2」；
##   已解锁 → 分子亮起，标注「可以重启了」；
##   主线完成 → 分子转绿，标注首次主线结局（获批路线为「已获批」，把答案留下为「研究已归档」）。
## 分子形态随公司获批数进化（1 + 获批数，最多 5 级；3 级起长出膜带）。

var _molecule: MoleculeView
var _avatar: PlayerAvatar
var _code: Label
var _status: Label
var _glow := Color(0.93, 0.42, 0.42)
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_molecule = MoleculeView.new()
	_molecule.character = true
	var lm := Molecule.create()
	lm.apply_preset("balanced")
	_molecule.set_molecule(lm)
	add_child(_molecule)
	_avatar = PlayerAvatar.new()
	add_child(_avatar)
	_avatar.visible = false
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
		_molecule.modulate = Color(0.82, 0.9, 1.0) if archived else Color.WHITE
		# 主动终止的主线结局（把答案留下）不是获批：显示为研究已归档
		_status.text = tr("hero.archived" if ending == "leave_answer" else "hero.done") % tr("campaign.%s.title" % ending)
		_status.add_theme_color_override("font_color", _glow.lightened(0.2))
	elif company.final_unlocked():
		_glow = UIKit.GOLD
		_molecule.modulate = Color(1.0, 0.96, 0.86)
		_status.text = tr("hero.unlocked")
		_status.add_theme_color_override("font_color", UIKit.GOLD.lightened(0.2))
	else:
		_glow = UIKit.DANGER
		_molecule.modulate = Color(0.74, 0.72, 0.8)   # 搁置：暗淡、失去光泽
		_status.text = tr("hero.shelved") % [company.evidence.size(), need]
		_status.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	_avatar.form = 1 + company.approvals
	_molecule.form = clampi(1 + company.approvals, 1, 5)
	queue_redraw()


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w < 200 or h < 200:
		return
	var base_y := h - 70.0
	var mol := Vector2(minf(w * 0.95, 540), minf(h - 130, 350))
	_molecule.size = mol
	# 双脚踩在铭牌上方的地面上
	var bounds := _molecule.visual_bounds()
	_molecule.position = Vector2(w * 0.58 - bounds.get_center().x, base_y - 12 - bounds.end.y)
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


## 脚下的接地阴影和一圈随主线状态变色的微光，让分子站在场景里而不是浮在上面
func _draw() -> void:
	if _molecule == null or _molecule.size.x <= 0.0:
		return
	var feet := _molecule.support_points()
	if feet.is_empty():
		return
	var center := _molecule.position + (feet[0] + feet[1]) * 0.5
	var span := absf(feet[1].x - feet[0].x) + 60.0
	var pulse := 0.5 + 0.5 * sin(_time * 1.6)
	Shading.glow(self, center, span * 0.7, Color(_glow, 0.10 + 0.05 * pulse))
	var shadow := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		shadow.append(center + Vector2(cos(a) * span * 0.55, sin(a) * 9.0 + 3.0))
	draw_colored_polygon(shadow, Color(0.02, 0.02, 0.05, 0.35))
