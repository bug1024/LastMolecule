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
	_test_card_face_readable()
	_test_project_types()
	_test_backfire_preview()
	_test_program_decisions()
	_test_evidence_and_campaign()
	_test_campaign_end_to_end()
	_test_build_cards()
	_test_final_checklist()
	await _test_status_wording()
	_test_avatar_faces()
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


func _arg_str(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


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


## 不依赖随机手牌：塞一张普通攻击牌进手牌并打出
func _play_finisher(manager: BattleManager) -> void:
	var finisher := _card("mol_hit")
	manager.hand.append(finisher)
	manager.energy = maxi(manager.energy, finisher.cost)
	manager.play_card(finisher, 0)


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


## 项目类型：起始牌组 / 配置覆盖 / 战斗规则 / 存档
func _test_project_types() -> void:
	var merged := ProjectTypes.apply_overrides({"a": 1, "final_review": {"efficacy_min": 60, "safety_risk_below": 70}},
		{"overrides": {"final_review": {"safety_risk_below": 60}}})
	_expect(int(merged.final_review.efficacy_min) == 60 and int(merged.final_review.safety_risk_below) == 60,
		"Project type overrides merge nested dictionaries")
	_expect(ProjectTypes.code_for_run(0) == "LM-002" and ProjectTypes.code_for_run(5) == "LM-007",
		"Program codes start at LM-002 (LM-001 is reserved)")
	var standard := _new_game()
	_expect(standard.project_type == "standard" and standard.project_code == "LM-002" and standard.get_final_safety_limit() == 70,
		"A new game defaults to the standard program")
	_expect(standard.get_battle_rules().is_empty(), "Standard programs have no battle rules")
	standard.free()
	RunSave.new_project_type = "selective"
	var sel := _new_game()
	_expect(sel.project_type == "selective" and RunSave.new_project_type.is_empty(), "The chosen program type is applied once")
	_expect(sel.deck.count("mol_target") == 2 and sel.deck.size() == 10, "Selective programs swap in an extra Target Lock")
	_expect(sel.state.safety_risk == 15 and sel.get_final_safety_limit() == 65, "Selective programs start safer but need a cleaner final review")
	_expect(int(sel.get_battle_rules().get("offtarget_limit", 0)) == 2, "Selective rules apply in Discovery")
	_expect(String(sel.to_save().project_type) == "selective" and sel.get_project_name().contains("LM-002"),
		"Program type and code are saved and shown")
	sel.free()
	# 战斗规则：第 3 张非精准攻击牌起反噬；攻击带破绽的目标不计数
	var m := _manager(["poor_solubility"], ["mol_hit", "mol_hit", "mol_hit", "mol_hit", "mol_hit"],
		{"rules": {"offtarget_limit": 2, "offtarget_damage": 3, "precise_free": true}})
	m.energy = 5
	var enemy: Enemy = m.enemies[0]
	enemy.max_hp = 999
	enemy.hp = 999
	var hp := m.player.hp
	m.play_card(m.hand[0], 0)
	m.play_card(m.hand[0], 0)
	_expect(m.player.hp == hp and m.rule_attacks_left() == 0, "Two attacks a turn are safe in a selective program")
	m.play_card(m.hand[0], 0)
	_expect(m.player.hp == hp - 3, "The third attack backfires for 3")
	enemy.add_status("vulnerable", 2)
	m.play_card(m.hand[0], 0)
	_expect(m.player.hp == hp - 3, "Attacks on a Weak Spot target don't count toward the limit")
	_expect(m.get_mechanic_lines()[0].key == "mechanic.selective", "The selectivity rule is listed in the battle banner")
	m.free()


## 两种反噬统一计数与出牌预告；慢性项目的敌人成长
func _test_backfire_preview() -> void:
	var m := _manager(["activity_cliff"], ["mol_hit", "mol_hit", "mol_hit", "mol_hit", "mol_hit"],
		{"rules": {"offtarget_limit": 2, "offtarget_damage": 5, "precise_free": true}}, "boss")
	m.energy = 9
	m.enemies[0].max_hp = 999
	m.enemies[0].hp = 999
	m.enemies[0].add_status("vulnerable", 5)
	_expect(m.safe_attacks_left() == 2 and m.boss_attacks_left() == 3, "Safe-attack counter takes the tighter of program and boss limits")
	m.play_card(m.hand[0], 0)
	m.play_card(m.hand[0], 0)
	m.play_card(m.hand[0], 0)
	_expect(m.rule_attacks_left() == 2 and m.safe_attacks_left() == 0, "Weak Spot attacks skip the program rule but still count for the boss")
	var preview := m.backfire_preview(m.hand[0], 0)
	_expect(bool(preview.exempt) and int(preview.project) == 0 and int(preview.boss) == 4,
		"Preview shows the program exemption and the boss backfire separately")
	var lines := BattleView.backfire_lines(preview)
	_expect(lines.size() == 2, "Backfire preview lists both rule outcomes")
	_expect(int(m.stats.attacks) == 3 and int(m.stats.precise) == 3, "Battle stats count attacks and Weak Spot hits")
	m.free()
	var r := _manager(["poor_solubility"], ["exp_assay", "exp_assay", "exp_assay", "exp_assay", "exp_assay"], {"rules": {"enemy_ramp_every": 2}})
	r.enemies[0].max_hp = 999
	r.enemies[0].hp = 999
	r.end_turn()
	_expect(r.enemies[0].get_status("strength") == 0, "No ramp on turn 2")
	r.end_turn()
	_expect(r.enemies[0].get_status("strength") == 1, "Enemies gain Strength every 2 turns in chronic programs")
	_expect(r.get_mechanic_lines()[0].key == "mechanic.chronic", "The ramp rule is listed in the battle banner")
	r.free()


## 项目专属里程碑决策、阶段残留风险、存档
func _test_program_decisions() -> void:
	RunSave.new_project_type = "selective"
	var g := _new_game()
	g.state.stage = "临床前研究"
	g.state.stage_battle_won = true
	var seen: Array = []
	g.event_offered.connect(func(event: Dictionary, _gate: bool) -> void: seen.append(event))
	g._offer_milestone()
	var ids: Array = seen[0].choices.map(func(c: Dictionary) -> String: return String(c.get("option", c.action)))
	_expect(ids == ["sel_refine", "sel_potency", "sel_narrow", "terminate"], "Selective programs offer a three-way preclinical decision")
	g.resolve_event_choice("milestone", 1)
	_expect(g.state.stage == "一期临床试验" and g.decisions == ["sel_potency"], "A decision advances the stage and is recorded")
	_expect(int(g.get_battle_rules().get("offtarget_limit", 0)) == 2, "Keeping potency extends the selectivity rule into Phase I")
	_expect(int(g.run_flags.strength) == 1, "Keeping potency grants +1 Strength")
	var saved: Dictionary = g.to_save()
	_expect(saved.decisions == ["sel_potency"] and int(saved.run_flags.strength) == 1, "Decisions and flags are saved")
	g.free()
	RunSave.new_project_type = "chronic"
	var c := _new_game()
	var risk: int = c.state.safety_risk
	c._advance_stage("临床前研究")
	_expect(c.state.safety_risk == risk + 5, "Chronic programs add residual risk at each new stage")
	c.state.stage = "一期临床试验"
	c.state.stage_battle_won = true
	c._offer_milestone()
	c.resolve_event_choice("milestone", 0)
	risk = c.state.safety_risk
	c._advance_stage("三期临床试验")
	_expect(c.state.safety_risk == risk and c.decisions == ["chr_longtox"], "Long-term toxicology stops the residual risk")
	_expect(int(c.get_battle_rules().get("enemy_ramp_every", 0)) == 2, "Chronic ramp rule applies in Phase III")
	c.free()


## 研究证据、LM-001 解锁 / 路线 / Boss / 主线结局
func _test_evidence_and_campaign() -> void:
	var company := Company.new()
	_expect(company.grant_evidence("selectivity", {"code": "LM-003"}) and not company.grant_evidence("selectivity", {}),
		"Each kind of evidence is granted only once")
	_expect(not company.final_unlocked(), "One piece of evidence does not unlock LM-001")
	company.grant_evidence("foundation", {"code": "LM-002"})
	_expect(company.final_unlocked(), "Two pieces of evidence unlock LM-001")
	RunSave.new_project_type = "selective"
	var g := _new_game()
	g.state.stage = "临床前研究"
	g.state.stage_battle_won = true
	_expect(g._evidence_earned("terminated").is_empty(), "Terminating before Phase I earns no evidence")
	g.state.stage = "一期临床试验"
	_expect(g._evidence_earned("terminated") == "selectivity" and g._evidence_earned("approved") == "selectivity",
		"Approval or a quality termination earns the program's evidence")
	var ended: Array = []
	g.run_ended.connect(func(_o: String, _r: String, summary: Dictionary) -> void: ended.append(summary))
	g._finish("approved", "msg.marketing_approved")
	_expect(String(ended[0].evidence) == "selectivity" and bool(ended[0].evidence_new) and g.company.has_evidence("selectivity"),
		"Finishing reports and stores new evidence")
	_expect(String(g.company.history[0].evidence) == "selectivity" and g.company.history[0].has("stats"), "History records evidence and stats")
	g.free()
	RunSave.new_project_type = "final"
	var f := _new_game()
	_expect(f.project_code == "LM-001" and not f.is_idle(), "LM-001 opens with a route choice")
	f.company.evidence = {"selectivity": {"run": 1}, "foundation": {"run": 2}}
	f._queue_route_choice()
	var routes: Array = f._current_event.choices.map(func(c: Dictionary) -> String: return String(c.route))
	_expect(routes == ["route_standard", "route_selective"], "Routes depend on the evidence the company holds")
	var funds: int = f.state.funding
	f.resolve_event_choice("route", 1)
	_expect(f.route == "route_selective" and f.state.funding == funds - 8 and f.is_idle(), "Choosing a route applies its cost")
	_expect(f.get_battle_rules().is_empty(), "The selectivity route removes the off-target rule")
	f.state.stage = "三期临床试验"
	_expect(String(f.get_boss_info().id) == "boss_final" and int(f.get_battle_rules().get("enemy_ramp_every", 0)) == 2,
		"LM-001 has its own final boss and keeps the ramp rule")
	_expect(f._campaign_ending("approved") == "approved_route_selective" and f._campaign_ending("terminated") == "leave_answer",
		"LM-001 approval or termination after Phase I ends the campaign")
	f.state.stage = "临床前研究"
	_expect(f._campaign_ending("terminated").is_empty() and f._campaign_ending("failed").is_empty(), "Early stops and failures are not campaign endings")
	f.free()


## 把一局直接推到三期里程碑并走完终审（数据不够就做补充分析），返回 run_ended 的 summary
func _approve_via_review(g: Node) -> Dictionary:
	var ended: Array = []
	g.run_ended.connect(func(_o: String, _r: String, summary: Dictionary) -> void: ended.append(summary))
	g.state.stage = "三期临床试验"
	g.state.stage_battle_won = true
	g.state.efficacy = 95
	g.state.safety_risk = 10
	g.state.funding = 40
	g._offer_milestone()
	g.resolve_event_choice("milestone", 0)
	var guard := 0
	while ended.is_empty() and guard < 10:
		guard += 1
		var choices: Array = g._current_event.get("choices", [])
		var pick := 0
		if not g.state.can_meet(choices[0].get("requires", {})):
			pick = choices.find(choices.filter(func(c: Dictionary) -> bool: return c.label_key == "final.data_study").front())
		g.resolve_event_choice("final_review", pick)
	return ended[0] if not ended.is_empty() else {}


## 完整主线回归：两类项目获批得证据 → 解锁 LM-001 → 选路线 → 二期决策 → 补数据 → 获批 → 重开再通关
func _test_campaign_end_to_end() -> void:
	Company.default_save_path = "user://test_company.json"
	var co := Company.new()
	co.reset()
	var a := _new_game(11)
	var sa := _approve_via_review(a)
	_expect(String(sa.get("evidence", "")) == "foundation" and bool(sa.evidence_new), "E2E: standard approval earns foundation evidence")
	a.free()
	RunSave.new_project_type = "selective"
	var b := _new_game(12)
	b.state.stage = "临床前研究"
	b.state.stage_battle_won = true
	b._offer_milestone()
	b.resolve_event_choice("milestone", 0)
	var sb := _approve_via_review(b)
	_expect(String(sb.get("evidence", "")) == "selectivity", "E2E: selective approval earns selectivity evidence")
	_expect(b.project_code == "LM-003", "E2E: program codes advance with company runs")
	b.free()
	co.load_save()
	_expect(co.final_unlocked() and co.evidence.selectivity.decisions == ["sel_refine"], "E2E: two kinds of evidence unlock LM-001 and keep their decisions")
	RunSave.new_project_type = "final"
	var c := _new_game(13)
	var routes: Array = c._current_event.choices.map(func(ch: Dictionary) -> String: return String(ch.route))
	_expect(routes == ["route_standard", "route_selective"], "E2E: LM-001 offers the routes the evidence allows")
	c.resolve_event_choice("route", 1)
	c.state.stage = "二期临床试验"
	c.state.stage_battle_won = true
	c.state.data = 20
	c._offer_milestone()
	c.resolve_event_choice("milestone", 0)
	_expect(c.get_final_data_min() == 60 and c.state.stage == "三期临床试验", "E2E: broadening the indication adds a data requirement")
	var sc := _approve_via_review(c)
	_expect(String(sc.get("campaign_ending", "")) == "approved_route_selective" and c.state.data >= 60,
		"E2E: data analysis makes the review passable and LM-001 approval ends the campaign")
	_expect(sc.route == "route_selective" and sc.decisions.has("fin_broad"), "E2E: the ending gets this run's route and decisions")
	c.free()
	co.load_save()
	_expect(co.is_campaign_done() and String(co.campaign.route) == "route_selective" and String(co.history[0].project_code) == "LM-001",
		"E2E: the company remembers the first campaign ending")
	var chain := EndingPanel.chain_lines(co, "route_selective", ["route:route_selective", "fin_broad"])
	_expect(chain.size() == 5 and chain[1].begins_with("★") and chain[4].contains(tr("milestone.opt.fin_broad")),
		"E2E: the cause-and-effect chain marks the evidence this route used and lists the LM-001 decision")
	RunSave.new_project_type = "final"
	var d := _new_game(14)
	d.resolve_event_choice("route", 0)
	var sd := _approve_via_review(d)
	d.free()
	co.load_save()
	_expect(String(sd.campaign_ending) == "approved_route_standard" and String(co.campaign.route) == "route_selective",
		"E2E: a second clear reports its own route without overwriting the first campaign record")
	var chain2 := EndingPanel.chain_lines(co, String(sd.route), sd.decisions)
	_expect(chain2.back().contains(tr("route.route_standard")) and not chain2.any(func(l: String) -> bool: return l.begins_with("★")),
		"E2E: the second ending's chain uses the second run's route")
	co.reset()
	Company.default_save_path = ""


## 烧瓶表情优先级：短暂反应 > 持续状态 > 按生命自动（低于 30% 担心）
func _test_avatar_faces() -> void:
	var a := PlayerAvatar.new()
	a.ratio = 0.9
	_expect(a.face() == "idle", "Healthy flask looks calm")
	a.ratio = 0.2
	_expect(a.face() == "worried", "Low HP makes the flask worried")
	a.set_mood("focus")
	_expect(a.face() == "focus", "A mood overrides the automatic face")
	a.hit()
	_expect(a.face() == "hurt", "A hit reaction overrides the mood")
	a.free()
	var c := CreatureView.new()
	c.setup({"id": "last_molecule", "shape": "molecule", "size": 1.7}, true)
	_expect(c._mol_atoms.size() >= 20 and c._mol_bonds.size() > c._mol_atoms.size(), "The final boss is built from the LM-001 ring structure")
	c.free()


## 状态文案归因：门槛提高按来源描述；主动终止的主线结局在标题页不显示为获批
func _test_status_wording() -> void:
	var scene := load("res://main.tscn").instantiate() as Control
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("GameLogic")
	var map_screen = scene.get_node("MapScreen")
	var comp: Competition = game.competition
	for c in comp.competitors:
		c.status = "active"
	comp._new_mechanism = true
	comp.efficacy_bar_bonus = 5
	var text: String = map_screen.competition_summary()
	_expect(text == tr("comp.src_mechanism") % 5, "A new mechanism alone is not reported as a rival approval")
	comp.competitors[0].status = "approved"
	comp.efficacy_bar_bonus = 15
	text = map_screen.competition_summary()
	_expect(text.contains(tr("comp.src_mechanism") % 5) and text.contains("+15"), "Multiple bar sources are listed with a total")
	scene.free()
	Company.default_save_path = "user://test_company.json"
	var co := Company.new()
	co.reset()
	co.campaign = {"ending": "leave_answer", "route": "", "code": "LM-001", "run": 3}
	co.save()
	var hero := TitleHero.new()
	root.add_child(hero)
	_expect(hero._status.text.begins_with(tr("hero.archived").split("%")[0]), "Leave the Answer shows as archived, not approved")
	co.campaign = {"ending": "approved_route_standard", "route": "route_standard", "code": "LM-001", "run": 3}
	co.save()
	hero.refresh()
	_expect(hero._status.text.begins_with(tr("hero.done").split("%")[0]), "Campaign approvals show as approved")
	hero.free()
	co.reset()
	Company.default_save_path = ""


## 终审目标清单：与终审提交条件一致，数据要求出现时多一行
func _test_final_checklist() -> void:
	var g := _new_game(31)
	g.state.efficacy = 72
	g.state.safety_risk = 42
	var items: Array = g.get_final_checklist()
	_expect(items.size() == 2 and bool(items[0].ok) and bool(items[1].ok), "Checklist: efficacy and safety met, no data row without a requirement")
	g.run_flags["final_data_min"] = 60
	g.state.data = 48
	items = g.get_final_checklist()
	_expect(items.size() == 3 and String(items[2].id) == "data" and not bool(items[2].ok) and int(items[2].gap) == 12,
		"Checklist: a data requirement adds a row with the gap")
	g.state.safety_risk = 70
	_expect(not bool(g.get_final_checklist()[1].ok) and int(g.get_final_checklist()[1].gap) == 1, "Checklist: safety must be strictly below the limit")
	var card := InfoCard.new("outcome_approved", "goal.title", UIKit.ACCENT)
	HubView.fill_goal_card(card, g.get_final_checklist())
	_expect(card._name_label.text.contains("1/3"), "Goal card title summarizes how many conditions are met")
	card.free()
	g.free()


## v0.4 构筑卡：防守反击 / 护盾翻倍 / 护盾保留 / 数据驱动伤害 / 数据增幅；阶段卡池；牌组套路判断
func _test_build_cards() -> void:
	var m := _manager(["poor_solubility"], ["exp_assay", "exp_assay", "exp_assay", "exp_assay", "exp_assay"])
	var e: Enemy = m.enemies[0]
	e.max_hp = 999
	e.hp = 999
	m.energy = 9
	m.player.block = 10
	m.hand.append(_card("exp_counter"))
	m.play_card(m.hand.back(), 0)
	_expect(e.hp == 999 - 14, "Counter-Evidence deals damage equal to Block +4")
	m.hand.append(_card("exp_replicate"))
	m.play_card(m.hand.back(), -1)
	_expect(m.player.block == 20, "Replication doubles Block")
	m.hand.append(_card("exp_stable_platform"))
	m.play_card(m.hand.back(), -1)
	m.end_turn()
	_expect(m.player.block > 0, "Stable Platform keeps Block into the next turn")
	m.free()
	var a := _manager(["poor_solubility"], ["exp_hts", "exp_hts", "exp_hts", "exp_hts", "exp_hts"])
	a.enemies[0].max_hp = 999
	a.enemies[0].hp = 999
	a.energy = 9
	a.hand.append(_card("ai_mlops"))
	a.play_card(a.hand.back(), -1)
	a.play_card(a.hand[0], -1)
	_expect(a.data_gained == 3, "MLOps adds +1 data whenever data is gained")
	var lead := _card("ai_lead_opt")
	lead.effects[0]["value"] = 4
	a.hand.append(lead)
	var hp_before: int = a.enemies[0].hp
	a.play_card(lead, 0)
	_expect(a.last_deviation or hp_before - a.enemies[0].hp >= 3 + 3 / 2, "AI Lead Optimization adds damage per data gained this battle")
	a.free()
	_expect(ResearchCard.deck_build([_card("mol_analog"), _card("mol_broad"), _card("mol_sar"), _card("exp_assay")]) == "molecular",
		"Deck build: mostly molecular cards reads as Molecular Rush")
	_expect(ResearchCard.deck_build([_card("clin_dosing"), _card("clin_combo"), _card("ai_stratify"), _card("clin_endpoint"), _card("mol_broad")]) == "poison",
		"Deck build: four Poison/detonate cards read as Toxicity Control")
	_expect(ResearchCard.deck_build([_card("mol_hit"), _card("exp_assay")]) == "thin", "Deck build: starter cards are ignored")
	# 阶段卡池：二期临床阶段抽到的临床策略卡明显多于发现阶段
	var g := _new_game(21)
	var counts := {}
	for stage in ["候选化合物发现", "二期临床试验"]:
		g.state.stage = stage
		var n := 0
		for i in 200:
			for card in g._sample_cards(3):
				if card.type == "clinical":
					n += 1
		counts[stage] = n
	_expect(int(counts["二期临床试验"]) > int(counts["候选化合物发现"]) * 1.5, "Phase II rewards lean toward Clinical cards")
	g.free()


## 战斗手牌尺寸（0.9 倍）下，所有卡、中英文，牌面文字都不小于 12px，名称不超出名称条
func _test_card_face_readable() -> void:
	var small: Array[String] = []
	var ai := {"multiplier": 0.5, "need_data": 12, "next_multiplier": 1.0, "deviation": 30}
	for locale in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for data in JsonData.load_dict("res://data/cards.json").cards:
			var card := ResearchCard.from_dict(data)
			var face := CardFace.create(card, 0.9, {}, ai)
			var labels: Array = face.find_children("*", "Label", true, false)
			for label in labels:
				if (label as Label).get_theme_font_size("font_size") < 12:
					small.append("%s/%s" % [locale, card.id])
			face.free()
	TranslationServer.set_locale("zh_CN")
	_expect(small.is_empty(), "Card face text stays >= 12px at hand scale: %s" % ", ".join(small))


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
	_play_finisher(manager)
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
	_play_finisher(manager)
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
	var data_sum := 0
	var saved_by_bonus := 0   # 靠决策放宽的安全线才获批的局数
	var ends := {}
	var type_arg := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--type="):
			type_arg = arg.trim_prefix("--type=")
	Bot.respect_rules = _arg_int("--naive=") == 0
	Bot.decision_index = _arg_int("--decision=")
	Bot.build = _arg_str("--build=")
	var company_data := _arg_int("--company-data=")
	var by_build := {}     # 牌组主导套路 → [获批, 局数]
	var by_card := {}      # 卡 id → [获批, 出现局数]（只统计非起始卡）
	var starters: Array = JsonData.load_dict("res://data/cards.json").get("starter_cards", [])
	print("project type: %s, respect rules: %s, decision: %d, build: %s, company data: %d" % [type_arg if not type_arg.is_empty() else "standard",
		Bot.respect_rules, Bot.decision_index, Bot.build if not Bot.build.is_empty() else "any", company_data])
	for s in runs:
		RunSave.new_project_type = type_arg
		var game := _new_game(10000 + s)
		game.company.data = company_data   # 模拟公司已积累的数据（决定流程等级、AI 起点与可解锁的卡）
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
		data_sum += game.state.data
		var bonus := int(game.run_flags.get("final_safety_bonus", 0))
		if result.outcome == "approved" and bonus > 0 and game.state.safety_risk >= game.get_final_safety_limit() - bonus:
			saved_by_bonus += 1
		var won := 1 if result.outcome == "approved" else 0
		var dominant := _deck_build(game, starters)
		var bb: Array = by_build.get(dominant, [0, 0])
		by_build[dominant] = [bb[0] + won, bb[1] + 1]
		var seen := {}
		for card_id in game.deck:
			if starters.has(card_id) or seen.has(card_id):
				continue
			seen[card_id] = true
			var bc: Array = by_card.get(card_id, [0, 0])
			by_card[card_id] = [bc[0] + won, bc[1] + 1]
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
	print("avg data: %.1f" % (float(data_sum) / runs))
	print("approved only thanks to a looser safety limit: %d" % saved_by_bonus)
	var keys := ends.keys()
	keys.sort()
	for k in keys:
		print("  end ", k, ": ", ends[k])
	print("-- approval by dominant deck build (non-starter cards) --")
	for b in by_build:
		print("  build %-11s %3d / %3d  (%d%%)" % [b, by_build[b][0], by_build[b][1], roundi(100.0 * by_build[b][0] / by_build[b][1])])
	var rated: Array = by_card.keys().filter(func(id: String) -> bool: return int(by_card[id][1]) >= maxi(10, runs / 10))
	rated.sort_custom(func(a: String, b: String) -> bool: return float(by_card[a][0]) / by_card[a][1] > float(by_card[b][0]) / by_card[b][1])
	print("-- approval when the card is in the final deck (>= %d runs) --" % maxi(10, runs / 10))
	for id in rated:
		print("  card %-16s %3d%%  (%d runs)" % [id, roundi(100.0 * by_card[id][0] / by_card[id][1]), by_card[id][1]])


## 本局牌组的主导套路（同 ResearchCard.deck_build）
func _deck_build(game: Node, _starters: Array) -> String:
	return ResearchCard.deck_build(game.build_deck())


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
		labels.append((b as Button).text.strip_edges())
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
