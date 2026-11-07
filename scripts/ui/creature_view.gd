class_name CreatureView
extends Control
## 独立插画决定敌人的剪影；运动性格（CharacterProfiles）决定它怎么活着、怎么出手、怎么挨打。
## 插画被切成网格绘制，网格顶点按性格做局部形变（口袋张合、外壳起伏、细胞局部鼓胀……），
## 整体位移、倾斜、压扁统一来自 CharacterMotion；控件的布局位置从不被动画改写。

const LEGACY_CELLS := {"blob": 0, "cell": 1, "crystal": 2, "cloud": 3, "spiky": 4, "molecule": 5}
# Source boxes follow the visible alpha bounds inside each production sheet.
const GEOMETRIC_PORTRAITS := {
	"geometric-foes": {
		"activity_cliff": Rect2(22, 118, 964, 634),
		"resistant_clone": Rect2(1042, 171, 708, 578),
	},
	"geometric-foes-a": {
		"off_target": Rect2(40, 20, 372, 402),
		"poor_solubility": Rect2(466, 130, 406, 270),
		"metabolite": Rect2(916, 46, 379, 360),
		"herg": Rect2(1355, 13, 404, 412),
		"hepatotox": Rect2(14, 483, 414, 361),
		"animal_bias": Rect2(460, 466, 408, 391),
		"free_radical": Rect2(902, 461, 410, 402),
		"genotox": Rect2(1432, 456, 234, 416),
	},
	"geometric-foes-b": {
		"tox_storm": Rect2(26, 54, 393, 364),
		"infusion_reaction": Rect2(462, 114, 408, 247),
		"pk_variance": Rect2(913, 89, 388, 290),
		"cytokine_storm": Rect2(1335, 38, 425, 390),
		"dlt": Rect2(4, 466, 431, 393),
		"placebo": Rect2(488, 553, 359, 223),
		"enroll_drag": Rect2(901, 539, 414, 237),
		"progression": Rect2(1334, 466, 439, 384),
	},
	"geometric-foes-c": {
		"endpoint_miss": Rect2(49, 128, 376, 238),
		"protocol_dev": Rect2(465, 77, 400, 323),
		"safety_signal": Rect2(902, 106, 414, 240),
		"center_pd": Rect2(1350, 54, 409, 350),
		"center_ae": Rect2(46, 466, 354, 386),
		"center_drop": Rect2(483, 480, 361, 377),
		"last_molecule": Rect2(900, 457, 421, 398),
	},
}

var shape := "blob"
var _portrait := "painted-enemies"
var _source := Rect2()
var _geometric := false
var color := Color(0.6, 0.5, 0.9)
var radius := 60.0
var menace := 0        # 0 普通 / 1 精英 / 2 Boss
var flash := 0.0       # 受击闪白 0..1
var dying := 0.0       # 死亡进度 0..1
var _time := 0.0
var _seed := 0.0
var _blink := 0.0
var _next_blink := 2.0
var _hit_spot := Vector2.ZERO
var hp_ratio := 1.0                 # 当前生命比例（molecule 形态用来熄灭原子）
var _mol_atoms: Array[Vector2] = []  # molecule 形态：单位半径内的原子坐标（外圈在后）
var _mol_bonds: Array[Vector2i] = []
var _mol_colors: Array[int] = []
var strain := 0.0        # 剂量限制性毒性：剂量 / 最高剂量。身体随之膨胀、开裂、发烫
var windup := false      # 下一招很痛：身体后缩蓄力，底下透出危险光
var _surge := 0.0        # 剂量刚提高：一次猛烈的膨胀
var _shown_strain := 0.0
var _windup := 0.0
var _id := ""
var personality := "ooze"
var motion: CharacterMotion
var poison := 0.0        # 中毒程度 0..1：颜色发绿、形体出现不规则鼓动
var _shown_poison := 0.0
var _fx: Control         # 不受身份色着色的效果层（受击光、裂纹、毒滴）
var guarded := false     # 正有护盾：外壳类闭合起来
var special := false     # 下一招是特殊动作：提前露出征兆（局部异化、结合口袋发亮）
var death_style := "dissolve"
var boss := false
var _guard := 0.0
var _contract := 0.0     # 外壳受击时的一次收缩
var _special := 0.0
var _critical := 0.0     # Boss 临界状态（生命 ≤ 25%）
var _shards: Array = []  # 碎裂死亡时每个网格块的飞散方向


