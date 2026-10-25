class_name BattleManager
extends Node
## 战斗核心（纯逻辑，无 UI 依赖），规则参照杀戮尖塔：
##   玩家每回合 3 点行动力、抽 5 张牌；敌人头顶显示下回合意图；防护在自己回合开始时清零。
##   玩家生命 = 100 - 项目安全风险：受到的伤害会直接变成安全风险。
## 卡牌效果见 ResearchCard；敌人与 Boss 机制见 Enemy / data/enemies.json。
##
## 每次玩家操作后，逻辑立即结算完毕，并通过 events_emitted 一次性发出本次的事件列表，
## 界面按顺序播放动画。事件 {t: ...}：
##   card {card, target} / deviation {card} / damage {side, index, amount, blocked, hp, block}
##   block {side, index, amount, block} / status {side, index, id, amount}
##   data {amount} / draw {count, hand（手牌快照）} / energy {energy} / add_card {id, count}
##   enemy_turn / enemy_move {index, move} / turn {turn} / death {side, index}
##   mechanic {key, args} / end {victory}
## AI 卡：威力取决于有效数据所在档位（倍率 + 偏差概率），偏差时改为结算卡牌的 deviation 效果。
## 项目规则 rules（由项目类型决定，见 data/projects.json battle_rules）：
##   offtarget_limit / offtarget_damage：一回合超过 limit 张攻击牌，每多 1 张掉 damage 血（选择性项目）；
##   precise_free：攻击带「破绽」的目标不计入。
##   enemy_ramp_every：每隔 N 回合所有敌人力量 +1（慢性项目：拖得越久越危险）。

signal battle_started(encounter: Dictionary)
signal turn_started(turn: int)
signal events_emitted(events: Array)
signal card_resolved(card: ResearchCard, deviated: bool)
signal battle_ended(victory: bool, outcome: Dictionary)

const ENEMIES_PATH := "res://data/enemies.json"
const OFFTARGET_DAMAGE := 4
const DROPOUT_BLOCK := 4
const DOSE_PLAYER_STRENGTH := 2
const DOSE_BOSS_STRENGTH := 1

var rng := RandomNumberGenerator.new()
## 由 game 注入：func(extra_data: int, extra_process: int) -> {id, multiplier, deviation, effective}
var tier_provider: Callable = Callable()
## 由 game 注入：func(card_id: String) -> ResearchCard（生成噪声数据等状态牌）
var card_factory: Callable = Callable()

var player: Combatant = null
var enemies: Array[Enemy] = []
var encounter: Dictionary = {}
var hand_size := 5
var max_energy := 3
var energy := 0
var turn := 0
var hand: Array = []
var draw_pile: Array = []
var discard_pile: Array = []
var exhaust_pile: Array = []
var data_gained := 0
var process_gained := 0
var calibrate := 0
var intel := false
var dose := 0
var dose_max := 4
var attacks_this_turn := 0
var rules: Dictionary = {}           # 项目规则，见文件头
var rule_attacks := 0                # 本回合计入项目规则的攻击牌数
var stats := {"attacks": 0, "precise": 0, "backfires": 0}   # 本场统计：攻击牌数 / 打破绽目标的攻击 / 反噬次数
var last_deviation := false

var _enemy_defs := {}
var _abilities: Array = []
var _type_counts := {}
var _active := false
var _dosed_this_turn := false
var _start_hp := 0
var _start_block := 0
var _first_draw := 0
var _events: Array = []


func _ready() -> void:
	for def in JsonData.load_dict(ENEMIES_PATH).get("enemies", []):
		_enemy_defs[String(def.get("id", ""))] = def


# ---------- 战斗控制 ----------

