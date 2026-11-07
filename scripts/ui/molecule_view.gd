class_name MoleculeView
extends Control
## Live scaffold shared by battle, hub and editor. Battle and hub paint a character pose;
## editing and compact views show the structure and its fragment positions.

signal site_clicked(site_id: String)

var molecule: Molecule = null
var interactive := false
var selected := ""
var unit := 0.0:
	set(value):
		if not is_equal_approx(value, unit):
			unit = value
			queue_redraw()
var _time := 0.0
var _hover := ""
var compact := false
var character := false  # Character illustration in battle and observation; editor remains a readable plan.
var _profile := ""
## 角色模式的全部动作（待机、出招、受击、护盾、状态、倒下）由这一个状态机输出，布局位置从不被改写
var motion := CharacterMotion.new(CharacterProfiles.molecule(), 11)
var _shell := 0.0       # 护盾外壳展开进度（1 → 0）
var _flash := {}        # 属性 → 剩余闪光强度（1 → 0）
var _site_flash := {}   # 位点 → [剩余强度, 颜色]（被敌人攻击的片段闪红）
var _hit := 0.0         # 受击：抖动 + 泛红
var _cheer := 0.0       # 胜利：跳一跳、发光
var form := 1:          # 进化形态 1–5
	set(value):
		form = value
		queue_redraw()
var mood := ""          # 持续反应：focus / sad；空为按 ratio 自动（idle / worried）
var ratio := 1.0        # 生命比例（低了会担心）
var _react := ""        # 短暂反应：hurt / happy / fierce
var _react_t := 0.0
var _glow_burst := 0.0  # 进化时的闪光
var _jolt := {}         # 位点 → [偏移, 速度]：受击时片段被震开再弹回
var _offset := Vector2.ZERO   # 本帧整体位移（抖动 / 浮动 / 跳跃）
var preview_frag := ""  # 鼠标悬停在片段上时：先把它试装到选中的位点上看看
var _snap := {}         # 位点 → 吸附反馈强度（1 → 0）
var _links: Array = []  # 组合触发时点亮的化学键：{a, b, t, color}

const SITE_R := 28.0
const TYPE_MARK := {"linker": "连", "ring": "环", "terminal": "端"}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	if interactive:
		mouse_filter = Control.MOUSE_FILTER_STOP
	elif tooltip_text.is_empty():
		mouse_filter = Control.MOUSE_FILTER_IGNORE


## 分子某项属性的效果生效：给这项属性加分的片段闪一下
func flash(prop: String) -> void:
	_flash[prop] = 1.0


## 指定位点闪一下（敌人专攻的结构弱点用红色）
func flash_sites(site_ids: Array, color := Color(1.0, 0.35, 0.3)) -> void:
	for id in site_ids:
		_site_flash[String(id)] = [1.0, color]


## 片段装上位点：从 from（本控件坐标）飞入后弹簧吸附，相邻片段被轻轻顶开再回位
func snap(site_id: String, from := Vector2.INF) -> void:
	var by_id := {}
	for site in Molecule.config().get("sites", []):
		by_id[String(site.id)] = site
	if not by_id.has(site_id):
		return
	var c := site_center(by_id[site_id])
	var start: Vector2 = (from - c).limit_length(150.0) if from != Vector2.INF else (c - size * Vector2(0.5, 0.48)).normalized() * 18.0
	_snap[site_id] = 1.0
	_jolt[site_id] = [start, Vector2.ZERO]
	for id in by_id:
		var other := site_center(by_id[id])
		if id != site_id and other.distance_to(c) < _scale() * 2.4:
			_jolt[id] = [Vector2.ZERO, (other - c).normalized() * 150.0]


## 点亮组合涉及的化学键：一道光沿键跑过
func link_glow(pairs: Array, color: Color) -> void:
	for pair in pairs:
		_links.append({"a": String(pair[0]), "b": String(pair[1]), "t": 1.0, "color": color})


## 受击：主体后挫、骨架弹性形变、末端片段被震开后延迟弹回；strength 随伤害大小（轻击 / 重击不同）
func hit(strength := 1.0) -> void:
	_hit = minf(1.0, 0.5 + strength * 0.4)
	react("hurt", 0.7)
	motion.hit(strength)
	var spread := clampf(strength, 0.4, 2.0) * (0.55 if character else 1.0)
	for site in Molecule.config().get("sites", []):
		var dir := Vector2.from_angle(randf() * TAU)
		if character:   # 冲击从敌人方向来：片段先被推向后方
			dir = (dir + Vector2(-1.2, 0)).normalized()
		_jolt[String(site.id)] = [Vector2.ZERO, dir * randf_range(260.0, 520.0) * spread]


