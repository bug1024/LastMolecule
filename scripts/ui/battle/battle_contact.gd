class_name BattleContact
extends Control
## Directional painted ribbon and contact shards, owned by the transient FX layer.
var from_point := Vector2.ZERO
var to_point := Vector2.ZERO
var phase := 0.0
var burst := true
var strength := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_method(func(value: float) -> void:
		phase = value
		queue_redraw(),0.0,1.0,0.60)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var direction := (to_point-from_point).normalized()
	var normal := direction.orthogonal()
	var fade := pow(1.0-phase,1.4)
	for j in 3:
		var points := PackedVector2Array()
		for i in 18:
			var t := i / 17.0
			var p := from_point.lerp(to_point,t) + normal * (sin(t*PI)*(18+j*13))
			points.append(p)
		for i in range(17,-1,-1):
			var t := i / 17.0
			var p := from_point.lerp(to_point,t) + normal * (sin(t*PI)*(18+j*13) + sin(t*PI)*(7+j*4)*(1-phase))
			points.append(p)
		draw_colored_polygon(points,Color(0.45,0.80,0.64,fade*(0.88-j*0.17)))
	if not burst:
		return
	Shading.glow(self,to_point,115*strength,Color(UIKit.GOLD,fade*0.45))
	for i in 13:
		var angle := i * TAU / 13.0 + i * 0.43
		var dir := Vector2.from_angle(angle)
		var side := dir.orthogonal()
		var length := (34 + (i*31)%82) * strength
		var p := to_point + dir * phase * 42
		var shard := PackedVector2Array([p-dir*7,p+dir*length*(1-phase)+side*3,p+side*(4+i%4)])
		draw_colored_polygon(shard,Color(UIKit.GOLD if i%3 else UIKit.PAPER,fade))
	draw_line(to_point-direction*25,to_point+direction*38,Color(UIKit.PAPER,fade),4*fade+1,true)
