class_name BattleCue
extends Control
## Finite, inked gestures painted on the battle FX layer.
enum Kind { TRAIL, HIT, SHIELD, DATA, AI, TOXIN, BOSS, ENTRY, DEATH }
const DURATION := [0.29, 0.30, 0.55, 0.62, 0.53, 0.52, 0.54, 0.76, 0.76]
const GOLD := Color("f5b754")
const WHITE := Color("fff0c2")
const CYAN := Color("89d9e5")
const DATA := Color("86d4b0")
const PURPLE := Color("bd83d2")
const RED := Color("ed765f")

var kind := Kind.HIT
var origin := Vector2.ZERO
var target := Vector2.ZERO
var extent := Vector2(130, 100)
var power := 1.0
var _phase := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, 1.0, DURATION[kind])
	tween.tween_callback(queue_free)


func _advance(phase: float) -> void:
	_phase = phase
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - smoothstep(0.3, 1.0, _phase)
	match kind:
		Kind.TRAIL: _draw_trail(fade)
		Kind.HIT: _draw_hit(fade)
		Kind.SHIELD: _draw_shield(fade)
		Kind.DATA: _draw_data(fade)
		Kind.AI: _draw_scan(fade)
		Kind.TOXIN: _draw_toxin(fade)
		Kind.BOSS, Kind.ENTRY: _draw_pressure(fade)
		Kind.DEATH: _draw_death(fade)


func _draw_trail(fade: float) -> void:
	var axis := (target - origin).normalized()
	var normal := axis.orthogonal()
	var front := smoothstep(0.0, 0.62, _phase)
	if front < 0.025 or origin.distance_squared_to(target) < 16.0:
		return
	for band in 3:
		var shape := PackedVector2Array()
		var bow := 32.0 + band * 12.0
		for step in 14:
			var u := front * step / 13.0
			shape.append(origin.lerp(target, u) - normal * sin(u * PI) * bow)
		for step in range(12, 0, -1):
			var u := front * step / 13.0
			var blade := sin(float(step) / 13.0 * PI) * (13.0 - band * 3.0) * power
			shape.append(origin.lerp(target, u) - normal * (sin(u * PI) * bow + blade))
		draw_colored_polygon(shape, Color(WHITE if band == 0 else GOLD, fade * (0.94 - band * 0.22)))


func _draw_hit(fade: float) -> void:
	var angle := (target - origin).angle()
	var axis := Vector2.from_angle(angle)
	var p := target
	var flash := pow(1.0 - _phase, 4.0)
	Shading.glow(self, p, 62.0 * power, Color(GOLD, flash * 0.52))
	_streak(p, axis.rotated(-0.35), 62.0 * power, 9.0 * flash + 1.0, Color(WHITE, fade))
	_streak(p, axis.orthogonal(), 24.0 * power, 4.0, Color(GOLD, fade))
	for i in 9:
		var dir := axis.rotated((i - 4) * 0.35)
		var start := p + dir * (_phase * (30.0 + 5.0 * i) + 6.0)
		_streak(start, dir, (13.0 + (i * 7) % 24) * power, 2.4, Color(GOLD if i % 3 else WHITE, fade))


func _draw_shield(fade: float) -> void:
	var open := smoothstep(0.0, 0.46, _phase)
	var radii := extent * Vector2(0.55, 0.54) + Vector2(12, 8)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 12:
		var angle := lerpf(-PI * 0.83, PI * 0.80, i * open / 11.0)
		var dir := Vector2.from_angle(angle)
		if target.x < origin.x - 8.0:
			dir.x = -dir.x
		outer.append(origin + dir * radii)
		inner.append(origin + dir * (radii - Vector2(13, 10)))
	if open < 0.01:
		return
	for i in range(outer.size() - 1):
		var cell := PackedVector2Array([outer[i], outer[i + 1], inner[i + 1], inner[i]])
		draw_colored_polygon(cell, Color(CYAN, fade * (0.20 + 0.10 * (i % 3))))
		draw_polyline(cell, Color(CYAN, fade * 0.48), 1.2, true)
		if i in [3, 4, 5, 6, 7]:
			var tip := inner[i].lerp(origin, 0.13)
			draw_colored_polygon(PackedVector2Array([outer[i], outer[i + 1], inner[i + 1], tip]),
				Color(CYAN, fade * (0.11 + 0.045 * (i % 2))))
	draw_polyline(outer, Color(CYAN.lightened(0.3), fade), 3.0, true)
	draw_polyline(inner, Color(CYAN, fade * 0.52), 1.2, true)
	for i in range(1, 11, 2):
		_diamond(outer[i], 3.0, Color(WHITE, fade * 0.85))


func _draw_data(fade: float) -> void:
	var mid := origin.lerp(target, 0.47) + Vector2(0, -112)
	for i in 13:
		var t := _phase * 1.5 - i * 0.043
		if t <= 0.0 or t >= 1.0:
			continue
		var p := origin.lerp(mid, t).lerp(mid.lerp(target, t), t)
		p.y += float((i % 3) - 1) * 13.0 * sin(t * PI)
		var alpha := sin(t * PI) * 0.8 + 0.15
		_diamond(p, 3.0 + i % 3, Color(DATA if i % 3 else WHITE, alpha))
		if i % 3 == 0:
			draw_line(p - Vector2(14, -4), p - Vector2(4, -1), Color(DATA, alpha * 0.5), 1.5, true)
	draw_rect(Rect2(origin - Vector2(24, 11), Vector2(48, 22)), Color(DATA, fade * 0.20), false, 1.0)


