class_name Unit
extends Node2D
## Base for everything that fights: the Dreamseeker and all Dreamshapes.
## Handles pathing, attacking, damage, lifetime and drawing.
## Subclasses override think() (choose target / goal ~4x per second).

signal died(unit: Unit, expired: bool)

enum Team { PLAYER, ENEMY }

const THINK_INTERVAL := 0.25

var battle: Node  # Battle; untyped to avoid a class dependency cycle
var team: Team = Team.ENEMY
var shape_id := ""
var display_name := ""
var max_hp := 10.0
var hp := 10.0
var attack := 1.0
var defense := 0.0
var crit := 0.0
var speed := 100.0
var attack_range := 26.0
var attack_cooldown := 1.0
var radius := 8.0
var color := Color.WHITE
var aggro_range := 220.0
## Seconds until this unit dissolves on its own. <= 0 means it never expires.
var lifetime := -1.0
var age := 0.0
var target: Unit = null
var dead := false

var _path := PackedVector2Array()
var _path_i := 0
var _goal := Vector2.INF
var _cd := 0.0
var _think_cd := 0.0
var _flash := 0.0
var _shot_to := Vector2.ZERO
var _shot_t := 0.0


func setup_shape(id: String, shape: Dictionary, unit_team: Team, life: float, power := 1.0) -> void:
	shape_id = id
	team = unit_team
	display_name = shape["name"]
	max_hp = shape["hp"] * power
	hp = max_hp
	attack = shape["attack"] * power
	defense = shape["defense"]
	speed = shape["speed"]
	attack_range = shape["range"]
	attack_cooldown = shape["cooldown"]
	radius = shape["radius"]
	color = shape["color"]
	lifetime = life
	aggro_range = maxf(220.0, attack_range + 80.0)
	_think_cd = randf() * THINK_INTERVAL


func _physics_process(delta: float) -> void:
	if dead:
		return
	if lifetime > 0.0:
		age += delta
		if age >= lifetime:
			die(true)
			return
	_cd -= delta
	_flash = maxf(0.0, _flash - delta)
	_shot_t -= delta
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = THINK_INTERVAL
		think()
	act(delta)
	queue_redraw()


## Override: pick `target` and call set_goal().
func think() -> void:
	pass


## Default behaviour: stand and fight a target in reach, otherwise walk the path.
func act(delta: float) -> void:
	if has_target() and in_reach(target):
		try_attack(target)
	else:
		follow_path(delta)
	separate(delta)


func has_target() -> bool:
	return is_instance_valid(target) and not target.dead


func in_reach(u: Unit) -> bool:
	return position.distance_to(u.position) <= attack_range + u.radius + radius * 0.5


func set_goal(p: Vector2) -> void:
	if _goal != Vector2.INF and _goal.distance_to(p) < 20.0 and _path_i < _path.size():
		return
	_goal = p
	_path = battle.find_path(position, p)
	_path_i = 0


func clear_goal() -> void:
	_goal = Vector2.INF
	_path = PackedVector2Array()
	_path_i = 0


func at_goal(tolerance := 24.0) -> bool:
	return _goal == Vector2.INF or position.distance_to(_goal) <= tolerance or _path_i >= _path.size()


func follow_path(delta: float) -> void:
	if _path_i >= _path.size():
		return
	var next := _path[_path_i]
	var step := speed * delta
	var to_next := next - position
	if to_next.length() <= step:
		_try_move(next)
		_path_i += 1
	else:
		_try_move(position + to_next.normalized() * step)


func _try_move(p: Vector2) -> void:
	if battle.is_walkable(p):
		position = p


## Soft push-apart so crowds spread out instead of stacking.
func separate(delta: float) -> void:
	var push := Vector2.ZERO
	for u in battle.units:
		if u == self or u.dead:
			continue
		var d: Vector2 = position - u.position
		var min_d: float = radius + u.radius
		var len := d.length()
		if len < min_d and len > 0.01:
			push += d / len * (min_d - len)
	if push != Vector2.ZERO:
		_try_move(position + push.limit_length(60.0 * delta) )


func try_attack(t: Unit) -> void:
	if _cd > 0.0:
		return
	_cd = attack_cooldown
	var dmg := attack
	if randf() * 100.0 < crit:
		dmg *= 2.0
	t.take_damage(dmg * randf_range(0.85, 1.15), self)
	if attack_range > 60.0:
		_shot_to = t.position
		_shot_t = 0.15


func take_damage(amount: float, source: Unit) -> void:
	if dead:
		return
	# Armor gives diminishing returns: 10 defense halves damage.
	hp -= amount * 10.0 / (10.0 + defense)
	_flash = 0.12
	if not has_target() and is_instance_valid(source) and not source.dead:
		target = source
	if hp <= 0.0:
		hp = 0.0
		die(false)


func die(expired: bool) -> void:
	if dead:
		return
	dead = true
	died.emit(self, expired)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35 if expired else 0.15)
	tween.tween_callback(queue_free)


# --- Drawing --------------------------------------------------------------------------

func _draw() -> void:
	var body := color.lightened(0.6) if _flash > 0.0 else color
	var outline := Color("ffffff") if team == Team.PLAYER else Color("2a0010")
	draw_circle(Vector2.ZERO, radius + 2.0, outline)
	draw_circle(Vector2.ZERO, radius, body)
	if lifetime > 0.0:
		var remaining := 1.0 - age / lifetime
		draw_arc(Vector2.ZERO, radius + 4.0, -PI / 2, -PI / 2 + TAU * remaining, 24,
				Color(1, 1, 1, 0.45), 1.5)
	if hp < max_hp:
		var w := radius * 2.4
		var top := Vector2(-w / 2, -radius - 9)
		draw_rect(Rect2(top, Vector2(w, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top, Vector2(w * hp / max_hp, 3)),
				Color("6fdc8c") if team == Team.PLAYER else Color("ff5d6c"))
	if _shot_t > 0.0:
		draw_line(Vector2.ZERO, _shot_to - position, color.lightened(0.4), 2.0)