## encounter：{id, kind: fight/elite/boss, enemies: [enemy id]}
## deck：ResearchCard 列表；abilities：已持有能力定义
## ctx：{hp, max_hp, strength（来自疗效与团队等级）, hp_scale（Boss 血量倍率）, boss_strength（竞品加成）, dose_max,
##       start_block / first_draw / dexterity（团队等级自带能力）}
func start_battle(enc: Dictionary, deck: Array, abilities: Array, ctx: Dictionary) -> void:
	encounter = enc
	_abilities = abilities
	_type_counts.clear()
	_events.clear()
	player = Combatant.new()
	player.name_key = "ui.player"
	player.max_hp = int(ctx.get("max_hp", 100))
	player.hp = clampi(int(ctx.get("hp", player.max_hp)), 1, player.max_hp)
	_start_hp = player.hp
	rules = ctx.get("rules", {})
	stats = {"attacks": 0, "precise": 0, "backfires": 0}
	if int(ctx.get("strength", 0)) > 0:
		player.add_status("strength", int(ctx.strength))
	if int(ctx.get("dexterity", 0)) > 0:
		player.add_status("dexterity", int(ctx.dexterity))
	_start_block = int(ctx.get("start_block", 0))
	_first_draw = int(ctx.get("first_draw", 0))
	enemies.clear()
	var is_boss := String(enc.get("kind", "fight")) == "boss"
	for enemy_id in enc.get("enemies", []):
		var def: Dictionary = _enemy_defs.get(String(enemy_id), {})
		if def.is_empty():
			continue
		var e := Enemy.from_dict(def, rng, float(ctx.get("hp_scale", 1.0)) if is_boss else 1.0)
		if is_boss and int(ctx.get("boss_strength", 0)) > 0:
			e.add_status("strength", int(ctx.boss_strength))
		e.roll_intent(rng)
		enemies.append(e)
	turn = 0
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	draw_pile = deck.duplicate()
	_shuffle(draw_pile)
	data_gained = 0
	process_gained = 0
	calibrate = 0
	intel = false
	dose = 0
	dose_max = int(ctx.get("dose_max", 4))
	_active = true
	battle_started.emit(encounter)
	_begin_turn()
	_flush()


func can_play(card: ResearchCard) -> bool:
	return _active and card != null and hand.has(card) and not card.unplayable and card.cost <= energy


## 打出手牌；target_index 为目标敌人下标（单体牌必填，缺省取第一个存活的敌人）
func play_card(card: ResearchCard, target_index := -1) -> bool:
	if not can_play(card):
		return false
	var target := _resolve_target(target_index) if card.target == "enemy" else -1
	energy -= card.cost
	hand.erase(card)
	_emit({"t": "card", "card": card, "target": target})
	var precise := target >= 0 and target < enemies.size() and enemies[target].get_status("vulnerable") > 0
	var effects := card.effects
	last_deviation = false
	if card.can_deviate() and rng.randi_range(1, 100) <= deviation_chance():
		last_deviation = true
		effects = card.deviation
		_emit({"t": "deviation", "card": card})
	var multiplier := ai_multiplier() if card.is_ai() and not last_deviation else 1.0
	for effect in effects:
		if not _active:
			break
		_apply_card_effect(effect, card, target, multiplier)
	if card.kind == "attack":
		attacks_this_turn += 1
		stats.attacks += 1
		if precise:
			stats.precise += 1
		_check_offtarget()
		if _active and not (precise and bool(rules.get("precise_free", false))):
			rule_attacks += 1
			_check_rule_offtarget()
	_on_type_played(card)
	if card.kind == "power":
		pass   # 能力牌打出后本场生效，不再回到牌堆
	elif card.exhaust:
		exhaust_pile.append(card)
	else:
		discard_pile.append(card)
	card_resolved.emit(card, last_deviation)
	_check_end()
	_flush()
	return true


func end_turn() -> void:
	if not _active:
		return
	_end_player_turn()
	if _active:
		_enemy_phase()
	if _active:
		_begin_turn()
	_flush()


## Boss 专属操作（一期「加一档剂量」）
func get_actions() -> Array:
	if not _active or not _has_mechanic("dose"):
		return []
	return [{"id": "dose", "label_key": "battle.action.dose", "enabled": dose < dose_max and not _dosed_this_turn,
		"args": [dose, dose_max]}]