func setup(def: Dictionary, boss := false, elite := false) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	shape = String(def.get("shape", "blob"))
	color = Color.from_string(String(def.get("color", "#9b6cf2")), Color(0.6, 0.5, 0.9))
	radius = 58.0 * float(def.get("size", 1.0))
	menace = 2 if boss else (1 if elite else 0)
	_seed = float(hash(String(def.get("id", ""))) % 1000) / 100.0
	_id = String(def.get("id", ""))
	personality = CharacterProfiles.personality(_id, shape)
	self.boss = boss
	death_style = CharacterProfiles.death_style(_id, personality, boss)
	motion = CharacterMotion.new(CharacterProfiles.enemy(personality), hash(_id) % 100000 + 1)
	for sheet in GEOMETRIC_PORTRAITS:
		var entries: Dictionary = GEOMETRIC_PORTRAITS[sheet]
		if entries.has(_id) and UIKit.art(sheet) != null:
			_portrait = sheet
			_source = entries[_id]
			_geometric = true
			break
	if not _geometric:
		_source = PaintedArt.sprite_source(_portrait, int(LEGACY_CELLS.get(shape, 0)))
	if shape != "molecule" and not _geometric:
		var tint := ShaderMaterial.new()
		tint.shader = load("res://assets/shaders/enemy_tint.gdshader")
		tint.set_shader_parameter("target_hue", color.h)
		tint.set_shader_parameter("strength", 0.82 if color.s > 0.25 else 0.35)
		material = tint
	elif _portrait in ["geometric-foes-a", "geometric-foes-c"]:
		var edge := ShaderMaterial.new()
		edge.shader = preload("res://assets/shaders/painted_edge.gdshader")
		if _portrait == "geometric-foes-c":
			edge.set_shader_parameter("fringe", Vector2(0.90, 0.96))
			texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		material = edge
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	custom_minimum_size = Vector2(radius * 2.8, radius * 2.6)
	if shape == "molecule":
		_build_molecule()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit(point := Vector2(-1,-1), strength := 1.0) -> void:
	flash = 1.0
	var body := visible_body_rect()
	_hit_spot = point if point.x >= 0 else body.position + body.size * Vector2(0.28,0.52)
	if motion:
		motion.hit(strength * (0.5 if _guard > 0.5 else 1.0), Vector2(1, 0))   # 闭合的外壳挨打几乎不动
	if personality == "shell":
		_contract = 1.0   # 外壳受击时收缩一下


func _process(delta: float) -> void:
	_time += delta
	flash = maxf(0.0, flash - delta * 4.0)
	_next_blink -= delta
	if _next_blink <= 0:
		_blink = 1.0
		_next_blink = randf_range(2.0, 4.5)
	_blink = maxf(0.0, _blink - delta * 7.0)
	_surge = maxf(0.0, _surge - delta * 1.6)
	_shown_strain = move_toward(_shown_strain, strain, delta * 0.8)
	_windup = move_toward(_windup, 1.0 if windup else 0.0, delta * 2.5)
	_shown_poison = move_toward(_shown_poison, poison, delta * 0.8)
	_guard = move_toward(_guard, 1.0 if guarded and dying <= 0.0 else 0.0, delta * (4.0 if guarded else 1.2))
	_contract = maxf(0.0, _contract - delta * 3.0)
	_special = move_toward(_special, 1.0 if special and dying <= 0.0 else 0.0, delta * 2.0)
	_critical = move_toward(_critical, 1.0 if boss and hp_ratio <= 0.25 and hp_ratio > 0.0 else 0.0, delta * 1.5)
	if motion:
		motion.unit = maxf(visible_body_rect().size.y, 1.0)
		# 剂量越高、越接近临界，待机越急促
		motion.tempo = 1.0 + _shown_strain * 0.9 + _critical * 0.5
		motion.step(delta)
	if not _geometric and material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("heat", clampf(_shown_strain * 0.45 + _surge * 0.5, 0.0, 1.0))
	queue_redraw()
	if _fx:
		_fx.queue_redraw()


## 剂量提高：猛地鼓胀一下，裂纹随之扩张
func surge() -> void:
	_surge = 1.0


func _draw() -> void:
	if not _source.has_area():
		return
	var pivot := Vector2(size.x * 0.5, size.y)
	draw_set_transform_matrix(_body_transform())
	var neutral := Color.WHITE if _geometric else Color(0.85, 0.86, 0.93)
	var tint := neutral.lerp(Color(1.20, 1.10, 0.97), flash * 0.64)
	if motion and motion.tint.a > 0.0:
		tint = tint.lerp(Color(motion.tint, 1.0), motion.tint.a * 0.35)
	tint.a = 1.0 - dying
	var body := visible_body_rect()
	body.position -= pivot
	_draw_mesh(body, tint)
	draw_set_transform(Vector2.ZERO)


const GRID := 7


## 把插画切成网格画出来：顶点按运动性格形变，局部动起来而轮廓与笔触不被拉坏
func _draw_mesh(body: Rect2, tint: Color) -> void:
	var texture := UIKit.art(_portrait)
	if texture == null:
		return
	var dimensions := texture.get_size()
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var sick := Color(0.72, 1.0, 0.5)
	for row in GRID + 1:
		for col in GRID + 1:
			var uv := Vector2(float(col) / GRID, float(row) / GRID)
			points.append(body.position + body.size * (uv + _deform(uv.x, uv.y)))
			uvs.append((_source.position + _source.size * uv) / dimensions)
			var mottle := 0.6 + 0.4 * sin(_time * 3.0 + uv.x * 5.0 + uv.y * 3.0)
			var c := tint.lerp(Color(sick, tint.a), _shown_poison * 0.38 * mottle)
			c.a = tint.a
			colors.append(c)
	var indices := PackedInt32Array()
	for row in GRID:
		for col in GRID:
			var i := row * (GRID + 1) + col
			indices.append_array([i, i + 1, i + GRID + 2, i, i + GRID + 2, i + GRID + 1])
	if dying > 0.0 and death_style in ["shatter", "rupture"]:
		_draw_shards(body, points, uvs, colors, texture)
		return
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors, uvs,
		PackedInt32Array(), PackedFloat32Array(), texture.get_rid())


