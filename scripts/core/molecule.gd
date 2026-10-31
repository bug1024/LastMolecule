class_name Molecule
extends RefCounted
## 玩家亲手设计的候选分子（原型，只在标准新药项目启用）。「卡组是你的研发能力，分子才是你的角色。」
## 配置见 data/molecule.json：骨架 7 个带类型的位点（连接位 = 核心结构、环上取代位、末端位），片段有收益也有代价，
## 相邻片段按标签触发组合规则；部分片段或组合带「毒性警示」——待验证的风险，可以靠毒理验证排除或确认。
##
## 属性（0–6）如何改变战斗（effects()）。2 是中性值，≤1 有代价，≥3 有收益，≥5 收益更大：
##   活性      ≤1 开局虚弱；≥3 开局力量 +1；≥5 +2
##   选择性    ≤1 发现 / 临床前战斗有脱靶规则；≥3 打出的破绽 +1；≥5 破绽 +2
##   稳定性    ≤1 中毒 −1，活性力量减半；≥3 施加的中毒 +1；≥5 另外敌人开局带 2 层中毒
##   溶解度    ≤1 临床策略卡费用 +1（制剂优化卡可抵消）；≥3 第一回合多抽 1 张；≥5 另外第一回合能量 +1
##   毒性警示  未排除或已确认的每一项：终审安全线 −5
## 有靶点时（disease / variant，见 data/diseases.json），片段放在口袋热点上还会命中契合加成或空间冲突（pocket_fits）。
## 分子还决定：奖励卡池偏向（card_affinity）、分子特性卡（组合成立时加入战斗牌组）、
## 各阶段 Boss 战的「阶段考验」（exam_result，见 molecule.json 的 exams）。

const PATH := "res://data/molecule.json"
const DISEASE_PATH := "res://data/diseases.json"
const PROPS := ["potency", "selectivity", "stability", "solubility"]

var sites := {}        # 位点 id → 片段 id（空位不在字典里）
var inventory: Array = []   # 未使用的片段 id（可重复）
var alerts := {}       # 警示 id → "unknown" / "cleared" / "confirmed"
var disease := ""      # 要攻克的疾病（data/diseases.json），空表示没有靶点（只用片段本身的属性）
var variant := 0       # 靶点第几代变体（耐药突变）

static var _cfg: Dictionary = {}
static var _diseases: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		_cfg = JsonData.load_dict(PATH)
	return _cfg


static func diseases() -> Array:
	if _diseases.is_empty():
		_diseases = JsonData.load_dict(DISEASE_PATH)
	return _diseases.get("diseases", [])


static func disease_cfg(id: String) -> Dictionary:
	for d in diseases():
		if String(d.get("id", "")) == id:
			return d
	return {}


## 第 generation 代药物面对的靶点变体下标（获批几代，疾病就进化几次，到最后一个变体为止）
static func variant_for(disease_id: String, generation: int) -> int:
	return clampi(generation, 0, maxi(0, (disease_cfg(disease_id).get("variants", []) as Array).size() - 1))


static func variant_id(disease_id: String, index: int) -> String:
	var variants: Array = disease_cfg(disease_id).get("variants", [])
	return String(variants[index].get("id", "")) if index < variants.size() else ""


## 当前靶点口袋的热点 [{site, want / avoid, fx}]
func pocket() -> Array:
	var variants: Array = disease_cfg(disease).get("variants", [])
	return variants[variant].get("pocket", []) if variant < variants.size() else []


## 每个口袋热点现在是否命中：[{site, want / avoid, fx, hit}]（want 命中是加成；avoid 命中是冲突）
func pocket_fits() -> Array:
	var out: Array = []
	for spot in pocket():
		var tags: Array = fragment(String(sites.get(String(spot.site), ""))).get("tags", [])
		var tag := String(spot.get("want", spot.get("avoid", "")))
		var entry: Dictionary = spot.duplicate()
		entry["hit"] = tags.has(tag)
		out.append(entry)
	return out


static func fragment(id: String) -> Dictionary:
	for f in config().get("fragments", []):
		if String(f.get("id", "")) == id:
			return f
	return {}


static func site_type(site_id: String) -> String:
	for s in config().get("sites", []):
		if String(s.get("id", "")) == site_id:
			return String(s.get("type", ""))
	return ""


static func can_place(fragment_id: String, site_id: String) -> bool:
	return (fragment(fragment_id).get("sites", []) as Array).has(site_type(site_id))


