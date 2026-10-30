extends Node
## 研发核心逻辑层（无任何 UI 依赖）
## 所有业务数据均来自 res://data/ 下的 JSON 文件，脚本中不硬编码数值。
##
## 一局：立项 → [阶段分支地图 → 阶段 Boss → 里程碑 Go/No-Go] × 5 → 上市审评 → 获批（成功）
##   每进入一个地图节点都会消耗几个月（满 12 个月过一年：扣年度成本、竞品推进），再按节点类型分发：
##     战斗 / 精英 → 尖塔式卡牌战斗，胜利后选卡（精英额外选研发能力）
##     研究     → 三种推进方案三选一（前期研究削弱本阶段 Boss），再选 1 张卡
##     事件     → 随机事件
##     合作融资 → 注资 / 买卡 / 删卡
##     平台建设 → 安全评估（降低安全风险）/ 升级卡 / 本局流程 +1
##     加速通道 → 本阶段后续节点不再耗时，但 Boss 更强
##     Boss     → 阶段试验，各阶段有专属机制；胜利后进入里程碑
##     里程碑   → 继续 / 主动终止
## 战斗中玩家生命 = 100 - 安全风险，疗效换算成开局效力，数据决定 AI 卡档位。
## 项目类型（ProjectTypes / data/projects.json）在开局时改变起始牌组、终审要求与部分阶段的战斗规则。
## 项目状态统一由 ProjectState 持有，通过信号向 UI 广播。

signal state_changed(deltas: Dictionary)
signal state_synced(state: ProjectState)
signal event_offered(event: Dictionary, is_gate: bool)
signal card_pick_offered(cards: Array, purpose: String)
signal battle_resolved(victory: bool, effects: Dictionary)
signal reward_offered(reward: Dictionary)
signal reward_claimed()
signal map_updated()
signal news_posted(items: Array)
signal run_ended(outcome: String, reason_key: String, summary: Dictionary)
signal player_leveled(level: int)
signal molecule_design_requested(mode: String)   # initial：开局设计分子；modify：里程碑修饰分子
signal fragment_gained(fragment_id: String)

const PROJECT_DATA_PATH := "res://data/project.json"
const EVENTS_DATA_PATH := "res://data/events.json"
const CARDS_DATA_PATH := "res://data/cards.json"
const REWARDS_DATA_PATH := "res://data/rewards.json"
const PLANS_DATA_PATH := "res://data/research_plans.json"
const MAPS_DATA_PATH := "res://data/maps.json"
const ENCOUNTERS_DATA_PATH := "res://data/encounters.json"
const PLAYER_DATA_PATH := "res://data/player.json"

enum RoundPhase { IDLE, WAITING_EVENT, WAITING_CARD, BATTLE, REWARD, DESIGN, FINISHED }

var state: ProjectState = null
var company: Company = null
var competition: Competition = null
var rng := RandomNumberGenerator.new()

var _project: Dictionary = {}
var _random_events: Array = []
var _cards_data: Array = []
var _card_types: Dictionary = {}
var _rarity_weights: Dictionary = {}
var _stage_type_bias: Dictionary = {}   # 阶段 → {卡牌类型: 权重倍数}，见 cards.json stage_type_bias
var _abilities_data: Array = []
var _card_rarities: Dictionary = {}
var _battle_reward: Dictionary = {}
var _plans: Array = []
var _plan_card_choices := 3
var _node_types: Dictionary = {}
var _encounters: Dictionary = {}
var _player_cfg: Dictionary = {}

var _battle_manager: BattleManager = null
var _map: ResearchMap = null

var _phase := RoundPhase.IDLE
var _current_event: Dictionary = {}
var _offered_cards: Array = []       # ResearchCard 候选
var _pick_purpose := ""              # add / buy / remove / upgrade
var _pending_reward: Dictionary = {}

var deck: Array = []                 # 本局牌库 card id（可重复）
var upgraded := {}                   # 已升级的 card id
var run_process := 0                 # 本局流程临时等级
var rp2d := 0                        # 一期 Boss 战锁定的剂量（二期 Boss 战开局效力加成）
var fast_track := false              # 本阶段走了加速通道
var months := 0                      # 当年已过去的月份
var _battle_kind := ""               # 当前 / 刚结束的战斗类型 fight / elite / boss
var player_xp := 0                   # 研发团队经验：打赢战斗获得，升级后形象变化并自带基础能力
var battles_fought := 0
var resumed := false                 # 本局是从存档继续的
var project_type := "standard"       # 项目类型 id
var project_code := ""               # 项目编号，如 LM-002
var _type_cfg: Dictionary = {}
var run_stats := {"attacks": 0, "precise": 0, "backfires": 0}   # 本局累计：攻击牌 / 打破绽目标的攻击 / 反噬次数
var run_flags := {}                  # 项目专属决策带来的持续效果（见 projects.json milestones）
var decisions: Array = []            # 本局做过的项目专属决策 id（写入公司历史，结局因果链用）
var route := ""                      # 最终项目 LM-001 选择的研究路线 id
var molecule: Molecule = null        # 玩家设计的分子（项目类型 molecule: true 时启用）
var _design_mode := ""               # 分子设计阶段：initial / modify
var _event_is_gate := false


func _ready() -> void:
	# 语言来自玩家设置（默认中文）
	GameSettings.ensure_loaded()
	TranslationServer.set_locale(GameSettings.locale)
	rng.randomize()
	_load_data()
	company = Company.new()
	company.load_save()
	competition = Competition.new()
	competition.setup(rng)
	var saved := RunSave.read() if RunSave.resume_requested else {}
	RunSave.resume_requested = false
	if saved.is_empty():
		_apply_project_type(RunSave.new_project_type, ProjectTypes.code_for_run(company.runs))
	else:
		_apply_project_type(String(saved.get("project_type", "")), String(saved.get("project_code", "")))
	RunSave.new_project_type = ""
	state = ProjectState.from_data(_project)
	_map = ResearchMap.new()
	if not saved.is_empty() and _load_run(saved):
		resumed = true
	else:
		if not saved.is_empty():
			_apply_project_type("", ProjectTypes.code_for_run(company.runs))
			state = ProjectState.from_data(_project)
		RunSave.clear()
		var bonus := company.take_start_bonus()
		if bonus > 0:
			state.funding += bonus
			company.save()
		_map.generate(state.stage, rng)
		if bool(_type_cfg.get("molecule", false)):
			molecule = Molecule.create()
			_queue_design("initial")
		elif not (_type_cfg.get("routes", []) as Array).is_empty():
			_queue_route_choice()
	_battle_manager = BattleManager.new()
	_battle_manager.rng = rng
	_battle_manager.tier_provider = _ai_tier
	_battle_manager.card_factory = func(card_id: String) -> ResearchCard: return _make_card(get_card_by_id(card_id))
	add_child(_battle_manager)
	_battle_manager.battle_ended.connect(_on_battle_ended)
	state_synced.emit(state)
	map_updated.emit()