func do_action(id: String) -> void:
	if not _active or id != "dose" or dose >= dose_max or _dosed_this_turn or not _has_mechanic("dose"):
		return
	_dosed_this_turn = true
	dose += 1
	player.add_status("strength", DOSE_PLAYER_STRENGTH)
	_emit({"t": "status", "side": "player", "index": 0, "id": "strength", "amount": DOSE_PLAYER_STRENGTH})
	for i in enemies.size():
		if enemies[i].is_alive() and enemies[i].mechanic == "dose":
			enemies[i].add_status("strength", DOSE_BOSS_STRENGTH)
			_emit({"t": "status", "side": "enemy", "index": i, "id": "strength", "amount": DOSE_BOSS_STRENGTH})
	_emit({"t": "mechanic", "key": "mechanic.dose.up", "args": [dose]})
	_flush()


func is_battle_active() -> bool:
	return _active


func alive_enemies() -> Array:
	return enemies.filter(func(e: Enemy) -> bool: return e.is_alive())


## 当前 AI 档位 {id, multiplier, deviation, effective}
func get_ai_tier() -> Dictionary:
	if not tier_provider.is_valid():
		return {"id": "mid", "multiplier": 1.0, "deviation": 15, "effective": 0}
	return tier_provider.call(data_gained, process_gained)


## 获得数据 / 流程；AI 档位因此变化时额外发出 ai_tier 事件（升档提示）
func _gain_ai(data: int, process: int) -> void:
	var before := get_ai_tier()
	if data > 0 and player != null:
		data += player.get_status("data_boost")   # AI 训练平台：每次获得数据额外多得
	data_gained += data
	process_gained += process
	if data != 0:
		_emit({"t": "data", "amount": data})
	if process != 0:
		_emit({"t": "mechanic", "key": "mechanic.process", "args": [process]})
	var after := get_ai_tier()
	if String(after.get("id", "")) != String(before.get("id", "")):
		_emit({"t": "ai_tier", "tier": after, "up": float(after.get("multiplier", 1.0)) > float(before.get("multiplier", 1.0))})


## AI 卡底部提示用：{multiplier, deviation, next_multiplier, need_data, process_helps}
func ai_card_info() -> Dictionary:
	var tier := get_ai_tier()
	return {"multiplier": float(tier.get("multiplier", 1.0)), "deviation": deviation_chance(),
		"next_multiplier": float(tier.get("next_multiplier", 1.0)), "need_data": int(tier.get("need_data", -1)),
		"process_helps": bool(tier.get("process_helps", false))}


func ai_multiplier() -> float:
	return float(get_ai_tier().get("multiplier", 1.0))


func deviation_chance() -> int:
	var chance := int(get_ai_tier().get("deviation", 15)) - calibrate
	for ability in _abilities:
		chance += int(ability.get("passive", {}).get("ai_deviation", 0))
	return clampi(chance, 0, 100)


## Boss 机制说明 [{key, args}]
func get_mechanic_lines() -> Array:
	var lines: Array = []
	if int(rules.get("offtarget_limit", 0)) > 0:
		lines.append({"key": "mechanic.selective", "args": [int(rules.offtarget_limit), int(rules.get("offtarget_damage", 3))]})
	if int(rules.get("enemy_ramp_every", 0)) > 0:
		lines.append({"key": "mechanic.chronic", "args": [int(rules.enemy_ramp_every)]})
	var seen := {}
	for e in enemies:
		if e.mechanic.is_empty() or seen.has(e.mechanic):
			continue
		seen[e.mechanic] = true
		match e.mechanic:
			"offtarget":
				lines.append({"key": "mechanic.offtarget", "args": [int(e.data.get("mechanic_value", 3)), OFFTARGET_DAMAGE]})
			"dose":
				lines.append({"key": "mechanic.dose", "args": [DOSE_PLAYER_STRENGTH, DOSE_BOSS_STRENGTH, dose, dose_max]})
			"dropout":
				lines.append({"key": "mechanic.dropout", "args": [DROPOUT_BLOCK]})
			_:
				lines.append({"key": "mechanic." + e.mechanic, "args": []})
	return lines