func cheer() -> void:
	_cheer = 1.0
	react("happy", 3.0)


## 原地出招：小幅蓄力后前送释放。返回出手 / 命中的时间
func attack() -> Dictionary:
	react("fierce", 0.45)
	return motion.attack()


## 近身突进：reach 为从当前出招尖端到目标的像素距离
func charge(reach: Vector2) -> Dictionary:
	react("fierce", 0.6)
	motion.unit = _scale()
	return motion.attack(reach, "attack")


func recoil(px: float) -> void:
	motion.recoil(px)


## 护盾：收缩成防御姿态，外层展开一圈切面保护结构
func defend() -> void:
	motion.defend()
	_shell = 1.0


## 状态影响：颤一下并按状态着色
func afflict(color: Color) -> void:
	motion.status(color)


func collapse() -> void:
	motion.die()


## 新战斗开始：清掉上一场留下的动作、外壳和抖动
func reset_motion() -> void:
	motion.reset()
	_shell = 0.0
	_jolt.clear()
	_hit = 0.0
	_react_t = 0.0


func react(kind: String, duration := 0.8) -> void:
	_react = kind
	_react_t = duration


func set_mood(kind: String) -> void:
	mood = kind


func level_up() -> void:
	_glow_burst = 1.0
	react("happy", 2.0)


## 当前反应：短暂反馈优先，其次持续状态，最后看生命
func expression() -> String:
	if _react_t > 0:
		return _react
	if not mood.is_empty():
		return mood
	return "worried" if ratio < 0.35 else "idle"


func set_molecule(m: Molecule) -> void:
	molecule = m
	_profile = ""
	if character and m != null:
		var props := m.properties()
		if int(props.potency) >= 5 and int(props.potency) > int(props.selectivity):
			_profile = "potent"
		elif int(props.selectivity) >= 4 and int(props.selectivity) > int(props.potency):
			_profile = "selective"
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		if character:
			motion.step(delta)
			_shell = maxf(0.0, _shell - delta * 1.1)
		for prop in _flash.keys():
			_flash[prop] = float(_flash[prop]) - delta * 0.9
			if float(_flash[prop]) <= 0.0:
				_flash.erase(prop)
		for id in _site_flash.keys():
			_site_flash[id][0] = float(_site_flash[id][0]) - delta * 0.8
			if float(_site_flash[id][0]) <= 0.0:
				_site_flash.erase(id)
		for id in _snap.keys():
			_snap[id] = float(_snap[id]) - delta * 2.4
			if float(_snap[id]) <= 0.0:
				_snap.erase(id)
		for link in _links:
			link.t = float(link.t) - delta * 0.65
		_links = _links.filter(func(link: Dictionary) -> bool: return float(link.t) > 0.0)
		_hit = maxf(0.0, _hit - delta * 2.5)
		_cheer = maxf(0.0, _cheer - delta * 0.35)
		_glow_burst = maxf(0.0, _glow_burst - delta * 0.6)
		_react_t = maxf(0.0, _react_t - delta)
		for id in _jolt.keys():   # 阻尼弹簧：片段被震开后弹回原位（分步积分，掉帧时也不会发散）
			var j: Array = _jolt[id]
			var left := minf(delta, 0.1)
			while left > 0.0:
				var dt := minf(left, 1.0 / 120.0)
				left -= dt
				var v: Vector2 = j[1] + (-j[0] * 260.0 - j[1] * 14.0) * dt
				j[0] = (j[0] as Vector2) + v * dt
				j[1] = v
			if (j[0] as Vector2).length() < 0.2 and (j[1] as Vector2).length() < 2.0:
				_jolt.erase(id)
		var hurt := Color(1, 1 - 0.45 * _hit, 1 - 0.45 * _hit)
		self_modulate = hurt.lerp(Color(motion.tint, 1.0), motion.tint.a * 0.4)
		queue_redraw()


func _site_r() -> float:
	if compact:
		return maxf(7.0, _scale() * 0.36)
	return minf(SITE_R, _scale() * (0.62 if interactive else 0.44))