## 开局套用项目类型：合并配置覆盖、替换起始牌组
func _apply_project_type(type_id: String, code: String) -> void:
	_type_cfg = ProjectTypes.find(type_id if not type_id.is_empty() else ProjectTypes.default_id())
	project_type = String(_type_cfg.get("id", "standard"))
	# 最终项目有固定编号（LM-001）；普通项目用传入的编号（读档）或按公司项目次数生成
	project_code = String(_type_cfg.get("code", code if not code.is_empty() else ProjectTypes.code_for_run(company.runs)))
	_project = ProjectTypes.apply_overrides(JsonData.load_dict(PROJECT_DATA_PATH), _type_cfg)
	var starter: Array = _type_cfg.get("starter_cards", [])
	deck = (starter if not starter.is_empty() else JsonData.load_dict(CARDS_DATA_PATH).get("starter_cards", [])).duplicate()


## 读档后（或新局开场就有待做的选择时）由 UI 在连好信号后调用：
## 重新弹出正在进行的事件 / 选卡 / 奖励，或重开那场战斗
func replay_pending() -> void:
	if not resumed and _phase == RoundPhase.IDLE:
		return
	state_synced.emit(state)
	map_updated.emit()
	match _phase:
		RoundPhase.WAITING_EVENT:
			event_offered.emit(_current_event, _event_is_gate)
		RoundPhase.WAITING_CARD:
			card_pick_offered.emit(_offered_cards.duplicate(), _pick_purpose)
		RoundPhase.REWARD:
			reward_offered.emit(_pending_reward)
		RoundPhase.BATTLE:
			_start_battle(_battle_kind)
		RoundPhase.DESIGN:
			molecule_design_requested.emit(_design_mode)


# ---------- 存档 ----------

## 把整局进度写入存档（战斗只记「正在打哪种战斗」，继续时从头打）
func _autosave() -> void:
	if _phase == RoundPhase.FINISHED:
		return
	RunSave.write(to_save())


func to_save() -> Dictionary:
	var offered: Array = []
	for card in _offered_cards:
		offered.append({"id": card.id, "upgraded": card.upgraded})
	return {
		"state": state.to_dict(), "map": _map.to_dict(), "competition": competition.to_dict(),
		"rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"phase": _phase, "event": _current_event, "event_is_gate": _event_is_gate,
		"offered": offered, "pick_purpose": _pick_purpose, "reward": _pending_reward,
		"deck": deck.duplicate(), "upgraded": upgraded.keys(), "run_process": run_process, "rp2d": rp2d,
		"fast_track": fast_track, "months": months, "battle_kind": _battle_kind,
		"player_xp": player_xp, "battles_fought": battles_fought,
		"project_type": project_type, "project_code": project_code,
		"run_stats": run_stats.duplicate(), "run_flags": run_flags.duplicate(true), "decisions": decisions.duplicate(), "route": route,
		"molecule": molecule.to_dict() if molecule != null else {}, "design_mode": _design_mode,
	}


func _load_run(d: Dictionary) -> bool:
	if not d.has("state") or not d.has("map"):
		return false
	state.load_dict(d.state)
	_map.load_dict(d.map)
	competition.load_dict(d.get("competition", {}))
	rng.seed = String(d.get("rng_seed", "0")).to_int()
	rng.state = String(d.get("rng_state", "0")).to_int()
	deck.clear()
	for id in d.get("deck", []):
		deck.append(String(id))
	upgraded.clear()
	for id in d.get("upgraded", []):
		upgraded[String(id)] = true
	run_process = int(d.get("run_process", 0))
	rp2d = int(d.get("rp2d", 0))
	fast_track = bool(d.get("fast_track", false))
	months = int(d.get("months", 0))
	_battle_kind = String(d.get("battle_kind", ""))
	player_xp = int(d.get("player_xp", 0))
	battles_fought = int(d.get("battles_fought", 0))
	var stats: Dictionary = d.get("run_stats", {})
	for key in run_stats:
		run_stats[key] = int(stats.get(key, 0))
	run_flags = d.get("run_flags", {})
	decisions = d.get("decisions", []).duplicate()
	route = String(d.get("route", ""))
	var mol: Dictionary = d.get("molecule", {})
	molecule = Molecule.from_dict(mol) if not mol.is_empty() else null
	_design_mode = String(d.get("design_mode", ""))
	_current_event = d.get("event", {})
	_event_is_gate = bool(d.get("event_is_gate", false))
	_pick_purpose = String(d.get("pick_purpose", ""))
	_pending_reward = d.get("reward", {})
	_phase = clampi(int(d.get("phase", RoundPhase.IDLE)), RoundPhase.IDLE, RoundPhase.DESIGN)
	_offered_cards.clear()
	if _phase == RoundPhase.WAITING_CARD:
		if _pick_purpose == "upgrade" or _pick_purpose == "remove":
			_offered_cards = _unique_deck_cards(_pick_purpose == "upgrade")
		else:
			for entry in d.get("offered", []):
				var data := get_card_by_id(String(entry.get("id", "")))
				if not data.is_empty():
					_offered_cards.append(_make_card(data, bool(entry.get("upgraded", false))))
		if _offered_cards.is_empty():
			_phase = RoundPhase.IDLE
	return true


## 使用固定种子重新开局（测试与复盘用）
func reseed(seed_value: int) -> void:
	rng.seed = seed_value
	competition.setup(rng)
	_map.generate(state.stage, rng)
	map_updated.emit()


# ---------- 玩家操作 ----------

## 前往下一层的第 index 个节点（地图界面点击）
func choose_node(index: int) -> void:
	if _phase != RoundPhase.IDLE or not _map.choose(index):
		return
	var node := _map.get_current_node()
	var node_type := String(node.get("type", "research"))
	var cost := 0 if fast_track and node_type != "boss" else int(_node_types.get(node_type, {}).get("months", 4))
	_pass_time(cost)
	if _check_end_conditions():
		return
	map_updated.emit()
	_dispatch_node(node)


## 玩家选择事件选项（所有弹窗型节点共用）
func resolve_event_choice(event_id: String, choice_index: int) -> void:
	if _phase != RoundPhase.WAITING_EVENT or event_id != String(_current_event.get("id", "")):
		return
	var choices: Array = _current_event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var choice: Dictionary = choices[choice_index]
	if not state.can_meet(choice.get("requires", {})):
		return
	_apply_effects(choice.get("effects", {}))
	if _check_end_conditions():
		return
	_run_action(String(choice.get("action", "")), choice)


