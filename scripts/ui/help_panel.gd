class_name HelpPanel
extends ModalPanel
## 玩法说明：分页介绍目标、地图、五种阶段试验、卡牌与 AI、立项决策和术语。
## 每页正文是翻译表里的 BBCode（help.<id>）。

const PAGES := ["quick", "goal", "map", "battles", "cards", "decisions", "glossary"]


func _init() -> void:
	super._init()
	title_key = "help.title"
	panel_width = 940


func _build(box: VBoxContainer) -> void:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 470)
	for page in PAGES:
		var scroll := ScrollContainer.new()
		scroll.name = tr("help.tab." + page)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var text := UIKit.rich(tr("help." + page), 16)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("line_separation", 6)
		scroll.add_child(text)
		tabs.add_child(scroll)
	tabs.tab_changed.connect(func(_i: int) -> void: GameAudio.sfx("card_draw"))
	box.add_child(tabs)