## 新分子：拿到起始片段包，位点为空
static func create() -> Molecule:
	var m := Molecule.new()
	m.inventory = (config().get("starter_kit", []) as Array).duplicate()
	return m


## 用 placement（位点 → 片段）整体替换当前结构；片段从「当前结构 + 库存」里取，取不到或位点类型不符则失败
func apply_layout(placement: Dictionary) -> bool:
	var pool: Array = inventory.duplicate()
	for site_id in sites:
		pool.append(sites[site_id])
	for site_id in placement:
		var frag := String(placement[site_id])
		if not can_place(frag, String(site_id)) or not pool.has(frag):
			return false
		pool.erase(frag)
	sites = placement.duplicate()
	inventory = pool
	_sync_alerts()
	return true


## 按预设方案摆放（取不到的片段跳过）
func apply_preset(preset_id: String) -> void:
	apply_sites(config().get("presets", {}).get(preset_id, {}))


## 按给定结构摆放（预设方案、分子谱系里的上一代）；取不到或放不下的片段跳过
func apply_sites(preset: Dictionary) -> void:
	var pool: Array = inventory.duplicate()
	for site_id in sites:
		pool.append(sites[site_id])
	var placement := {}
	for site_id in preset:
		var frag := String(preset[site_id])
		if pool.has(frag) and can_place(frag, String(site_id)):
			placement[site_id] = frag
			pool.erase(frag)
	apply_layout(placement)


## 属性值 {potency, selectivity, stability, solubility}（已含组合效果，限制在 range 内）
func properties() -> Dictionary:
	var cfg := config()
	var props := {}
	for p in PROPS:
		props[p] = int(cfg.get("base", {}).get(p, 1))
	for site_id in sites:
		var fx: Dictionary = fragment(String(sites[site_id])).get("fx", {})
		for p in fx:
			props[p] = int(props.get(p, 0)) + int(fx[p])
	for combo in active_combos():
		var fx: Dictionary = combo.get("fx", {})
		for p in fx:
			props[p] = int(props.get(p, 0)) + int(fx[p])
	for fit in pocket_fits():   # 与靶点口袋的契合：命中热点加成，撞上空间冲突扣分
		if bool(fit.hit):
			var fit_fx: Dictionary = fit.get("fx", {})
			for p in fit_fx:
				props[p] = int(props.get(p, 0)) + int(fit_fx[p])
	var lo := int(cfg.get("range", [0, 6])[0])
	var hi := int(cfg.get("range", [0, 6])[1])
	for p in PROPS:
		props[p] = clampi(int(props[p]), lo, hi)
	return props


## 当前触发的组合规则（相邻标签组合 / 某标签数量达到阈值），每个组合最多一次
func active_combos() -> Array:
	var out: Array = []
	for combo in config().get("combos", []):
		match String(combo.get("kind", "")):
			"adjacent":
				var need: Array = combo.get("tags", [])
				for pair in config().get("adjacent", []):
					var a := fragment(String(sites.get(pair[0], ""))).get("tags", []) as Array
					var b := fragment(String(sites.get(pair[1], ""))).get("tags", []) as Array
					if (a.has(need[0]) and b.has(need[1])) or (a.has(need[1]) and b.has(need[0])):
						out.append(combo)
						break   # 同一组合在分子上出现几次都只算一次
			"count":
				var n := 0
				for site_id in sites:
					if (fragment(String(sites[site_id])).get("tags", []) as Array).has(String(combo.get("tag", ""))):
						n += 1
				if n >= int(combo.get("min", 99)):
					out.append(combo)
	return out


## 当前结构带来的警示 id（片段自带 + 组合触发）
func alert_ids() -> Array:
	var ids: Array = []
	for site_id in sites:
		var a := String(fragment(String(sites[site_id])).get("alert", ""))
		if not a.is_empty() and not ids.has(a):
			ids.append(a)
	for combo in active_combos():
		var a := String(combo.get("alert", ""))
		if not a.is_empty() and not ids.has(a):
			ids.append(a)
	return ids


## 结构变化后：新出现的警示为 unknown，不再存在的警示移除；已排除 / 已确认的保留状态
func _sync_alerts() -> void:
	var now := alert_ids()
	for id in alerts.keys():
		if not now.has(id):
			alerts.erase(id)
	for id in now:
		if not alerts.has(id):
			alerts[id] = "unknown"


## 仍有风险的警示数（未验证 + 已确认）
func open_alerts() -> int:
	var n := 0
	for id in alerts:
		if String(alerts[id]) != "cleared":
			n += 1
	return n