## 碎裂：每个网格块各自飞散、翻转，从外圈先散；裂开的边透出亮光
func _draw_shards(body: Rect2, points: PackedVector2Array, uvs: PackedVector2Array, colors: PackedColorArray, texture: Texture2D) -> void:
	if _shards.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_id)
		for k in GRID * GRID:
			_shards.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1.2, 0.3), rng.randf_range(-2, 2)))
	var center := body.get_center()
	var k := 0
	for row in GRID:
		for col in GRID:
			var i := row * (GRID + 1) + col
			var quad := PackedInt32Array([i, i + 1, i + GRID + 2, i + GRID + 1])
			var mid := Vector2.ZERO
			for q in quad:
				mid += points[q]
			mid /= 4.0
			var spread: Vector3 = _shards[k]
			var outward := (mid - center) / maxf(body.size.x, 1.0)
			var travel := maxf(0.0, dying * 1.3 - 0.3 + outward.length() * 0.4)
			var offset := (outward * 2.0 + Vector2(spread.x, spread.y)) * body.size.x * 0.35 * travel + Vector2(0, body.size.y * 0.35 * travel * travel)
			var spin := spread.z * travel
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			var tex := PackedVector2Array()
			for q in quad:
				pts.append(mid + (points[q] - mid).rotated(spin) * (1.0 - travel * 0.3) + offset)
				tex.append(uvs[q])
				var c := colors[q]
				c.a *= clampf(1.4 - travel, 0.0, 1.0)
				cols.append(c)
			draw_primitive(pts, cols, tex, texture)
			k += 1


## 局部形变（以身体尺寸为单位）。u 从左到右，v 从上到下；脚底一行固定在地面上（毒云除外）
func _deform(u: float, v: float) -> Vector2:
	if motion == null:
		return Vector2.ZERO
	var o := motion.value("open")
	var t := _time
	var amp := motion.amount
	var pin := clampf(1.0 - v, 0.0, 1.0)
	var disp := Vector2.ZERO
	match personality:
		"pocket":
			disp = Vector2(u - 0.5, v - 0.42) * o * 0.09 * pin
			if _id == "activity_cliff":
				# 受体口袋：收拢时上方的褶皱压进开口，张开时向上翻起
				var fold := v / 0.34 if v < 0.34 else (lerpf(1.0, 0.29, (v - 0.34) / 0.29) if v < 0.63 else lerpf(0.29, 0.0, (v - 0.63) / 0.37))
				disp.y += (clampf(-o, -1.2, 1.2) * 0.11 + _windup * 0.06 - flash * 0.05) * fold
		"shell":
			var d := Vector2(u - 0.5, v - 0.55)
			var rim := clampf(d.length() * 2.2, 0.0, 1.0)
			var a := d.angle()
			var swell := CharacterMotion.noise(a * 3.0 + t * 0.55, _seed) * 0.013 + CharacterMotion.noise(a * 5.0 - t * 0.8, _seed + 2.0) * 0.006
			var quake := motion.value("bend")
			disp = d.normalized() * swell * rim * amp
			disp += Vector2(sin(v * 13.0 + u * 4.0), cos(u * 11.0 + v * 3.0)) * quake * 0.045 * rim
			disp *= pin * 0.8 + 0.2
		"pulse":
			for i in 3:
				var c := Vector2(0.5 + 0.26 * CharacterMotion.noise(t * 0.4, i * 3.0 + _seed), 0.5 + 0.22 * CharacterMotion.noise(t * 0.35, i * 5.0 + 1.0))
				var rate := (1.3 + 0.4 * i) * (1.0 + _shown_poison * 0.9)
				var bulge := maxf(0.0, CharacterMotion.noise(t * rate, i * 7.0 + _seed)) * (0.05 + 0.05 * _shown_poison) * amp + o * 0.03
				var d := Vector2(u, v) - c
				disp += d.normalized() * bulge * exp(-d.length_squared() / 0.06)
			disp *= pin * 0.7 + 0.3
		"pump":
			# 门控节律：快速收紧、慢慢放开，像有节拍的泵
			var phase := fmod(t / 1.7 + _seed, 1.0)
			var gate := phase / 0.12 if phase < 0.12 else exp(-(phase - 0.12) * 6.0)
			var squeeze := gate * 0.045 * amp - o * 0.05
			disp = Vector2((u - 0.5) * -squeeze, -absf(squeeze) * 0.25 * (1.0 - v)) * pin
		"spark":
			disp = Vector2(CharacterMotion.noise(t * 9.0 + v * 7.0, _seed), CharacterMotion.noise(t * 8.0 + u * 6.0, _seed + 4.0)) * 0.006 * amp
		"ooze":
			# 黏稠：上部下坠时下部向两边摊开，波动从上往下慢半拍传过身体
			disp = Vector2((u - 0.5) * o * 0.05 * v, o * 0.035 * (1.0 - v))
			disp.y += sin(t * 1.3 - v * 2.2 + _seed) * 0.014 * (1.0 - v) * amp
		"cloud":
			disp = Vector2(CharacterMotion.noise(v * 4.0 + t * 1.2, _seed) * 0.03 + (u - 0.5) * o * 0.05,
				CharacterMotion.noise(u * 3.5 + t * 0.9, _seed + 3.0) * 0.025 + (v - 0.5) * o * 0.03) * (0.5 + 0.5 * amp)
	if personality == "shell":
		# 外壳闭合：两片壳向中间合拢、顶部压低；受击时同样收一下
		var close := maxf(_guard, _contract * 0.7)
		disp += Vector2(-(u - 0.5) * 0.13 * close, 0.06 * close * (1.0 - v))
	if _special > 0.0 and CharacterProfiles.SPECIAL_SPOTS.has(_id) and personality == "pulse":
		# 局部异化：管壁上一处鼓起，节律变快
		var spot: Vector2 = CharacterProfiles.SPECIAL_SPOTS[_id][0]
		var d := Vector2(u, v) - spot
		disp += d.normalized() * _special * (0.06 + 0.02 * sin(t * 9.0)) * exp(-d.length_squared() / 0.03)
	if dying > 0.0:
		match death_style:
			"dissolve":   # 失去张力：结构松垮下垂，边缘先散
				disp += Vector2((u - 0.5) * dying * 0.25, dying * dying * 0.35 * (1.0 - v)) \
					+ Vector2(CharacterMotion.noise(v * 6.0 + t * 3.0, _seed), CharacterMotion.noise(u * 6.0 + t * 2.0, _seed)) * dying * 0.05
			"melt":
				disp += Vector2((u - 0.5) * dying * 0.5 * v, dying * 0.55 * (1.0 - v))
			"disperse":
				disp += Vector2(u - 0.5, v - 0.5) * dying * 0.6 + Vector2(CharacterMotion.noise(v * 5.0 + t, _seed), 0) * dying * 0.1
			"seal":   # 口袋彻底合拢、封死
				disp += Vector2(-(u - 0.5) * dying * 0.3, dying * 0.25 * (1.0 - v) * (1.0 - v))
	if _shown_poison > 0.0 and personality != "pulse":
		disp += Vector2(CharacterMotion.noise(t * 2.3 + v * 5.0, _seed), CharacterMotion.noise(t * 2.0 + u * 5.0, _seed + 1.0)) * 0.012 * _shown_poison * pin
	return disp


