extends SceneTree
## 运行：Godot --headless --path . --script tests/run_tests.gd
## 加 -- --sim=N 额外输出 N 局机器人模拟的胜率统计（平衡调参用）

const Game = preload("res://scripts/game.gd")
const Bot = preload("res://tests/bot.gd")
var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	Company.default_save_path = ""
	GameSettings.save_path = ""
	RunSave.save_path = ""
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _new_game(seed_value := 1024) -> Node:
	var game := Game.new()
	root.add_child(game)
	game.reseed(seed_value)
	return game


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var sim := _arg_int("--sim=")
	if sim > 0:
		_simulate(sim)
		quit(0)
		return
	_test_effects()
	_test_company()
	_test_map_generation()
	_test_node_time_cost()
	_test_efficacy_strength()
	_test_combat_basics()
	_test_combat_statuses()
	_test_ai_deviation()
	_test_boss_mechanics()
	_test_battle_flow()
	_test_player_levels()
	_test_ai_next_tier()
	_test_upgrade_preview()
	_test_run_save()
	_test_card_roles()
	_test_competition()
	_test_milestone_terminate()
	_test_bot_runs()
	await _test_ui_smoke()
	await _test_restart()
	await _test_ending_and_menu()
	await _test_title_screen()
	print("%d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _arg_int(prefix: String) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return int(arg.trim_prefix(prefix))
	return 0


# ---------- 属性与公司 ----------

func _test_effects() -> void:
	var state := ProjectState.new()
	state.efficacy = 30
	var deltas := state.apply_effects({"set_efficacy": 90, "efficacy": 20})
	_expect(state.efficacy == 100 and deltas.get("efficacy") == 70,
		"Absolute and additive effects must report the combined clamped delta")
	state.apply_effects({"set_funding": -10, "set_year": 0, "data": -5})
	_expect(state.funding == 0 and state.year == 1 and state.data == 0, "Effects must respect bounds")
	_expect(not state.can_meet({"battle_won": true}), "Milestone continue requires a won stage battle")
	state.stage_battle_won = true
	_expect(state.can_meet({"battle_won": true}), "Won stage battle unlocks continue")


func _test_company() -> void:
	var company := Company.new()
	_expect(company.process_level() == 0 and is_equal_approx(company.utilization(0), 0.4), "Fresh company starts at level 0")
	_expect(company.tier_for(company.effective_data(10, 0)).id == "low", "Little data keeps AI in the low tier")
	company.data = 120
	_expect(company.process_level() == 2, "Company data thresholds raise the process level")
	_expect(company.effective_data(0, 0) == int(40 * company.utilization(0)), "Inherited company data is capped")
	var summary := company.settle_run(50, "terminated", 20)
	_expect(summary.data_saved == 30 and summary.funding_carry == 6, "Termination saves 60% data and carries 30% funding")
	_expect(company.take_start_bonus() == 6 and company.take_start_bonus() == 0, "Start bonus is consumed once")
	summary = company.settle_run(50, "failed", 20)
	_expect(summary.data_saved == 15 and summary.funding_carry == 0, "Failure saves 30% data and no funding")
	company.settle_run(40, "approved", 5, {"stage": "获批上市", "year": 9})
	company.settle_run(40, "approved", 5, {"stage": "获批上市", "year": 11})
	_expect(company.history.size() == 4 and company.history[0].outcome == "approved" and company.history[0].year == 11,
		"Run history keeps newest records first")
	_expect(company.best_years == 9, "Fastest approval keeps the lowest year count")
	for i in 20:
		company.settle_run(0, "failed", 0)
	_expect(company.history.size() == Company.HISTORY_LIMIT, "Run history is capped")
	company.reset()
	_expect(company.runs == 0 and company.data == 0 and company.history.is_empty(), "Reset clears the archive")


# ---------- 地图与节点 ----------

func _test_map_generation() -> void:
	var rng := RandomNumberGenerator.new()
	for s in 30:
		rng.seed = s
		var map := ResearchMap.new()
		map.generate("临床前研究", rng)
		var layers := map.get_layers()
		_expect(layers.size() == 7 and layers[5][0].type == "boss" and layers[6][0].type == "milestone",
			"Each stage map ends with the boss then the milestone")
		_expect(layers[0].all(func(n: Dictionary) -> bool: return n.type == "fight"), "The first layer is all fights")
		_expect(layers[4].all(func(n: Dictionary) -> bool: return n.type == "platform"), "The layer before the boss is all rest")
		_expect(layers[1].all(func(n: Dictionary) -> bool: return n.type != "elite"), "Elites never appear in layer 2")
		for i in layers.size() - 1:
			var reached := {}
			for node in layers[i]:
				_expect(not node.next.is_empty(), "Every node must lead somewhere")
				for t in node.next:
					reached[t] = true
			_expect(reached.size() == layers[i + 1].size(), "Every node must be reachable")


func _test_node_time_cost() -> void:
	var game := _new_game()
	var year: int = game.state.year
	var funding: int = game.state.funding
	game.choose_node(99)
	_expect(game.state.year == year and game.get_months() == 0, "Unreachable nodes are rejected")
	game._pass_time(8)
	_expect(game.state.year == year and game.get_months() == 8, "Months accumulate within a year")
	game._pass_time(4)
	_expect(game.state.year == year + 1 and game.state.funding == funding - 2 and game.get_months() == 0,
		"A full year advances the year and charges the yearly cost")
	game.choose_node(game.get_map().get_choices()[0])
	_expect(game._phase == Game.RoundPhase.BATTLE and game.get_battle_kind() == "fight", "The first layer starts a fight")
	game.free()


func _test_efficacy_strength() -> void:
	var game := _new_game()
	game.state.efficacy = 25
	_expect(game.get_efficacy_strength() == 0, "Starting efficacy gives no strength")
	game.state.efficacy = 61
	_expect(game.get_efficacy_strength() == 2, "Every 20 efficacy above 20 grants 1 strength")
	game.state.research_progress = 50
	_expect(is_equal_approx(game.get_boss_info().hp_scale, 0.7), "Research progress weakens the boss up to 30%")
	game.free()


# ---------- 战斗 ----------

func _card(card_id: String, upgrade := false) -> ResearchCard:
	for data in JsonData.load_dict("res://data/cards.json").cards:
		if data.id == card_id:
			return ResearchCard.from_dict(data, upgrade)
	return null


func _manager(enemy_ids: Array, deck_ids: Array, context := {}, kind := "fight") -> BattleManager:
	var manager := BattleManager.new()
	root.add_child(manager)
	manager.rng.seed = 7
	manager.card_factory = func(card_id: String) -> ResearchCard: return _card(card_id)
	var deck: Array = []
	for card_id in deck_ids:
		deck.append(_card(card_id))
	var ctx := {"hp": 80, "max_hp": 100}
	ctx.merge(context, true)
	manager.start_battle({"id": "test", "kind": kind, "enemies": enemy_ids}, deck, [], ctx)
	return manager


func _hand_card(manager: BattleManager, card_id: String) -> ResearchCard:
	for card in manager.hand:
		if card.id == card_id:
			return card
	return null


func _test_combat_basics() -> void:
	var manager := _manager(["poor_solubility"], ["mol_hit", "mol_hit", "mol_target", "exp_assay", "exp_assay"])
	var enemy: Enemy = manager.enemies[0]
	_expect(manager.energy == 3 and manager.hand.size() == 5, "Turn starts with 3 energy and 5 cards")
	var hp := enemy.hp
	manager.play_card(_hand_card(manager, "mol_hit"))
	_expect(enemy.hp == hp - 6, "Strike deals its damage")
	manager.play_card(_hand_card(manager, "mol_target"))
	_expect(enemy.hp == hp - 14 and enemy.get_status("vulnerable") == 2, "Target lock deals damage and applies vulnerable")
	_expect(manager.energy == 0 and not manager.can_play(_hand_card(manager, "mol_hit")), "Cards cost energy")
	manager.free()

	manager = _manager(["poor_solubility"], ["mol_hit", "mol_hit", "mol_hit", "mol_hit", "mol_hit"])
	enemy = manager.enemies[0]
	enemy.add_status("vulnerable", 1)
	hp = enemy.hp
	manager.play_card(manager.hand[0])
	_expect(enemy.hp == hp - 9, "Vulnerable adds 50% damage")
	manager.player.add_status("weak", 1)
	manager.player.add_status("strength", 2)
	hp = enemy.hp
	manager.play_card(manager.hand[0])
	_expect(enemy.hp == hp - 9, "Strength adds per hit, weak cuts 25% before vulnerable")
	manager.free()

	manager = _manager(["off_target"], ["exp_assay", "exp_assay", "exp_assay", "exp_assay", "exp_assay"])
	enemy = manager.enemies[0]
	enemy.intent = {"id": "bind", "intent": "attack", "damage": 8}
	manager.play_card(manager.hand[0])
	manager.play_card(manager.hand[0])
	var player_hp := manager.player.hp
	manager.end_turn()
	_expect(manager.player.hp == player_hp and manager.player.block == 0, "Block absorbs the intent and clears next turn")
	enemy.intent = {"id": "bind", "intent": "attack", "damage": 8}
	player_hp = manager.player.hp
	manager.end_turn()
	_expect(manager.player.hp == player_hp - 8, "Unblocked attacks hit HP")
	manager.free()


func _test_combat_statuses() -> void:
	var manager := _manager(["poor_solubility"], ["clin_dosing", "clin_endpoint", "exp_assay", "exp_assay", "exp_assay"])
	var enemy: Enemy = manager.enemies[0]
	manager.play_card(_hand_card(manager, "clin_dosing"))
	_expect(enemy.get_status("poison") == 6, "Sustained dosing applies poison")
	var hp := enemy.hp
	manager.play_card(_hand_card(manager, "clin_endpoint"), 0)
	_expect(enemy.hp == hp - 12, "Endpoint detonates poison stacks")
	enemy.block = 0
	hp = enemy.hp
	enemy.intent = {"id": "noop", "intent": "buff"}
	manager.end_turn()
	_expect(enemy.hp == hp - 6 and enemy.get_status("poison") == 5, "Poison ticks at the start of the enemy turn")
	manager.free()

	manager = _manager(["genotox"], ["mol_hit", "mol_hit", "mol_hit", "mol_hit", "mol_hit"])
	var player_hp := manager.player.hp
	var thorns := manager.enemies[0].get_status("thorns")
	manager.play_card(manager.hand[0])
	_expect(thorns > 0 and manager.player.hp == player_hp - thorns, "Thorns hurt the attacker")
	manager.free()

	manager = _manager(["poor_solubility"], ["proc_sop", "proc_qbd", "exp_assay", "exp_assay", "exp_assay"])
	manager.play_card(_hand_card(manager, "proc_qbd"))
	manager.play_card(_hand_card(manager, "exp_assay"))
	_expect(manager.player.block == 7, "Dexterity adds to block")
	_expect(not manager.discard_pile.any(func(c: ResearchCard) -> bool: return c.id == "proc_qbd"),
		"Power cards leave the deck for this battle")
	manager.free()


func _test_ai_deviation() -> void:
	var manager := _manager(["poor_solubility"], ["ai_screen", "ai_screen", "ai_screen", "ai_screen", "ai_screen"])
	var enemy: Enemy = manager.enemies[0]
	manager.tier_provider = func(_d: int, _p: int) -> Dictionary:
		return {"id": "high", "multiplier": 2.0, "deviation": 0, "effective": 80}
	var hp := enemy.hp
	manager.play_card(manager.hand[0])
	_expect(enemy.hp == hp - 18 and not manager.last_deviation and manager.data_gained == 1,
		"High tier multiplies AI card damage")
	manager.tier_provider = func(_d: int, _p: int) -> Dictionary:
		return {"id": "low", "multiplier": 0.5, "deviation": 100, "effective": 0}
	hp = enemy.hp
	var discard := manager.discard_pile.size()
	manager.play_card(manager.hand[0])
	_expect(enemy.hp == hp and manager.last_deviation and manager.discard_pile.any(func(c: ResearchCard) -> bool: return c.id == "noise"),
		"Model deviation voids the card and adds noise data")
	_expect(manager.discard_pile.size() == discard + 2, "Deviated card and the noise card go to the discard pile")
	manager.free()


func _test_ai_next_tier() -> void:
	var company := Company.new()
	var step := company.next_tier_step(10, 0)
	_expect(step.next_id == "mid" and step.need_data == 40 and not step.process_helps,
		"Low tier reports the data needed to reach mid")
	step = company.next_tier_step(45, 0)
	_expect(step.need_data == 5 and step.process_helps, "One more process level can also lift the tier")
	_expect(company.next_tier_step(200, 0).need_data == -1, "Top tier reports no next step")
	var manager := _manager(["poor_solubility"], ["ai_governance", "ai_governance", "ai_governance", "ai_governance", "ai_governance"])
	manager.tier_provider = func(d: int, _p: int) -> Dictionary:
		return {"id": "low" if d < 2 else "mid", "multiplier": 0.5 if d < 2 else 1.0, "deviation": 30, "effective": d,
			"next_multiplier": 1.0, "need_data": maxi(0, 2 - d)}
	var seen: Array = []
	manager.events_emitted.connect(func(events: Array) -> void: seen.append_array(events))
	manager.play_card(manager.hand[0])
	var tier_events := seen.filter(func(e: Dictionary) -> bool: return e.t == "ai_tier")
	_expect(tier_events.size() == 1 and bool(tier_events[0].up), "Gaining data across a tier boundary emits an AI tier-up event")
	_expect(manager.ai_card_info().need_data == 0 and is_equal_approx(manager.ai_card_info().multiplier, 1.0),
		"AI card info reflects the new tier")
	_expect(CardFace.ai_foot({"multiplier": 0.5, "deviation": 30, "need_data": 6, "next_multiplier": 1.0}).contains("6"),
		"AI card footer names the data still needed")
	manager.free()


func _test_upgrade_preview() -> void:
	var game := _new_game()
	var options: Array = game._unique_deck_cards(true)
	var hit: ResearchCard = null
	for c in options:
		if c.id == "mol_hit":
			hit = c
	_expect(hit != null and hit.copies == 4 and hit.upgrade_preview != null and hit.upgrade_preview.upgraded,
		"Upgrade options count copies and carry an upgraded preview")
	var diff := ResearchCard.upgrade_diff(hit, hit.upgrade_preview)
	_expect(diff.size() >= 1 and diff[0].contains("→"), "Upgrade diff lists before → after numbers")
	var rows: Array = hit.upgrade_preview.effect_rows({"compare_to": hit})
	_expect(int(rows[0].change) == 1, "Upgraded numbers are marked as raised")
	game.upgraded["mol_hit"] = true
	_expect(not game._unique_deck_cards(true).any(func(c: ResearchCard) -> bool: return c.id == "mol_hit"),
		"Upgraded cards are at max level and no longer offered")
	game.free()


func _test_run_save() -> void:
	RunSave.save_path = "user://test_run.json"
	RunSave.clear()
	var a := _new_game(77)
	a.deck.append("ai_generate")
	a.upgraded["mol_hit"] = true
	a.player_xp = 5
	a.choose_node(int(a._map.get_choices()[0]))
	_expect(RunSave.exists() and int(RunSave.read().phase) == a.RoundPhase.BATTLE, "Starting a battle autosaves the run")
	a._battle_manager._active = false
	a._phase = a.RoundPhase.IDLE
	a._offer_platform()
	var snapshot: Dictionary = a.to_save()
	RunSave.resume_requested = true
	var b := Game.new()
	root.add_child(b)
	_expect(b.resumed and not RunSave.resume_requested, "Continue loads the saved run")
	_expect(b.deck == a.deck and b.upgraded.has("mol_hit") and b.player_xp == 5 and b.months == a.months,
		"Deck, upgrades, team XP and time survive save/load")
	_expect(b.state.to_dict() == a.state.to_dict() and b._map.get_layer_index() == a._map.get_layer_index()
		and b._map.get_choices() == a._map.get_choices(), "Project state and map position survive save/load")
	_expect(b.competition.to_dict().competitors.size() == a.competition.competitors.size(), "Competitors survive save/load")
	_expect(b.rng.state == a.rng.state, "Random state survives save/load")
	var offered: Array = []
	b.event_offered.connect(func(event: Dictionary, _gate: bool) -> void: offered.append(String(event.id)))
	b.replay_pending()
	_expect(offered == ["platform"], "An open event is offered again after continuing")
	b._finish("terminated", "msg.terminated")
	_expect(not RunSave.exists(), "Finishing the run deletes the save")
	RunSave.write(snapshot)
	snapshot.phase = a.RoundPhase.BATTLE
	RunSave.write(snapshot)
	RunSave.resume_requested = true
	var c := Game.new()
	root.add_child(c)
	c.replay_pending()
	_expect(c._battle_manager.is_battle_active(), "Quitting mid-battle restarts that battle on continue")
	var d := Game.new()
	root.add_child(d)
	_expect(not d.resumed and not RunSave.exists(), "Starting a new project discards the old save")
	for g in [a, b, c, d]:
		g.free()
	RunSave.save_path = ""


func _test_boss_mechanics() -> void:
	var manager := _manager(["activity_cliff"], ["mol_hit", "mol_hit", "mol_hit", "mol_hit", "clin_site"], {}, "boss")
	manager.play_card(_hand_card(manager, "clin_site"))
	var hp := manager.player.hp
	for i in 3:
		manager.play_card(_hand_card(manager, "mol_hit"))
	_expect(manager.player.hp == hp, "Three attacks are safe against the activity cliff")
	manager.play_card(_hand_card(manager, "mol_hit"))
	_expect(manager.player.hp == hp - BattleManager.OFFTARGET_DAMAGE, "A fourth attack triggers off-target backlash")
	manager.free()

	manager = _manager(["dlt"], ["exp_assay", "exp_assay", "exp_assay", "exp_assay", "exp_assay"], {}, "boss")
	_expect(manager.get_actions()[0].enabled, "Dose escalation is offered in the phase 1 boss")
	manager.do_action("dose")
	_expect(manager.dose == 1 and manager.player.get_status("strength") == 2 and manager.enemies[0].get_status("strength") == 1,
		"Each dose level buffs both sides")
	_expect(not manager.get_actions()[0].enabled, "Dose can rise once per turn")
	manager.free()

	manager = _manager(["center_pd", "center_ae", "center_drop"], ["mol_hit", "mol_hit", "mol_hit", "mol_hit", "mol_hit"], {}, "boss")
	manager.play_card(manager.hand[0], 0)
	manager._end_player_turn()
	_expect(manager.enemies[0].block == 0 and manager.enemies[1].block == BattleManager.DROPOUT_BLOCK,
		"Untouched trial centers gain block from dropout")
	manager.free()

	manager = _manager(["progression"], ["exp_assay", "exp_assay", "exp_assay", "exp_assay", "exp_assay"], {}, "boss")
	_expect(manager.enemies[0].intent.id == "invade", "Disease progression opens by invading")
	var ritual := manager.enemies[0].get_status("ritual")
	manager.end_turn()
	var ae := manager.draw_pile.filter(func(c: ResearchCard) -> bool: return c.id == "ae_card").size() \
		+ manager.hand.filter(func(c: ResearchCard) -> bool: return c.id == "ae_card").size()
	_expect(ae == 2 and ritual > 0 and manager.enemies[0].get_status("strength") == ritual, "Progression seeds adverse events and grows stronger")
	manager.free()


func _test_battle_flow() -> void:
	var game := _new_game()
	var deck_size: int = game.deck.size()
	game.choose_node(game.get_map().get_choices()[0])
	var manager: BattleManager = game.get_battle_manager()
	manager.enemies[0].hp = 1
	for i in range(1, manager.enemies.size()):
		manager.enemies[i].hp = 0
	var funding: int = game.state.funding
	manager.play_card(manager.hand.filter(func(c: ResearchCard) -> bool: return c.kind == "attack" and not c.is_ai())[0], 0)
	_expect(game._phase == Game.RoundPhase.REWARD and game._pending_reward.abilities.is_empty()
		and game.state.funding == funding + 2, "A normal fight pays funding and offers cards only")
	var reward: Dictionary = game._pending_reward
	game.claim_reward("forged", "")
	_expect(game._phase == Game.RoundPhase.REWARD, "Reject rewards outside the offered candidates")
	game.claim_reward(reward.cards[0].id, "")
	_expect(game.is_idle() and game.deck.size() == deck_size + 1, "Claiming a fight reward returns to the map")
	game.free()

	game = _new_game()
	game._start_battle("boss")
	manager = game.get_battle_manager()
	manager.enemies[0].hp = 1
	var efficacy: int = game.state.efficacy
	manager.player.add_status("strength", 5)
	manager.play_card(manager.hand.filter(func(c: ResearchCard) -> bool: return c.kind == "attack" and not c.is_ai())[0], 0)
	_expect(game._phase == Game.RoundPhase.REWARD and game._pending_reward.abilities.size() == 2
		and game.state.efficacy == efficacy + 12, "Beating a boss raises efficacy and offers abilities")
	reward = game._pending_reward
	game.claim_reward(reward.cards[0].id, reward.abilities[0].id)
	_expect(game._current_event.get("id", "") == "milestone", "Boss rewards lead to the milestone")
	game.free()

	game = _new_game()
	var ended := []
	game.run_ended.connect(func(o: String, r: String, _s: Dictionary) -> void: ended.append([o, r]))
	game._start_battle("fight")
	manager = game.get_battle_manager()
	manager.player.hp = 1
	for e in manager.enemies:
		e.intent = {"id": "x", "intent": "attack", "damage": 50}
	manager.end_turn()
	_expect(ended == [["failed", "msg.battle_lost"]] and game.state.safety_risk == 100,
		"Losing a battle halts the project")
	game.free()


func _test_player_levels() -> void:
	var game := _new_game()
	_expect(game.get_player_level() == 1 and game.get_player_bonus().is_empty(), "The team starts at level 1 without perks")
	game.player_xp = 8
	_expect(game.get_player_level() == 3 and int(game.get_player_bonus().strength) == 1, "XP thresholds unlock levels and perks")
	game.state.efficacy = 25
	game._start_battle("fight")
	var manager: BattleManager = game.get_battle_manager()
	_expect(manager.player.get_status("strength") == 1 and manager.player.block == 4, "Level perks apply at battle start")
	var leveled := []
	game.player_leveled.connect(func(level: int) -> void: leveled.append(level))
	game.player_xp = 13
	game._battle_kind = "elite"
	for e in manager.enemies:
		e.hp = 0
	manager._check_end()
	_expect(game.player_xp == 15 and leveled == [4], "Winning grants XP and announces level ups")
	game.free()


func _test_card_roles() -> void:
	_expect(_card("mol_hit").role() == "attack" and _card("exp_assay").role() == "defend"
		and _card("proc_sop").role() == "power" and _card("clin_protocol").role() == "skill" and _card("noise").role() == "status",
		"Cards expose a clear role for their badge")
	var rows: Array = _card("mol_analog").effect_rows({"damage": func(v: int) -> int: return v + 2})
	_expect(rows.size() == 1 and rows[0].number == "6×2" and rows[0].change == 1, "Effect rows show live numbers and highlight increases")


func _test_competition() -> void:
	var game := _new_game()
	var bar: int = game.get_final_efficacy_bar()
	game.competition.competitors = [{"name_key": "competitor.a", "stage": 4, "status": "active", "chance": 100}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	game.competition._config["fail_chance"] = 0
	game.competition.tick_year(rng)
	_expect(game.get_final_efficacy_bar() == bar + int(game.competition._config.approval_efficacy_bar)
		and game.competition.boss_strength_bonus == 1,
		"Competitor approval raises the review bar and boss strength")
	game.free()


func _test_milestone_terminate() -> void:
	var game := _new_game()
	game.state.data = 20
	var ended := []
	game.run_ended.connect(func(o: String, _r: String, s: Dictionary) -> void: ended.append([o, s]))
	game._offer_milestone()
	game.resolve_event_choice("milestone", 0)
	_expect(game._phase == Game.RoundPhase.WAITING_EVENT, "Continue is locked without beating the boss")
	game.resolve_event_choice("milestone", 1)
	_expect(not ended.is_empty() and ended[0][0] == "terminated" and ended[0][1].data_saved == 12,
		"Voluntary termination ends the run and banks data")
	game.free()


# ---------- 整局 ----------

func _test_bot_runs() -> void:
	var approved := 0
	for s in 40:
		var game := _new_game(s)
		var result: Dictionary = Bot.play(game, 600)
		_expect(result.finished, "Seed %d run must terminate without a softlock" % s)
		if result.outcome == "approved":
			approved += 1
		game.free()
	_expect(approved > 0, "At least one of 40 bot runs must reach approval")


func _simulate(runs: int) -> void:
	var outcomes := {}
	var stages := {}
	var battles := {}
	var years := 0
	var ends := {}
	for s in runs:
		var game := _new_game(10000 + s)
		var result: Dictionary = Bot.play(game, 600)
		outcomes[result.outcome] = int(outcomes.get(result.outcome, 0)) + 1
		var key := "%s/%s" % [result.outcome, result.reason]
		stages[key] = int(stages.get(key, 0)) + 1
		for battle_key in result.battles:
			var entry: Array = battles.get(battle_key, [0, 0])
			entry[0] += int(result.battles[battle_key][0])
			entry[1] += int(result.battles[battle_key][1])
			battles[battle_key] = entry
		years += game.state.year
		var end_key := "%s eff=%d" % [game.state.stage, game.state.efficacy / 10 * 10]
		ends[end_key] = int(ends.get(end_key, 0)) + 1
		game.free()
	print("== sim %d runs ==" % runs)
	print("outcomes: ", outcomes)
	print("reasons: ", stages)
	var battle_keys := battles.keys()
	battle_keys.sort()
	for key in battle_keys:
		print("battle %s: %d wins / %d fights" % [key, battles[key][0], battles[key][1]])
	print("avg year: %.1f" % (float(years) / runs))
	var keys := ends.keys()
	keys.sort()
	for k in keys:
		print("  end ", k, ": ", ends[k])


# ---------- 界面 ----------

func _test_ui_smoke() -> void:
	var scene := load("res://main.tscn").instantiate() as Control
	root.add_child(scene)
	var game: Node = scene.get_node("GameLogic")
	game.reseed(5)
	await process_frame
	var view: BattleView = scene.get_node("BattleView")
	var manager: BattleManager = game.get_battle_manager()
	for stage in game.get_stages().slice(0, 5):
		game.state.stage = stage
		game._phase = Game.RoundPhase.IDLE
		game._start_battle("boss")
		await process_frame
		_expect(view.visible and view._enemy_widgets.size() == manager.enemies.size(), "Battle view shows every %s boss" % stage)
		manager._active = false
	game.state.stage = game.get_stages()[0]
	game._phase = Game.RoundPhase.IDLE
	game._start_battle("fight")
	await create_timer(2.6).timeout
	# 洗牌用的是全局随机数，手牌不固定：放一张确定的攻击牌进手牌再点
	var played := _card("mol_hit")
	manager.hand.append(played)
	view._sync_hand(manager.hand)
	await process_frame
	var hp: int = manager.enemies[0].hp
	view._try_card(played)
	if view._selected != null:
		view._on_enemy_pressed(0)
	await create_timer(1.0).timeout
	_expect(not manager.hand.has(played) and not view._faces.has(played), "Clicking a card plays it and removes its face")
	_expect(manager.enemies.any(func(e: Enemy) -> bool: return e.hp < e.max_hp) or hp <= 0, "The played attack damages an enemy")
	view._on_end_turn()
	await create_timer(4.0).timeout
	_expect(not view._busy and view._faces.size() == manager.hand.size(), "After the enemy turn the hand view matches the new hand")
	manager._active = false
	view.visible = false
	game._battle_kind = "boss"
	game._offer_reward()
	await process_frame
	await process_frame
	var popup: Control = scene.get_node("RewardPopup")
	var confirm: Button = popup.get_node("Center/Panel/Margin/VBox/ButtonsRow/ConfirmButton")
	_expect(popup.visible and root.get_visible_rect().encloses(confirm.get_global_rect()),
		"Reward confirmation must fit inside the default 1280x720 viewport")
	var reward: Dictionary = game._pending_reward
	game.claim_reward(reward.cards[0].id, reward.abilities[0].id)
	_expect(not popup.visible and scene.get_node("EventPopup").visible, "Claiming a boss reward shows the milestone decision")
	game.resolve_event_choice("milestone", 1)
	_expect(scene._advance_button.text == scene.tr("ui.restart") and not scene._advance_button.disabled,
		"Terminal UI must offer an enabled restart button")
	scene.free()


func _test_restart() -> void:
	var scene := load("res://main.tscn").instantiate() as Control
	root.add_child(scene)
	current_scene = scene
	var game: Node = scene.get_node("GameLogic")
	game.state.funding = 1
	game._pass_time(12)
	game._check_end_conditions()
	scene._advance_button.pressed.emit()
	await scene_changed
	var restarted: Node = current_scene.get_node("GameLogic")
	_expect(restarted.is_idle() and restarted.state.funding == 40 and restarted.state.year == 1,
		"Restart button must reload a clean project with initial resources")
	_expect(restarted.state.abilities.is_empty() and restarted.get_map().get_layer_index() == -1,
		"Restart must reset abilities and map progress")
	current_scene.free()


# ---------- 标题、菜单与结局 ----------

func _test_ending_and_menu() -> void:
	var scene := load("res://main.tscn").instantiate() as Control
	root.add_child(scene)
	await process_frame
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	root.push_input(esc)
	await process_frame
	_expect(scene._pause_menu.visible, "Esc opens the in-game menu")
	scene._pause_menu.help_requested.emit()
	_expect(scene._help.visible and scene._help.find_children("*", "TabContainer", true, false)[0].get_tab_count() == HelpPanel.PAGES.size(),
		"Help opens from the menu with every page")
	scene._help.close()
	scene._pause_menu.close()
	var game: Node = scene.get_node("GameLogic")
	game.state.funding = 1
	game._pass_time(12)
	game._check_end_conditions()
	await process_frame
	_expect(scene._ending.visible, "Running out of funding shows the ending screen")
	_expect(root.get_visible_rect().encloses(scene._ending._panel.get_global_rect()),
		"Ending screen fits inside the 1280x720 viewport")
	scene.free()


func _test_title_screen() -> void:
	var title := load("res://title.tscn").instantiate() as Control
	root.add_child(title)
	await process_frame
	await process_frame
	var labels: Array[String] = []
	for b in title.find_children("*", "Button", true, false):
		labels.append((b as Button).text)
	_expect(labels.has(title.tr("title.start")) and labels.has(title.tr("title.settings")) and labels.has(title.tr("title.archive")),
		"Title screen offers start, settings and archive")
	title._settings.open()
	await process_frame
	_expect(title._settings.find_children("*", "HSlider", true, false).size() == 3, "Settings has three volume sliders")
	_expect(root.get_visible_rect().encloses(title._settings._panel.get_global_rect()), "Settings panel fits the viewport")
	title._settings.close()
	title._archive.open()
	await process_frame
	_expect(title._archive.visible, "Archive opens from the title screen")
	title.free()
