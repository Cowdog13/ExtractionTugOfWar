extends Node
## Item catalog + loot rolling. Autoloaded as `ItemDB`.
##
## Items are defined in code here to keep the prototype in one place.
## To move to designer-editable data later, save ItemData resources as .tres
## files and load them in _init() instead.

## Dreamshape unit types. Allies come out of the player's portals; enemies patrol
## and stream through the dream. `range` > 40 means a ranged attacker.
const SHAPES := {
	# --- summoned by player portals ---
	"wisp": {"name": "Wisp", "hp": 14, "attack": 3, "defense": 0, "speed": 190.0,
			"range": 26.0, "cooldown": 0.6, "radius": 7.0, "color": Color("9be7ff")},
	"doll": {"name": "Hollow Doll", "hp": 30, "attack": 5, "defense": 1, "speed": 130.0,
			"range": 28.0, "cooldown": 0.9, "radius": 10.0, "color": Color("ffd6e8")},
	"bell_knight": {"name": "Bell Knight", "hp": 70, "attack": 9, "defense": 4, "speed": 110.0,
			"range": 30.0, "cooldown": 1.1, "radius": 13.0, "color": Color("7fb2ff")},
	"gear_titan": {"name": "Gear Titan", "hp": 160, "attack": 16, "defense": 7, "speed": 85.0,
			"range": 36.0, "cooldown": 1.5, "radius": 18.0, "color": Color("ffcf70")},
	"lullaby_spirit": {"name": "Lullaby Spirit", "hp": 40, "attack": 8, "defense": 1, "speed": 140.0,
			"range": 170.0, "cooldown": 1.0, "radius": 9.0, "color": Color("e0b3ff")},
	# --- hostile Dreamshapes ---
	"shade": {"name": "Shade", "hp": 22, "attack": 4, "defense": 0, "speed": 120.0,
			"range": 26.0, "cooldown": 0.9, "radius": 9.0, "color": Color("ff5d6c")},
	"stalker": {"name": "Stalker", "hp": 16, "attack": 6, "defense": 0, "speed": 200.0,
			"range": 24.0, "cooldown": 0.7, "radius": 8.0, "color": Color("ff8a3d")},
	"maw": {"name": "Maw", "hp": 90, "attack": 10, "defense": 4, "speed": 80.0,
			"range": 32.0, "cooldown": 1.4, "radius": 16.0, "color": Color("c2185b")},
	"wailer": {"name": "Wailer", "hp": 26, "attack": 5, "defense": 0, "speed": 105.0,
			"range": 150.0, "cooldown": 1.3, "radius": 9.0, "color": Color("ff4fd8")},
}

var _items: Dictionary = {}  # id -> ItemData


func _init() -> void:
	# Registered in _init so the catalog exists before GameState._ready() loads the save.
	_register_weapons()
	_register_armor()
	_register_trinkets()
	_register_materials()
	_register_portals()


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> ItemData:
	return _items.get(id)


func all_items() -> Array:
	return _items.values()


## Rolls one loot drop. Higher portal tier and Lucidity shift odds toward rarer items.
func roll_loot(tier: int, lucidity: int, rng: RandomNumberGenerator) -> String:
	var bonus := float(tier) + lucidity / 20.0
	var weights := [
		maxf(5.0, 60.0 - bonus * 12.0),  # common
		25.0 + bonus * 3.0,              # uncommon
		10.0 + bonus * 4.0,              # rare
		3.0 + bonus * 3.0,               # epic
		0.5 + bonus * 1.5,               # legendary
	]
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	var rarity := 0
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			rarity = i
			break

	# Pick an item of that rarity; step down if none exist.
	while rarity >= 0:
		var pool: Array[String] = []
		for item: ItemData in _items.values():
			if item.rarity == rarity:
				pool.append(item.id)
		if not pool.is_empty():
			return pool[rng.randi_range(0, pool.size() - 1)]
		rarity -= 1
	return "mat_memory_shard"


## Rolls which Dreamshape portal is hidden somewhere in the dream.
func roll_portal(lucidity: int, rng: RandomNumberGenerator) -> String:
	var portals: Array = _items.values().filter(func(i: ItemData): return i.is_portal())
	var total := 0.0
	var weights: Array[float] = []
	for p: ItemData in portals:
		var w: float = [50.0, 28.0, 14.0, 6.0, 2.0][p.rarity] * (1.0 + p.rarity * lucidity / 50.0)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in portals.size():
		roll -= weights[i]
		if roll <= 0.0:
			return portals[i].id
	return portals[0].id


# --- Catalog -----------------------------------------------------------------

func _add(id: String, display_name: String, kind: ItemData.Kind, rarity: ItemData.Rarity,
		slots: Array, stats: Dictionary, value: int, desc: String) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.display_name = display_name
	item.kind = kind
	item.rarity = rarity
	item.equip_slots = PackedStringArray(slots)
	item.stats = stats
	item.value = value
	item.description = desc
	_items[id] = item
	return item