func _draw_scan(fade: float) -> void:
	var radius := extent * Vector2(0.52, 0.48)
	var window := Rect2(origin - radius, radius * 2)
	var ink := Color(CYAN, fade * 0.82)
	for corner in [window.position, Vector2(window.end.x, window.position.y), window.end, Vector2(window.position.x, window.end.y)]:
		var inward: Vector2 = (origin - corner).sign()
		draw_polyline(PackedVector2Array([corner + Vector2(17 * inward.x, 0), corner,
			corner + Vector2(0, 13 * inward.y)]), ink, 2.0, true)
	var sweep := lerpf(window.position.y, window.end.y, smoothstep(0.04, 0.76, _phase))
	draw_rect(Rect2(window.position.x, sweep - 16, window.size.x, 16), Color(CYAN, fade * 0.10))
	draw_line(Vector2(window.position.x, sweep), Vector2(window.end.x, sweep), ink, 2.3, true)
	for i in 7:
		var p := origin + Vector2((i % 2 * 2 - 1) * (radius.x + 9 + (i * 7) % 17), (i - 3) * 14.0)
		draw_rect(Rect2(p, Vector2(8 + i % 3 * 5, 3)), Color(CYAN, fade * 0.55))
	if target.distance_to(origin) > 8.0:
		var reach := smoothstep(0.05, 0.6, _phase)
		var mid := origin.lerp(target, 0.4) - Vector2(0, 36)
		var line := PackedVector2Array([origin, mid, mid.lerp(target, reach)])
		draw_polyline(line, Color(CYAN, fade * 0.72), 1.8, true)
		_diamond(line[-1], 6, Color(CYAN, fade))


func _draw_toxin(fade: float) -> void:
	var bloom := smoothstep(0.0, 0.8, _phase)
	for i in 11:
		var a := i * TAU / 11.0 + 0.3
		var spread := (20.0 + (i * 19) % 39) * power
		var p := origin + Vector2.from_angle(a) * Vector2(1, 0.72) * spread * bloom - Vector2(0, _phase * 22)
		var r := (4.0 + (i * 13) % 10) * (0.55 + 0.6 * bloom)
		draw_circle(p, r, Color(PURPLE.darkened(0.6), fade * 0.7), true, -1.0, true)
		draw_arc(p, r, a - 1.3, a + 1.1, 14, Color(PURPLE, fade * 0.92), 1.7, true)
		if i % 3 == 0:
			_diamond(p + Vector2(-2, -2), 2.6, Color("b7cc74", fade))


func _draw_pressure(fade: float) -> void:
	var entry := kind == Kind.ENTRY
	var wave := smoothstep(0.0, 0.6, _phase)
	var size := (210.0 if entry else 144.0) * power
	var p := origin.lerp(target, wave * (0.75 if not entry else 0.0))
	var color := GOLD if entry else RED
	var forward := -1.0 if target.x < origin.x else 1.0
	for i in range(-3, 4):
		var start := p + Vector2(i * size * wave / 3.0, absf(i) * 4.0)
		var height := (22.0 + float((i + 4) * 19 % 45)) * (1.0 - _phase) * power
		var slash := PackedVector2Array([start + Vector2(-24 * forward, 4), start + Vector2((-18 - absf(i) * 6) * forward, -height),
			start + Vector2(10 * forward, -8), start + Vector2(30 * forward, 2)])
		draw_colored_polygon(slash, Color(color, fade * (0.76 - 0.09 * absf(i))))
	draw_line(p - Vector2(size * wave, 1), p + Vector2(size * wave, 1), Color(color, fade), 2.0, true)
	if entry:
		Shading.glow(self, p, size * 0.75, Color(GOLD, pow(1.0 - _phase, 3.0) * 0.32))


func _draw_death(fade: float) -> void:
	var collapse := smoothstep(0.06, 0.43, _phase)
	var spread := smoothstep(0.20, 1.0, _phase)
	var core := extent * Vector2(0.23, 0.40) * (1.0 - collapse)
	if core.y > 1:
		draw_line(origin - Vector2(0, core.y), origin + Vector2(0, core.y), Color(WHITE, fade), maxf(1.0, core.x * 0.11), true)
	for i in 14:
		var dir := Vector2.from_angle(i * TAU / 14.0 + i * 0.54)
		var travel := extent * (0.23 + (i * 19) % 45 / 100.0)
		var p := origin + dir * travel * spread * power + Vector2(0, 44.0 * spread * spread)
		_streak(p, dir.rotated(spread * 2.4), (20 + i % 6 * 4) * (1.0 - spread) + 4.0, 3.0,
			Color(WHITE if i % 4 == 0 else Color("a389b8"), fade))


func _streak(p: Vector2, direction: Vector2, length: float, width: float, color: Color) -> void:
	var n := direction.orthogonal() * width
	draw_colored_polygon(PackedVector2Array([p - direction * length * 0.36, p + n,
		p + direction * length * 0.64, p - n * 0.64]), color)


func _diamond(p: Vector2, size: float, color: Color) -> void:
	_streak(p, Vector2.RIGHT, size * 2, size * 0.68, color)