func unknown_alerts() -> Array:
	return alerts.keys().filter(func(id: String) -> bool: return String(alerts[id]) == "unknown")


## 属性带来的战斗效果（game 拼进战斗上下文；stage 决定哪些只在特定阶段生效）
## {strength, start_block, weak, offtarget (bool), vulnerable_bonus, poison_bonus, enemy_poison, clinical_cost,
##  first_draw, first_energy, lines: [{key, args, prop}]}
func effects(stage: String) -> Dictionary:
	var p := properties()
	var fx := {"strength": 0, "start_block": 0, "weak": 0, "offtarget": false, "vulnerable_bonus": 0, "poison_bonus": 0,
		"enemy_poison": 0, "clinical_cost": 0, "first_draw": 0, "first_energy": 0, "lines": []}
	var lines: Array = []
	var pot := int(p.potency)
	var sel := int(p.selectivity)
	var stab := int(p.stability)
	var sol := int(p.solubility)
	var strength := (2 if pot >= 5 else 1) if pot >= 3 else 0
	if stab <= 1 and strength > 0:
		strength = strength / 2
		lines.append({"key": "mol.fx.unstable_strength", "args": [strength], "prop": "stability"})
	if strength > 0:
		fx.strength = strength
		lines.append({"key": "mol.fx.strength", "args": [strength], "prop": "potency"})
	if pot <= 1:
		fx.weak = 1
		lines.append({"key": "mol.fx.weak", "args": [], "prop": "potency"})
	if sel <= 1 and stage in ["候选化合物发现", "临床前研究"]:
		fx.offtarget = true
		lines.append({"key": "mol.fx.offtarget", "args": [], "prop": "selectivity"})
	if sel >= 3:
		fx.vulnerable_bonus = 2 if sel >= 5 else 1
		lines.append({"key": "mol.fx.vulnerable_plus" if sel >= 5 else "mol.fx.vulnerable", "args": [], "prop": "selectivity"})
	if stab >= 3:
		fx.poison_bonus = 1
		fx.enemy_poison = 2 if stab >= 5 else 0
		lines.append({"key": "mol.fx.poison_plus" if stab >= 5 else "mol.fx.poison_up", "args": [], "prop": "stability"})
	elif stab <= 1:
		fx.poison_bonus = -1
		lines.append({"key": "mol.fx.poison_down", "args": [], "prop": "stability"})
	if sol <= 1:
		fx.clinical_cost = 1
		lines.append({"key": "mol.fx.clinical_cost", "args": [], "prop": "solubility"})
	elif sol >= 3:
		fx.first_draw = 1
		fx.first_energy = 1 if sol >= 5 else 0
		lines.append({"key": "mol.fx.draw_plus" if sol >= 5 else "mol.fx.draw", "args": [], "prop": "solubility"})
	fx.lines = lines
	return fx


## 阶段考验：{has, passed, props, min, value, alerts_max}；该阶段没有考验时 has = false
func exam_result(stage: String) -> Dictionary:
	var exam: Dictionary = config().get("exams", {}).get(stage, {})
	if exam.is_empty():
		return {"has": false}
	if exam.has("alerts_max"):
		var n := open_alerts()
		return {"has": true, "passed": n <= int(exam.alerts_max), "alerts": true, "value": n, "min": int(exam.alerts_max)}
	var p := properties()
	var total := 0
	for prop in exam.get("props", []):
		total += int(p.get(prop, 0))
	return {"has": true, "passed": total >= int(exam.get("min", 0)), "alerts": false, "props": exam.get("props", []),
		"value": total, "min": int(exam.get("min", 0))}


## 「选择性 3 / 需 ≥4」「未排除的毒性警示 1 项（需全部排除）」这样的考验说明
static func exam_label(exam: Dictionary) -> String:
	if bool(exam.get("alerts", false)):
		return TranslationServer.translate("mol.exam.alerts_fmt") % int(exam.value)
	var names: Array = (exam.get("props", []) as Array).map(func(p: String) -> String: return TranslationServer.translate("prop." + p))
	return TranslationServer.translate("mol.exam.props_fmt") % ["+".join(names), int(exam.value), int(exam.min)]