func action_contact() -> Vector2:
	var body := visible_body_rect()
	var mark := Vector2(0.28, 0.52)
	if _geometric:
		mark = Vector2(0.26, 0.49) if _id == "activity_cliff" else Vector2(0.34, 0.49)
	var point := body.position + body.size * mark
	return _body_transform() * (point - Vector2(size.x * 0.5, size.y)) if _geometric else point


func _body_transform() -> Transform2D:
	var pivot := Vector2(size.x * 0.5, size.y)
	var lean := -0.028 if menace == 2 else 0.0
	var swell := 1.0 + _shown_strain * 0.12 + _surge * 0.08
	var squeeze := 1.0 - _windup * (0.035 + 0.01 * sin(_time * 9.0))
	var jitter := Vector2(sin(_time * 37.0), cos(_time * 41.0)) * (_shown_strain * 2.4 + _surge * 4.0)
	var sq := motion.squash() if motion else Vector2.ONE
	var angle := lean + _windup * 0.05 + (motion.angle() if motion else 0.0) + sin(_time * 54.0) * flash * 0.012
	if personality == "agile":   # 脱靶蛋白：特殊动作前朝目标探身，抖得更厉害
		angle -= _special * (0.07 + 0.03 * sin(_time * 23.0))
	jitter += Vector2(sin(_time * 31.0), cos(_time * 27.0)) * _critical * 2.5   # 临界：整个身体在发颤
	var deformation := Vector2((sq.x - dying * 0.32) * swell * (2.0 - squeeze), (sq.y - dying * 0.3) * swell * squeeze)
	var shift := motion.offset() if motion else Vector2.ZERO
	return Transform2D(angle, deformation, 0.0, pivot + jitter + Vector2(_windup * 10.0, 0) + shift)


## 不着身份色的效果层：受击光、蓄力光、剂量毒性的裂纹 / 暴露的核心 / 滴落的毒液
func _draw_fx() -> void:
	var body := visible_body_rect()
	var c := body.get_center() + Vector2(0, body.size.y * 0.06)
	var r := minf(body.size.x, body.size.y) * 0.5
	var alpha := 1.0 - dying
	if _windup > 0.01:
		Shading.glow(_fx, Vector2(c.x, body.end.y - 6), r * 1.3, Color(1.0, 0.3, 0.2, 0.32 * _windup * alpha))
	if _id == "dlt" or strain > 0.0:
		var pivot := Vector2(size.x * 0.5, size.y)
		var chest := body.position + body.size * Vector2(0.69, 0.57)
		var pose := _body_transform()
		_draw_toxicity(pose * (chest - pivot), r * 0.47 * pose.x.length(), alpha)
	var pose := _body_transform()
	var pivot2 := Vector2(size.x * 0.5, size.y)
	if _special > 0.01 and CharacterProfiles.SPECIAL_SPOTS.has(_id):
		_draw_special(body, pose, pivot2, alpha)
	if _critical > 0.01 and dying <= 0.0:
		_draw_critical(pose * (c - pivot2), r, alpha)
	if _windup > 0.01 and strain > 0.0:   # 剂量毒性蓄力：体内的危险脉冲从胸口一圈圈扩出去
		var chest := pose * (body.position + body.size * Vector2(0.69, 0.57) - pivot2)
		for k in 2:
			var beat := fmod(_time * (1.4 + strain) + k * 0.5, 1.0)
			_fx.draw_arc(chest, r * (0.2 + 0.6 * beat), 0, TAU, 36, Color(1.0, 0.45, 0.2, (1.0 - beat) * 0.7 * _windup * alpha), 3.0, true)
	if dying > 0.0:
		_draw_death_fx(body, pose, pivot2, c, r)
	if flash > 0:
		Shading.glow(_fx,_hit_spot,85,Color(UIKit.GOLD,flash*0.65))
		_fx.draw_arc(_hit_spot,28+flash*14,-1.1,1.2,20,Color(UIKit.PAPER,flash*0.8),2,true)


