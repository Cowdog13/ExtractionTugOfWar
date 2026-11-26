class_name PortalStream
extends Node2D
## An open Dreamshape portal that emits a stream of units.
## Player portals are finite (stream_count); enemy flows are endless (count < 0).

signal spawned(unit: Dreamshape)

var battle: Node
var team: Unit.Team = Unit.Team.PLAYER
## Shape ids to pick from (random each spawn).
var shape_pool: Array[String] = []
var remaining := 1
var interval := 1.0
var shape_lifetime := 20.0
var power := 1.0
## Configures each spawned unit's AI (mode, rally point, route...).
var configure: Callable

var _t := 0.0
var _closing := false
var _spin := 0.0


func _process(delta: float) -> void:
	_spin += delta * 2.0
	queue_redraw()
	if _closing:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = interval
	var id: String = shape_pool[randi() % shape_pool.size()]
	var u: Dreamshape = battle.spawn_shape(id, team, position, shape_lifetime, power)
	if configure.is_valid():
		configure.call(u)
	spawned.emit(u)
	if remaining > 0:
		remaining -= 1
		if remaining == 0:
			_close()


func _close() -> void:
	_closing = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.6)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var c := Color("b48cff") if team == Unit.Team.PLAYER else Color("ff3d6e")
	for i in 3:
		var r := 22.0 - i * 6.0
		draw_arc(Vector2.ZERO, r, _spin + i, _spin + i + PI * 1.4, 24, c, 3.0 - i)
	draw_circle(Vector2.ZERO, 6.0, Color(c, 0.5))
