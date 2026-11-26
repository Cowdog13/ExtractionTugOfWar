extends Node
## Headless smoke tests. Run:
##   godot --headless --path . res://tests/test_flow.tscn
## Exits with code 0 on success, 1 on any failure.

var _failures := 0


func _ready() -> void:
	GameState.save_path = "user://test_save.json"
	_test_loadout()
	_test_death_keeps_only_pouch()
	_test_extract_keeps_loot()
	_test_quit_mid_raid_is_death()
	_test_map_generation()
	await _test_battle_runs()
	print("\n%s (%d failures)" % ["ALL TESTS PASSED" if _failures == 0 else "TESTS FAILED", _failures])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
	get_tree().quit(1 if _failures else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		_failures += 1
		printerr("  FAIL ", what)


func _uid_of(id: String) -> int:
	for inst in GameState.stash:
		if inst["id"] == id:
			return inst["uid"]
	return -1


func _test_loadout() -> void:
	print("loadout")
	GameState.new_game()
	var before: int = GameState.get_stats()["defense"]
	check(GameState.equip_from_stash(_uid_of("off_pillow_buckler"), "off_hand"), "equip buckler")
	check(GameState.get_stats()["defense"] == before + 3, "defense includes buckler")
	check(not GameState.equip_from_stash(_uid_of("legs_restless_greaves"), "head"), "wrong slot rejected")
	check(GameState.move_to_belt(_uid_of("portal_wisp_swarm")), "portal onto belt")
	check(not GameState.move_to_belt(_uid_of("mat_memory_shard")), "non-portal can't go on belt")
	check(GameState.move_to_pouch(_uid_of("mat_memory_shard")), "shard into pouch")


func _test_death_keeps_only_pouch() -> void:
	print("death")
	GameState.new_game()
	GameState.move_to_pouch(_uid_of("wpn_reverie_dagger"))
	check(GameState.begin_raid(), "raid starts")
	check(not GameState.unequip("main_hand"), "can't change gear mid-raid")
	var portal_uid: int = GameState.belt[0]["uid"]
	check(GameState.consume_portal(portal_uid) != null, "portal consumed in battle")
	check(GameState.belt[0] == null, "belt slot emptied")
	var loot := GameState.add_raid_loot("mat_lucid_pearl")
	GameState.add_raid_loot("wpn_somnium_spear")
	check(GameState.secure_backpack_item(loot["uid"]), "secure pearl mid-raid")
	var report := GameState.end_raid(false, "test death")
	check(GameState.equipped.values().all(func(v): return v == null), "all gear lost")
	check(GameState.belt.all(func(v): return v == null), "unused portals lost")
	check(report["lost"].has("wpn_somnium_spear"), "unsecured loot lost")
	var pouch_ids := GameState.pouch.filter(func(v): return v != null).map(func(v): return v["id"])
	check(pouch_ids.has("wpn_reverie_dagger") and pouch_ids.has("mat_lucid_pearl"), "pouch survived")


func _test_extract_keeps_loot() -> void:
	print("extract")
	GameState.new_game()
	GameState.begin_raid()
	GameState.belt[3] = null
	var p := GameState.add_raid_loot("portal_last_lullaby")
	check(GameState.belt[3] != null and GameState.belt[3]["uid"] == p["uid"], "found portal goes to free belt slot")
	GameState.add_raid_loot("wpn_dawnbreaker")
	GameState.end_raid(true)
	check(_uid_of("wpn_dawnbreaker") >= 0, "loot in stash after extract")
	check(GameState.equipped["main_hand"] != null, "gear kept after extract")


func _test_quit_mid_raid_is_death() -> void:
	print("quit mid-raid")
	GameState.new_game()
	GameState.begin_raid()
	GameState.load_game()
	check(GameState.is_in_raid(), "raid persisted in save")
	GameState._ready()  # simulate next launch
	check(not GameState.is_in_raid() and GameState.equipped["main_hand"] == null, "treated as death")


func _test_map_generation() -> void:
	print("map generation")
	var ok := true
	for seed_value in 40:
		var m := DreamMap.new()
		m.generate(seed_value)
		var field := m.distance_field(m.room_center(m.spawn_room))
		var reach := func(c: Vector2i): return field[c.y * m.width + c.x] >= 0
		if m.extract_rooms.size() != 2 or m.extract_rooms[0] == m.extract_rooms[1] \
				or m.extract_rooms.has(m.spawn_room):
			ok = false
			printerr("    seed %d: bad extraction rooms %s" % [seed_value, m.extract_rooms])
		for i in m.rooms.size():
			if not reach.call(m.room_center(i)):
				ok = false
				printerr("    seed %d: room %d unreachable" % [seed_value, i])
		for c in m.portal_cells + m.cache_cells:
			if not m.is_floor(c):
				ok = false
				printerr("    seed %d: pickup in wall %s" % [seed_value, c])
	check(ok, "40 seeds: 2 distinct exits, all rooms reachable, pickups on floor")


func _test_battle_runs() -> void:
	print("battle")
	GameState.new_game()
	GameState.begin_raid()
	var battle: Node2D = load("res://scenes/battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	check(battle.player != null, "player spawned")
	check(battle.extraction_points.size() == 2, "two extraction points")
	battle.open_portal(GameState.belt[0]["uid"], battle.extraction_points[0])
	for i in 240:  # ~4 seconds of simulated play
		await get_tree().physics_frame
	check(battle.allies_alive() > 0, "allies streamed out of the portal (%d)" % battle.allies_alive())
	check(battle.enemies_alive() > 0, "enemy patrols/streams present (%d)" % battle.enemies_alive())
	var start: Vector2 = battle.player.position
	battle.player.order_move(battle.extraction_points[0])
	for i in 60:
		await get_tree().physics_frame
	check(battle.player.position.distance_to(start) > 20.0, "player walks along a path")
	# Teleport onto an exit and wait out the timer.
	battle.player.max_hp = 99999
	battle.player.hp = 99999
	battle.player.position = battle.extraction_points[1]
	battle.player.clear_goal()
	await get_tree().create_timer(battle.EXTRACT_TIME + 0.5).timeout
	check(not GameState.is_in_raid(), "standing in extraction zone ends the raid")
	check(GameState.last_raid_report.get("extracted", false), "report says extracted")
	battle.set_process(false)
	battle.queue_free()