## 暴露给敌人的结构弱点：位点 id 列表（敌人的 exploit 按它加伤害）
##   soft_spot 没被相邻卤素挡住的代谢软点；alert 还没排除的毒性警示片段；其它标签（如 lipophilic）按标签数
func exposed(tag: String) -> Array:
	var out: Array = []
	for site_id in sites:
		var frag := fragment(String(sites[site_id]))
		var tags: Array = frag.get("tags", [])
		match tag:
			"soft_spot":
				if tags.has("soft_spot") and not _shielded(String(site_id)):
					out.append(site_id)
			"alert":
				var a := String(frag.get("alert", ""))
				if not a.is_empty() and String(alerts.get(a, "unknown")) != "cleared":
					out.append(site_id)
			_:
				if tags.has(tag):
					out.append(site_id)
	out.sort()
	return out


## 这个位点是否被相邻的卤素（氟原子）挡住
func _shielded(site_id: String) -> bool:
	for pair in config().get("adjacent", []):
		if not (pair as Array).has(site_id):
			continue
		var other := String(pair[1] if String(pair[0]) == site_id else pair[0])
		if (fragment(String(sites.get(other, ""))).get("tags", []) as Array).has("halogen"):
			return true
	return false


## 当前组合带来的分子特性卡 id（同一组合触发多次也只给一张）
func signature_cards() -> Array:
	var ids: Array = []
	for combo in active_combos():
		var id := String(combo.get("card", ""))
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	return ids


## 一张卡和哪些属性「契合」：攻击 / 力量 ↔ 活性，破绽 ↔ 选择性，中毒 / 引爆 ↔ 稳定性，抽牌 / 能量 / 临床卡 ↔ 溶解度
static func card_affinity(card: Dictionary) -> Array:
	var out: Array = []
	var effects: Array = card.get("effects", [])
	var has_status := func(id: String) -> bool:
		return effects.any(func(e: Dictionary) -> bool: return String(e.get("op", "")) == "status" and String(e.get("id", "")) == id)
	var has_op := func(op: String) -> bool:
		return effects.any(func(e: Dictionary) -> bool: return String(e.get("op", "")) == op)
	if String(card.get("kind", "")) == "attack" or has_status.call("strength"):
		out.append("potency")
	if has_status.call("vulnerable"):
		out.append("selectivity")
	if has_status.call("poison") or has_op.call("detonate"):
		out.append("stability")
	if String(card.get("type", "")) == "clinical" or has_op.call("draw") or has_op.call("energy") or has_op.call("formulate"):
		out.append("solubility")
	return out


## 奖励卡池里这张卡的权重倍数（×10 的整数）：契合的属性越高越常出现；属性 ≤2 的契合不加成
func pool_weight(card: Dictionary) -> int:
	var p := properties()
	var mult := 1.0
	for prop in card_affinity(card):
		mult = maxf(mult, 1.0 + maxi(0, int(p[prop]) - 2) * 0.5)
	return roundi(mult * 10)


## 这张卡契合的「强项」（属性 ≥3），奖励界面用来标注
func strong_fits(card: Dictionary) -> Array:
	var p := properties()
	return card_affinity(card).filter(func(prop: String) -> bool: return int(p[prop]) >= 3)


## 「活性+2 溶解度−1」这样的短文本
static func fx_text(fx: Dictionary) -> String:
	var parts: Array[String] = []
	for p in PROPS:
		var v := int(fx.get(p, 0))
		if v != 0:
			parts.append("%s%s%d" % [TranslationServer.translate("prop." + p), "+" if v > 0 else "", v])
	return " ".join(parts)


## 修饰的规模：none（没变）/ local（只换了取代基）/ core（换了连接位 = 核心结构）
func change_kind(new_sites: Dictionary) -> String:
	var changed := false
	for site_id in _all_site_ids():
		if String(sites.get(site_id, "")) != String(new_sites.get(site_id, "")):
			if site_type(site_id) == "linker":
				return "core"
			changed = true
	return "local" if changed else "none"


static func _all_site_ids() -> Array:
	return (config().get("sites", []) as Array).map(func(s: Dictionary) -> String: return String(s.id))


func to_dict() -> Dictionary:
	return {"sites": sites.duplicate(), "inventory": inventory.duplicate(), "alerts": alerts.duplicate(),
		"disease": disease, "variant": variant}


static func from_dict(d: Dictionary) -> Molecule:
	var m := Molecule.new()
	for k in d.get("sites", {}):
		m.sites[String(k)] = String(d.sites[k])
	for id in d.get("inventory", []):
		m.inventory.append(String(id))
	for k in d.get("alerts", {}):
		m.alerts[String(k)] = String(d.alerts[k])
	m.disease = String(d.get("disease", ""))
	m.variant = int(d.get("variant", 0))
	return m
