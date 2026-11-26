extends Node2D
## Real-time raid on a procedural dream map.
##
## Controls:
##   Left / Right click   move the Dreamseeker (auto-attacks anything in reach)
##   1-4                  ready a portal from the belt, then left-click a rally point
##   R                    send every living ally (and open portals) to the cursor
##   Mouse wheel          zoom
##   Esc                  cancel / pause menu
##
## Win: stand in one of the two extraction zones for EXTRACT_TIME seconds.
## Lose: the Dreamseeker dies -> everything except the Safe Pouch is gone.

const HUB_SCENE := "res://scenes/hub.tscn"
const EXTRACT_TIME := 4.0
const EXTRACT_RADIUS := 70.0
const ENEMY_STREAM_POOL: Array[String] = ["shade", "shade", "stalker", "wailer"]
const PATROL_POOL: Array[String] = ["shade", "shade", "stalker", "wailer", "maw"]
const PATROL_RESPAWN := 22.0
## Enemies grow stronger the longer you stay: power = 1 + elapsed / this.
const INSTABILITY_SECONDS := 180.0

var map := DreamMap.new()
var astar := AStarGrid2D.new()
var map_texture: ImageTexture
var rng := RandomNumberGenerator.new()
var units: Array[Unit] = []
var player: Dreamseeker
var extraction_points: Array[Vector2] = []
var player_streams: Array[PortalStream] = []
var elapsed := 0.0
var extract_progress := 0.0
## Belt slot / backpack uid of the portal waiting for a rally click (-1 = none).
var aiming_uid := -1

var _units_root := Node2D.new()
var _portals_root := Node2D.new()
var _pickups_root := Node2D.new()
var _camera := Camera2D.new()
var _hud: BattleHud
var _enemy_streams: Array[PortalStream] = []
var _nests: Array = []  # [{points, alive: Array, respawn}]
var _pickups: Array[Pickup] = []
var _ended := false
var _full_msg_cd := 0.0


func _ready() -> void:
	if not GameState.is_in_raid():
		get_tree().change_scene_to_file.call_deferred(HUB_SCENE)
		return
	rng.seed = GameState.raid["seed"]
	RenderingServer.set_default_clear_color(Color("0b0914"))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	map.generate(GameState.raid["seed"])
	_build_navigation()
	_build_map_texture()
	for root in [_pickups_root, _portals_root, _units_root]:
		add_child(root)

	player = Dreamseeker.new()
	player.battle = self
	player.setup_from_stats(GameState.get_stats())
	player.position = map.cell_to_world(map.room_center(map.spawn_room))
	_add_unit(player)

	for i in map.extract_rooms:
		extraction_points.append(map.cell_to_world(map.room_center(i)))
	_spawn_enemy_streams()
	_spawn_nests()
	_spawn_pickups()

	_camera.position = player.position
	_camera.zoom = Vector2(1.2, 1.2)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = map.width * DreamMap.TILE
	_camera.limit_bottom = map.height * DreamMap.TILE
	_camera.position_smoothing_enabled = true
	add_child(_camera)

	_hud = BattleHud.new()
	_hud.battle = self
	add_child(_hud)
	_hud.show_message("You slip into the dream. Find an exit — there are two.")


# --- World setup -------------------------------------------------------------------

func _build_navigation() -> void:
	astar.region = Rect2i(0, 0, map.width, map.height)
	astar.cell_size = Vector2(DreamMap.TILE, DreamMap.TILE)
	astar.offset = Vector2(DreamMap.TILE, DreamMap.TILE) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in map.height:
		for x in map.width:
			if not map.is_floor(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y), true)


func _build_map_texture() -> void:
	var img := Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.08
	for y in map.height:
		for x in map.width:
			var c := Vector2i(x, y)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			if map.is_floor(c):
				img.set_pixel(x, y, Color("2b2544").lerp(Color("3b3160"), n))
			elif _touches_floor(c):
				img.set_pixel(x, y, Color("4a3f78"))  # wall edge
			else:
				img.set_pixel(x, y, Color("0f0c1c").lerp(Color("161127"), n))
	map_texture = ImageTexture.create_from_image(img)