## 特殊动作的征兆：脱靶蛋白的结合口袋和结合位亮起；感染细胞的异化点长出暗紫的病灶
func _draw_special(body: Rect2, pose: Transform2D, pivot: Vector2, alpha: float) -> void:
	var spots: Array = CharacterProfiles.SPECIAL_SPOTS[_id]
	var throb := 0.6 + 0.4 * sin(_time * 8.0)
	var r := minf(body.size.x, body.size.y)
	for i in spots.size():
		var p := pose * (body.position + body.size * (spots[i] as Vector2) - pivot)
		if personality == "pulse":
			var blot := PackedVector2Array()
			for k in 14:
				var a := k * TAU / 14.0
				blot.append(p + Vector2.from_angle(a) * r * 0.13 * _special * (1.0 + 0.3 * sin(a * 3.0 + _time * 4.0)))
			Shading.glow(_fx, p, r * 0.22 * _special, Color(0.75, 0.3, 0.9, 0.5 * throb * alpha))
			_fx.draw_colored_polygon(blot, Color(0.18, 0.08, 0.24, 0.85 * _special * alpha))
			blot.append(blot[0])
			_fx.draw_polyline(blot, Color(0.95, 0.55, 1.0, 0.9 * _special * alpha), 2.0, true)
			for k in 3:   # 向外蔓延的异化纹
				var a := k * 2.1 + 0.5
				_fx.draw_line(p, p + Vector2.from_angle(a) * r * 0.28 * _special, Color(0.85, 0.45, 1.0, 0.6 * _special * alpha), 1.5, true)
		else:
			# 结合口袋（分叉处）：两圈向内收的亮环；金色结合位：小而亮的光点
			if i == 0:
				for k in 2:
					var shrink := fmod(_time * 1.6 + k * 0.5, 1.0)
					_fx.draw_arc(p, r * (0.2 - 0.12 * shrink), 0, TAU, 28, Color(1.0, 0.88, 0.5, (0.3 + 0.7 * shrink) * _special * alpha), 2.4, true)
			else:
				Shading.glow(_fx, p, r * 0.07 * (0.8 + 0.4 * throb), Color(1.0, 0.92, 0.6, 0.8 * _special * alpha))


## Boss 临界：身体里几道发亮的裂纹一起搏动，读起来是「快撑不住了」
func _draw_critical(c: Vector2, r: float, alpha: float) -> void:
	var throb := 0.55 + 0.45 * sin(_time * 7.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	Shading.glow(_fx, c, r * 0.5, Color(1.0, 0.35, 0.2, 0.35 * throb * _critical * alpha))
	for i in 6:
		var a := rng.randf() * TAU
		var pts := PackedVector2Array([c + Vector2.from_angle(a) * r * 0.1])
		for k in 3:
			a += rng.randf_range(-0.5, 0.5)
			pts.append(pts[-1] + Vector2.from_angle(a) * r * 0.16)
		_fx.draw_polyline(pts, Color(1.0, 0.6, 0.3, (0.4 + 0.5 * throb) * _critical * alpha), 2.2, true)


## 死亡的效果层：溃散时碎屑飘散，封闭时一道光从合缝里漏出，过量破裂时橙色的光从裂缝喷出
func _draw_death_fx(body: Rect2, pose: Transform2D, pivot: Vector2, c: Vector2, r: float) -> void:
	var center := pose * (c - pivot)
	var fade_out := 1.0 - dying
	match death_style:
		"dissolve", "melt", "disperse":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(_id) + 5
			for i in 16:
				var start := body.position + body.size * Vector2(rng.randf(), rng.randf_range(0.1, 0.9))
				var drift := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-1.0, -0.2)) * r * dying
				var p := pose * (start - pivot) + drift
				var bit := rng.randf_range(3.0, 7.0) * (1.0 - dying * 0.5)
				_fx.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -bit), p + Vector2(bit, 0), p + Vector2(0, bit * 0.7), p + Vector2(-bit * 0.8, 0)]),
					Color(color.lightened(0.3), fade_out * 0.8))
		"seal":
			var seam := pose * (body.position + body.size * Vector2(0.3, 0.45) - pivot)
			Shading.glow(_fx, seam, r * 0.9, Color(1.0, 0.92, 0.7, sin(dying * PI) * 0.6))
			_fx.draw_line(seam - Vector2(r * 0.7, 0), seam + Vector2(r * 0.7, 0), Color(1.0, 0.95, 0.8, sin(dying * PI)), 3.0, true)
		"rupture":
			Shading.glow(_fx, center, r * (1.0 + dying), Color(1.0, 0.5, 0.15, (1.0 - dying) * 0.7))
		"burst":
			Shading.glow(_fx, center, r * (0.8 + dying * 1.5), Color(1.0, 0.95, 0.75, (1.0 - dying) * 0.8))