## 玩家在选卡弹窗中选择一张卡（加入 / 购买 / 删除 / 升级）
func select_card(card: ResearchCard) -> void:
	if _phase != RoundPhase.WAITING_CARD or card == null or not _offered_cards.has(card):
		return
	var cost := _pick_cost()
	if state.funding < cost:
		return
	if cost > 0:
		_apply_effects({"funding": -cost})
	match _pick_purpose:
		"add", "buy":
			deck.append(card.id)
		"remove":
			deck.erase(card.id)
		"upgrade":
			upgraded[card.id] = true
	_offered_cards.clear()
	if _check_end_conditions():
		return
	_finish_node()


func skip_cards() -> void:
	if _phase != RoundPhase.WAITING_CARD:
		return
	_offered_cards.clear()
	_finish_node()


func claim_reward(card_id: String, ability_id: String) -> void:
	if _phase != RoundPhase.REWARD:
		return
	if card_id != "" and not _is_reward_selection_valid(_pending_reward.get("cards", []), card_id):
		return
	if not _is_reward_selection_valid(_pending_reward.get("abilities", []), ability_id):
		return
	if card_id != "":
		deck.append(card_id)
	if ability_id != "" and not state.abilities.has(ability_id):
		state.abilities.append(ability_id)
		state_synced.emit(state)
	_pending_reward = {}
	reward_claimed.emit()
	if _battle_kind == "boss":
		_enter_milestone()
	else:
		_finish_node()


## 本阶段地图是否已经走出第一步（继续游戏时直接打开地图）
func has_started_map() -> bool:
	return _map.get_layer_index() >= 0


func is_idle() -> bool:
	return _phase == RoundPhase.IDLE


func is_finished() -> bool:
	return _phase == RoundPhase.FINISHED


# ---------- 状态读取 ----------

func get_state() -> ProjectState:
	return state


## 界面显示用的项目名，如「LM-003 · 选择性项目」
func get_project_name() -> String:
	return tr("project.title") % [project_code, tr("project.type." + project_type)]


## 当前项目类型配置（见 data/projects.json）
func get_project_type() -> Dictionary:
	return _type_cfg


## 本阶段生效的项目战斗规则（合并成一个字典；不在任何规则阶段时为空）
## battle_rules 可以是单条或多条规则，每条有自己的 stages；最终项目的路线可以移除某条（remove_rules），
## 项目专属决策可以把规则延长到更多阶段（run_flags.rule_stages）
func get_battle_rules() -> Dictionary:
	var merged := {}
	var removed: Array = _route_cfg().get("remove_rules", [])
	for rule in _rule_list():
		if removed.has(String(rule.get("id", ""))):
			continue
		var stages: Array = (rule.get("stages", []) as Array).duplicate()
		if String(rule.get("id", "")) == String(run_flags.get("rule_id", "")) or not run_flags.has("rule_id"):
			stages.append_array(run_flags.get("rule_stages", []))
		if stages.has(state.stage):
			merged.merge(rule, true)
	merged.erase("stages")
	merged.erase("id")
	return merged


func _rule_list() -> Array:
	var raw = _type_cfg.get("battle_rules", [])
	return [raw] if raw is Dictionary and not (raw as Dictionary).is_empty() else (raw if raw is Array else [])


func _route_cfg() -> Dictionary:
	for r in _type_cfg.get("routes", []):
		if String(r.get("id", "")) == route:
			return r
	return {}


## 前期研究最多削弱 Boss 的百分比（阶段进度条的上限）
func get_progress_gate() -> int:
	return int(_encounters.get("boss_research_cut_max", 30))


## 本阶段 Boss 信息 {id, enemies, hp_scale}
func get_boss_info() -> Dictionary:
	var boss: Dictionary = _stage_boss().duplicate()
	boss["hp_scale"] = _boss_hp_scale()
	return boss


## 本阶段 Boss（项目类型可以用 boss_overrides 换成专属 Boss）
func _stage_boss() -> Dictionary:
	var custom: Dictionary = _type_cfg.get("boss_overrides", {}).get(state.stage, {})
	return custom if not custom.is_empty() else _encounters.get("stages", {}).get(state.stage, {}).get("boss", {})


## 研发团队等级（1 起）
func get_player_level() -> int:
	var level := 0
	for entry in _player_cfg.get("levels", []):
		if player_xp >= int(entry.get("xp", 0)):
			level += 1
	return maxi(level, 1)


## 当前等级自带的基础能力 {start_block, strength, first_draw, dexterity}
func get_player_bonus() -> Dictionary:
	var levels: Array = _player_cfg.get("levels", [])
	return levels[get_player_level() - 1].get("bonus", {}) if not levels.is_empty() else {}


## 升到下一级所需的总经验（满级返回 -1）
func get_next_level_xp() -> int:
	var levels: Array = _player_cfg.get("levels", [])
	var level := get_player_level()
	return int(levels[level].get("xp", 0)) if level < levels.size() else -1


func get_battle_kind() -> String:
	return _battle_kind


func get_months() -> int:
	return months


func get_final_efficacy_bar() -> int:
	return int(_project.get("final_review", {}).get("efficacy_min", 60)) + competition.efficacy_bar_bonus


func get_final_safety_limit() -> int:
	var alerts := molecule.open_alerts() if molecule != null else 0   # 未排除的毒性警示：每项安全线 −5
	return int(_project.get("final_review", {}).get("safety_risk_below", 70)) + int(run_flags.get("final_safety_bonus", 0)) - 5 * alerts


## 终审目标清单（总览与地图常驻显示，和终审弹窗的提交条件一致）：
## [{id: efficacy / safety / data, current, need, ok, gap}]；安全风险是「低于 need」，其余是「达到 need」
func get_final_checklist() -> Array:
	var items: Array = []
	var bar := get_final_efficacy_bar()
	items.append({"id": "efficacy", "current": state.efficacy, "need": bar, "ok": state.efficacy >= bar, "gap": maxi(0, bar - state.efficacy)})
	var limit := get_final_safety_limit()
	items.append({"id": "safety", "current": state.safety_risk, "need": limit, "ok": state.safety_risk < limit,
		"gap": maxi(0, state.safety_risk - limit + 1)})
	if get_final_data_min() > 0:
		var need := get_final_data_min()
		items.append({"id": "data", "current": state.data, "need": need, "ok": state.data >= need, "gap": maxi(0, need - state.data)})
	return items


