class_name ResearchCard
extends RefCounted
## 研发卡牌数据模型。卡牌只在战斗中打出，定义来自 data/cards.json。
##
## kind：attack 攻击 / skill 技能 / power 能力（本场持续）/ status 状态牌（无法打出）
## target：enemy 单个敌人 / all 所有敌人 / self 自身
## effects：按顺序结算的效果列表，每项 {op, value, ...}
##   damage {value, times}      造成伤害（受效力、药效抑制、靶点暴露影响）
##   block {value}              获得防护
##   status {to, id, value}     施加状态，to 为 target / all / self
##   self_damage {value}        自己受到伤害（= 安全风险上升）
##   draw / energy / data / process / calibrate {value}，intel，cleanse（清除自身负面状态）
##   detonate {value}           造成目标「持续损伤」层数 × value 的伤害
##   add_card {id, value}       往弃牌堆加入状态牌
## deviation：AI 卡模型偏差时代替 effects 结算的效果
## 升级：data.upgrade 可指定 {cost, effects}；未指定时数值效果自动提升约三分之一

const MAGNITUDE_OPS := ["damage", "block", "status", "self_damage", "detonate", "block_damage", "data_damage"]

var id: String = ""
var name: String = ""        # 名称 i18n key
var type: String = ""        # ai / molecular / experiment / clinical / process / status
var type_name: String = ""   # 类型显示名 i18n key
var kind: String = "skill"
var rarity: String = "common"
var cost: int = 1
var target: String = "self"
var effects: Array = []
var deviation: Array = []
var requires_process := 0
var exhaust := false
var unplayable := false
var ethereal := false
var reliable := false         # AI 卡：不会偏差
var end_turn_damage := 0      # 状态牌：回合结束仍在手中时受到的伤害
var starter := false           # 起始专属卡（判断牌组套路时不计）
var upgraded := false          # 每张卡只有两级：普通 → 升级（+），升级即满级
var copies := 1                # 牌库里同名卡的张数（升级界面显示「×4 张一起升级」）
var upgrade_preview: ResearchCard = null   # 升级界面用：这张卡升级后的样子


static func from_dict(data: Dictionary, upgrade := false) -> ResearchCard:
	var card := ResearchCard.new()
	card.id = String(data.get("id", ""))
	card.name = String(data.get("name_key", "card." + card.id))
	card.type = String(data.get("type", "molecular"))
	card.kind = String(data.get("kind", "skill"))
	card.rarity = String(data.get("rarity", "common"))
	card.cost = int(data.get("cost", 1))
	card.target = String(data.get("target", "self"))
	card.effects = (data.get("effects", []) as Array).duplicate(true)
	card.deviation = (data.get("deviation", []) as Array).duplicate(true)
	card.requires_process = int(data.get("requires_process", 0))
	card.exhaust = bool(data.get("exhaust", false))
	card.unplayable = bool(data.get("unplayable", false))
	card.ethereal = bool(data.get("ethereal", false))
	card.reliable = bool(data.get("reliable", false))
	card.end_turn_damage = int(data.get("end_turn_damage", 0))
	card.starter = bool(data.get("starter_only", false))
	if upgrade and not card.unplayable:
		card.upgraded = true
		var spec: Dictionary = data.get("upgrade", {})
		card.cost = int(spec.get("cost", card.cost))
		if spec.has("effects"):
			card.effects = (spec.effects as Array).duplicate(true)
		else:
			for effect in card.effects:
				if MAGNITUDE_OPS.has(String(effect.get("op", ""))) and effect.has("value"):
					var value := int(effect.value)
					effect["value"] = value + maxi(1, int(ceil(value / 3.0)))
	return card


## 牌组的主要套路（查看牌库与模拟统计共用）：只看非起始卡；
## 中毒 / 引爆卡超过 3 张为 poison，某一类型过半为该类型，非起始卡不足 3 张为 thin，其余 mixed
static func deck_build(cards: Array) -> String:
	var counts := {}
	var extra := 0
	var poison := 0
	for card in cards:
		if card.starter or card.type == "status":
			continue
		extra += 1
		counts[card.type] = int(counts.get(card.type, 0)) + 1
		if card.effects.any(func(e: Dictionary) -> bool:
				return e.get("op", "") == "detonate" or (e.get("op", "") == "status" and e.get("id", "") == "poison")):
			poison += 1
	if extra < 3:
		return "thin"
	if poison > 3:
		return "poison"
	var best := ""
	for t in counts:
		if best.is_empty() or int(counts[t]) > int(counts[best]):
			best = t
	return best if int(counts[best]) * 2 > extra else "mixed"


func is_ai() -> bool:
	return type == "ai"


func can_deviate() -> bool:
	return is_ai() and not reliable


func needs_target() -> bool:
	return target == "enemy"


