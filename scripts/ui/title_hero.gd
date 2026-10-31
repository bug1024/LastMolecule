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
	_code.add_theme_color_override("font_color", UIKit.INK)
	_code.add_theme_constant_override("outline_size", 0)
	_code.add_theme_color_override("font_outline_color", UIKit.PAPER_LIGHT)
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
	_avatar.visible = false
	queue_redraw()


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w < 200 or h < 200:
		return
	var base_y := h - 70.0      # 编号和状态写在底座下方的纸面上
	var mol := Vector2(minf(w * 0.9, 460), minf(h - 250, 340))
	_molecule.size = mol
	_molecule.position = Vector2(w * 0.58 - mol.x * 0.5, base_y - 70 - mol.y)
	_avatar.size = _avatar.custom_minimum_size
	_avatar.position = Vector2(w * 0.12, base_y - _avatar.size.y + 8)
	_code.position = Vector2(w * 0.58 - 120, base_y - 14)
	_code.size = Vector2(240, 36)
	_status.position = Vector2(w * 0.58 - 180, base_y + 22)
	_status.size = Vector2(360, 22)
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(20, 24), size - Vector2(40, 48))
	UIKit.folio(self, rect)
	var font := get_theme_default_font()
	draw_string(font, Vector2(42, 60), "RESEARCH ARCHIVE   /   LM–001", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.TEXT_DIM)
	draw_line(Vector2(42, 75), Vector2(size.x - 42, 75), Color(UIKit.BRASS, 0.5), 1)
	var pedestal := UIKit.art("pedestal")
	if pedestal:
		draw_texture_rect(pedestal, Rect2(size.x * 0.58 - 150, size.y - 182, 300, 100), false)
