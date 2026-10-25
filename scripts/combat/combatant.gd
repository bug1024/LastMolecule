class_name Combatant
extends RefCounted
## 战斗单位（玩家或敌人）：生命、防护与状态层数。纯数据，结算规则由 BattleManager 驱动。
##
## 状态（statuses，id → 层数）：
##   vulnerable 靶点暴露：受到伤害 +50%，回合结束 -1
##   weak       药效抑制：造成伤害 -25%，回合结束 -1
##   strength   效力：每次伤害 +层数
##   dexterity  规范：每次获得防护 +层数
##   poison     持续损伤：回合开始受到层数伤害（无视防护），然后 -1
##   metallicize 代谢稳定：回合结束获得层数防护
##   thorns     反噬：被攻击时攻击者受到层数伤害
##   retain_block 稳定平台：自己回合开始时护盾不清零
##   data_boost   数据增幅：每次获得数据额外多得层数
##   ritual     疾病进展：回合结束获得层数效力
##   auto_block 标准作业：回合开始获得层数防护
##   pipeline   临床网络：回合开始多抽层数张牌
##   lims       实验信息系统：每打出一张实验卡获得层数数据

const DEBUFFS := ["vulnerable", "weak", "poison"]
const DECAYING := ["vulnerable", "weak"]

var name_key := ""
var max_hp := 1
var hp := 1
var block := 0
var statuses := {}


func is_alive() -> bool:
	return hp > 0


func get_status(id: String) -> int:
	return int(statuses.get(id, 0))


func add_status(id: String, amount: int) -> void:
	var value := get_status(id) + amount
	if value <= 0:
		statuses.erase(id)
	else:
		statuses[id] = value


func gain_block(amount: int) -> int:
	var gained := maxi(0, amount)
	block += gained
	return gained


## 承受伤害（先扣防护），返回 {blocked, lost}
func take_damage(amount: int, ignore_block := false) -> Dictionary:
	var blocked := 0 if ignore_block else mini(block, amount)
	block -= blocked
	var lost := mini(hp, amount - blocked)
	hp -= lost
	return {"blocked": blocked, "lost": lost}


func clear_debuffs() -> void:
	for id in DEBUFFS:
		statuses.erase(id)


## 回合结束时递减的状态
func decay() -> void:
	for id in DECAYING:
		if statuses.has(id):
			add_status(id, -1)