## 敌人本回合意图的实际伤害（已计入效力、药效抑制与玩家的靶点暴露）
func intent_damage(enemy: Enemy) -> int:
	if enemy.intent_damage() <= 0:
		return 0
	return _calc_damage(enemy, player, enemy.intent_damage(), true)


## 玩家对某个敌人造成的实际伤害（卡面数值预览）
func preview_damage(base: int, enemy_index := -1) -> int:
	var target: Combatant = null
	if enemy_index >= 0 and enemy_index < enemies.size():
		target = enemies[enemy_index]
	elif alive_enemies().size() == 1:
		target = alive_enemies()[0]
	return _calc_damage(player, target, base, true)


func preview_block(base: int) -> int:
	return maxi(0, base + player.get_status("dexterity"))


func get_outcome() -> Dictionary:
	return {
		"damage_taken": _start_hp - player.hp,
		"hp": player.hp,
		"data": data_gained,
		"process": process_gained,
		"intel": intel,
		"dose": dose,
		"kind": String(encounter.get("kind", "fight")),
		"stats": stats.duplicate(),
	}


# ---------- 回合流程 ----------

func _begin_turn() -> void:
	turn += 1
	attacks_this_turn = 0
	rule_attacks = 0
	_dosed_this_turn = false
	if player.get_status("retain_block") <= 0:   # 稳定平台：护盾不再每回合清零
		player.block = 0
	_emit({"t": "turn", "turn": turn})
	_ramp_enemies()
	_tick_poison(player, "player", 0)
	if _check_end():
		return
	energy = max_energy
	var auto := player.get_status("auto_block") + (_start_block if turn == 1 else 0)
	if auto > 0:
		_gain_block(player, "player", 0, auto)
	_draw(hand_size + player.get_status("pipeline") + (_first_draw if turn == 1 else 0))
	for ability in _abilities:
		var trigger := String(ability.get("trigger", ""))
		if trigger == "turn_start" or (trigger == "battle_start" and turn == 1):
			for effect in ability.get("effects", []):
				_apply_card_effect(effect, null, _resolve_target(-1), 1.0)
	_emit({"t": "energy", "energy": energy})
	turn_started.emit(turn)


func _end_player_turn() -> void:
	for card: ResearchCard in hand.duplicate():
		if card.end_turn_damage > 0:
			_emit({"t": "mechanic", "key": "mechanic.ae_card", "args": [card.end_turn_damage]})
			_hurt(player, "player", 0, card.end_turn_damage, false)
		if card.ethereal:
			exhaust_pile.append(card)
		else:
			discard_pile.append(card)
	hand.clear()
	_emit({"t": "draw", "count": 0, "hand": []})
	player.decay()
	if _check_end():
		return
	for i in enemies.size():
		var e := enemies[i]
		if e.is_alive() and e.mechanic == "dropout" and not e.damaged_this_turn:
			_gain_block(e, "enemy", i, DROPOUT_BLOCK)
			_emit({"t": "mechanic", "key": "mechanic.dropout.trigger", "args": [e.name_key, DROPOUT_BLOCK]})


func _enemy_phase() -> void:
	_emit({"t": "enemy_turn"})
	for i in enemies.size():
		var e := enemies[i]
		if not e.is_alive():
			continue
		e.block = 0
		_tick_poison(e, "enemy", i)
		if not e.is_alive():
			if _check_end():
				return
			continue
		_execute(e, i)
		if _check_end():
			return
		var metal := e.get_status("metallicize")
		if metal > 0:
			_gain_block(e, "enemy", i, metal)
		var ritual := e.get_status("ritual")
		if ritual > 0:
			e.add_status("strength", ritual)
			_emit({"t": "status", "side": "enemy", "index": i, "id": "strength", "amount": ritual})
		e.decay()
	for e in enemies:
		e.damaged_this_turn = false
		if e.is_alive():
			e.roll_intent(rng)