## 卡牌角色（牌面角标与边框颜色）：attack 攻击 / defend 防护 / skill 技能 / power 能力 / status 状态
func role() -> String:
	if kind == "attack" or kind == "power" or kind == "status":
		return kind
	for effect in effects:
		if String(effect.get("op", "")) == "block":
			return "defend"
	return "skill"


## 牌面效果行：[{icon, color, number, text, change}]，change 为实时数值相对基础值的升降（1 / 0 / -1）
func effect_rows(mods := {}) -> Array:
	var rows: Array = []
	var t := TranslationServer
	for effect in effects:
		var op := String(effect.get("op", ""))
		var base := int(effect.get("value", 0))
		var value := base
		if is_ai() and MAGNITUDE_OPS.has(op) and op != "self_damage":
			value = int(round(value * float(mods.get("ai_multiplier", 1.0))))
		match op:
			"damage":
				if mods.has("damage"):
					value = int((mods.damage as Callable).call(value))
				var times := int(effect.get("times", 1))
				var number := str(value) + ("×%d" % times if times > 1 else "")
				var where := "row.damage_all" if target == "all" else "row.damage"
				rows.append({"icon": "intent_attack", "color": Color(1.0, 0.45, 0.35), "number": number, "text": t.translate(where), "change": signi(value - base)})
			"block":
				if mods.has("block"):
					value = int((mods.block as Callable).call(value))
				rows.append({"icon": "intent_defend", "color": Color(0.45, 0.72, 1.0), "number": str(value), "text": t.translate("row.block"), "change": signi(value - base)})
			"status":
				var id := String(effect.get("id", ""))
				var bad := Combatant.DEBUFFS.has(id)
				var who := String(effect.get("to", "target"))
				rows.append({"icon": "status_" + id, "color": Color(0.8, 0.55, 1.0) if bad else Color(0.45, 0.9, 0.55),
					"number": str(value), "text": t.translate("row.status_" + who) % t.translate("status." + id), "change": signi(value - base)})
			"self_damage":
				rows.append({"icon": "ui_heart_broken", "color": Color(1.0, 0.4, 0.45), "number": "-%d" % value, "text": t.translate("row.self_damage"), "change": 0})
			"draw":
				rows.append({"icon": "ui_draw_pile", "color": Color(0.95, 0.95, 1.0), "number": "+%d" % value, "text": t.translate("row.draw"), "change": 0})
			"energy":
				rows.append({"icon": "ui_energy", "color": Color(1.0, 0.78, 0.3), "number": "+%d" % value, "text": t.translate("row.energy"), "change": 0})
			"data":
				rows.append({"icon": "stat_data", "color": Color(0.45, 0.85, 1.0), "number": "+%d" % value, "text": t.translate("row.data"), "change": 0})
			"process":
				rows.append({"icon": "type_process", "color": Color(0.4, 0.85, 0.75), "number": "+%d" % value, "text": t.translate("row.process"), "change": 0})
			"calibrate":
				rows.append({"icon": "type_ai", "color": Color(0.45, 0.75, 1.0), "number": "-%d%%" % value, "text": t.translate("row.calibrate"), "change": 0})
			"intel":
				rows.append({"icon": "ui_help", "color": Color(0.95, 0.85, 0.5), "number": "", "text": t.translate("row.intel"), "change": 0})
			"cleanse":
				rows.append({"icon": "ui_plus", "color": Color(0.5, 1.0, 0.75), "number": "", "text": t.translate("row.cleanse"), "change": 0})
			"detonate":
				rows.append({"icon": "status_poison", "color": Color(1.0, 0.45, 0.35), "number": "×%d" % value, "text": t.translate("row.detonate"), "change": 0})
			"block_damage":
				rows.append({"icon": "intent_attack", "color": Color(0.45, 0.72, 1.0), "number": "+%d" % value if value > 0 else "",
					"text": t.translate("row.block_damage"), "change": signi(value - base)})
			"formulate":
				rows.append({"icon": "type_clinical", "color": Color(0.95, 0.55, 0.55), "number": "-%d" % value, "text": t.translate("row.formulate"), "change": 0})
			"double_block":
				rows.append({"icon": "intent_defend", "color": Color(0.45, 0.72, 1.0), "number": "×2", "text": t.translate("row.double_block"), "change": 0})
			"data_damage":
				rows.append({"icon": "intent_attack", "color": Color(1.0, 0.45, 0.35), "number": str(value),
					"text": t.translate("row.data_damage"), "change": signi(value - base)})
			"add_card":
				rows.append({"icon": "intent_debuff", "color": Color(0.7, 0.7, 0.75), "number": "+%d" % value,
					"text": t.translate("row.add_card") % t.translate("card." + String(effect.get("id", ""))), "change": 0})
	# 升级预览：与升级前同一行比较，数字变大显示绿色
	if mods.has("compare_to"):
		var before: Array = (mods.compare_to as ResearchCard).effect_rows()
		for i in mini(rows.size(), before.size()):
			if rows[i].icon == before[i].icon:
				rows[i].change = signi(_lead_int(String(rows[i].number)) - _lead_int(String(before[i].number)))
	return rows


