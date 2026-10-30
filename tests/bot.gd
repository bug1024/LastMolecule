extends RefCounted
## 规则型机器人：用于整局回归与平衡模拟。策略刻意朴素，代表「认真但不精通」的玩家：
## 先出能力牌，按来袭伤害补防护，其余打攻击（优先残血敌人）。

const Game = preload("res://scripts/game.gd")
const NODE_PREFERENCE := {"fight": 4, "research": 4, "event": 2, "partner": 2, "platform": 3, "elite": 3, "fast_track": 1}


static func play(game: Node, max_steps: int) -> Dictionary:
	var battles := {}
	var outcome := {"outcome": "", "reason": ""}
	game.run_ended.connect(func(o: String, r: String, _s: Dictionary) -> void:
		outcome.outcome = o
		outcome.reason = r)
	var steps := 0
	while not game.is_finished() and steps < max_steps:
		steps += 1
		match game._phase:
			Game.RoundPhase.DESIGN:
				_design(game)
			Game.RoundPhase.IDLE:
				_choose_node(game)
			Game.RoundPhase.WAITING_EVENT:
				_choose_event(game)
			Game.RoundPhase.WAITING_CARD:
				_choose_card(game)
			Game.RoundPhase.BATTLE:
				var manager: BattleManager = game.get_battle_manager()
				var key := "%s/%s" % [game.state.stage, game.get_battle_kind()]
				var entry: Array = battles.get(key, [0, 0])
				var ended := []
				var callback := func(v: bool, _o: Dictionary) -> void: ended.append(v)
				manager.battle_ended.connect(callback)
				var guard := 0
				while manager.is_battle_active() and guard < 60:
					guard += 1
					play_turn(manager)
				manager.battle_ended.disconnect(callback)
				entry[1] += 1
				if ended == [true]:
					entry[0] += 1
				battles[key] = entry
			Game.RoundPhase.REWARD:
				var reward: Dictionary = game._pending_reward
				game.claim_reward(_pick_reward_card(reward.cards, game), reward.abilities[0].id if not reward.abilities.is_empty() else "")
	return {"finished": game.is_finished(), "outcome": outcome.outcome, "reason": outcome.reason,
		"battles": battles, "steps": steps}


## 分子设计：开局按预设方案摆放；里程碑修饰时按 _best_tweak 换一个取代基（找不到就不改）
static func _design(game: Node) -> void:
	if game.get_design_mode() == "initial":
		game.molecule.apply_preset(mol_preset)
		game.submit_molecule(game.molecule.sites.duplicate())
		return
	var tweak := _best_tweak(game)
	game.submit_molecule(tweak if not tweak.is_empty() else game.molecule.sites.duplicate())


## 只换一个取代基（不动连接位），让下一阶段的分子考验通过；多个方案时取属性总和最高的
static func _best_tweak(game: Node) -> Dictionary:
	var mol: Molecule = game.molecule
	var stage := String(game._next_stage())
	if not bool(mol.exam_result(stage).get("has", false)) or bool(mol.exam_result(stage).passed):
		return {}
	var best := {}
	var best_score := -1
	for site in Molecule.config().get("sites", []):
		if String(site.type) == "linker":
			continue
		for frag in mol.inventory:
			if not Molecule.can_place(String(frag), String(site.id)):
				continue
			var trial := Molecule.from_dict(mol.to_dict())
			var placement: Dictionary = trial.sites.duplicate()
			placement[String(site.id)] = String(frag)
			if not trial.apply_layout(placement) or not bool(trial.exam_result(stage).passed):
				continue
			var score := 0
			for v in trial.properties().values():
				score += int(v)
			score -= trial.open_alerts() * 3
			if score > best_score:
				best_score = score
				best = placement
	return best


## 看懂分子的玩家：拿契合分子强项的卡；溶解度差就要制剂卡、少拿临床卡
static func _mol_score(game: Node, card: Dictionary) -> int:
	if not mol_aware or game.molecule == null:
		return 0
	var p: Dictionary = game.molecule.properties()
	var score: int = game.molecule.strong_fits(card).size() * 2
	if int(p.solubility) <= 1:
		if (card.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return e.op == "formulate"):
			score += 3
		elif String(card.get("type", "")) == "clinical":
			score -= 2
	return score


