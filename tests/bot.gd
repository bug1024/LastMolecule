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
				game.claim_reward(_pick_reward_card(reward.cards), reward.abilities[0].id if not reward.abilities.is_empty() else "")
	return {"finished": game.is_finished(), "outcome": outcome.outcome, "reason": outcome.reason,
		"battles": battles, "steps": steps}


static func _pick_reward_card(cards: Array) -> String:
	if cards.is_empty():
		return ""
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
			preferred = 0
		"final_review":
			preferred = 0 if state.can_meet(choices[0].get("requires", {})) else (1 if state.funding > 4 else 2)
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
	game.select_card(cards[0])


## 打完一个回合（公开给测试用）
static func play_turn(manager: BattleManager) -> void:
	for action in manager.get_actions():
		if action.id == "dose" and action.enabled and manager.player.hp > 45 and manager.dose < 3:
			manager.do_action("dose")
	var guard := 0
	while manager.is_battle_active() and guard < 20:
		guard += 1
		var card := _pick_card(manager)
		if card == null:
			break
		manager.play_card(card, _weakest(manager))
	if manager.is_battle_active():
		manager.end_turn()


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
		if score > best_score:
			best_score = score
			best = card
	return best


static func _weakest(manager: BattleManager) -> int:
	var best := -1
	for i in manager.enemies.size():
		var e: Enemy = manager.enemies[i]
		if e.is_alive() and (best < 0 or e.hp < manager.enemies[best].hp):
			best = i
	return best
