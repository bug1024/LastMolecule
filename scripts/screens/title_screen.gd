extends Control
## 标题界面：膜世界里一束光落在被搁置的 LM-001 上（TitleBackdrop + TitleHero），
## 左侧是字标和菜单（主项是玉绿厚板，其余是文字行），页脚一行版本与公司概况。

const LEFT := 88.0
const MENU_WIDTH := 340.0

var _menu: VBoxContainer
var _company_box: VBoxContainer
var _settings: SettingsPanel
var _help: HelpPanel
var _archive: ArchivePanel
var _credits: CreditsPanel
var _backdrop: TitleBackdrop
var _haze: TitleBackdrop
var _lockup: VBoxContainer
var _rule: Control
var _version: Label
var _rule_grow := 1.0
var _confirm: ConfirmDialog
var _hero: TitleHero
var _project_select: ProjectSelectPanel
var _primary: TitleMenuButton


func _ready() -> void:
	GameSettings.apply()
	_backdrop = TitleBackdrop.new()
	_haze = TitleBackdrop.new()
	_haze.front = true
	for layer in [_backdrop, _haze]:
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(layer)
	_build()
	_curtain()
	GameAudio.play("TITLE")
	GameAudio.set_paused(false)


func _build() -> void:
	for child in get_children():
		if not child is TitleBackdrop:
			child.queue_free()
	# 主视觉站在右侧的光里；左侧是字标和菜单；页脚一行版本与公司概况
	_hero = TitleHero.new()
	_hero.anchor_left = 0.36
	_hero.anchor_right = 1.0
	_hero.anchor_bottom = 1.0
	_hero.offset_top = 30
	_hero.offset_right = -30
	_hero.offset_bottom = -64
	add_child(_hero)
	move_child(_hero, _backdrop.get_index() + 1)   # 近景浮尘和暗角盖在主视觉之上

	var has_save := RunSave.exists()
	var left := VBoxContainer.new()
	left.position = Vector2(LEFT, 44 if has_save else 84)
	left.add_theme_constant_override("separation", 0)
	add_child(left)
	_lockup = VBoxContainer.new()
	_lockup.add_theme_constant_override("separation", 0)
	left.add_child(_lockup)
	_lockup.add_child(_wordmark())
	_rule = Control.new()
	_rule.custom_minimum_size = Vector2(MENU_WIDTH, 22)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.draw.connect(_draw_rule)
	_lockup.add_child(_rule)
	var english := UIKit.label(tr("title.english").to_upper(), UIKit.ACCENT.lightened(0.3), 17)
	english.add_theme_font_override("font", _tracked(ThemeDB.get_project_theme().default_font, 5))
	_lockup.add_child(english)
	# 英文版的副标题和上一行是同一句话，不重复
	if not tr("ui.subtitle").to_lower().contains(tr("title.english").to_lower()):
		var subtitle := UIKit.label(tr("ui.subtitle"), Color(UIKit.TEXT_DIM, 0.9), 15)
		subtitle.add_theme_font_override("font", _tracked(ThemeDB.get_project_theme().default_font, 2))
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_top", 8)
		pad.add_child(subtitle)
		_lockup.add_child(pad)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24 if has_save else 44)
	left.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	_menu.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(_menu)
	_primary = null
	var saved := RunSave.summary()
	if not saved.is_empty():
		_menu_button("title.continue", "ui_play", _on_continue, true)
		var project := tr("project.title") % [String(saved.project_code), tr("project.type." + String(saved.project_type))]
		var line := UIKit.label(tr("title.continue_line") % [project, tr("stage." + String(saved.stage)), int(saved.year), int(saved.funding)], UIKit.ACCENT.lightened(0.1), 12, true)
		line.custom_minimum_size = Vector2(430, 0)   # 中文一行放得下；英文较长，折成两行
		var line_pad := MarginContainer.new()
		line_pad.add_theme_constant_override("margin_left", 4)
		line_pad.add_theme_constant_override("margin_top", 4)
		line_pad.add_theme_constant_override("margin_bottom", 8)
		line_pad.add_child(line)
		_menu.add_child(line_pad)
		_menu_button("title.start", "ui_plus", _on_start)
	else:
		_menu_button("title.start", "ui_play", _on_start, true)
		var breath := Control.new()
		breath.custom_minimum_size = Vector2(0, 8)
		_menu.add_child(breath)
	_menu_button("title.archive", "ui_archive", func() -> void: _archive.open())
	_menu_button("title.help", "ui_help", func() -> void: _help.open())
	_menu_button("title.settings", "type_process", func() -> void: _settings.open())
	_menu_button("title.credits", "ui_music", func() -> void: _credits.open())
	if OS.get_name() != "Web":
		_menu_button("title.quit", "ui_power", func() -> void: get_tree().quit())

	_version = UIKit.label(tr("title.version"), Color(UIKit.TEXT_DIM, 0.55), 12)
	_version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.offset_left = LEFT
	_version.offset_bottom = -22
	add_child(_version)
	_company_box = VBoxContainer.new()
	_company_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_company_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_company_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_company_box.offset_right = -48
	_company_box.offset_bottom = -22
	_company_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(_company_box)
	_fill_company()

	_settings = SettingsPanel.new()
	_settings.allow_reset = true
	_settings.locale_changed.connect(func() -> void: _rebuild_after_locale.call_deferred())
	_settings.closed.connect(func() -> void:
		_fill_company()
		_hero.refresh())   # 设置里可能重置了公司档案
	_help = HelpPanel.new()
	_archive = ArchivePanel.new()
	_credits = CreditsPanel.new()
	_project_select = ProjectSelectPanel.new()
	_project_select.project_chosen.connect(_start_new)
	_confirm = null
	for panel in [_settings, _help, _archive, _credits, _project_select]:
		add_child(panel)
	_intro()