func _touches_floor(c: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if map.is_floor(c + d):
			return true
	return false


func _spawn_enemy_streams() -> void:
	for route in map.stream_routes:
		var s := PortalStream.new()
		s.battle = self
		s.team = Unit.Team.ENEMY
		s.shape_pool = ENEMY_STREAM_POOL
		s.remaining = -1  # endless
		s.interval = 3.2
		s.shape_lifetime = 75.0
		s.position = map.cell_to_world(route[0])
		var dest := map.cell_to_world(route[1])
		s.configure = func(u: Dreamshape):
			u.mode = Dreamshape.Mode.STREAM
			u.stream_dest = dest
		_portals_root.add_child(s)
		_enemy_streams.append(s)


func _spawn_nests() -> void:
	for route in map.patrol_routes:
		var pts: Array[Vector2] = []
		for c in route:
			pts.append(map.cell_to_world(c))
		_nests.append({"points": pts, "alive": [], "respawn": 0.0})


func _spawn_pickups() -> void:
	var lucidity := player.lucidity
	for c in map.portal_cells:
		var p := _make_pickup(Pickup.Kind.HIDDEN_PORTAL, map.cell_to_world(c))
		p.contents = [ItemDB.roll_portal(lucidity, rng)]
	for c in map.cache_cells:
		var p := _make_pickup(Pickup.Kind.CACHE, map.cell_to_world(c))
		for i in rng.randi_range(1, 3):
			p.contents.append(ItemDB.roll_loot(1, lucidity, rng))


func _make_pickup(kind: Pickup.Kind, pos: Vector2) -> Pickup:
	var p := Pickup.new()
	p.battle = self
	p.kind = kind
	p.position = pos
	p.reveal_radius = 120.0 + player.lucidity * 3.0
	_pickups_root.add_child(p)
	_pickups.append(p)
	return p


# --- Units --------------------------------------------------------------------------

func spawn_shape(id: String, team: Unit.Team, pos: Vector2, life: float, power := 1.0) -> Dreamshape:
	var u := Dreamshape.new()
	u.battle = self
	u.setup_shape(id, ItemDB.SHAPES[id], team, life, power)
	u.position = pos + Vector2(randf_range(-6, 6), randf_range(-6, 6))
	_add_unit(u)
	return u


func _add_unit(u: Unit) -> void:
	units.append(u)
	u.died.connect(_on_unit_died)
	_units_root.add_child(u)


func _on_unit_died(u: Unit, expired: bool) -> void:
	units.erase(u)
	if u == player:
		_end(false, "Your Dreamseeker was unmade by the dream.")
		return
	if u.team == Unit.Team.ENEMY and not expired:
		var chance := 0.3 if u.shape_id == "maw" else 0.08
		if rng.randf() < chance:
			var p := _make_pickup(Pickup.Kind.DROP, u.position)
			p.contents = [ItemDB.roll_loot(int(danger()), player.lucidity, rng)]


func danger() -> float:
	return 1.0 + elapsed / INSTABILITY_SECONDS


func allies_alive() -> int:
	return units.filter(func(u): return u.team == Unit.Team.PLAYER and u != player).size()


func enemies_alive() -> int:
	return units.filter(func(u): return u.team == Unit.Team.ENEMY).size()


# --- Queries used by units ----------------------------------------------------------

func is_walkable(p: Vector2) -> bool:
	return map.is_floor(map.world_to_cell(p))


func snap_to_floor(p: Vector2) -> Vector2:
	var c := map.world_to_cell(p)
	return p if map.is_floor(c) else map.cell_to_world(map.nearest_floor(c))


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := map.nearest_floor(map.world_to_cell(from))
	var b := map.nearest_floor(map.world_to_cell(to))
	var path := astar.get_point_path(a, b)
	if path.size() > 1:
		path.remove_at(0)  # we're already standing in the first cell
	if path.size() > 0 and is_walkable(to):
		path[path.size() - 1] = to
	return path


func has_los(a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / 12.0) + 1
	for i in steps:
		if not is_walkable(a.lerp(b, float(i) / steps)):
			return false
	return true


func find_target(u: Unit, radius: float) -> Unit:
	var best: Unit = null
	var best_d := radius * radius
	for o in units:
		if o.team == u.team or o.dead:
			continue
		var d2 := u.position.distance_squared_to(o.position)
		if d2 < best_d:
			best_d = d2
			best = o
	if best != null and not has_los(u.position, best.position):
		return null
	return best


# --- Loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended:
		return
	elapsed += delta
	_full_msg_cd -= delta
	if is_instance_valid(player):
		_camera.position = player.position
	for s in _enemy_streams:
		s.power = danger()
	_tick_nests(delta)
	_tick_pickups()
	_tick_extraction(delta)
	player_streams = player_streams.filter(func(s): return is_instance_valid(s))
	queue_redraw()


func _tick_nests(delta: float) -> void:
	for nest in _nests:
		nest["alive"] = nest["alive"].filter(func(u): return is_instance_valid(u) and not u.dead)
		if not nest["alive"].is_empty():
			continue
		nest["respawn"] -= delta
		if nest["respawn"] > 0.0:
			continue
		nest["respawn"] = PATROL_RESPAWN
		var pts: Array[Vector2] = nest["points"]
		for i in rng.randi_range(2, 4):
			var id: String = PATROL_POOL[rng.randi_range(0, PATROL_POOL.size() - 1)]
			var u := spawn_shape(id, Unit.Team.ENEMY, pts[0], rng.randf_range(50.0, 80.0), danger())
			u.mode = Dreamshape.Mode.PATROL
			u.patrol_points = pts
			nest["alive"].append(u)


func _tick_pickups() -> void:
	if not is_instance_valid(player) or player.dead:
		return
	for p in _pickups.duplicate():
		if p.position.distance_to(player.position) > Pickup.GRAB_RADIUS + player.radius:
			continue
		var got: Array[String] = []
		while not p.contents.is_empty():
			if GameState.add_raid_loot(p.contents[0]).is_empty():
				break
			got.append(p.contents.pop_front())
		for id in got:
			var item := ItemDB.get_item(id)
			var where := "belt" if item.is_portal() and _in_belt(id) else "backpack"
			_hud.show_message("Found %s  → %s" % [item.display_name, where], item.rarity_color())
		if p.contents.is_empty():
			_pickups.erase(p)
			p.queue_free()
		elif _full_msg_cd <= 0.0:
			_full_msg_cd = 2.5
			_hud.show_message("Backpack full! Secure something in your pouch or leave it.", Color("ff8a8a"))


func _in_belt(id: String) -> bool:
	for inst in GameState.belt:
		if inst != null and inst["id"] == id:
			return true
	return false


func _tick_extraction(delta: float) -> void:
	if not is_instance_valid(player) or player.dead:
		return
	var inside := extraction_points.any(func(p): return p.distance_to(player.position) <= EXTRACT_RADIUS)
	if inside:
		extract_progress += delta
		if extract_progress >= EXTRACT_TIME:
			_end(true)
	else:
		extract_progress = 0.0


# --- Player actions ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _ended or not is_instance_valid(player):
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if aiming_uid >= 0:
					open_portal(aiming_uid, get_global_mouse_position())
				else:
					player.order_move(get_global_mouse_position())
			MOUSE_BUTTON_RIGHT:
				aiming_uid = -1
				player.order_move(get_global_mouse_position())
			MOUSE_BUTTON_WHEEL_UP:
				_camera.zoom = (_camera.zoom * 1.1).clamp(Vector2(0.5, 0.5), Vector2(2.5, 2.5))
			MOUSE_BUTTON_WHEEL_DOWN:
				_camera.zoom = (_camera.zoom / 1.1).clamp(Vector2(0.5, 0.5), Vector2(2.5, 2.5))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			ready_belt_slot(event.keycode - KEY_1)
		elif event.keycode == KEY_R:
			rally_all(get_global_mouse_position())


## Arms a belt portal: the next left click chooses where its Dreamshapes march.
func ready_belt_slot(i: int) -> void:
	var inst = GameState.belt[i]
	if inst == null:
		_hud.show_message("Belt slot %d is empty." % (i + 1), Color("ff8a8a"))
		return
	ready_portal(inst["uid"])


func ready_portal(uid: int) -> void:
	aiming_uid = uid
	_hud.show_message("Click where your Dreamshapes should go. (Right-click / Esc cancels)")


func open_portal(uid: int, rally: Vector2) -> void:
	aiming_uid = -1
	var item := GameState.consume_portal(uid)
	if item == null:
		return
	var s := PortalStream.new()
	s.battle = self
	s.team = Unit.Team.PLAYER
	s.shape_pool = [item.summon_shape]
	s.remaining = item.stream_count
	s.interval = item.stream_interval
	s.shape_lifetime = item.shape_lifetime
	s.set_meta("rally", snap_to_floor(rally))
	s.position = _portal_spot(rally)
	s.configure = func(u: Dreamshape):
		u.mode = Dreamshape.Mode.RALLY
		u.rally_point = s.get_meta("rally")
	_portals_root.add_child(s)
	player_streams.append(s)
	_hud.show_message("%s opens!" % item.display_name, item.rarity_color())


## Opens the portal just beside the Dreamseeker, leaning toward the rally point.
func _portal_spot(rally: Vector2) -> Vector2:
	var dir := (rally - player.position).normalized()
	for dist in [40.0, 24.0, 0.0]:
		var p: Vector2 = player.position + dir * dist
		if is_walkable(p):
			return p
	return player.position


func rally_all(p: Vector2) -> void:
	var dest := snap_to_floor(p)
	for u in units:
		if u is Dreamshape and u.team == Unit.Team.PLAYER:
			u.rally_point = dest
			u.target = null
	for s in player_streams:
		s.set_meta("rally", dest)
	_hud.show_message("Allies rally to the marked point.")


func abandon() -> void:
	_end(false, "You let go of the dream. It did not let go of your gear.")


func _end(extracted: bool, reason := "") -> void:
	if _ended:
		return
	_ended = true
	aiming_uid = -1
	GameState.end_raid(extracted, reason)
	_hud.show_message("You wake up..." if extracted else reason,
			Color("8fffb0") if extracted else Color("ff6b6b"))
	get_tree().paused = false
	await get_tree().create_timer(1.6).timeout
	get_tree().change_scene_to_file(HUB_SCENE)


# --- Drawing -------------------------------------------------------------------------

func _draw() -> void:
	draw_texture_rect(map_texture,
			Rect2(Vector2.ZERO, Vector2(map.width, map.height) * DreamMap.TILE), false)
	var t := elapsed
	for p in extraction_points:
		draw_circle(p, EXTRACT_RADIUS, Color(0.4, 1.0, 0.6, 0.10))
		draw_arc(p, EXTRACT_RADIUS, t, t + TAU, 48, Color(0.5, 1.0, 0.7, 0.7), 2.0)
		draw_arc(p, EXTRACT_RADIUS * 0.6, -t * 1.3, -t * 1.3 + PI, 32, Color(0.5, 1.0, 0.7, 0.5), 2.0)
	for s in player_streams:
		_draw_flag(s.get_meta("rally"))
	if aiming_uid >= 0:
		var m := get_global_mouse_position()
		draw_arc(m, 26.0, 0, TAU, 32, Color(0.8, 0.6, 1.0, 0.9), 2.0)
		draw_line(player.position, m, Color(0.8, 0.6, 1.0, 0.35), 1.5)


func _draw_flag(p: Vector2) -> void:
	draw_line(p, p + Vector2(0, -22), Color("d9c8ff"), 2.0)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -22), p + Vector2(14, -17), p + Vector2(0, -12)]),
			Color("b48cff"))