## 升级前后对比，如 ["伤害 6 → 9", "费用 2 → 1"]
static func upgrade_diff(before: ResearchCard, after: ResearchCard) -> Array[String]:
	var lines: Array[String] = []
	var t := TranslationServer
	if after.cost != before.cost:
		lines.append("%s %d → %d" % [t.translate("row.cost"), before.cost, after.cost])
	var old_rows := before.effect_rows()
	var new_rows := after.effect_rows()
	for i in new_rows.size():
		var row: Dictionary = new_rows[i]
		if i < old_rows.size() and old_rows[i].icon == row.icon:
			if String(old_rows[i].number) != String(row.number):
				lines.append("%s %s → %s" % [row.text, old_rows[i].number, row.number])
		else:
			lines.append("%s %s %s" % [t.translate("row.new"), row.number, row.text])
	return lines


static func _lead_int(text: String) -> int:
	var digits := ""
	for ch in text:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif not digits.is_empty():
			break
	return digits.to_int()


## 牌面底部的关键词（无法打出 / 回合结束受伤 / 消散 / 消耗）
func keywords() -> String:
	var parts: Array[String] = []
	var t := TranslationServer
	if unplayable:
		parts.append(t.translate("cardtext.unplayable"))
	if end_turn_damage > 0:
		parts.append(t.translate("cardtext.end_turn_damage") % end_turn_damage)
	if ethereal:
		parts.append(t.translate("cardtext.ethereal"))
	if exhaust:
		parts.append(t.translate("cardtext.exhaust"))
	return " · ".join(parts)


## 卡面效果文本。mods 由战斗传入，用于显示实时数值：
##   {damage: Callable(int)->int, block: Callable(int)->int, ai_multiplier: float}
func describe(mods := {}) -> String:
	var lines: Array[String] = []
	for effect in effects:
		lines.append(describe_effect(effect, mods, is_ai()))
	if unplayable:
		lines.append(TranslationServer.translate("cardtext.unplayable"))
	if end_turn_damage > 0:
		lines.append(TranslationServer.translate("cardtext.end_turn_damage") % end_turn_damage)
	if ethereal:
		lines.append(TranslationServer.translate("cardtext.ethereal"))
	if exhaust:
		lines.append(TranslationServer.translate("cardtext.exhaust"))
	return "\n".join(lines.filter(func(l: String) -> bool: return not l.is_empty()))


func describe_deviation() -> String:
	var lines: Array[String] = []
	for effect in deviation:
		lines.append(describe_effect(effect, {}, false))
	return "；".join(lines)


static func describe_effect(effect: Dictionary, mods: Dictionary, ai_scaled: bool) -> String:
	var op := String(effect.get("op", ""))
	var value := int(effect.get("value", 0))
	if ai_scaled and MAGNITUDE_OPS.has(op) and op != "self_damage":
		value = int(round(value * float(mods.get("ai_multiplier", 1.0))))
	var t := TranslationServer
	match op:
		"damage":
			if mods.has("damage"):
				value = int((mods.damage as Callable).call(value))
			var times := int(effect.get("times", 1))
			return t.translate("cardtext.damage_times") % [value, times] if times > 1 else t.translate("cardtext.damage") % value
		"block":
			if mods.has("block"):
				value = int((mods.block as Callable).call(value))
			return t.translate("cardtext.block") % value
		"status":
			var who := String(effect.get("to", "target"))
			var status_name := t.translate("status." + String(effect.get("id", "")))
			return t.translate("cardtext.status_" + who) % [value, status_name]
		"self_damage":
			return t.translate("cardtext.self_damage") % value
		"draw":
			return t.translate("cardtext.draw") % value
		"energy":
			return t.translate("cardtext.energy") % value
		"data":
			return t.translate("cardtext.data") % value
		"process":
			return t.translate("cardtext.process") % value
		"calibrate":
			return t.translate("cardtext.calibrate") % value
		"intel":
			return t.translate("cardtext.intel")
		"cleanse":
			return t.translate("cardtext.cleanse")
		"detonate":
			return t.translate("cardtext.detonate") % value
		"block_damage":
			return t.translate("cardtext.block_damage") % value
		"double_block":
			return t.translate("cardtext.double_block")
		"formulate":
			return t.translate("cardtext.formulate") % value
		"data_damage":
			return t.translate("cardtext.data_damage") % [value, maxi(1, int(effect.get("per", 1)))]
		"add_card":
			return t.translate("cardtext.add_card") % [value, t.translate("card." + String(effect.get("id", "")))]
	return ""
