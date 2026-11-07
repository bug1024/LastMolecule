class_name CharacterMotion
extends RefCounted
## 角色动画状态机：一个角色的位移、倾斜、形变全部从这里的弹簧通道输出。
## 角色的布局位置（Control.position）只由布局决定，动画只给出相对偏移，所以连续战斗不会漂移。
## 动作由「阶段」组成：每个阶段只给通道设定目标值和弹簧硬度，真实运动由弹簧追随目标产生，
## 加速、减速、过冲回弹都是物理结果；新动作随时可以打断旧动作，从当前位置和速度接着走，不会跳帧。
## 待机由不成周期的噪声、偶发的姿态调整和呼吸构成；动作期间待机自动收敛。

enum State { IDLE, ANTICIPATION, ATTACK, HIT, DEFEND, STATUS, DEATH, RECOVERY }

const STATE_KEYS := {
	State.ANTICIPATION: "anticipation", State.ATTACK: "attack", State.HIT: "hit",
	State.DEFEND: "defend", State.STATUS: "status", State.DEATH: "death", State.RECOVERY: "recovery",
}
## x / y 为位移（以 unit 为单位）；angle 为倾斜（弧度）；sx / sy 为以脚底为基点的缩放；
## pose 为出招姿态（分子骨架前探）；open 为张合 / 膨胀；bend 为骨架弹性弯曲 / 外壳震颤
const CHANNELS := ["x", "y", "angle", "sx", "sy", "pose", "open", "bend"]
const REST := {"sx": 1.0, "sy": 1.0}
const MAX_STEP := 1.0 / 120.0

var state := State.IDLE
var profile: Dictionary = {}
var unit := 50.0                 # 1 个动作单位的像素
var amount := 1.0                # 动态幅度：降低动态效果时变小
var time := 0.0
var lag := Vector2.ZERO          # 末端片段：滞后于身体位移的量（单位）
var trail := Vector2.ZERO        # 丝带：比末端更软的跟随
var heavy := false               # 本次受击是否重击
var tint := Color(1, 1, 1, 0)    # 状态影响的着色（a 为强度，自行衰减）

var _reach := Vector2.ZERO       # 本次攻击要到达的偏移（单位）
var _chain: Array = []           # 待播放的状态队列：[State, phases]
var _phases: Array = []
var _phase := -1
var _phase_left := 0.0
var _value := {}
var _velocity := {}
var _target := {}
var _stiff := {}                 # 本阶段各通道的 [k, zeta]
var _idle_weight := 1.0
var _adjust := {}                # 偶发的姿态调整目标
var _adjust_left := 2.0
var _lag_pos := Vector2.ZERO
var _lag_vel := Vector2.ZERO
var _trail_pos := Vector2.ZERO
var _trail_vel := Vector2.ZERO
var _seed := 0.0
var _rng := RandomNumberGenerator.new()


func _init(motion_profile: Dictionary = {}, seed_value := 0) -> void:
	profile = motion_profile
	_rng.seed = seed_value if seed_value != 0 else 7
	_seed = float(seed_value % 997) * 0.37
	reset()


## 回到静止待机：清空所有通道、速度和队列（每场战斗开始时调用，防止残留）
func reset() -> void:
	state = State.IDLE
	_chain.clear()
	_phases = []
	_phase = -1
	_phase_left = 0.0
	for c in CHANNELS:
		_value[c] = float(REST.get(c, 0.0))
		_velocity[c] = 0.0
		_target[c] = float(REST.get(c, 0.0))
		_stiff[c] = _default_spring(c)
	_adjust = {}
	_adjust_left = _rng.randf_range(1.5, 3.5)
	_idle_weight = 1.0
	_lag_pos = Vector2.ZERO
	_lag_vel = Vector2.ZERO
	_trail_pos = Vector2.ZERO
	_trail_vel = Vector2.ZERO
	lag = Vector2.ZERO
	trail = Vector2.ZERO
	tint = Color(1, 1, 1, 0)
	heavy = false


# ---------- 动作入口 ----------

## 攻击：预备 → 出手 → 回弹。reach 是出手阶段要到达的像素偏移（近身突进时为到目标的距离，原地出招为零）。
## 返回 {release, impact, total}：出手开始、命中、整套动作结束的秒数，表现层按它安排特效和伤害飘字。
func attack(reach_px := Vector2.ZERO, variant := "") -> Dictionary:
	if state == State.DEATH:
		return {"release": 0.0, "impact": 0.0, "total": 0.0}
	_reach = reach_px * (0.4 if amount < 1.0 else 1.0) / maxf(unit, 1.0)
	var key := variant if not variant.is_empty() else ("attack" if reach_px.length() > unit * 0.5 else "cast")
	var pre: Array = profile.get("anticipation_" + key, profile.get("anticipation", []))
	var act: Array = profile.get(key, profile.get("attack", []))
	_play([[State.ANTICIPATION, pre], [State.ATTACK, act], [State.RECOVERY, profile.get("recovery", [])]])
	var release := _duration(pre)
	var impact := release
	for p in act:
		if String(p.get("cue", "")) == "impact":
			break
		impact += float(p.t)
	return {"release": release, "impact": impact, "total": remaining()}