static func _pick_reward_card(cards: Array, game: Node = null) -> String:
	if cards.is_empty():
		return ""
	if mol_aware and game != null:
		var best: Dictionary = {}
		var best_score := 0
		for c in cards:
			var sc := _mol_score(game, c)
			if sc > best_score:
				best_score = sc
				best = c
		if not best.is_empty():
			return String(best.id)
	if not build.is_empty():
		# 偏向构筑：有本套路的牌就拿（稀有优先），没有就按普通方式挑一张
		var fits := cards.filter(func(c: Dictionary) -> bool: return _fits_build(c))
		fits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return RARITY_ORDER.find(String(a.get("rarity", "common"))) > RARITY_ORDER.find(String(b.get("rarity", "common"))))
		if not fits.is_empty():
			return String(fits[0].id)
	for card in cards:
		if String(card.get("rarity", "")) != "common":
			return String(card.id)
	return String(cards[0].id)


static func _choose_node(game: Node) -> void:
	var map: ResearchMap = game.get_map()
	var choices: Array = map.get_choices()
	var layer: Array = map.get_layers()[map.get_layer_index() + 1]
	var hp: int = 100 - game.state.safety_risk
	var best := int(choices[0])
	var best_score := -999
	for c in choices:
		var type := String(layer[c].type)
		var score := int(NODE_PREFERENCE.get(type, 0))
		if type == "elite" and hp < 65:
			score = -1
		if type == "platform" and hp < 60:
			score = 6
		if score > best_score:
			best_score = score
			best = int(c)
	game.choose_node(best)


static func _choose_event(game: Node) -> void:
	var event: Dictionary = game._current_event
	var state: ProjectState = game.state
	var choices: Array = event.get("choices", [])
	var event_id := String(event.get("id", ""))
	var preferred := -1
	match event_id:
		"partner":
			preferred = 0 if state.funding < 15 else 2
		"platform":
			preferred = 0 if state.safety_risk > 35 else 1
		"fast_track":
			preferred = 1
		"milestone":
			preferred = mini(decision_index, choices.size() - 2) if choices.size() > 2 else 0
			if mol_aware and game.molecule != null and not _best_tweak(game).is_empty():
				for i in choices.size():
					if String(choices[i].get("action", "")) == "modify_molecule":
						preferred = i
		"final_review":
			preferred = 0 if state.can_meet(choices[0].get("requires", {})) else (1 if state.funding > 4 else choices.size() - 1)
			if preferred == 1 and state.data < game.get_final_data_min():
				for i in choices.size():
					if String(choices[i].get("label_key", "")) == "final.data_study":
						preferred = i
	if preferred >= 0 and preferred < choices.size() and state.can_meet(choices[preferred].get("requires", {})):
		game.resolve_event_choice(event_id, preferred)
		return
	var best := -1
	var best_score := -100000
	for i in choices.size():
		var choice: Dictionary = choices[i]
		if not state.can_meet(choice.get("requires", {})) or String(choice.get("action", "")) == "terminate":
			continue
		var fx: Dictionary = choice.get("effects", {})
		var score := int(fx.get("efficacy", 0)) * 3 + int(fx.get("research_progress", 0)) \
			+ int(fx.get("funding", 0)) * (3 if state.funding < 12 else 1) - int(fx.get("safety_risk", 0)) * 2 \
			+ int(fx.get("data", 0)) - int(fx.get("year", 0)) * 2
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		best = choices.size() - 1
	game.resolve_event_choice(event_id, best)


static func _choose_card(game: Node) -> void:
	var cards: Array = game._offered_cards
	if game._pick_purpose == "remove":
		for card in cards:
			if card.id in ["mol_hit", "exp_assay"]:
				game.select_card(card)
				return
		game.skip_cards()
		return
	if game.get_pick_cost() > game.state.funding - 4:
		game.skip_cards()
		return
	if not build.is_empty() and game._pick_purpose in ["add", "buy"]:
		for card in cards:
			if _fits_build({"type": card.type, "id": card.id, "effects": card.effects}):
				game.select_card(card)
				return
	game.select_card(cards[0])


