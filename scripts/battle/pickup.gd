class_name Pickup
extends Node2D
## Something to grab in the world: a hidden portal, a loot cache, or an enemy drop.
## Hidden pickups only fade into view when the Dreamseeker is close
## (Lucidity widens that radius).

enum Kind { HIDDEN_PORTAL, CACHE, DROP }

const GRAB_RADIUS := 26.0

var battle: Node
var kind: Kind = Kind.CACHE
var reveal_radius := 120.0
## Item ids waiting inside. Whatever doesn't fit in your bags stays here.
var contents: Array[String] = []
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if kind == Kind.HIDDEN_PORTAL:
		var player: Node2D = battle.player
		var d := position.distance_to(player.position) if is_instance_valid(player) else INF
		modulate.a = clampf(1.0 - (d - reveal_radius * 0.5) / (reveal_radius * 0.5), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	match kind:
		Kind.HIDDEN_PORTAL:
			var r := 9.0 + sin(_t * 3.0) * 2.0
			draw_arc(Vector2.ZERO, r, _t, _t + PI * 1.5, 16, Color("d9b3ff"), 2.0)
			draw_circle(Vector2.ZERO, 3.0, Color("ffffff"))
		Kind.CACHE:
			draw_rect(Rect2(-9, -7, 18, 14), Color("6b4f2a"))
			draw_rect(Rect2(-9, -7, 18, 14), Color("e8c26a"), false, 2.0)
			draw_circle(Vector2(0, 0), 2.0 + sin(_t * 4.0), Color("fff2b0"))
		Kind.DROP:
			draw_circle(Vector2.ZERO, 5.0 + sin(_t * 5.0), Color("fff2b0"))
