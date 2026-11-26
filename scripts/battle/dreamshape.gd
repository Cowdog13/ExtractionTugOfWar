class_name Dreamshape
extends Unit
## A timed AI unit. Allies march to a rally point; enemies patrol or stream.
## All of them engage anything hostile they can see along the way.

enum Mode { RALLY, PATROL, STREAM }

var mode: Mode = Mode.RALLY
var rally_point := Vector2.ZERO
var patrol_points: Array[Vector2] = []
var stream_dest := Vector2.ZERO
var _patrol_i := 0


func think() -> void:
	# Drop targets that ran too far away; otherwise keep fighting what we have.
	if has_target() and position.distance_to(target.position) > aggro_range * 1.6:
		target = null
	if not has_target():
		target = battle.find_target(self, aggro_range)
	if has_target():
		set_goal(target.position)
		return

	match mode:
		Mode.RALLY:
			set_goal(rally_point)
		Mode.PATROL:
			if patrol_points.is_empty():
				return
			if position.distance_to(patrol_points[_patrol_i]) < 28.0 or at_goal():
				_patrol_i = (_patrol_i + 1) % patrol_points.size()
			set_goal(patrol_points[_patrol_i])
		Mode.STREAM:
			set_goal(stream_dest)
			if position.distance_to(stream_dest) < 40.0:
				die(true)  # flowed out of the area


func act(delta: float) -> void:
	if has_target() and in_reach(target):
		try_attack(target)
	elif mode == Mode.RALLY and not has_target() and position.distance_to(rally_point) < 40.0:
		pass  # hold position at the rally point
	else:
		follow_path(delta)
	separate(delta)