## 剂量限制性毒性：每加一档剂量多几道发烫的裂纹；生命过半后核心露出来；剂量高时毒液往下滴
func _draw_toxicity(c: Vector2, r: float, alpha: float) -> void:
	var s := _shown_strain
	var throb := 0.6 + 0.4 * sin(_time * (2.0 + s * 6.0))
	var hot := Color(1.0, 0.55, 0.2)
	var cracks := int(round(2 + s * 7)) + (2 if hp_ratio < 0.5 else 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 731
	for i in 15:
		var a := rng.randf() * TAU
		var len := r * rng.randf_range(0.30, 0.66)
		var pts := PackedVector2Array([c + Vector2.from_angle(a) * r * rng.randf_range(0.14, 0.50)])
		for k in 4:
			a += rng.randf_range(-0.45, 0.45)
			pts.append(pts[pts.size() - 1] + Vector2.from_angle(a) * len / 4.0)
		if i >= cracks:
			continue
		var glow := Color(hot, (0.35 + 0.5 * throb) * alpha * minf(1.0, 0.4 + s + _surge))
		_fx.draw_polyline(pts, Color(hot.darkened(0.3), glow.a * 0.5), 6.0, true)
		_fx.draw_polyline(pts, glow, 2.2, true)
		_fx.draw_polyline(pts, Color(1.0, 0.92, 0.7, glow.a * 0.8), 0.8, true)
	if hp_ratio < 0.5:
		Shading.glow(_fx, c, r * (0.6 + 0.1 * throb), Color(1.0, 0.35, 0.15, 0.7 * alpha))
		Shading.sphere(_fx, c, r * (0.17 + 0.03 * throb), Color(1.0, 0.8, 0.45, alpha), 1.0)
		_fx.draw_arc(c, r * (0.24 + 0.04 * throb), 0, TAU, 40, Color(1.0, 0.9, 0.6, 0.7 * alpha), 2.0, true)
	if s > 0.2:
		for i in int(s * 6):
			var t := fmod(_time * 0.7 + i * 0.37, 1.0)
			var x := c.x + (fmod(i * 0.618, 1.0) - 0.5) * r * 1.3
			var p := Vector2(x, c.y + r * 0.7 + t * r * 0.55)
			_fx.draw_circle(p, 3.0 * (1.0 - t * 0.5), Color(0.75, 1.0, 0.35, (1.0 - t) * 0.85 * alpha))
	if _surge > 0.0:
		Shading.glow(_fx, c, r * (1.2 + (1.0 - _surge) * 0.6), Color(1.0, 0.3, 0.15, 0.5 * _surge * alpha))


func _wobble_points(c: Vector2, r: float, amp: float, lobes: int, speed: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		var k := 1.0 + amp * sin(lobes * a + _time * speed + _seed) + amp * 0.6 * sin((lobes + 2) * a - _time * speed * 1.4)
		pts.append(c + Vector2(cos(a), sin(a)) * r * k)
	return pts


## 团块（聚集体、酶、外排泵等）：有明暗的胶质身体 + 半透明外膜 + 体内漂浮的颗粒和表面孔洞
func _draw_blob(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var outer := _wobble_points(c, r * 1.06, 0.06, 3, 1.3)
	draw_colored_polygon(outer, Color(body.lightened(0.3), 0.18 * alpha))
	var pts := _wobble_points(c, r, 0.06, 3, 1.3)
	Shading.shaded_polygon(self, pts, c, r, body)
	for i in 7:   # 体内颗粒（有深度：小而暗的在后）
		var a := _seed * 3.0 + i * 0.9 + _time * 0.25 * (1.0 if i % 2 == 0 else -1.0)
		var d := r * (0.25 + 0.4 * fmod(i * 0.37 + _seed, 1.0))
		var gr := r * (0.06 + 0.035 * (i % 3))
		Shading.sphere(self, c + Vector2(cos(a), sin(a) * 0.8) * d, gr, Color(body.lightened(0.25), 0.75 * alpha), 0.6)
	for i in 4:   # 表面孔洞
		var a := _seed + i * 1.7
		_ellipse(c + Vector2(cos(a), sin(a)) * r * 0.72, Vector2(r * 0.07, r * 0.045), Color(body.darkened(0.55), 0.6 * alpha))
	pts.append(pts[0])
	draw_polyline(pts, Color(body.lightened(0.35), 0.55 * alpha), 2.0, true)


## 细胞：纤毛、双层膜、有明暗的胞质、细胞核（带核仁）、线粒体与囊泡
func _draw_cell(c: Vector2, r: float, body: Color, alpha: float) -> void:
	for i in 26:   # 纤毛：柔软弯曲的细线
		var a := TAU * i / 26.0 + _time * 0.15
		var base := c + Vector2.from_angle(a) * r * 1.02
		var sway := 0.22 * sin(_time * 3.0 + i * 0.8)
		var mid := c + Vector2.from_angle(a + sway * 0.5) * r * 1.13
		var tip := c + Vector2.from_angle(a + sway) * r * 1.24
		draw_polyline(PackedVector2Array([base, mid, tip]), Color(body.lightened(0.2), 0.55 * alpha), 1.5, true)
	var pts := _wobble_points(c, r, 0.04, 5, 1.0)
	Shading.shaded_polygon(self, pts, c, r, Color(body.lightened(0.05), 0.92 * alpha))
	var membrane := pts.duplicate()
	membrane.append(pts[0])
	draw_polyline(membrane, Color(body.lightened(0.45), 0.7 * alpha), 2.5, true)
	draw_polyline(_wobble_points(c, r * 0.93, 0.04, 5, 1.0) + PackedVector2Array([_wobble_points(c, r * 0.93, 0.04, 5, 1.0)[0]]),
		Color(body.darkened(0.3), 0.5 * alpha), 1.5, true)
	for i in 3:   # 线粒体
		var a := _seed + i * 2.1 + _time * 0.2
		var p := c + Vector2(cos(a), sin(a)) * r * 0.55
		draw_set_transform(p, a + 0.6)
		_ellipse(Vector2.ZERO, Vector2(r * 0.13, r * 0.06), Color(body.darkened(0.35), 0.85 * alpha))
		draw_line(Vector2(-r * 0.09, 0), Vector2(r * 0.09, 0), Color(body.lightened(0.3), 0.6 * alpha), 1.2, true)
		draw_set_transform(Vector2.ZERO)
	for i in 5:   # 囊泡
		var a := _seed * 2.0 + i * 1.25 - _time * 0.3
		draw_arc(c + Vector2(cos(a), sin(a)) * r * 0.68, r * 0.045, 0, TAU, 12, Color(body.lightened(0.5), 0.7 * alpha), 1.2, true)
	var nucleus := c + Vector2(r * 0.26, r * 0.22)
	Shading.sphere(self, nucleus, r * 0.3, Color(body.darkened(0.4), alpha), 0.6)
	Shading.sphere(self, nucleus + Vector2(r * 0.05, r * 0.03), r * 0.1, Color(body.darkened(0.65), alpha), 0.4)


## 尖刺（脱靶激酶、活性氧、DNA 损伤……）：有明暗的衣壳球 + 一圈带球头的刺突蛋白 + 淡淡的表面网格
func _draw_spiky(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var spikes := 14
	var rot := _time * 0.2
	for i in spikes:
		var a := rot + TAU * i / spikes
		var length := r * (1.38 + 0.06 * sin(_time * 3.0 + i))
		var base := c + Vector2.from_angle(a) * r * 0.85
		var tip := c + Vector2.from_angle(a) * length
		draw_line(base, tip, Color(body.darkened(0.35), alpha), r * 0.07, true)
		draw_line(base, tip, Color(body.lightened(0.2), 0.6 * alpha), r * 0.025, true)
		Shading.sphere(self, tip, r * 0.1, Color(body.lightened(0.15), alpha), 0.7)
	Shading.sphere(self, c, r * 0.9, body)
	for i in 6:   # 衣壳表面的六边形网格
		var a := rot * 0.5 + i * TAU / 6.0
		var p := c + Vector2.from_angle(a) * r * 0.45
		var hex := PackedVector2Array()
		for k in 7:
			hex.append(p + Vector2.from_angle(k * TAU / 6.0) * r * 0.2)
		draw_polyline(hex, Color(body.lightened(0.4), 0.22 * alpha), 1.2, true)


## 晶体（hERG 通道、结合口袋……）：渐变的多面体刻面 + 内部折射线 + 星芒高光
func _draw_crystal(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var sides := 6
	var rot := _time * 0.15 + _seed
	var outer: Array[Vector2] = []
	for i in sides:
		outer.append(c + Vector2.from_angle(rot + TAU * i / sides) * r * Vector2(1.0, 1.25))
	var top := c + Vector2(-r * 0.12, -r * 0.18)   # 偏心的顶点，让刻面更立体
	for i in sides:
		var tri := PackedVector2Array([top, outer[i], outer[(i + 1) % sides]])
		var light := 0.5 + 0.5 * cos(rot + TAU * (i + 0.5) / sides + 2.3)
		Shading.shaded_polygon(self, tri, c, r * 1.2, body.darkened(0.35).lerp(body.lightened(0.4), light))
	for i in sides:
		draw_line(top, outer[i], Color(1, 1, 1, 0.3 * alpha), 1.5, true)
		draw_line(outer[i], outer[(i + 1) % sides], Color(body.lightened(0.5), 0.8 * alpha), 2.0, true)
	for i in 3:   # 内部折射线
		var a := rot * 2.0 + i * 2.0
		draw_line(c + Vector2.from_angle(a) * r * 0.2, c + Vector2.from_angle(a + 0.8) * r * 0.75, Color(1, 1, 1, 0.12 * alpha), 1.0, true)
	var tw := 0.5 + 0.5 * sin(_time * 3.0 + _seed)
	var star := outer[0].lerp(top, 0.3)
	draw_line(star - Vector2(r * 0.18 * tw, 0), star + Vector2(r * 0.18 * tw, 0), Color(1, 1, 1, 0.8 * alpha), 1.5, true)
	draw_line(star - Vector2(0, r * 0.18 * tw), star + Vector2(0, r * 0.18 * tw), Color(1, 1, 1, 0.8 * alpha), 1.5, true)
	Shading.glow(self, star, r * 0.15, Color(1, 1, 1, 0.6 * tw * alpha))


## 毒云（器官毒性、细胞因子风暴……）：几团半透明、有明暗的烟团 + 内部辉光 + 向上飘散的颗粒
func _draw_cloud(c: Vector2, r: float, body: Color, alpha: float) -> void:
	Shading.glow(self, c, r * 1.4, Color(body, 0.35 * alpha))
	for i in 9:
		var a := TAU * i / 9.0 + _time * 0.2
		var d := r * (0.55 + 0.12 * sin(_time * 1.3 + i))
		var p := c + Vector2(cos(a) * d * 1.2, sin(a) * d * 0.8)
		Shading.sphere(self, p, r * (0.46 + 0.06 * sin(_time * 2.0 + i * 2.0)), Color(body.darkened(0.15), 0.6 * alpha), 0.3)
	Shading.sphere(self, c, r * 0.72, Color(body, 0.9 * alpha), 0.5)
	for i in 14:
		var t := fmod(_time * 0.35 + i * 0.07, 1.0)
		var a := i * 2.4 + _seed
		var p := c + Vector2(cos(a), sin(a)) * r * (0.6 + t * 0.9) + Vector2(0, -t * r * 0.6)
		Shading.glow(self, p, r * 0.08 * (1.0 - t) + 2.0, Color(body.lightened(0.5), (1.0 - t) * 0.8 * alpha))


## 与标题页 / 总览的 MoleculeArt 同一套多环结构（6 个苯环 + 侧链），归一化到单位半径
func _build_molecule() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1024
	var centers := [Vector2.ZERO, Vector2(1.732, 0), Vector2(0.866, 1.5), Vector2(-0.866, 1.5), Vector2(-1.732, 0), Vector2(0.866, -1.5)]
	var index_of := {}
	var pts: Array[Vector2] = []
	for ring in centers:
		var ids: Array[int] = []
		for k in 6:
			var a := PI / 6 + k * TAU / 6
			var p: Vector2 = ring + Vector2(cos(a), sin(a))
			var key := Vector2i(roundi(p.x * 100), roundi(p.y * 100))
			if not index_of.has(key):
				index_of[key] = pts.size()
				pts.append(p)
				_mol_colors.append(0 if rng.randf() < 0.65 else rng.randi_range(1, 4))
			ids.append(index_of[key])
		for k in 6:
			var b := Vector2i(mini(ids[k], ids[(k + 1) % 6]), maxi(ids[k], ids[(k + 1) % 6]))
			if not _mol_bonds.has(b):
				_mol_bonds.append(b)
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= pts.size()
	var extent := 0.0
	for p in pts:
		extent = maxf(extent, (p - centroid).length())
	for p in pts:
		_mol_atoms.append((p - centroid) / extent)


func _draw_molecule(c: Vector2, r: float, body: Color, alpha: float) -> void:
	var hurt := clampf(1.0 - hp_ratio, 0.0, 1.0)
	var spin := _time * (0.25 if hp_ratio > 0.5 else 0.6)
	var tone := body.lerp(Color(1.0, 0.35, 0.35), (0.5 + 0.5 * sin(_time * 5.0)) * 0.6 if hp_ratio <= 0.5 else 0.0)
	var span := r * 1.25
	# 金色光环
	for i in 12:
		var a := -spin * 0.6 + i * TAU / 12.0
		draw_arc(c, span * 1.12, a, a + TAU / 24.0, 6, Color(1.0, 0.85, 0.4, 0.6 * alpha), 3.0, true)
	var pts: Array[Vector2] = []
	for p in _mol_atoms:
		pts.append(c + p.rotated(spin) * span * Vector2(1.0, 0.9))
	# 熄灭顺序：离中心越远越先熄灭
	var order := range(_mol_atoms.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _mol_atoms[a].length() > _mol_atoms[b].length())
	var dark := {}
	for k in int(round(hurt * order.size() * 0.85)):
		dark[order[k]] = true
	for b in _mol_bonds:
		var lit := not dark.has(b.x) and not dark.has(b.y)
		draw_line(pts[b.x], pts[b.y], Color(tone, (0.3 if lit else 0.1) * alpha), 10.0, true)
		draw_line(pts[b.x], pts[b.y], Color(tone.lightened(0.35), (0.9 if lit else 0.25) * alpha), 3.5, true)
	var palette := [Color(0.95, 0.97, 1.0), Color(0.45, 0.75, 1.0), Color(0.6, 0.48, 0.95), Color(0.95, 0.72, 0.35), Color(0.93, 0.45, 0.45)]
	for i in pts.size():
		var col: Color = palette[_mol_colors[i]]
		if dark.has(i):
			draw_circle(pts[i], r * 0.07, Color(0.25, 0.27, 0.3, 0.8 * alpha))
		else:
			draw_circle(pts[i], r * 0.13, Color(col, 0.2 * alpha))
			draw_circle(pts[i], r * 0.08, Color(col.lerp(Color.WHITE, flash * 0.8), alpha))
	# 核心（脸画在这里）
	draw_circle(c, r * 0.5, Color(0.05, 0.06, 0.09, 0.9 * alpha))
	draw_circle(c, r * 0.46, Color(tone.darkened(0.35).lerp(Color.WHITE, flash * 0.6), alpha))
	draw_arc(c, r * 0.5, 0, TAU, 40, Color(1.0, 0.85, 0.4, 0.9 * alpha), 3.0, true)


## 眼睛：有光泽的眼球 + 带颜色的虹膜和竖瞳，朝向玩家（左）；精英和 Boss 是向内下斜的细长杏眼，显得凶；不画嘴
func _draw_face(c: Vector2, r: float, alpha: float) -> void:
	var eye_r := r * (0.15 if menace == 0 else 0.14)
	var gap := r * 0.3
	var look := Vector2(-eye_r * 0.3, eye_r * 0.08)
	var iris := color.lightened(0.55) if menace == 0 else Color(1.0, 0.75, 0.3)
	var squint := 1.0 if menace == 0 else 0.55
	for side in [-1, 1]:
		var e := c + Vector2(side * gap, 0)
		var open := (1.0 - _blink) * squint
		Shading.glow(self, e, eye_r * 1.9, Color(0, 0, 0, 0.35 * alpha))
		draw_set_transform(e, side * 0.28 if menace > 0 else 0.0)
		_ellipse(Vector2.ZERO, Vector2(eye_r * 1.1, eye_r * maxf(open, 0.08)), Color(0.95, 0.96, 0.92, alpha))
		if open > 0.2:
			var h := eye_r * minf(0.6, open)
			_ellipse(look, Vector2(eye_r * 0.6, h), Color(iris, alpha))
			_ellipse(look, Vector2(eye_r * 0.15, h * 0.85), Color(0.05, 0.04, 0.06, alpha))
			draw_circle(look + Vector2(-eye_r * 0.22, -h * 0.4), eye_r * 0.13, Color(1, 1, 1, 0.9 * alpha))
		var rim := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			rim.append(Vector2(cos(a) * eye_r * 1.1, sin(a) * eye_r * maxf(open, 0.08)))
		draw_polyline(rim, Color(0, 0, 0, 0.55 * alpha), 1.5, true)
		draw_set_transform(Vector2.ZERO)


func _ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)


func visible_body_rect() -> Rect2:
	var source_size := _source.size if _source.has_area() else size
	var factor := minf(size.x / maxf(1, source_size.x), size.y / maxf(1, source_size.y))
	var extent := source_size * factor
	return Rect2(Vector2((size.x-extent.x)*0.5,size.y-extent.y),extent)
