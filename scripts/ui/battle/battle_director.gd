class_name BattleDirector
extends RefCounted
## 战斗演出调度：只读战斗事件，不改战斗逻辑。决定每个动作的演出强度、节奏、顿帧、震屏、
## 闪屏和伤害数字的位置；同一回合重复的动作逐渐压缩，常态画面保持克制。
##
## 强度分四级：
##   1 安静：抽牌、普通护盾、状态变化——只有简短的形体反馈
##   2 有方向：普通攻击、破绽、中毒——有明确的作用方向，没有震屏和闪屏
##   3 爆点：高伤害、片段联动、AI 强化、连击——命中有爆点，可有轻微震屏和顿帧
##   4 独立演出：Boss 技能、致命攻击、击杀 Boss、阶段转换——压暗、顿帧、闪屏、重震

enum Tier { QUIET = 1, DIRECT = 2, BURST = 3, SIGNATURE = 4 }

## 普通攻击的时间轴（秒）：预备 → 释放 → 命中峰值 → 受击反馈 → 恢复。只作初始手感参数
const TIMELINE := {"prep": 0.10, "release": 0.12, "peak": 0.05, "react": 0.15, "recover": 0.13}
const HEAVY_DAMAGE := 15
const COMBO_HITS := 3

var pace := 1.0                 # 当前动作的演出速度（重复动作 > 1，压缩演出）
var compressed := false         # 本回合同一动作已经重复多次：省掉次要特效
var tier := Tier.DIRECT         # 当前这张牌的演出强度
var _repeats := {}              # 本回合各动作出现的次数
var _numbers: Array = []        # 最近弹出的伤害数字：[位置, 剩余时间]，用来错开


static func lite() -> bool:
	return GameSettings.fx_level == "lite"


## 新回合：重复计数清零
func new_turn() -> void:
	_repeats.clear()
	pace = 1.0
	compressed = false


## 打出一张牌：算出这张牌的强度和节奏
func begin_card(card: ResearchCard, deviated: bool) -> Dictionary:
	tier = card_tier(card, deviated)
	var key := card.id + ("!" if deviated else "")
	var count := int(_repeats.get(key, 0)) + 1
	_repeats[key] = count
	# 第二次起每次加快 20%，最多 1.7 倍；第三次起省掉次要特效。重要技能（3 级以上）只加快不省略
	pace = minf(1.0 + 0.2 * (count - 1), 1.7)
	if lite():
		pace = maxf(pace, 1.2)
	compressed = (count >= 3 and tier <= Tier.DIRECT) or lite()
	return {"tier": tier, "pace": pace, "compressed": compressed, "count": count}


static func card_tier(card: ResearchCard, deviated := false) -> int:
	if deviated:
		return Tier.DIRECT
	var damage := 0
	var hits := 1
	for e in card.effects:
		if String(e.get("op", "")) == "damage":
			hits = maxi(hits, int(e.get("times", 1)))
			damage += int(e.get("value", 0)) * int(e.get("times", 1))
	if card.is_ai() and card.kind == "attack":
		return Tier.BURST
	if not card.synergy_site.is_empty() or hits >= COMBO_HITS or damage >= HEAVY_DAMAGE:
		return Tier.BURST
	if card.kind == "attack" or card.target == "enemy":
		return Tier.DIRECT
	return Tier.QUIET


## 一次伤害的强度：伤害量、是否致命、是否来自 Boss
static func damage_tier(amount: int, lethal: bool, boss: bool, card_tier_value := Tier.DIRECT) -> int:
	if lethal and boss:
		return Tier.SIGNATURE
	if lethal:
		return Tier.BURST if amount < HEAVY_DAMAGE else Tier.SIGNATURE
	if boss and amount >= 10:
		return Tier.SIGNATURE
	if amount >= HEAVY_DAMAGE:
		return maxi(Tier.BURST, card_tier_value)
	return maxi(Tier.DIRECT, mini(card_tier_value, Tier.BURST))


## 震屏：2 级以下不震；精简模式和降低动态效果再减弱
static func shake_for(level: int, amount := 0) -> float:
	var strength := 0.0
	match level:
		Tier.BURST: strength = 3.0 + minf(amount, 30) * 0.12
		Tier.SIGNATURE: strength = 8.0 + minf(amount, 40) * 0.15
	if lite():
		strength *= 0.4
	return strength


## 闪屏只留给 4 级
static func flash_for(level: int) -> float:
	if level < Tier.SIGNATURE:
		return 0.0
	return 0.10 if lite() else 0.18


## 局部顿帧：只冻结命中双方的姿态 30–60ms，不阻塞战斗推进
static func hitstop_for(level: int) -> float:
	match level:
		Tier.BURST: return 0.035
		Tier.SIGNATURE: return 0.06
	return 0.0


## 伤害数字：字号和颜色随强度变化；数字放在身体上方并左右错开，不压住角色
func number_style(level: int, amount: int) -> Dictionary:
	var size := 24 + mini(amount, 12)
	var color := UIKit.GOLD.lightened(0.25)
	match level:
		Tier.BURST:
			size = 32 + mini(amount, 14)
			color = Color(1.0, 0.86, 0.45)
		Tier.SIGNATURE:
			size = 42 + mini(amount, 16)
			color = Color(1.0, 0.62, 0.42)
	if compressed:
		size = int(size * 0.85)
	return {"size": size, "color": color}


## 给新数字找一个不和最近数字重叠的位置
func number_slot(anchor: Vector2) -> Vector2:
	var now := Time.get_ticks_msec() / 1000.0
	_numbers = _numbers.filter(func(entry: Array) -> bool: return float(entry[1]) > now)
	var offsets := [Vector2.ZERO, Vector2(-50, -14), Vector2(50, -14), Vector2(0, -46), Vector2(-50, -60), Vector2(50, -60)]
	var spot := anchor
	for offset in offsets:
		spot = anchor + offset
		var free := true
		for entry in _numbers:
			if (entry[0] as Vector2).distance_to(spot) < 40.0:
				free = false
				break
		if free:
			break
	_numbers.append([spot, now + 0.6])
	return spot
