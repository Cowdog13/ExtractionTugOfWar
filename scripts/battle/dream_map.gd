class_name DreamMap
extends RefCounted
## Procedural dream layout: rooms joined by corridors on a tile grid.
## Pure data — Battle turns it into visuals, pathfinding and spawns.
##
## Output:
##   cells            0 = wall, 1 = floor (width * height)
##   rooms            Array[Rect2i] in cell coordinates
##   spawn_room       index into rooms
##   extract_rooms    two room indices, both far from spawn and from each other
##   stream_routes    [[from_cell, to_cell], ...] endless enemy flows
##   patrol_routes    [[cell, cell, ...], ...] looping patrol waypoints
##   portal_cells     hidden Dreamshape portals
##   cache_cells      loot caches

const TILE := 32

var width := 96
var height := 64
var cells := PackedByteArray()
var rooms: Array[Rect2i] = []
var spawn_room := 0
var extract_rooms: Array[int] = []
var stream_routes: Array = []
var patrol_routes: Array = []
var portal_cells: Array[Vector2i] = []
var cache_cells: Array[Vector2i] = []

var _rng := RandomNumberGenerator.new()


func generate(seed_value: int) -> void:
	_rng.seed = seed_value
	cells.resize(width * height)
	cells.fill(0)
	_place_rooms()
	_connect_rooms()
	_choose_key_rooms()
	_choose_streams()
	_choose_patrols()
	_choose_pickups()


# --- Queries -------------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_floor(c: Vector2i) -> bool:
	return in_bounds(c) and cells[c.y * width + c.x] == 1


func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE, TILE) * 0.5


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func room_center(i: int) -> Vector2i:
	return rooms[i].position + rooms[i].size / 2


func random_cell_in_room(i: int, inset := 1) -> Vector2i:
	var r := rooms[i].grow(-inset)
	return Vector2i(_rng.randi_range(r.position.x, r.end.x - 1), _rng.randi_range(r.position.y, r.end.y - 1))