## 受击：strength 约等于伤害 / 10；超过 1.2 为重击（更大的后挫、更长的硬直）
func hit(strength := 1.0, push := Vector2(-1, 0)) -> void:
	if state == State.DEATH:
		return
	heavy = strength >= 1.2
	var s := clampf(strength, 0.3, 2.2)
	var phases: Array = profile.get("hit_heavy" if heavy else "hit", profile.get("hit", []))
	_play([[State.HIT, phases], [State.RECOVERY, profile.get("recovery", [])]])
	var kick: Dictionary = profile.get("hit_kick", {})
	var dir := push.normalized() if push.length() > 0.01 else Vector2(-1, 0)
	_velocity.x += float(kick.get("x", 6.0)) * s * dir.x * amount
	_velocity.y += float(kick.get("x", 6.0)) * s * dir.y * amount
	for c in ["angle", "sx", "sy", "bend", "open"]:
		_velocity[c] += float(kick.get(c, 0.0)) * s * amount


## 防御：收缩成防御姿态，再恢复战斗姿态
func defend() -> void:
	if state == State.DEATH:
		return
	_play([[State.DEFEND, profile.get("defend", [])], [State.RECOVERY, profile.get("recovery", [])]])


## 状态影响（中毒、虚弱、被强化）：一次颤动，并按状态着色
func status(color := Color(0.6, 1.0, 0.4)) -> void:
	if state == State.DEATH:
		return
	tint = Color(color, 1.0)
	if state in [State.ATTACK, State.ANTICIPATION]:
		return   # 不打断出手，只着色
	_play([[State.STATUS, profile.get("status", [])]])


## 射击后坐：只给身体一个向后的冲量，不改变当前状态
func recoil(px: float) -> void:
	_velocity.x -= px / maxf(unit, 1.0) * 14.0 * amount
	_velocity.angle += px * 0.004 * amount


func die() -> void:
	_play([[State.DEATH, profile.get("death", [])]])


## 只用于持续性的姿态提示（例如敌人蓄力），不进入状态机
func kick(channel: String, velocity: float) -> void:
	if _velocity.has(channel):
		_velocity[channel] += velocity * amount


func busy() -> bool:
	return state != State.IDLE and state != State.DEATH


## 当前动作链剩余的秒数（待机为 0）
func remaining() -> float:
	if state == State.IDLE or state == State.DEATH:
		return 0.0
	var total := _phase_left
	for i in range(_phase + 1, _phases.size()):
		total += float(_phases[i].t)
	for entry in _chain:
		total += _duration(entry[1])
	return total


# ---------- 输出 ----------

func offset() -> Vector2:
	return Vector2(value("x"), value("y")) * unit


func angle() -> float:
	return value("angle")


func squash() -> Vector2:
	return Vector2(value("sx"), value("sy"))


func value(channel: String) -> float:
	var idle: Dictionary = profile.get("idle", {})
	var base := float(_value.get(channel, 0.0))
	return base + _idle_term(channel, idle) * _idle_weight * amount


## 以 pivot（脚底）为基点的完整动画变换
func transform(pivot: Vector2) -> Transform2D:
	var shift := Transform2D(0.0, pivot + offset())
	return shift * Transform2D(angle(), squash(), 0.0, Vector2.ZERO) * Transform2D(0.0, -pivot)


# ---------- 推进 ----------

func step(delta: float) -> void:
	delta = minf(delta, 0.1)
	time += delta
	amount = 0.35 if GameSettings.reduce_motion else 1.0
	_advance(delta)
	var resting := state == State.IDLE
	_idle_weight = move_toward(_idle_weight, 1.0 if resting else (0.0 if state == State.DEATH else 0.25), delta * (1.5 if resting else 6.0))
	_update_adjust(delta)
	var left := delta
	while left > 0.0:
		var dt := minf(left, MAX_STEP)
		left -= dt
		for c in CHANNELS:
			var spring: Array = _stiff[c]
			var k := float(spring[0])
			var damping := 2.0 * float(spring[1]) * sqrt(k)
			var goal := float(_target[c])
			if state == State.IDLE and _adjust.has(c):
				goal += float(_adjust[c]) * amount
			var v := float(_velocity[c]) + (k * (goal - float(_value[c])) - damping * float(_velocity[c])) * dt
			_velocity[c] = v
			_value[c] = float(_value[c]) + v * dt
		var body := Vector2(value("x"), value("y"))
		var follow: Array = profile.get("lag", [70.0, 0.45])
		_lag_vel += (float(follow[0]) * (body - _lag_pos) - 2.0 * float(follow[1]) * sqrt(float(follow[0])) * _lag_vel) * dt
		_lag_pos += _lag_vel * dt
		var ribbon: Array = profile.get("trail", [26.0, 0.32])
		_trail_vel += (float(ribbon[0]) * (body - _trail_pos) - 2.0 * float(ribbon[1]) * sqrt(float(ribbon[0])) * _trail_vel) * dt
		_trail_pos += _trail_vel * dt
	lag = (_lag_pos - Vector2(value("x"), value("y"))).limit_length(0.9)
	trail = (_trail_pos - Vector2(value("x"), value("y"))).limit_length(1.4)
	tint.a = maxf(0.0, tint.a - delta * 0.9)