func _execute(e: Enemy, index: int) -> void:
	var move := e.intent
	_emit({"t": "enemy_move", "index": index, "move": move})
	if int(move.get("damage", 0)) > 0:
		for h in e.intent_hits():
			if not player.is_alive():
				break
			_attack(e, "enemy", index, player, "player", 0, int(move.damage), true)
	if int(move.get("block", 0)) > 0:
		_gain_block(e, "enemy", index, int(move.block))
	for status_id in move.get("status", {}):
		_add_status(player, "player", 0, String(status_id), int(move.status[status_id]))
	for status_id in move.get("self_status", {}):
		_add_status(e, "enemy", index, String(status_id), int(move.self_status[status_id]))
	for j in enemies.size():
		if not enemies[j].is_alive():
			continue
		for status_id in move.get("ally_status", {}):
			_add_status(enemies[j], "enemy", j, String(status_id), int(move.ally_status[status_id]))
		if j != index and int(move.get("ally_block", 0)) > 0:
			_gain_block(enemies[j], "enemy", j, int(move.ally_block))
	var add: Dictionary = move.get("add_card", {})
	if not add.is_empty() and card_factory.is_valid():
		for k in int(add.get("value", 1)):
			draw_pile.insert(rng.randi_range(0, draw_pile.size()), card_factory.call(String(add.id)))
		_emit({"t": "add_card", "id": String(add.id), "count": int(add.get("value", 1)), "pile": "draw"})


# ---------- 效果结算 ----------

func _apply_card_effect(effect: Dictionary, card: ResearchCard, target: int, multiplier: float) -> void:
	var op := String(effect.get("op", ""))
	var value := int(effect.get("value", 0))
	if ResearchCard.MAGNITUDE_OPS.has(op) and op != "self_damage":
		value = int(round(value * multiplier)) + _type_bonus(card, op)
	match op:
		"damage":
			var targets := _targets(card, target)
			for h in maxi(1, int(effect.get("times", 1))):
				for i in targets:
					_attack(player, "player", 0, enemies[i], "enemy", i, value, true)
		"block":
			_gain_block(player, "player", 0, value + player.get_status("dexterity"))
		"block_damage":
			# 防守反击：造成等于当前护盾（再加 value）的伤害
			for i in _targets(card, target):
				_attack(player, "player", 0, enemies[i], "enemy", i, player.block + value, true)
		"double_block":
			_gain_block(player, "player", 0, player.block)
		"data_damage":
			# 数据驱动：基础伤害 + 本场每获得 per 点数据 +1
			var bonus := data_gained / maxi(1, int(effect.get("per", 1)))
			for i in _targets(card, target):
				_attack(player, "player", 0, enemies[i], "enemy", i, value + bonus, true)
		"status":
			var to := String(effect.get("to", "target"))
			if to == "self":
				_add_status(player, "player", 0, String(effect.id), value)
			else:
				for i in (_alive_indices() if to == "all" else ([target] if target >= 0 else [])):
					_add_status(enemies[i], "enemy", i, String(effect.id), value)
		"self_damage":
			_hurt(player, "player", 0, value, true)
		"draw":
			_draw(value)
		"energy":
			energy += value
			_emit({"t": "energy", "energy": energy})
		"data":
			_gain_ai(value, 0)
		"process":
			_gain_ai(0, value)
		"calibrate":
			calibrate += value
		"intel":
			intel = true
			_emit({"t": "mechanic", "key": "mechanic.intel", "args": []})
		"cleanse":
			player.clear_debuffs()
			_emit({"t": "status", "side": "player", "index": 0, "id": "cleanse", "amount": 0})
		"detonate":
			if target >= 0:
				var amount := enemies[target].get_status("poison") * value
				_attack(player, "player", 0, enemies[target], "enemy", target, amount, false)
		"add_card":
			if card_factory.is_valid():
				for k in maxi(1, value):
					discard_pile.append(card_factory.call(String(effect.get("id", "noise"))))
				_emit({"t": "add_card", "id": String(effect.get("id", "noise")), "count": maxi(1, value), "pile": "discard"})