## 字标：大号标题字，字面从骨白过渡到暖金；过长的标题（英文）自动缩到左栏放得下
func _wordmark() -> Label:
	var text := tr("ui.title")
	var font := _tracked(ThemeDB.get_project_theme().get_font("font", "HeaderLabel"), 4)
	var font_size := 88
	while font_size > 40 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 500.0:
		font_size -= 2
	var title := UIKit.header(text, font_size, Color.WHITE)
	title.add_theme_font_override("font", font)
	title.add_theme_color_override("font_shadow_color", Color(0.01, 0.015, 0.04, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 8)
	var gradient := ShaderMaterial.new()
	gradient.shader = preload("res://assets/shaders/title_gradient.gdshader")
	gradient.set_shader_parameter("height", font.get_height(font_size))
	title.material = gradient
	return title


static func _tracked(base: Font, spacing: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	font.spacing_glyph = spacing
	return font


## 字标下的分隔：一枚小六元环，后面一道向右淡出的金线（入场时从左向右画出来）
func _draw_rule() -> void:
	var y := _rule.size.y * 0.5
	var ring := PackedVector2Array()
	for i in 7:
		ring.append(Vector2(8, y) + Vector2.from_angle(PI / 6 + i * TAU / 6) * 6.0)
	_rule.draw_polyline(ring, UIKit.GOLD, 1.6, true)
	var reach := 22.0 + (_rule.size.x - 22.0) * _rule_grow
	_rule.draw_polyline_colors(PackedVector2Array([Vector2(22, y), Vector2(reach, y)]),
		PackedColorArray([Color(UIKit.GOLD, 0.85), Color(UIKit.GOLD, 0.0)]), 1.5, true)


func _menu_button(key: String, icon_name: String, action: Callable, primary := false) -> void:
	var btn := TitleMenuButton.new(tr(key), UIKit.icon(icon_name), primary)
	btn.pressed.connect(func() -> void:
		GameAudio.sfx("click")
		action.call())
	_menu.add_child(btn)
	if primary:
		_primary = btn

func _fill_company() -> void:
	if _company_box == null:
		return
	for child in _company_box.get_children():
		child.queue_free()
	var company := Company.new()
	company.load_save()
	var text := tr("title.company_new_short") if company.runs == 0 else tr("title.company_short") % [company.runs, company.approvals,
		company.process_level(), tr("tier." + String(company.tier_for(company.effective_data(0, 0)).id))]
	var label := UIKit.label(text, Color(UIKit.TEXT_DIM, 0.85), 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_company_box.add_child(label)


## 入场：字标先落定，分隔线画出，菜单逐项亮起，主视觉在光里慢慢显形
func _intro() -> void:
	_hero.modulate.a = 0.0
	_lockup.modulate.a = 0.0
	_rule_grow = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_hero, "modulate:a", 1.0, 1.4).set_delay(0.15)
	tween.tween_property(_lockup, "modulate:a", 1.0, 0.7).set_delay(0.2)
	tween.tween_method(func(value: float) -> void:
		_rule_grow = value
		_rule.queue_redraw(), 0.0, 1.0, 0.9).set_delay(0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var index := 0
	for item in _menu.get_children():
		item.modulate.a = 0.0
		tween.tween_property(item, "modulate:a", 1.0, 0.45).set_delay(0.6 + index * 0.07)
		index += 1
	for footer in [_version, _company_box]:
		footer.modulate.a = 0.0
		tween.tween_property(footer, "modulate:a", 1.0, 0.6).set_delay(1.1)


## 首次进入时从黑场淡入（切换语言重建界面时不再重复）
func _curtain() -> void:
	var black := ColorRect.new()
	black.color = Color(0.01, 0.015, 0.04)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var tween := black.create_tween()
	tween.tween_property(black, "color:a", 0.0, 0.9)
	tween.tween_callback(black.queue_free)


## 键盘 / 手柄：还没有当前项时，方向键或确认键先落到主项上
func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() != null or _primary == null or not is_instance_valid(_primary):
		return
	for panel in [_settings, _help, _archive, _credits, _project_select, _confirm]:
		if panel != null and panel.visible:
			return
	for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_focus_next"]:
		if event.is_action_pressed(action):
			_primary.grab_focus()
			get_viewport().set_input_as_handled()
			return


func _rebuild_after_locale() -> void:
	_build()
	_settings.open()


func _on_start() -> void:
	if RunSave.exists():
		if _confirm == null:
			_confirm = ConfirmDialog.new()
			add_child(_confirm)
		_confirm.ask(tr("title.start"), tr("title.start_overwrite"), _project_select.open)
		return
	_project_select.open()


func _start_new(type_id: String) -> void:
	RunSave.resume_requested = false
	RunSave.new_project_type = type_id
	GameAudio.sfx("stage")
	SceneRouter.goto(SceneRouter.GAME)


func _on_continue() -> void:
	RunSave.resume_requested = true
	GameAudio.sfx("stage")
	SceneRouter.goto(SceneRouter.GAME)