func _scale() -> float:
	if unit > 0:
		return unit
	return minf(size.x / (8.85 if character else 8.0), size.y / (6.25 if character else 4.9))


func site_center(site: Dictionary) -> Vector2:
	if character:
		return size * Vector2(0.5, 0.48) + MoleculeCharacter.anchor(String(site.id), _profile) * _scale()
	var p: Array = site.get("pos", [0, 0])
	var projected := Vector2(float(p[0]) + float(p[1]) * 0.12, float(p[1]) * 0.88)
	return size * Vector2(0.5, 0.48) + projected * _scale()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		var hit := _site_at((event as InputEventMouseMotion).position)
		if hit != _hover:
			_hover = hit
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hit.is_empty() else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _site_at((event as InputEventMouseButton).position)
		if not hit.is_empty():
			GameAudio.sfx("click")
			site_clicked.emit(hit)


## 画图用的位点位置：叠加受击时的弹开偏移
func _pos(site: Dictionary) -> Vector2:
	var j: Array = _jolt.get(String(site.id), [])
	return site_center(site) + (j[0] if not j.is_empty() else Vector2.ZERO)


func _site_at(pos: Vector2) -> String:
	var nearest := ""
	var distance := INF
	for site in Molecule.config().get("sites", []):
		var center := site_center(site)
		var id := String(site.id)
		var frag_id := String(molecule.sites.get(id, "")) if molecule != null else ""
		var inside := center.distance_to(pos) <= _site_r() + 4
		if not frag_id.is_empty():
			inside = inside or MoleculeSpecimen.bounds(frag_id, center, _scale()).grow(4).has_point(pos)
		if inside and center.distance_squared_to(pos) < distance:
			nearest = id
			distance = center.distance_squared_to(pos)
	return nearest