## 终审额外要求的本局数据（精准分层等决策带来，0 表示没有）
func get_final_data_min() -> int:
	return int(run_flags.get("final_data_min", 0))


## 阶段 id 列表（发现 → 获批上市）
func get_stages() -> Array:
	return _stages()


func get_battle_manager() -> BattleManager:
	return _battle_manager


func get_map() -> ResearchMap:
	return _map


func get_card_type_name(type_key: String) -> String:
	return String(_card_types.get(type_key, type_key))


func get_ability_by_id(ability_id: String) -> Dictionary:
	for a in _abilities_data:
		if String(a.get("id", "")) == ability_id:
			return a
	return {}


func get_card_by_id(card_id: String) -> Dictionary:
	for c in _cards_data:
		if String(c.get("id", "")) == card_id:
			return c
	return {}


func get_rarity_name_key(rarity: String) -> String:
	return String(_card_rarities.get(rarity, {}).get("name_key", ""))


## AI 面板信息：有效数据、档位、偏差概率、公司数据与流程等级
func get_ai_info() -> Dictionary:
	var tier := _ai_tier(0, 0)
	return {
		"effective": int(tier.get("effective", 0)),
		"tier": String(tier.get("id", "mid")),
		"multiplier": float(tier.get("multiplier", 1.0)),
		"deviation": int(tier.get("deviation", 15)),
		"run_data": state.data,
		"company_data": company.data,
		"level": company.process_level(),
		"run_process": run_process,
		"next_threshold": company.next_level_threshold(),
		"next_id": String(tier.get("next_id", "")),
		"next_multiplier": float(tier.get("next_multiplier", 1.0)),
		"need_data": int(tier.get("need_data", -1)),
		"process_helps": bool(tier.get("process_helps", false)),
	}


## 本局牌库的 ResearchCard 实例
func build_deck() -> Array:
	var cards: Array = []
	for card_id in deck:
		var data := get_card_by_id(String(card_id))
		if data.is_empty():
			continue
		cards.append(_make_card(data, upgraded.has(card_id)))
	return cards


# ---------- 节点分发 ----------

func _dispatch_node(node: Dictionary) -> void:
	match String(node.get("type", "research")):
		"research":
			_offer_research()
		"event":
			_offer_random_event()
		"partner":
			_offer_partner()
		"platform":
			_offer_platform()
		"fast_track":
			_offer_fast_track()
		"fight", "elite", "boss":
			_start_battle(String(node.type))
		"milestone":
			_offer_milestone()
		_:
			_finish_node()


func _offer_event(event: Dictionary, is_gate := false) -> void:
	_current_event = event
	_event_is_gate = is_gate
	_phase = RoundPhase.WAITING_EVENT
	_autosave()
	event_offered.emit(event, is_gate)


func _offer_research() -> void:
	var choices: Array = []
	for style in ["fast", "steady", "cheap"]:
		var options := _plans.filter(func(p: Dictionary) -> bool: return String(p.get("style", "")) == style)
		if options.is_empty():
			continue
		var plan: Dictionary = options[rng.randi_range(0, options.size() - 1)]
		var cost := -int(plan.get("effects", {}).get("funding", 0))
		choices.append({
			"label_key": "plan." + String(plan.id),
			"desc_key": "plan." + String(plan.id) + ".desc",
			"tag_key": "plan.style." + style,
			"effects": plan.get("effects", {}),
			"requires": {"funding_min": cost} if cost > 0 else {},
			"action": "card_reward",
		})
	choices.append({"label_key": "plan.skip", "effects": {}, "action": ""})
	_offer_event({"id": "research", "tag_key": "ui.decision_tag", "title_key": "node.research", "desc_key": "node.research.desc", "choices": choices})


func _offer_random_event() -> void:
	if _random_events.is_empty():
		_finish_node()
		return
	_offer_event(_random_events[JsonData.weighted_index(_random_events, rng)])


func _offer_partner() -> void:
	var partner: Dictionary = _project.get("partner", {})
	var invest := maxi(2, int(partner.get("invest_base", 5)) + competition.finance_mod * 2)
	var buy_cost := int(partner.get("buy_cost", 3))
	var remove_cost := int(partner.get("remove_cost", 1))
	_offer_event({"id": "partner", "tag_key": "ui.decision_tag", "title_key": "node.partner", "desc_key": "node.partner.desc",
		"desc_args": [competition.finance_mod], "choices": [
			{"label_key": "partner.invest", "effects": {"funding": invest}, "action": ""},
			{"label_key": "partner.buy", "label_args": [buy_cost], "requires": {"funding_min": buy_cost}, "effects": {}, "action": "buy"},
			{"label_key": "partner.remove", "label_args": [remove_cost], "requires": {"funding_min": remove_cost}, "effects": {}, "action": "remove"},
			{"label_key": "partner.leave", "effects": {}, "action": ""},
		]})


## 平台建设「安全评估」降低的安全风险（= 回血量）
func get_rest_heal() -> int:
	return int(_project.get("rest_heal", 15))


func _offer_platform() -> void:
	var heal := get_rest_heal()
	_offer_event({"id": "platform", "tag_key": "ui.decision_tag", "title_key": "node.platform", "desc_key": "node.platform.desc", "choices": [
		{"label_key": "platform.rest", "label_args": [heal], "effects": {"safety_risk": -heal}, "action": ""},
		{"label_key": "platform.upgrade", "effects": {}, "action": "upgrade"},
		{"label_key": "platform.process", "effects": {}, "action": "process"},
	] + _tox_choice()})


## 有未验证的毒性警示时，平台建设多一个「毒理验证」：花钱花时间，按概率排除或确认一项警示
func _tox_choice() -> Array:
	if molecule == null or molecule.unknown_alerts().is_empty():
		return []
	var cfg: Dictionary = Molecule.config().get("tox_study", {})
	var cost := -int(cfg.get("funding", -2))
	return [{"label_key": "tox.study", "label_args": ["alert." + String(molecule.unknown_alerts()[0])], "desc_key": "tox.study.desc",
		"requires": {"funding_min": cost + 1},
		"effects": {"funding": -cost}, "action": "tox_study"}]


func _offer_fast_track() -> void:
	var config: Dictionary = _project.get("fast_track", {})
	_offer_event({"id": "fast_track", "tag_key": "ui.decision_tag", "title_key": "node.fast_track", "desc_key": "node.fast_track.desc", "choices": [
		{"label_key": "fast_track.accept", "effects": {"research_progress": int(config.get("research_progress", 15))}, "action": "fast_track"},
		{"label_key": "fast_track.decline", "effects": {"research_progress": int(config.get("decline_progress", 5))}, "action": ""},
	]})