## 打完一个回合（公开给测试用）
const RARITY_ORDER := ["common", "rare", "epic"]
## 偏向构筑（模拟用，有本套路的牌就优先拿和优先打）："" 为不挑牌；类型名（molecular / experiment / clinical / ai / process）按卡牌类型挑；
## "poison" 按效果挑（中毒 / 引爆）
static var build := ""
static var mol_preset := "balanced"   # 分子方案：potent / balanced / selective（开局设计用）
static var mol_aware := false         # 选卡时是否顺着分子的长短处挑（模拟「看懂分子的玩家」）
static var decision_index := 0     # 项目专属里程碑决策选第几个（模拟不同决策）
static var respect_rules := true   # false 时无视项目规则一味猛攻（模拟「攻击最高的牌全拿」）


static func play_turn(manager: BattleManager) -> void:
	for action in manager.get_actions():
		if action.id == "dose" and action.enabled and manager.player.hp > 45 and manager.dose < 3:
			manager.do_action("dose")
	var guard := 0
	while manager.is_battle_active() and guard < 20:
		guard += 1
		var card := _pick_card(manager)
		if card == null or (respect_rules and card.kind == "attack" and manager.rule_attacks_left() == 0 \
				and not _precise(manager, card)):
			break
		manager.play_card(card, _target(manager))
	if manager.is_battle_active():
		manager.end_turn()


static func _fits_build(card: Dictionary) -> bool:
	if build == "poison":
		return (card.get("effects", []) as Array).any(func(e: Dictionary) -> bool:
			return e.get("op", "") == "detonate" or (e.get("op", "") == "status" and e.get("id", "") == "poison"))
	return String(card.get("type", "")) == build


static func _pick_card(manager: BattleManager) -> ResearchCard:
	var incoming := 0
	for e in manager.alive_enemies():
		incoming += manager.intent_damage(e) * e.intent_hits()
	var need_block := incoming - manager.player.block > 4
	var best: ResearchCard = null
	var best_score := -1
	for card: ResearchCard in manager.hand:
		if not manager.can_play(card):
			continue
		var score := 1
		var blocks := card.effects.any(func(e: Dictionary) -> bool: return e.op == "block")
		match card.kind:
			"power":
				score = 9
			"attack":
				score = 5
			"skill":
				score = 6 if blocks and need_block else 4
		if card.cost == 0:
			score += 1
		if not build.is_empty() and _fits_build({"type": card.type, "effects": card.effects}) and (need_block or not blocks or card.kind == "power"):
			score += 2   # 偏向构筑：优先打出本套路的牌（纯护盾牌只在需要挡伤害时优先）
		if card.effects.any(func(e: Dictionary) -> bool: return e.op == "block_damage"):
			score = 9 if manager.player.block >= 8 else 2   # 防守反击：先叠护盾再打
		if respect_rules and manager.rule_attacks_left() >= 0 and _vulnerable_target(manager) < 0 \
				and card.effects.any(func(e: Dictionary) -> bool: return e.op == "status" and e.get("id", "") == "vulnerable"):
			score += 3   # 选择性项目：先打出破绽，后面的攻击就不算脱靶
		if respect_rules and card.kind == "attack" and manager.rule_attacks_left() == 0:
			var t := _target(manager)
			if card.target != "enemy" or t < 0 or manager.enemies[t].get_status("vulnerable") <= 0:
				score = -1 if manager.player.hp > 30 else 0   # 会脱靶：留到下回合
		if score > best_score:
			best_score = score
			best = card
	return best


static func _precise(manager: BattleManager, card: ResearchCard) -> bool:
	var t := _target(manager)
	return card.target == "enemy" and t >= 0 and manager.enemies[t].get_status("vulnerable") > 0


## 遵守项目规则时优先打带破绽的敌人
static func _target(manager: BattleManager) -> int:
	if respect_rules and manager.rule_attacks_left() >= 0:
		var v := _vulnerable_target(manager)
		if v >= 0:
			return v
	return _weakest(manager)


static func _vulnerable_target(manager: BattleManager) -> int:
	var best := -1
	for i in manager.enemies.size():
		var e: Enemy = manager.enemies[i]
		if e.is_alive() and e.get_status("vulnerable") > 0 and (best < 0 or e.hp < manager.enemies[best].hp):
			best = i
	return best


static func _weakest(manager: BattleManager) -> int:
	var best := -1
	for i in manager.enemies.size():
		var e: Enemy = manager.enemies[i]
		if e.is_alive() and (best < 0 or e.hp < manager.enemies[best].hp):
			best = i
	return best