func _attack(attacker: Combatant, a_side: String, a_index: int, defender: Combatant, d_side: String, d_index: int,
		base: int, use_strength: bool) -> void:
	if not defender.is_alive() or not attacker.is_alive():
		return
	var amount := _calc_damage(attacker, defender, base, use_strength)
	_hurt(defender, d_side, d_index, amount, false)
	if defender is Enemy:
		(defender as Enemy).damaged_this_turn = true
	var thorns := defender.get_status("thorns")
	if thorns > 0 and attacker.is_alive():
		_hurt(attacker, a_side, a_index, thorns, true)


func _calc_damage(attacker: Combatant, defender: Combatant, base: int, use_strength: bool) -> int:
	var amount := float(base + (attacker.get_status("strength") if use_strength else 0))
	if attacker.get_status("weak") > 0:
		amount *= 0.75
	if defender != null and defender.get_status("vulnerable") > 0:
		amount *= 1.5
	return maxi(0, int(floor(amount)))


func _hurt(target: Combatant, side: String, index: int, amount: int, ignore_block: bool) -> void:
	var result := target.take_damage(amount, ignore_block)
	_emit({"t": "damage", "side": side, "index": index, "amount": result.lost, "blocked": result.blocked,
		"hp": target.hp, "block": target.block})
	if not target.is_alive():
		_emit({"t": "death", "side": side, "index": index})


func _gain_block(target: Combatant, side: String, index: int, amount: int) -> void:
	var gained := target.gain_block(amount)
	if gained > 0:
		_emit({"t": "block", "side": side, "index": index, "amount": gained, "block": target.block})


func _add_status(target: Combatant, side: String, index: int, id: String, amount: int) -> void:
	if amount == 0 or not target.is_alive():
		return
	target.add_status(id, amount)
	_emit({"t": "status", "side": side, "index": index, "id": id, "amount": amount})


func _tick_poison(target: Combatant, side: String, index: int) -> void:
	var poison := target.get_status("poison")
	if poison <= 0:
		return
	_hurt(target, side, index, poison, true)
	target.add_status("poison", -1)


func _check_offtarget() -> void:
	for e in enemies:
		if e.is_alive() and e.mechanic == "offtarget" and attacks_this_turn > int(e.data.get("mechanic_value", 3)):
			_emit({"t": "mechanic", "key": "mechanic.offtarget.trigger", "args": [OFFTARGET_DAMAGE]})
			stats.backfires += 1
			_hurt(player, "player", 0, OFFTARGET_DAMAGE, true)
			return


## 慢性项目：每隔 N 回合敌人整体变强一档
func _ramp_enemies() -> void:
	var every := int(rules.get("enemy_ramp_every", 0))
	if every <= 0 or turn <= 1 or (turn - 1) % every != 0:
		return
	_emit({"t": "mechanic", "key": "mechanic.chronic.trigger", "args": []})
	for i in enemies.size():
		_add_status(enemies[i], "enemy", i, "strength", 1)


## 选择性项目：本回合计入的攻击牌超过上限，每多 1 张反噬一次
func _check_rule_offtarget() -> void:
	var limit := int(rules.get("offtarget_limit", 0))
	if limit <= 0 or rule_attacks <= limit:
		return
	var damage := int(rules.get("offtarget_damage", 3))
	_emit({"t": "mechanic", "key": "mechanic.selective.trigger", "args": [damage]})
	stats.backfires += 1
	_hurt(player, "player", 0, damage, true)


## 本回合还能打几张不带破绽目标的攻击牌而不触发项目脱靶（没有项目规则时为 -1）
func rule_attacks_left() -> int:
	var limit := int(rules.get("offtarget_limit", 0))
	return maxi(0, limit - rule_attacks) if limit > 0 else -1


## Boss「活性悬崖」：本回合还能打几张攻击牌（破绽目标也计数；没有该 Boss 时为 -1）
func boss_attacks_left() -> int:
	for e in enemies:
		if e.is_alive() and e.mechanic == "offtarget":
			return maxi(0, int(e.data.get("mechanic_value", 3)) - attacks_this_turn)
	return -1