func _start_battle(kind: String) -> void:
	var stage_cfg: Dictionary = _encounters.get("stages", {}).get(state.stage, {})
	var encounter: Dictionary
	if kind == "boss":
		encounter = _stage_boss().duplicate()
	else:
		var pool: Array = stage_cfg.get("elite" if kind == "elite" else "normal", [])
		if pool.is_empty():
			_finish_node()
			return
		encounter = {"id": kind, "enemies": pool[rng.randi_range(0, pool.size() - 1)]}
	encounter["kind"] = kind
	_battle_kind = kind
	_phase = RoundPhase.BATTLE
	_autosave()
	var abilities: Array = []
	for ability_id in state.abilities:
		abilities.append(get_ability_by_id(String(ability_id)))
	var bonus := get_player_bonus()
	var strength := get_efficacy_strength() + int(bonus.get("strength", 0)) + int(run_flags.get("strength", 0))
	if kind == "boss" and state.stage == "二期临床试验":
		strength += rp2d
	var mol := molecule.effects(state.stage) if molecule != null else {}
	strength += int(mol.get("strength", 0))
	var deck_cards := build_deck()
	if int(mol.get("clinical_cost", 0)) > 0:   # 溶解度差：临床策略卡（给药）更贵
		for card in deck_cards:
			if card.type == "clinical":
				card.cost += int(mol.clinical_cost)
	var rules := get_battle_rules()
	if bool(mol.get("offtarget", false)) and not rules.has("offtarget_limit"):
		rules.merge({"offtarget_limit": 2, "offtarget_damage": 3, "precise_free": true})
	_battle_manager.start_battle(encounter, deck_cards, abilities, {
		"hp": 100 - state.safety_risk,
		"max_hp": 100,
		"strength": strength,
		"hp_scale": _boss_hp_scale(),
		"boss_strength": competition.boss_strength_bonus,
		"dose_max": int(_encounters.get("dose_max", 4)),
		"start_block": int(bonus.get("start_block", 0)),
		"first_draw": int(bonus.get("first_draw", 0)) + int(mol.get("first_draw", 0)),
		"dexterity": int(bonus.get("dexterity", 0)) + int(mol.get("dexterity", 0)),
		"rules": rules,
		"weak": int(mol.get("weak", 0)),
		"vulnerable_bonus": int(mol.get("vulnerable_bonus", 0)),
		"poison_bonus": int(mol.get("poison_bonus", 0)),
		"enemy_strength": int(mol.get("enemy_strength", 0)),
		"extra_lines": mol.get("lines", []),
	})


## 疗效换算成战斗开局效力：每超过基准 20 点 +1
func get_efficacy_strength() -> int:
	var base := int(_project.get("strength_efficacy_base", 20))
	var per := maxi(1, int(_project.get("strength_per_efficacy", 20)))
	return maxi(0, (state.efficacy - base) / per)


func _boss_hp_scale() -> float:
	var cut := mini(state.research_progress, int(_encounters.get("boss_research_cut_max", 30)))
	var extra := int(_encounters.get("fast_track_boss_hp", 15)) if fast_track else 0
	return (100.0 - cut + extra) / 100.0


func _on_battle_ended(victory: bool, outcome: Dictionary) -> void:
	if _phase != RoundPhase.BATTLE:
		return
	run_process += int(outcome.get("process", 0))
	battles_fought += 1
	var stats: Dictionary = outcome.get("stats", {})
	for key in run_stats:
		run_stats[key] = int(run_stats[key]) + int(stats.get(key, 0))
	if bool(outcome.get("intel", false)):
		competition.intel_revealed = true
	var effects := {"safety_risk": int(outcome.get("damage_taken", 0)), "data": int(outcome.get("data", 0))}
	if victory:
		var reward: Dictionary = _encounters.get("rewards", {}).get(_battle_kind, {})
		effects["funding"] = int(reward.get("funding", 0))
		effects["efficacy"] = int(reward.get("efficacy", 0))
		effects["safety_risk"] = int(effects.safety_risk) + int(reward.get("safety_risk", 0)) - _victory_heal()
		if _battle_kind == "boss" and state.stage == "一期临床试验":
			rp2d = int(outcome.get("dose", 0))
	else:
		effects["set_safety_risk"] = 100
	_apply_effects(effects)
	battle_resolved.emit(victory, effects)
	if not victory:
		_finish("failed", "msg.battle_lost")
		return
	if _check_end_conditions():
		return
	if _battle_kind == "boss":
		state.stage_battle_won = true
	var before := get_player_level()
	player_xp += int(_player_cfg.get("xp_per_battle", {}).get(_battle_kind, 1))
	if get_player_level() > before:
		player_leveled.emit(get_player_level())
	if molecule != null and _battle_kind != "verify" and state.stage in ["候选化合物发现", "临床前研究"]:
		_grant_fragment()
	if _battle_kind == "verify":
		_offer_milestone()   # 修饰后的验证试验通过：回到里程碑继续决策
		return
	_offer_reward()


func _victory_heal() -> int:
	var heal := 0
	for ability_id in state.abilities:
		heal += int(get_ability_by_id(String(ability_id)).get("passive", {}).get("victory_heal", 0))
	return heal


func _offer_reward() -> void:
	var reward: Dictionary = _encounters.get("rewards", {}).get(_battle_kind, {})
	var cards: Array = []
	for card in _sample_cards(int(reward.get("card_choices", 3)), _battle_kind != "fight"):
		var data := get_card_by_id(card.id).duplicate()
		data["type_name"] = card.type_name
		cards.append(data)
	var level := company.process_level()
	var pool := _abilities_data.filter(func(a: Dictionary) -> bool:
		return not state.abilities.has(String(a.id)) and int(a.get("requires_process", 0)) <= level)
	var abilities: Array = []
	while abilities.size() < int(reward.get("ability_choices", 0)) and not pool.is_empty():
		var idx := JsonData.weighted_index(pool, rng)
		abilities.append(pool[idx])
		pool.remove_at(idx)
	var resources := {}
	for key in ["funding", "efficacy", "safety_risk"]:
		if int(reward.get(key, 0)) != 0:
			resources[key] = int(reward[key])
	_pending_reward = {"kind": _battle_kind, "resources": resources, "cards": cards, "abilities": abilities}
	_phase = RoundPhase.REWARD
	_autosave()
	reward_offered.emit(_pending_reward)


## 战斗结束后自动进入里程碑节点
func _enter_milestone() -> void:
	var choices := _map.get_choices()
	if not choices.is_empty():
		_map.choose(int(choices[0]))
		map_updated.emit()
	_offer_milestone()