func _draw() -> void:
	var cfg := Molecule.config()
	var center := size * Vector2(0.5, 0.48)
	var k := _scale()
	var offset := Vector2(0, -absf(sin(_time * 9.0)) * 10.0 * _cheer)
	if character:
		_offset = offset
		_draw_character(center + offset, k)
		return
	offset.x += sin(_time * 70.0) * 6.0 * _hit
	_offset = offset
	draw_set_transform(offset)
	if _cheer > 0:
		Shading.glow(self, center, k * 2.6, Color(0.55, 1.0, 0.75, 0.3 * _cheer))
	var font := get_theme_default_font()
	var bw := maxf(1.2, k * 0.12)
	var bond_col := Color("b6c7a5")
	# 键：环上位点和连接位接在核心环上，末端位接在连接位上
	var by_id := {}
	for site in cfg.get("sites", []):
		by_id[String(site.id)] = site
	for site in cfg.get("sites", []):
		var c := _pos(site)
		var anchor: Vector2
		match String(site.type):
			"terminal":
				anchor = _pos(by_id["L1" if float(site.pos[0]) < 0 else "L2"])
			_:
				anchor = center + (c - center).normalized() * Vector2(k * 0.64, k * 0.42)
		var filled := molecule != null and molecule.sites.has(String(site.id))
		draw_line(anchor, c, Color(UIKit.INK, 1.0 if filled else 0.35), bw + 3, true)
		draw_line(anchor, c, Color(bond_col, 1.0 if filled else 0.35), bw, true)
		var bond_snap := float(_snap.get(String(site.id), 0.0))
		if bond_snap > 0.0:
			draw_line(anchor, c, Color(1.0, 0.97, 0.8, bond_snap), bw + 2.0 * bond_snap, true)
	MoleculeSpecimen.draw_fragment(self, "core", center, k)
	# 位点：绘制对应化学片段；名字只在编辑器里写
	var r := _site_r()
	for site in cfg.get("sites", []):
		var id := String(site.id)
		var c := _pos(site)
		var frag_id := String(molecule.sites.get(id, "")) if molecule != null else ""
		var is_sel := interactive and id == selected
		if is_sel and not preview_frag.is_empty():
			frag_id = preview_frag
		if is_sel:
			var pulse := 0.5 + 0.5 * sin(_time * 5.0)
			Shading.glow(self, c, r + 16 + pulse * 4, Color(UIKit.ACCENT, 0.4))
			draw_arc(c, r + 6, 0, TAU, 40, Color(UIKit.ACCENT, 0.9), 2.5, true)
		elif interactive and id == _hover:
			draw_arc(c, r + 5, 0, TAU, 40, Color(1, 1, 1, 0.4), 1.5, true)
		if frag_id.is_empty():
			if not interactive:
				MoleculeSpecimen.draw_fragment(self, "hydrogen", c, k)   # 空位：只留一个小氢原子似的点
				continue
			draw_circle(c, r, Color(0.06, 0.08, 0.11, 0.95))
			for d in 16:
				var a0 := d * TAU / 16.0
				draw_arc(c, r, a0, a0 + TAU / 32.0, 4, Color(0.6, 0.68, 0.76, 0.6), 1.5, true)
			var mark := String(TYPE_MARK.get(String(site.type), "?"))
			var mw := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, c + Vector2(-mw * 0.5, 6), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.68, 0.76, 0.8))
			continue
		var frag := Molecule.fragment(frag_id)
		var col := Color.from_string(String(frag.get("color", "#9fb4c8")), Color(0.6, 0.7, 0.8))
		for prop in _flash:   # 效果生效时，给这项属性加分的片段发亮
			if int(frag.get("fx", {}).get(prop, 0)) > 0:
				var f := float(_flash[prop])
				Shading.glow(self, c, r * (1.6 + (1.0 - f) * 0.8), Color(col.lightened(0.4), 0.7 * f))
		if _site_flash.has(id):
			var sf: Array = _site_flash[id]
			var t := float(sf[0])
			Shading.glow(self, c, r * (1.7 + (1.0 - t) * 0.9), Color(sf[1], 0.8 * t))
			draw_arc(c, r + 3, 0, TAU, 32, Color(sf[1], t), 2.5, true)
		var snap_t := float(_snap.get(id, 0.0))
		if snap_t > 0.0:
			Shading.glow(self, c, r * (1.5 + (1.0 - snap_t) * 1.2), Color(col.lightened(0.45), 0.75 * snap_t))
			draw_arc(c, r * (1.0 + (1.0 - snap_t) * 1.5), 0, TAU, 40, Color(col.lightened(0.5), snap_t), 1.0 + 2.5 * snap_t, true)
		MoleculeSpecimen.draw_fragment(self, frag_id, c, k * (1.0 + 0.22 * snap_t * snap_t))
		if not String(frag.get("alert", "")).is_empty():
			_draw_alert(c + Vector2(r * 0.85, -r * 0.85), 0.6 if compact else (1.0 if interactive else 0.75))
		if not interactive or not (is_sel or id == _hover):
			continue   # 名字只写在正在看的位置上，其余交给形状
		var frag_name := tr("frag." + frag_id)
		var fs := 12
		var label_y := -MoleculeSpecimen.bounds(frag_id, c, k).size.y * 0.5 - 7.0
		var nw := font.get_string_size(frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, c + Vector2(-nw * 0.5, label_y), frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.75))
		draw_string(font, c + Vector2(-nw * 0.5, label_y), frag_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	_draw_links(by_id)
	if interactive:
		_draw_pocket(font)


const TRAIL_WEIGHT := {"T1": 1.0, "T2": 1.0, "L1": 0.55, "L2": 0.55, "R1": 0.4, "R2": 0.4, "R3": 0.4}


## 分子单位空间到控件坐标的变换：动画以两只脚的中点为基点倾斜、压扁，偏移叠加在布局位置之上
func _body_matrix(center: Vector2, k: float) -> Transform2D:
	var feet: Vector2 = (MoleculeCharacter.SUPPORTS[0] + MoleculeCharacter.SUPPORTS[1]) * 0.5
	var shift := Vector2(motion.value("x"), motion.value("y"))
	var local := Transform2D(0.0, feet + shift) * Transform2D(motion.angle(), motion.squash(), 0.0, Vector2.ZERO) * Transform2D(0.0, -feet)
	return Transform2D(0.0, center) * Transform2D(0.0, Vector2.ONE * k, 0.0, Vector2.ZERO) * local


func _draw_character(center: Vector2, k: float) -> void:
	if k <= 0.0:
		return
	motion.unit = k
	var pose := motion.value("pose")
	var bend := motion.value("bend")
	var t := motion.time
	var points := {}
	var i := 0
	for site in Molecule.config().sites:
		var id := String(site.id)
		var weight := float(TRAIL_WEIGHT.get(id, 0.4))
		# 末端片段：跟着身体走但慢半拍，再加一点各自的延迟摆动
		var drift := Vector2(CharacterMotion.noise(t * 1.3, i * 1.7), CharacterMotion.noise(t * 1.05, i * 2.9 + 5.0)) * 0.035
		points[id] = MoleculeCharacter.anchor(id, _profile, pose) + (_pos(site) - site_center(site)) * 0.62 / k \
			+ (motion.lag + drift * motion.amount) * weight
		i += 1
	var ribbon := motion.trail + Vector2(0.0, sin(t * 2.3) * 0.05 + CharacterMotion.noise(t * 1.7, 3.0) * 0.04) * motion.amount
	var body := _body_matrix(center, k)
	draw_set_transform_matrix(body)
	MoleculeCharacter.draw(self, points, molecule.sites if molecule != null else {}, form, pose + bend, ribbon)
	draw_set_transform(Vector2.ZERO)
	for site in Molecule.config().sites:
		var id := String(site.id)
		var point := body * (points[id] as Vector2)
		var frag := Molecule.fragment(String(molecule.sites.get(id, ""))) if molecule != null else {}
		if _site_flash.has(id):
			var cue: Array = _site_flash[id]
			draw_arc(point, k * 0.28, -0.8, 4.3, 20, Color(cue[1], cue[0]), 2.2, true)
		for prop in _flash:
			if int(frag.get("fx", {}).get(prop, 0)) > 0:
				draw_arc(point, k * 0.33, -PI, 0.75, 16, Color(MoleculeCharacter.BONE, _flash[prop]), 1.8, true)
	if _shell > 0.0:
		_draw_shell(body, k)
	if _glow_burst > 0.0:
		draw_arc(center, k * (1.2 + 0.45 * (1.0 - _glow_burst)), -2.1, 1.3, 36,
			Color(MoleculeCharacter.GOLD, _glow_burst), 2.5, true)


## 护盾外壳：一圈骨白切面板从正面折叠处展开成弧，和场景同一束左上方的光；之后淡成一道薄边
func _draw_shell(body: Transform2D, k: float) -> void:
	var age := 1.0 - _shell
	var open := clampf(age / 0.28, 0.0, 1.0)
	open = 1.0 + 2.2 * pow(open - 1.0, 3) + 1.2 * pow(open - 1.0, 2)   # 带一点回弹的展开
	var alpha := clampf(_shell * 2.4, 0.0, 1.0)
	var center := MoleculeCharacter.FRAME.get_center()
	var radii := Vector2(4.1, 3.3) * (0.72 + 0.28 * open)
	var ink := Color(PaintedStyle.INK_EDGE, 0.85 * alpha)
	var light := PaintedStyle.LIGHT.normalized()
	for n in 7:
		var a := lerpf(0.0, (n - 3) * 0.36, open)    # 折叠时都叠在正面，展开后排成弧
		var mid := center + Vector2(cos(a) * radii.x, sin(a) * radii.y)
		var out := (mid - center).normalized()
		var side := out.orthogonal()
		var plate := PackedVector2Array([
			body * (mid - out * 0.36), body * (mid + side * 0.42), body * (mid + out * 0.26 + side * 0.18),
			body * (mid + out * 0.26 - side * 0.18), body * (mid - side * 0.42)])
		var lit := maxf(0.0, -out.dot(light)) * 0.35 + 0.65
		draw_colored_polygon(plate, Color(Color("cfe8dc").darkened(0.35 * (1.0 - lit)), 0.62 * alpha))
		var edge := plate.duplicate()
		edge.append(plate[0])
		draw_polyline(edge, ink, maxf(1.5, k * 0.05), true)
		draw_line(plate[1], plate[2], Color(MoleculeCharacter.BONE, 0.9 * alpha * lit), maxf(1.0, k * 0.035), true)
	if open >= 1.0:
		var rim := PackedVector2Array()
		for n in 25:
			var a := lerpf(-1.25, 1.25, n / 24.0)
			rim.append(body * (center + Vector2(cos(a) * radii.x, sin(a) * radii.y) * 1.08))
		draw_polyline(rim, Color("9fe3cf", 0.45 * alpha), maxf(1.0, k * 0.04), true)


## 出招尖端：live 时跟随当前动画姿态和位移；否则给出静止站位、指定姿态下的位置（用来计算突进距离）
func attack_tip(pose := 0.0, live := true) -> Vector2:
	if character:
		var center := size * Vector2(0.5, 0.48)
		var tip := MoleculeCharacter.attack_anchor(molecule.sites if molecule != null else {}, _profile,
			motion.value("pose") if live else pose)
		return _body_matrix(center, _scale()) * tip if live else center + tip * _scale()
	var bounds := visual_bounds()
	return Vector2(bounds.end.x, bounds.get_center().y)


## 动画让身体离开站位的水平距离（影子跟着走，但留在地面上）
func motion_offset() -> Vector2:
	return motion.offset() if character else Vector2.ZERO


func support_points() -> PackedVector2Array:
	var supports := PackedVector2Array()
	if character:
		for point in MoleculeCharacter.SUPPORTS:
			supports.append(size * Vector2(0.5, 0.48) + point * _scale() + Vector2(motion_offset().x, 0.0))
	return supports


func _draw_links(by_id: Dictionary) -> void:
	for link in _links:
		if not by_id.has(link.a) or not by_id.has(link.b):
			continue
		var a := _pos(by_id[link.a])
		var b := _pos(by_id[link.b])
		var t := float(link.t)
		var col: Color = link.color
		draw_line(a, b, Color(col, 0.35 * t), 9.0, true)
		draw_line(a, b, Color(col.lightened(0.5), t), 2.5, true)
		Shading.glow(self, a.lerp(b, fmod((1.0 - t) * 2.2, 1.0)), 16.0, Color(1, 1, 1, t))


## 靶点口袋热点：位点外一圈虚线（绿＝想要的标签，红＝空间冲突），下方写提示；命中时实线发亮
func _draw_pocket(font: Font) -> void:
	if molecule == null or molecule.disease.is_empty() or compact:
		return
	var r := _site_r()
	var by_site := {}
	for fit in molecule.pocket_fits():
		var list: Array = by_site.get(String(fit.site), [])
		list.append(fit)
		by_site[String(fit.site)] = list
	for site in Molecule.config().get("sites", []):
		var fits: Array = by_site.get(String(site.id), [])
		if fits.is_empty():
			continue
		var c := _pos(site)
		var y := r + 13.0
		var looking := String(site.id) == selected or String(site.id) == _hover
		for fit in fits:
			var want: bool = fit.has("want")
			var hit: bool = bool(fit.hit)
			var col := (Color(0.45, 0.95, 0.6) if want else Color(1.0, 0.45, 0.4))
			var rr := r + (7.0 if want else 11.0)
			if hit:
				draw_arc(c, rr, 0, TAU, 40, Color(col, 0.95), 2.5, true)
			else:
				for d in 12:
					var a0 := d * TAU / 12.0
					draw_arc(c, rr, a0, a0 + TAU / 24.0, 4, Color(col, 0.55), 1.5, true)
			if not looking:
				continue
			var label := tr("pocket.%s.%s" % ["want" if want else "avoid", String(fit.get("want", fit.get("avoid", "")))])
			var fs := 11
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, c + Vector2(-w * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
			draw_string(font, c + Vector2(-w * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col if (hit == want) else Color(col, 0.75))
			y += 13.0


func _draw_alert(p: Vector2, k := 1.0) -> void:
	var tri := PackedVector2Array([p + Vector2(0, -9) * k, p + Vector2(9, 7) * k, p + Vector2(-9, 7) * k])
	draw_colored_polygon(tri, UIKit.GOLD)
	draw_line(p + Vector2(0, -3) * k, p + Vector2(0, 2) * k, Color(0.1, 0.08, 0.02), 2.0 * k)
	draw_circle(p + Vector2(0, 4.5) * k, 1.2 * k, Color(0.1, 0.08, 0.02))


## Stable structural footprint, independent of bobbing and hit displacement.
func visual_bounds() -> Rect2:
	var center := size * Vector2(0.5,0.48)
	if character:
		var frame := MoleculeCharacter.FRAME
		return Rect2(center + frame.position * _scale(), frame.size * _scale())
	var result := MoleculeSpecimen.bounds("core",center,_scale())
	for site in Molecule.config().sites:
		var id := String(molecule.sites.get(String(site.id),"")) if molecule != null else ""
		result = result.merge(MoleculeSpecimen.bounds("hydrogen" if id.is_empty() else id,site_center(site),_scale()))
	return result
