class_name Enemy
extends Combatant
## 敌人：定义来自 data/enemies.json。
## pattern：cycle 按顺序循环出招；random 按权重随机（同一招不会连续出现三次）。
## move：{id, intent, damage, hits, block, status（给玩家）, self_status, ally_status, ally_block, add_card}
## intent 用于界面图标：attack / defend / buff / debuff / attack_defend / attack_debuff
## mechanic 为 Boss 专属机制，由 BattleManager 解释：offtarget / toxic / dose / progression / dropout

var id := ""
var data: Dictionary = {}
var intent: Dictionary = {}      # 本回合要执行的招式
var is_boss := false
var is_elite := false
var mechanic := ""
var damaged_this_turn := false
var _history: Array = []
var _cycle := 0


static func from_dict(def: Dictionary, rng: RandomNumberGenerator, hp_scale := 1.0) -> Enemy:
	var e := Enemy.new()
	e.id = String(def.get("id", ""))
	e.data = def
	e.name_key = "enemy." + e.id
	var range_hp: Array = def.get("hp", [20, 20])
	e.max_hp = maxi(1, int(round(rng.randi_range(int(range_hp[0]), int(range_hp[1])) * hp_scale)))
	e.hp = e.max_hp
	e.is_boss = bool(def.get("boss", false))
	e.is_elite = bool(def.get("elite", false))
	e.mechanic = String(def.get("mechanic", ""))
	for status_id in def.get("start_status", {}):
		e.add_status(String(status_id), int(def.start_status[status_id]))
	return e


func roll_intent(rng: RandomNumberGenerator) -> void:
	var moves: Array = data.get("moves", [])
	if moves.is_empty():
		intent = {}
		return
	if String(data.get("pattern", "random")) == "cycle":
		intent = moves[_cycle % moves.size()]
		_cycle += 1
	else:
		var pool := moves.duplicate()
		if _history.size() >= 2 and _history[-1] == _history[-2]:
			pool = pool.filter(func(m: Dictionary) -> bool: return String(m.id) != String(_history[-1]))
		intent = pool[JsonData.weighted_index(pool, rng)]
	_history.append(String(intent.get("id", "")))


func intent_damage() -> int:
	return int(intent.get("damage", 0))


func intent_hits() -> int:
	return maxi(1, int(intent.get("hits", 1)))