func _register_weapons() -> void:
	var W := ItemData.Kind.WEAPON
	var R := ItemData.Rarity
	_add("wpn_driftglass_blade", "Driftglass Blade", W, R.COMMON, ["main_hand"],
			{"attack": 6}, 10, "Sea-glass honed on the shore between sleep and waking.")
	_add("wpn_reverie_dagger", "Reverie Dagger", W, R.COMMON, ["main_hand", "off_hand"],
			{"attack": 4, "crit": 8}, 12, "Light enough to wield in either hand.")
	_add("wpn_somnium_spear", "Somnium Spear", W, R.UNCOMMON, ["main_hand"],
			{"attack": 9, "defense": 1}, 30, "Its tip hums a half-remembered tune.")
	_add("wpn_lullaby_scepter", "Lullaby Scepter", W, R.RARE, ["main_hand"],
			{"attack": 8, "lucidity": 15}, 70, "Dreams bend toward whoever holds it.")
	_add("wpn_nightmare_cleaver", "Nightmare Cleaver", W, R.RARE, ["main_hand"],
			{"attack": 14, "crit": 5}, 80, "Forged from a fear that never ended.")
	_add("wpn_oneiric_greatblade", "Oneiric Greatblade", W, R.EPIC, ["main_hand"],
			{"attack": 20, "max_hp": 10}, 180, "Each swing rewrites the dream around it.")
	_add("wpn_dawnbreaker", "Dawnbreaker", W, R.LEGENDARY, ["main_hand"],
			{"attack": 28, "crit": 12, "lucidity": 10}, 500, "The first light of morning, sharpened.")


func _register_armor() -> void:
	var O := ItemData.Kind.OFFHAND
	var A := ItemData.Kind.ARMOR
	var R := ItemData.Rarity
	# Off-hands
	_add("off_pillow_buckler", "Pillow Buckler", O, R.COMMON, ["off_hand"],
			{"defense": 3}, 10, "Softer than it should be. Sturdier than it looks.")
	_add("off_moonward_aegis", "Moonward Aegis", O, R.RARE, ["off_hand"],
			{"defense": 7, "max_hp": 15}, 75, "Moonlight pools on its face.")
	# Head
	_add("head_sleepcap", "Sleepcap", A, R.COMMON, ["head"],
			{"max_hp": 5, "defense": 1}, 8, "Comes with a tassel.")
	_add("head_visage_of_waking", "Visage of Waking", A, R.RARE, ["head"],
			{"defense": 4, "crit": 6}, 70, "Eyes that are always open.")
	# Body
	_add("body_quilted_vestment", "Quilted Vestment", A, R.COMMON, ["body"],
			{"max_hp": 15, "defense": 2}, 12, "Stitched from old blankets.")
	_add("body_starwoven_mail", "Starwoven Mail", A, R.RARE, ["body"],
			{"max_hp": 30, "defense": 6}, 90, "Constellations shift across the links.")
	_add("body_deep_sleeper_mantle", "Mantle of the Deep Sleeper", A, R.EPIC, ["body"],
			{"max_hp": 50, "defense": 9}, 200, "Worn by one who never woke.")
	# Legs
	_add("legs_restless_greaves", "Restless Greaves", A, R.COMMON, ["legs"],
			{"max_hp": 8, "defense": 2}, 10, "They twitch when you stand still.")
	_add("legs_wanderer_leggings", "Wanderer's Leggings", A, R.UNCOMMON, ["legs"],
			{"max_hp": 12, "defense": 3, "lucidity": 5}, 28, "Worn thin by endless corridors.")


func _register_trinkets() -> void:
	var T := ItemData.Kind.TRINKET
	var R := ItemData.Rarity
	var both := ["trinket_1", "trinket_2"]
	_add("trk_dreamcatcher", "Dreamcatcher Charm", T, R.UNCOMMON, both,
			{"lucidity": 15}, 35, "Catches the good ones.")
	_add("trk_sandman_tooth", "Tooth of the Sandman", T, R.UNCOMMON, both,
			{"attack": 2, "crit": 8}, 35, "Still gritty.")
	_add("trk_hourglass", "Hourglass of Stillness", T, R.RARE, both,
			{"max_hp": 20, "defense": 2}, 70, "The sand falls upward.")
	_add("trk_heart_of_reverie", "Heart of Reverie", T, R.EPIC, both,
			{"max_hp": 25, "attack": 5, "lucidity": 20}, 220, "It beats in time with yours.")


func _register_materials() -> void:
	var M := ItemData.Kind.MATERIAL
	var R := ItemData.Rarity
	_add("mat_memory_shard", "Shard of Memory", M, R.COMMON, [], {}, 5,
			"A sliver of someone's forgotten afternoon.")
	_add("mat_lucid_pearl", "Lucid Pearl", M, R.RARE, [], {}, 60,
			"Perfectly clear. Perfectly valuable.")
	_add("mat_waking_ember", "Waking Ember", M, R.LEGENDARY, [], {}, 400,
			"Warm proof that the real world exists.")


func _register_portals() -> void:
	var P := ItemData.Kind.PORTAL
	var R := ItemData.Rarity
	# id, name, rarity, shape, count, interval, lifetime, value, description
	var defs := [
		["portal_wisp_swarm", "Dreamshape: Wisp Swarm", R.COMMON, "wisp", 8, 0.4, 18.0, 12,
				"A flutter of half-thoughts. Fast, fragile, numerous."],
		["portal_hollow_nursery", "Dreamshape: Hollow Nursery", R.UNCOMMON, "doll", 6, 0.8, 25.0, 30,
				"Cribs rock on their own. The dolls climb out to help."],
		["portal_drowned_belltower", "Dreamshape: Drowned Belltower", R.RARE, "bell_knight", 4, 1.2, 30.0, 70,
				"Knights in rusted bell-helms march out to the toll."],
		["portal_last_lullaby", "Dreamshape: The Last Lullaby", R.EPIC, "lullaby_spirit", 7, 0.7, 32.0, 160,
				"Spirits that sing harm from a distance."],
		["portal_clockwork_abyss", "Dreamshape: Clockwork Abyss", R.LEGENDARY, "gear_titan", 3, 2.0, 40.0, 400,
				"Gears the size of moons grind toward your enemies."],
	]
	for d in defs:
		var p := _add(d[0], d[1], P, d[2], [], {}, d[7], d[8])
		p.summon_shape = d[3]
		p.stream_count = d[4]
		p.stream_interval = d[5]
		p.shape_lifetime = d[6]
