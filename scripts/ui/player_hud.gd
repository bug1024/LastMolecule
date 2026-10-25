class_name PlayerHud
extends HBoxContainer
## 主界面的研发团队卡片：小号烧瓶形象 + 等级名称 + 经验条 + 当前自带能力。

var _avatar: PlayerAvatar
var _title: Label
var _bar: ProgressBar
var _bonus: Label


## 自带能力说明，如「开场护盾 +4 · 力量 +1」
static func bonus_text(bonus: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["start_block", "strength", "first_draw", "dexterity"]:
		if int(bonus.get(key, 0)) > 0:
			parts.append(TranslationServer.translate("player.bonus." + key) % int(bonus[key]))
	return " · ".join(parts) if not parts.is_empty() else TranslationServer.translate("player.bonus.none")


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_avatar = PlayerAvatar.new()
	_avatar.custom_minimum_size = Vector2(64, 84)
	add_child(_avatar)
	_avatar.custom_minimum_size = Vector2(64, 84)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	_title = UIKit.header("", 15, PlayerAvatar.GREEN)
	col.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.show_percentage = false
	col.add_child(_bar)
	_bonus = UIKit.label("", UIKit.TEXT_DIM, 12, true)
	col.add_child(_bonus)


func refresh(game) -> void:
	if _avatar == null:
		return
	var level: int = game.get_player_level()
	_avatar.form = level
	_avatar.ratio = float(100 - game.state.safety_risk) / 100.0
	var next: int = game.get_next_level_xp()
	_title.text = tr("player.tag") % [level, tr("player.level.%d" % level)]
	_bar.max_value = maxi(next, 1) if next > 0 else 1
	_bar.value = game.player_xp if next > 0 else 1
	_bar.tooltip_text = tr("player.xp") % [game.player_xp, next] if next > 0 else tr("player.max")
	_bonus.text = bonus_text(game.get_player_bonus())