## Nearest floor cell to `c` (spiral search), for snapping clicks on walls.
func nearest_floor(c: Vector2i, max_radius := 6) -> Vector2i:
	if is_floor(c):
		return c
	for r in range(1, max_radius + 1):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				if is_floor(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
		for dy in range(-r + 1, r):
			for dx in [-r, r]:
				if is_floor(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return c


## BFS walking distance from `from` to every cell (-1 = unreachable).
func distance_field(from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	if not is_floor(from):
		return dist
	var queue: Array[Vector2i] = [from]
	dist[from.y * width + from.x] = 0
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d := dist[c.y * width + c.x]
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + n
			if is_floor(nc) and dist[nc.y * width + nc.x] < 0:
				dist[nc.y * width + nc.x] = d + 1
				queue.append(nc)
	return dist


# --- Generation steps ----------------------------------------------------------

func _place_rooms() -> void:
	rooms.clear()
	for attempt in 400:
		if rooms.size() >= 16:
			break
		var w := _rng.randi_range(7, 15)
		var h := _rng.randi_range(6, 11)
		var r := Rect2i(_rng.randi_range(2, width - w - 2), _rng.randi_range(2, height - h - 2), w, h)
		var ok := true
		for other in rooms:
			if other.grow(3).intersects(r):
				ok = false
				break
		if ok:
			rooms.append(r)
			_carve_rect(r)


func _connect_rooms() -> void:
	# Grow a spanning tree: each room links to the closest already-linked room.
	var linked: Array[int] = [0]
	var pairs := {}
	for i in range(1, rooms.size()):
		var best := 0
		var best_d := INF
		for j in linked:
			var d := Vector2(room_center(i)).distance_to(Vector2(room_center(j)))
			if d < best_d:
				best_d = d
				best = j
		_carve_corridor(room_center(i), room_center(best))
		pairs[Vector2i(mini(i, best), maxi(i, best))] = true
		linked.append(i)
	# A few extra links create loops so there is more than one way around.
	for k in 4:
		var a := _rng.randi_range(0, rooms.size() - 1)
		var b := _rng.randi_range(0, rooms.size() - 1)
		if a != b and not pairs.has(Vector2i(mini(a, b), maxi(a, b))):
			_carve_corridor(room_center(a), room_center(b))


func _choose_key_rooms() -> void:
	spawn_room = _rng.randi_range(0, rooms.size() - 1)
	var from_spawn := _room_distances(room_center(spawn_room))
	# Extraction A: the room furthest (by walking distance) from spawn.
	var a := _argmax(func(i): return from_spawn[i] if i != spawn_room else -1)
	var from_a := _room_distances(room_center(a))
	var far_threshold: float = from_spawn[a] * 0.45
	# Extraction B: far from spawn AND from A, so the two exits pull you different ways.
	var b := _argmax(func(i):
		if i == spawn_room or i == a or from_spawn[i] < far_threshold:
			return -1
		return mini(from_spawn[i], from_a[i]))
	if b < 0 or b == a:
		b = _argmax(func(i): return from_spawn[i] if i != spawn_room and i != a else -1)
	extract_rooms = [a, b]


func _choose_streams() -> void:
	stream_routes.clear()
	var candidates: Array[int] = []
	for i in rooms.size():
		if i != spawn_room and not extract_rooms.has(i):
			candidates.append(i)
	candidates.shuffle()
	var spawn_dist := _room_distances(room_center(spawn_room))
	for i in candidates:
		if stream_routes.size() >= 2:
			break
		# Pick the destination room furthest from this source: the flow crosses the map.
		var d := _room_distances(room_center(i))
		var dest := _argmax(func(j): return d[j] if j != i and j != spawn_room else -1)
		# Keep stream sources from sitting right on top of the spawn.
		if dest >= 0 and spawn_dist[i] > 12:
			stream_routes.append([room_center(i), room_center(dest)])


func _choose_patrols() -> void:
	patrol_routes.clear()
	var spawn_dist := _room_distances(room_center(spawn_room))
	for i in rooms.size():
		if i == spawn_room or spawn_dist[i] < 18:
			continue
		if _rng.randf() > 0.6:
			continue
		var route: Array[Vector2i] = []
		for k in _rng.randi_range(2, 4):
			route.append(random_cell_in_room(i))
		patrol_routes.append(route)


func _choose_pickups() -> void:
	portal_cells.clear()
	cache_cells.clear()
	var order: Array[int] = []
	for i in rooms.size():
		if i != spawn_room:
			order.append(i)
	order.shuffle()
	# Hidden portals hug the walls of rooms; caches sit anywhere inside.
	for i in order.slice(0, 5):
		var r := rooms[i]
		var c := Vector2i(
				r.position.x + (0 if _rng.randf() < 0.5 else r.size.x - 1),
				_rng.randi_range(r.position.y, r.end.y - 1))
		portal_cells.append(c)
	order.shuffle()
	for i in order.slice(0, 7):
		cache_cells.append(random_cell_in_room(i, 2))


# --- Helpers ------------------------------------------------------------------------

func _carve_rect(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			cells[y * width + x] = 1


func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	# L-shaped, 2 tiles wide, randomly horizontal-first or vertical-first.
	var corner := Vector2i(b.x, a.y) if _rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_carve_line(a, corner)
	_carve_line(corner, b)


func _carve_line(a: Vector2i, b: Vector2i) -> void:
	var c := a
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	while true:
		_carve_rect(Rect2i(c, Vector2i(2, 2)).intersection(Rect2i(1, 1, width - 2, height - 2)))
		if c == b:
			break
		c += step


func _room_distances(from: Vector2i) -> Array[int]:
	var field := distance_field(from)
	var out: Array[int] = []
	for i in rooms.size():
		var c := room_center(i)
		out.append(field[c.y * width + c.x])
	return out


func _argmax(score: Callable) -> int:
	var best := -1
	var best_score := -1
	for i in rooms.size():
		var s: int = score.call(i)
		if s > best_score:
			best_score = s
			best = i
	return best