func _offer_milestone() -> void:
	var is_last := state.stage == _last_stage()
	var desc_key := "milestone.desc_won" if state.stage_battle_won else "milestone.desc_lost"
	var choices: Array = []
	var options: Array = _type_cfg.get("milestones", {}).get(state.stage, [])
	if options.is_empty():
		choices.append({"label_key": "milestone.final" if is_last else "milestone.continue", "requires": {"battle_won": true},
			"effects": {}, "action": "continue"})
	else:
		# 项目专属决策：每个选项都是「带着某种方案继续」，效果持续到项目结束
		desc_key = "milestone.%s.desc" % project_type if state.stage_battle_won else desc_key
		for option in options:
			var key := "milestone.opt.%s" % String(option.id)
			var effects: Dictionary = option.get("effects", {})
			var cost := -int(effects.get("funding", 0))
			var requires := {"battle_won": true}
			if cost > 0:
				requires["funding_min"] = cost + 1
			choices.append({"label_key": key, "desc_key": key + ".desc", "tag_key": "milestone.opt_tag",
				"requires": requires, "effects": effects, "action": "decide", "option": String(option.id)})
	if molecule != null and state.stage == "临床前研究" and state.stage_battle_won and not bool(run_flags.get("modified", false)):
		choices.append({"label_key": "mol.modify", "desc_key": "mol.modify.desc", "tag_key": "mol.tag", "effects": {}, "action": "modify_molecule"})
	choices.append({"label_key": "milestone.terminate", "effects": {}, "action": "terminate"})
	_offer_event({"id": "milestone", "title_key": "node.milestone", "desc_key": desc_key,
		"desc_args": [_tr_stage(state.stage), get_final_efficacy_bar(), state.efficacy], "choices": choices}, true)


# ---------- 分子设计 ----------

func _queue_design(mode: String) -> void:
	_design_mode = mode
	_current_event = {}
	_phase = RoundPhase.DESIGN
	_autosave()
	molecule_design_requested.emit(mode)


func is_designing() -> bool:
	return _phase == RoundPhase.DESIGN


func get_design_mode() -> String:
	return _design_mode


## 提交分子结构（位点 → 片段）。开局设计直接生效；里程碑修饰按规模付代价并打一场验证试验：
##   局部修饰（只换取代基）：额外耗时，打一场验证试验后回到里程碑；
##   更换核心结构（连接位）：前期疗效数据作废（疗效 −8），同样需要验证试验。
## 返回 "" 表示成功，否则为错误键
func submit_molecule(placement: Dictionary) -> String:
	if _phase != RoundPhase.DESIGN or molecule == null:
		return "mol.err.phase"
	var kind := molecule.change_kind(placement) if _design_mode == "modify" else "initial"
	if not molecule.apply_layout(placement):
		return "mol.err.layout"
	if _design_mode == "initial":
		_design_mode = ""
		state_synced.emit(state)
		_finish_node()
		return ""
	_design_mode = ""
	if kind == "none":
		_offer_milestone()
		return ""
	run_flags["modified"] = true
	decisions.append("mol_" + kind)
	var cfg: Dictionary = Molecule.config().get("modify", {})
	_pass_time(int(cfg.get("months", 2)))
	if kind == "core":
		_apply_effects({"efficacy": int(cfg.get("core_efficacy", -8))})
	state_synced.emit(state)
	if _check_end_conditions():
		return ""
	_start_battle("verify")
	return ""


## 修饰时改主意：不改了，回到里程碑
func cancel_design() -> void:
	if _phase == RoundPhase.DESIGN and _design_mode == "modify":
		_design_mode = ""
		_offer_milestone()


## 修饰预估：{kind: none/local/core, efficacy}（界面在确认前展示代价）
func preview_modify(placement: Dictionary) -> Dictionary:
	if molecule == null:
		return {"kind": "none"}
	var kind := molecule.change_kind(placement)
	return {"kind": kind, "efficacy": int(Molecule.config().get("modify", {}).get("core_efficacy", -8)) if kind == "core" else 0}


func _run_tox_study() -> void:
	var cfg: Dictionary = Molecule.config().get("tox_study", {})
	_pass_time(int(cfg.get("months", 4)))
	var unknown := molecule.unknown_alerts()
	if unknown.is_empty() or _check_end_conditions():
		_finish_node()
		return
	var alert := String(unknown[0])
	var cleared := rng.randi_range(1, 100) <= int(cfg.get("clear_chance", 55))
	molecule.alerts[alert] = "cleared" if cleared else "confirmed"
	if not cleared:
		_apply_effects({"safety_risk": int(cfg.get("confirm_risk", 8))})
		if _check_end_conditions():
			return
	state_synced.emit(state)
	_offer_event({"id": "tox_result", "tag_key": "ui.decision_tag", "title_key": "tox.result_title",
		"desc_key": "tox.cleared" if cleared else "tox.confirmed", "desc_args": ["alert." + alert, int(cfg.get("confirm_risk", 8))],
		"choices": [{"label_key": "tox.ok", "effects": {}, "action": ""}]})


## 打赢发现 / 临床前的战斗：随机获得一个分子片段（进库存，里程碑修饰时可用）
func _grant_fragment() -> void:
	var pool: Array = Molecule.config().get("fragments", [])
	if pool.is_empty():
		return
	var id := String(pool[rng.randi_range(0, pool.size() - 1)].id)
	molecule.inventory.append(id)
	fragment_gained.emit(id)


## 最终项目开场：按公司已有的研究证据选择研究路线
func _queue_route_choice() -> void:
	var choices: Array = []
	for r in _type_cfg.get("routes", []):
		var need := String(r.get("requires", ""))
		if not need.is_empty() and not company.has_evidence(need):
			continue
		var key := "route." + String(r.id)
		choices.append({"label_key": key, "desc_key": key + ".desc", "tag_key": "route.tag." + (need if not need.is_empty() else "none"),
			"effects": r.get("effects", {}), "action": "route", "route": String(r.id)})
	_current_event = {"id": "route", "tag_key": "route.event_tag", "title_key": "route.title", "desc_key": "route.desc", "choices": choices}
	_event_is_gate = true
	_phase = RoundPhase.WAITING_EVENT
	_autosave()


