class_name Dreamseeker
extends Unit
## The player's avatar. Moves where you click and auto-attacks whatever
## hostile is in reach — even while walking.

const REGEN_DELAY := 5.0
const REGEN_PER_SEC := 1.5

var lucidity := 0
var _since_hit := 99.0


func setup_from_stats(stats: Dictionary) -> void:
	team = Team.PLAYER
	display_name = "Dreamseeker"
	max_hp = stats.get("max_hp", 50)
	hp = max_hp
	attack = stats.get("attack", 3)
	defense = stats.get("defense", 0)
	crit = stats.get("crit", 5)
	lucidity = stats.get("lucidity", 0)
	speed = 170.0
	attack_range = 34.0
	attack_cooldown = 0.7
	radius = 12.0
	color = Color("f2e9ff")
	lifetime = -1.0


func order_move(p: Vector2) -> void:
	_goal = Vector2.INF  # force a re-path even for nearby clicks
	set_goal(p)


func think() -> void:
	if not has_target() or not in_reach(target):
		target = battle.find_target(self, attack_range + 30.0)


func act(delta: float) -> void:
	_since_hit += delta
	if _since_hit > REGEN_DELAY and hp < max_hp:
		hp = minf(max_hp, hp + REGEN_PER_SEC * delta)
	if has_target() and in_reach(target):
		try_attack(target)
	follow_path(delta)
	separate(delta * 0.3)


func take_damage(amount: float, source: Unit) -> void:
	_since_hit = 0.0
	super.take_damage(amount, source)


func _draw() -> void:
	var r := radius
	draw_circle(Vector2.ZERO, r + 10.0, Color(0.85, 0.75, 1.0, 0.08))
	var pts := PackedVector2Array([Vector2(0, -r - 4), Vector2(r, 0), Vector2(0, r + 4), Vector2(-r, 0)])
	draw_colored_polygon(pts, Color("ffffff") if _flash > 0.0 else color)
	pts.append(pts[0])
	draw_polyline(pts, Color("7d5cff"), 2.0)
	if hp < max_hp:
		var w := 36.0
		var top := Vector2(-w / 2, -r - 14)
		draw_rect(Rect2(top, Vector2(w, 4)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top, Vector2(w * hp / max_hp, 4)), Color("6fdc8c"))