## 界面计数：两种反噬中更紧的那个（都没有时为 -1）
func safe_attacks_left() -> int:
	var a := rule_attacks_left()
	var b := boss_attacks_left()
	if a < 0:
		return b
	return a if b < 0 else mini(a, b)


## 打出这张牌会触发的反噬预告 {project, boss, exempt}：project / boss 为掉血量，exempt 表示破绽目标豁免了项目规则
func backfire_preview(card: ResearchCard, target := -1) -> Dictionary:
	var result := {"project": 0, "boss": 0, "exempt": false}
	if card == null or card.kind != "attack":
		return result
	var t := _resolve_target(target) if card.target == "enemy" else -1
	if int(rules.get("offtarget_limit", 0)) > 0:
		if t >= 0 and enemies[t].get_status("vulnerable") > 0 and bool(rules.get("precise_free", false)):
			result.exempt = true
		elif rule_attacks + 1 > int(rules.offtarget_limit):
			result.project = int(rules.get("offtarget_damage", 3))
	var left := boss_attacks_left()
	if left == 0:
		result.boss = OFFTARGET_DAMAGE
	return result


func _on_type_played(card: ResearchCard) -> void:
	if card.type == "experiment" and player.get_status("lims") > 0:
		_gain_ai(player.get_status("lims"), 0)
	_type_counts[card.type] = int(_type_counts.get(card.type, 0)) + 1
	for ability in _abilities:
		if String(ability.get("trigger", "")) != "type_played" or String(ability.get("type", "")) != card.type:
			continue
		if int(_type_counts[card.type]) % maxi(1, int(ability.get("count", 1))) == 0:
			for effect in ability.get("effects", []):
				_apply_card_effect(effect, null, -1, 1.0)


func _type_bonus(card: ResearchCard, op: String) -> int:
	if card == null:
		return 0
	var bonus := 0
	for ability in _abilities:
		var spec: Dictionary = ability.get("passive", {}).get("type_bonus", {})
		if String(spec.get("type", "")) == card.type and String(spec.get("op", "")) == op:
			bonus += int(spec.get("amount", 0))
	return bonus


func _targets(card: ResearchCard, target: int) -> Array:
	if card != null and card.target == "all":
		return _alive_indices()
	return [target] if target >= 0 else []


func _alive_indices() -> Array:
	var result: Array = []
	for i in enemies.size():
		if enemies[i].is_alive():
			result.append(i)
	return result


## 用本场的 rng 洗牌（Array.shuffle 走全局随机数，测试与模拟无法复现）
func _shuffle(cards: Array) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


func _resolve_target(index: int) -> int:
	if index >= 0 and index < enemies.size() and enemies[index].is_alive():
		return index
	var alive := _alive_indices()
	return int(alive[0]) if not alive.is_empty() else -1


func _has_mechanic(id: String) -> bool:
	for e in enemies:
		if e.is_alive() and e.mechanic == id:
			return true
	return false


func _draw(count: int) -> void:
	var drawn := 0
	for i in maxi(count, 0):
		if hand.size() >= 10:
			break
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile = discard_pile.duplicate()
			_shuffle(draw_pile)
			discard_pile.clear()
		hand.append(draw_pile.pop_back())
		drawn += 1
	if drawn > 0:
		_emit({"t": "draw", "count": drawn, "hand": hand.duplicate()})


func _check_end() -> bool:
	if not _active:
		return true
	var victory := alive_enemies().is_empty()
	if player.is_alive() and not victory:
		return false
	_active = false
	victory = player.is_alive()
	_emit({"t": "end", "victory": victory})
	battle_ended.emit(victory, get_outcome())
	return true


func _emit(event: Dictionary) -> void:
	_events.append(event)


func _flush() -> void:
	if _events.is_empty():
		return
	var batch := _events.duplicate()
	_events.clear()
	events_emitted.emit(batch)