func _offer_final_review() -> void:
	var review: Dictionary = _project.get("final_review", {})
	var extra: Dictionary = review.get("extra_study", {})
	var submit_req := {"efficacy_min": get_final_efficacy_bar(), "safety_risk_below": get_final_safety_limit()}
	var desc_key := "final.desc"
	var desc_args := [state.efficacy, get_final_efficacy_bar(), state.safety_risk, get_final_safety_limit()]
	if get_final_data_min() > 0:
		submit_req["data_min"] = get_final_data_min()
		desc_key = "final.desc_data"
		desc_args.append_array([state.data, get_final_data_min()])
	var choices: Array = [
		{"label_key": "final.submit", "requires": submit_req, "effects": {}, "action": "submit"},
		{"label_key": "final.extra_study", "requires": {"funding_min": -int(extra.get("funding", -3)) + 1},
			"effects": extra, "action": "final_review"},
	]
	# 决策带来了数据要求却没达标：给一个补数据的办法（花钱花时间），否则只能干等终止
	var data_study: Dictionary = review.get("data_study", {})
	if get_final_data_min() > state.data and not data_study.is_empty():
		choices.append({"label_key": "final.data_study", "desc_key": "final.data_study.desc",
			"requires": {"funding_min": -int(data_study.get("funding", -3)) + 1}, "effects": data_study, "action": "final_review"})
	choices.append({"label_key": "milestone.terminate", "effects": {}, "action": "terminate"})
	_offer_event({"id": "final_review", "title_key": "node.final_review", "desc_key": desc_key,
		"desc_args": desc_args, "choices": choices}, true)


func _run_action(action: String, choice: Dictionary) -> void:
	match action:
		"decide":
			_apply_decision(String(choice.get("option", "")))
			if _phase == RoundPhase.FINISHED:
				return
			if state.stage == _last_stage():
				_offer_final_review()
			else:
				_advance_stage(_next_stage())
		"tox_study":
			_run_tox_study()
		"modify_molecule":
			_queue_design("modify")
		"route":
			route = String(choice.get("route", ""))
			decisions.append("route:" + route)
			_finish_node()
		"card_reward":
			_offer_card_pick("add", _sample_cards(_plan_card_choices))
		"buy":
			_offer_card_pick("buy", _sample_cards(_plan_card_choices))
		"remove":
			_offer_card_pick("remove", _unique_deck_cards(false))
		"upgrade":
			_offer_card_pick("upgrade", _unique_deck_cards(true))
		"process":
			run_process += 1
			_finish_node()
		"fast_track":
			fast_track = true
			_finish_node()
		"continue":
			if state.stage == _last_stage():
				_offer_final_review()
			else:
				_advance_stage(_next_stage())
		"final_review":
			_offer_final_review()
		"submit":
			_apply_effects({"stage": "获批上市"})
			_finish("approved", "msg.marketing_approved")
		"terminate":
			_finish("terminated", "msg.terminated")
		_:
			_finish_node()


func _offer_card_pick(purpose: String, cards: Array) -> void:
	if cards.is_empty():
		_finish_node()
		return
	_pick_purpose = purpose
	_offered_cards = cards
	_phase = RoundPhase.WAITING_CARD
	_autosave()
	card_pick_offered.emit(cards.duplicate(), purpose)


func _pick_cost() -> int:
	var partner: Dictionary = _project.get("partner", {})
	if String(_current_event.get("id", "")) != "partner":
		return 0
	match _pick_purpose:
		"buy":
			return int(partner.get("buy_cost", 3))
		"remove":
			return int(partner.get("remove_cost", 1))
	return 0


func get_pick_cost() -> int:
	return _pick_cost()


## 节点处理完毕：回到地图
func _finish_node() -> void:
	_current_event = {}
	_phase = RoundPhase.IDLE
	_autosave()
	map_updated.emit()


## 项目专属决策：记录 id，套用持续效果（flags）与耗时
func _apply_decision(option_id: String) -> void:
	for option in _type_cfg.get("milestones", {}).get(state.stage, []):
		if String(option.get("id", "")) != option_id:
			continue
		decisions.append(option_id)
		var flags: Dictionary = option.get("flags", {})
		for key in flags:
			if flags[key] is Array:
				var list: Array = run_flags.get(key, [])
				list.append_array(flags[key])
				run_flags[key] = list
			elif flags[key] is bool:
				run_flags[key] = flags[key]
			else:
				run_flags[key] = int(run_flags.get(key, 0)) + int(flags[key])
		_pass_time(int(option.get("months", 0)))
		_check_end_conditions()
		return


## 慢性项目：每进入新阶段，长期用药的残留风险累积（决策可关闭或加重）
func _stage_drift() -> int:
	if bool(run_flags.get("drift_off", false)):
		return 0
	return int(_project.get("stage_safety_drift", 0)) + int(run_flags.get("drift_extra", 0))


func _advance_stage(stage: String) -> void:
	var drift := _stage_drift()
	if drift > 0:
		_apply_effects({"safety_risk": drift})
		if _check_end_conditions():
			return
	_apply_effects({"stage": stage, "set_research_progress": 0})
	state.stage_battle_won = false
	fast_track = false
	_battle_kind = ""
	_map.generate(state.stage, rng)
	_finish_node()


func _finish(outcome: String, reason_key: String) -> void:
	_phase = RoundPhase.FINISHED
	RunSave.clear()
	var evidence_id := _evidence_earned(outcome)
	var record := {"stage": state.stage, "year": state.year, "efficacy": state.efficacy, "safety_risk": state.safety_risk,
		"project_type": project_type, "project_code": project_code, "stats": run_stats.duplicate(),
		"decisions": decisions.duplicate(), "evidence": evidence_id}
	var evidence_new := company.grant_evidence(evidence_id, {"code": project_code, "project_type": project_type,
		"outcome": outcome, "run": company.runs + 1, "decisions": decisions.duplicate()})
	var ending := _campaign_ending(outcome)
	if not ending.is_empty() and not company.is_campaign_done():
		company.campaign = {"ending": ending, "route": route, "code": project_code, "run": company.runs + 1}   # 只记首次完成
	var summary := company.settle_run(state.data, outcome, state.funding, record)
	summary["evidence"] = evidence_id
	summary["evidence_new"] = evidence_new
	summary["campaign_ending"] = ending
	summary["route"] = route                    # 结局画面用本次的路线与决策（不是首次通关的记录）
	summary["decisions"] = decisions.duplicate()
	run_ended.emit(outcome, reason_key, summary)


## 本局获得的研究证据：获批，或在一期及以后的里程碑主动终止（高质量终止）才有
func _evidence_earned(outcome: String) -> String:
	var id := String(_type_cfg.get("evidence", ""))
	if id.is_empty():
		return ""
	if outcome == "approved":
		return id
	if outcome == "terminated" and state.stage_battle_won and _stages().find(state.stage) >= _stages().find("一期临床试验"):
		return id
	return ""