func _advance(delta: float) -> void:
	if state == State.IDLE:
		return
	_phase_left -= delta
	while _phase_left <= 0.0:
		if _phase + 1 < _phases.size():
			_enter_phase(_phase + 1, -_phase_left)
		elif not _chain.is_empty():
			var carry := -_phase_left
			var entry: Array = _chain.pop_front()
			_start_state(entry[0], entry[1])
			_phase_left -= carry
		elif state == State.DEATH:
			_phase_left = INF   # 死亡停在最后一个姿态
		else:
			_go_idle()
			return


func _play(chain: Array) -> void:
	_chain = chain.duplicate()
	var first: Array = _chain.pop_front()
	_start_state(first[0], first[1])


func _start_state(next: State, phases: Array) -> void:
	state = next
	_phases = phases
	if _phases.is_empty():
		_phases = [{"t": 0.01}]
	_enter_phase(0, 0.0)


func _enter_phase(index: int, overshoot: float) -> void:
	_phase = index
	var p: Dictionary = _phases[index]
	_phase_left = float(p.t) - overshoot
	var k := float(p.get("k", 240.0))
	var zeta := float(p.get("z", 0.7))
	for c in CHANNELS:
		var rest := float(REST.get(c, 0.0))
		var goal := float(p.get(c, rest))
		if c in ["x", "y"] and p.has("reach"):
			goal += (_reach.x if c == "x" else _reach.y) * float(p.reach)
		var reached: bool = c in ["x", "y"] and p.has("reach")   # 到达目标的距离已在 attack() 里按幅度缩放
		_target[c] = goal if reached else rest + (goal - rest) * amount
		var springs: Dictionary = profile.get("springs", {})
		_stiff[c] = springs.get(c, [k, zeta])


func _go_idle() -> void:
	state = State.IDLE
	_phases = []
	_phase = -1
	for c in CHANNELS:
		_target[c] = float(REST.get(c, 0.0))
		_stiff[c] = _default_spring(c)


func _default_spring(c: String) -> Array:
	var springs: Dictionary = profile.get("springs", {})
	return springs.get(c, profile.get("idle_spring", [90.0, 0.8]))


func _duration(phases: Array) -> float:
	var total := 0.0
	for p in phases:
		total += float(p.t)
	return total


## 偶发姿态调整：每隔几秒换一个重心 / 倾斜目标，弹簧慢慢挪过去，打破周期感
func _update_adjust(delta: float) -> void:
	var idle: Dictionary = profile.get("idle", {})
	var shifts: Dictionary = idle.get("adjust", {})
	if shifts.is_empty():
		return
	_adjust_left -= delta
	if _adjust_left > 0.0:
		return
	var every: Array = idle.get("adjust_every", [2.5, 5.5])
	_adjust_left = _rng.randf_range(float(every[0]), float(every[1]))
	_adjust = {}
	for c in shifts:
		_adjust[c] = _rng.randf_range(-1.0, 1.0) * float(shifts[c])


## 待机项：几组不成整数比的正弦叠加，节奏像生物而不是钟摆
func _idle_term(channel: String, idle: Dictionary) -> float:
	var spec: Array = idle.get(channel, [])
	if spec.is_empty():
		return 0.0
	var amp := float(spec[0])
	var hz := float(spec[1])
	var irregular := float(spec[2]) if spec.size() > 2 else 0.35
	var phase := float(spec[3]) if spec.size() > 3 else 0.0
	var t := time * hz * TAU + _seed + phase
	var wave := sin(t) * (1.0 - irregular) + (sin(t * 1.618 + 1.3) * 0.6 + sin(t * 2.71 + 4.1) * 0.4) * irregular
	return amp * wave


## 平滑的局部噪声，供形变函数使用
static func noise(t: float, s := 0.0) -> float:
	return sin(t + s) * 0.55 + sin(t * 1.618 + s * 2.3 + 1.1) * 0.3 + sin(t * 2.71 + s * 3.7 + 2.9) * 0.15