## 最终项目的战役结局：获批 → 按路线的结局；一期之后主动终止并留下证据 → 「把答案留下」
func _campaign_ending(outcome: String) -> String:
	if not bool(_type_cfg.get("final", false)):
		return ""
	if outcome == "approved":
		return "approved_" + (route if not route.is_empty() else "standard_route")
	if outcome == "terminated" and _stages().find(state.stage) >= _stages().find("一期临床试验"):
		return "leave_answer"
	return ""


# ---------- 内部实现 ----------

func _apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	var deltas: Dictionary = state.apply_effects(effects)
	if deltas.is_empty():
		return
	state_changed.emit(deltas)
	state_synced.emit(state)
	for i in maxi(0, int(deltas.get("year", 0))):
		var fresh := competition.tick_year(rng)
		if not fresh.is_empty():
			news_posted.emit(fresh)


## 时间推进：满一年扣年度成本、年份 +1（竞品随之推进）
func _pass_time(cost_months: int) -> void:
	months += cost_months
	var per_year := maxi(1, int(_project.get("months_per_year", 12)))
	while months >= per_year:
		months -= per_year
		_apply_effects({"year": 1, "funding": -int(_project.get("yearly_cost_billion", 2))})


func _check_end_conditions() -> bool:
	if _phase == RoundPhase.FINISHED:
		return true
	if state.funding <= 0:
		_finish("failed", "msg.funding_depleted")
		return true
	if state.safety_risk >= 100:
		_finish("failed", "msg.safety_critical")
		return true
	return false


func _ai_tier(extra_data: int, extra_process: int) -> Dictionary:
	var effective := company.effective_data(state.data + extra_data, run_process + extra_process)
	var tier := company.tier_for(effective).duplicate()
	tier["effective"] = effective
	tier.merge(company.next_tier_step(state.data + extra_data, run_process + extra_process))
	return tier


func _make_card(data: Dictionary, upgrade := false) -> ResearchCard:
	var card := ResearchCard.from_dict(data, upgrade)
	card.type_name = get_card_type_name(card.type)
	return card


## 从可获取卡池（非起始专属 / 状态牌、流程等级已解锁；项目类型的 card_pool_bonus 加权）按稀有度加权抽取 count 张不重复的卡
## rare_boost 时稀有与史诗权重翻倍（精英与 Boss 奖励）
func _sample_cards(count: int, rare_boost := false) -> Array:
	var level := company.process_level()
	var pool_bonus: Dictionary = _type_cfg.get("card_pool_bonus", {})   # 项目类型偏好的卡（可含起始专属卡）
	var pool: Array = []
	for data in _cards_data:
		var bonus := int(pool_bonus.get(String(data.get("id", "")), 0))
		if (bool(data.get("starter_only", false)) and bonus <= 0) or bool(data.get("token", false)) or int(data.get("requires_process", 0)) > level:
			continue
		var rarity := String(data.get("rarity", "common"))
		var stage_bias := float(_stage_type_bias.get(state.stage, {}).get(String(data.get("type", "")), 1.0))
		var weight := int(_rarity_weights.get(rarity, 5)) * (2 if rare_boost and rarity != "common" else 1) * maxi(1, bonus) \
			* maxi(1, roundi(stage_bias * 10))   # 阶段偏向（×10 取整，保持整数权重）
		pool.append({"data": data, "weight": weight})
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		var idx := JsonData.weighted_index(pool, rng)
		picked.append(_make_card(pool[idx].data))
		pool.remove_at(idx)
	return picked


func _unique_deck_cards(only_upgradable: bool) -> Array:
	var seen := {}
	var cards: Array = []
	for card_id in deck:
		if seen.has(card_id):
			seen[card_id].copies += 1
			continue
		if only_upgradable and upgraded.has(card_id):
			continue
		var data := get_card_by_id(String(card_id))
		if data.is_empty() or (only_upgradable and bool(data.get("unplayable", false))):
			continue
		var card := _make_card(data, upgraded.has(card_id))
		if only_upgradable:
			card.upgrade_preview = _make_card(data, true)
		seen[card_id] = card
		cards.append(card)
	return cards


func _is_reward_selection_valid(candidates: Array, selected_id: String) -> bool:
	if candidates.is_empty():
		return selected_id.is_empty()
	for candidate in candidates:
		if String(candidate.get("id", "")) == selected_id:
			return true
	return false


func _stages() -> Array:
	return _project.get("stages", [])


func _last_stage() -> String:
	var stages := _stages()
	return String(stages[stages.size() - 2]) if stages.size() >= 2 else ""


func _next_stage() -> String:
	var stages := _stages()
	var idx := stages.find(state.stage)
	return String(stages[mini(idx + 1, stages.size() - 1)])


func _tr_stage(stage: String) -> String:
	return "stage." + stage


func _load_data() -> void:
	_project = JsonData.load_dict(PROJECT_DATA_PATH)   # 开局时由 _apply_project_type 按项目类型重新合并
	_random_events = JsonData.load_dict(EVENTS_DATA_PATH).get("random_events", [])
	for event in _random_events:
		var event_id := String(event.get("id", ""))
		event["title_key"] = "event." + event_id
		event["desc_key"] = "event." + event_id + ".desc"
		var choices: Array = event.get("choices", [])
		for i in choices.size():
			choices[i]["label_key"] = "event.%s.choice.%d" % [event_id, i]
			choices[i]["desc_key"] = "event.%s.choice.%d.desc" % [event_id, i]
	var cards := JsonData.load_dict(CARDS_DATA_PATH)
	_cards_data = cards.get("cards", [])
	_card_types = cards.get("card_types", {})
	_rarity_weights = cards.get("rarity_weights", {})
	_stage_type_bias = cards.get("stage_type_bias", {})
	deck = cards.get("starter_cards", []).duplicate()
	var rewards := JsonData.load_dict(REWARDS_DATA_PATH)
	_abilities_data = rewards.get("abilities", [])
	for ability in _abilities_data:
		ability["name_key"] = "ability." + String(ability.get("id", ""))
		ability["desc_key"] = "ability." + String(ability.get("id", "")) + ".desc"
	_card_rarities = rewards.get("card_rarities", {})
	_battle_reward = rewards.get("battle_reward", {})
	var plans := JsonData.load_dict(PLANS_DATA_PATH)
	_plans = plans.get("plans", [])
	_plan_card_choices = int(plans.get("card_choices", 3))
	_node_types = JsonData.load_dict(MAPS_DATA_PATH).get("node_types", {})
	_encounters = JsonData.load_dict(ENCOUNTERS_DATA_PATH)
	_player_cfg = JsonData.load_dict(PLAYER_DATA_PATH)
