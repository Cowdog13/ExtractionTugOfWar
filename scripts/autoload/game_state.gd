extends Node
## Persistent player profile and the raid lifecycle. Autoloaded as `GameState`.
##
## Item ownership — every owned item instance lives in exactly ONE place:
##   stash     : safe storage in the hub (never at risk)
##   equipped  : the Dreamseeker's loadout (AT RISK during a raid)
##   belt      : 4 Dreamshape portals brought into battle (AT RISK, consumed on use)
##   pouch     : 4-slot Safe Pouch (comes into the raid, always survives death)
##   raid.backpack : loot picked up during the current raid (AT RISK)
##
## Raid lifecycle:
##   begin_raid()            -> raid starts with a fresh map seed, game saved
##   consume_portal / add_raid_loot / secure_backpack_item during battle
##   end_raid(extracted)     -> extract keeps everything; death keeps only the pouch
## Quitting mid-raid counts as death (resolved on next load).

signal changed

const SAVE_VERSION := 1
const POUCH_SIZE := 4
const BELT_SIZE := 4
const BACKPACK_SIZE := 8
const SLOTS := ["main_hand", "off_hand", "head", "body", "legs", "trinket_1", "trinket_2"]
const SLOT_NAMES := {
	"main_hand": "Main Hand",
	"off_hand": "Off Hand",
	"head": "Head",
	"body": "Body",
	"legs": "Legs",
	"trinket_1": "Trinket I",
	"trinket_2": "Trinket II",
}
const BASE_STATS := {"max_hp": 50, "attack": 3, "defense": 0, "crit": 5, "lucidity": 0}

var save_path := "user://save.json"

var stash: Array = []           # Array of instances
var equipped: Dictionary = {}   # slot -> instance or null
var pouch: Array = []           # POUCH_SIZE entries, instance or null
var belt: Array = []            # BELT_SIZE entries, portal instance or null
var raid: Dictionary = {}       # empty when not in a raid
var last_raid_report: Dictionary = {}
var _next_uid := 1


func _ready() -> void:
	if not load_game():
		new_game()
	if is_in_raid():
		end_raid(false, "The dream collapsed while you were away.")


# --- Profile -----------------------------------------------------------------

func new_game() -> void:
	stash = []
	equipped = {}
	for slot in SLOTS:
		equipped[slot] = null
	pouch = []
	pouch.resize(POUCH_SIZE)
	belt = []
	belt.resize(BELT_SIZE)
	raid = {}
	last_raid_report = {}
	_next_uid = 1

	equipped["main_hand"] = _make("wpn_driftglass_blade")
	equipped["body"] = _make("body_quilted_vestment")
	equipped["head"] = _make("head_sleepcap")
	belt[0] = _make("portal_wisp_swarm")
	belt[1] = _make("portal_wisp_swarm")
	belt[2] = _make("portal_hollow_nursery")
	for id in ["off_pillow_buckler", "legs_restless_greaves", "wpn_reverie_dagger",
			"mat_memory_shard", "portal_wisp_swarm", "portal_drowned_belltower"]:
		stash.append(_make(id))
	_commit()


func get_stats() -> Dictionary:
	var result := BASE_STATS.duplicate()
	for slot in SLOTS:
		var inst = equipped[slot]
		if inst == null:
			continue
		var item := ItemDB.get_item(inst["id"])
		for key in item.stats:
			result[key] = result.get(key, 0) + item.stats[key]
	return result


func item_of(inst: Dictionary) -> ItemData:
	return ItemDB.get_item(inst["id"])


func find_in_stash(uid: int) -> int:
	for i in stash.size():
		if stash[i]["uid"] == uid:
			return i
	return -1


func get_stash_instance(uid: int) -> Dictionary:
	var i := find_in_stash(uid)
	return stash[i] if i >= 0 else {}


func portals_in_stash() -> Array:
	return stash.filter(func(inst): return item_of(inst).is_portal())


# --- Loadout & pouch (hub only) ------------------------------------------------

func can_equip(inst: Dictionary, slot: String) -> bool:
	return not is_in_raid() and item_of(inst).equip_slots.has(slot)


## Moves an item from the stash into a slot; whatever was there goes back to the stash.
func equip_from_stash(uid: int, slot: String) -> bool:
	var i := find_in_stash(uid)
	if i < 0 or not can_equip(stash[i], slot):
		return false
	var inst: Dictionary = stash[i]
	stash.remove_at(i)
	if equipped[slot] != null:
		stash.append(equipped[slot])
	equipped[slot] = inst
	_commit()
	return true


func unequip(slot: String) -> bool:
	if is_in_raid() or equipped.get(slot) == null:
		return false
	stash.append(equipped[slot])
	equipped[slot] = null
	_commit()
	return true


func pouch_free_index() -> int:
	return pouch.find(null)


func move_to_pouch(uid: int) -> bool:
	var i := find_in_stash(uid)
	var p := pouch_free_index()
	if is_in_raid() or i < 0 or p < 0:
		return false
	pouch[p] = stash[i]
	stash.remove_at(i)
	_commit()
	return true


func move_from_pouch(index: int) -> bool:
	if is_in_raid() or index < 0 or index >= POUCH_SIZE or pouch[index] == null:
		return false
	stash.append(pouch[index])
	pouch[index] = null
	_commit()
	return true


func move_to_belt(uid: int) -> bool:
	var i := find_in_stash(uid)
	var b := belt.find(null)
	if is_in_raid() or i < 0 or b < 0 or not item_of(stash[i]).is_portal():
		return false
	belt[b] = stash[i]
	stash.remove_at(i)
	_commit()
	return true


func move_from_belt(index: int) -> bool:
	if is_in_raid() or index < 0 or index >= BELT_SIZE or belt[index] == null:
		return false
	stash.append(belt[index])
	belt[index] = null
	_commit()
	return true


# --- Raid lifecycle ------------------------------------------------------------

func is_in_raid() -> bool:
	return not raid.is_empty()


func begin_raid() -> bool:
	if is_in_raid():
		return false
	raid = {"seed": randi(), "backpack": []}
	last_raid_report = {}
	_commit()
	return true


## Removes a portal from the belt (or backpack, if it was found this raid) when opened.
func consume_portal(uid: int) -> ItemData:
	if not is_in_raid():
		return null
	for i in BELT_SIZE:
		if belt[i] != null and belt[i]["uid"] == uid:
			var item := item_of(belt[i])
			belt[i] = null
			_commit()
			return item
	var backpack: Array = raid["backpack"]
	for i in backpack.size():
		if backpack[i]["uid"] == uid and item_of(backpack[i]).is_portal():
			var item := item_of(backpack[i])
			backpack.remove_at(i)
			_commit()
			return item
	return null


## Portals usable right now in battle: the belt first, then any found this raid.
func usable_portals() -> Array:
	var out: Array = belt.filter(func(inst): return inst != null)
	if is_in_raid():
		out.append_array(raid["backpack"].filter(func(inst): return item_of(inst).is_portal()))
	return out


## Adds a found item to the raid. Portals slot into a free belt slot first.
## Returns the instance, or {} if there was no room.
func add_raid_loot(id: String) -> Dictionary:
	if not is_in_raid():
		return {}
	var inst := {}
	var b := belt.find(null)
	if ItemDB.get_item(id).is_portal() and b >= 0:
		inst = _make(id)
		belt[b] = inst
	elif raid["backpack"].size() < BACKPACK_SIZE:
		inst = _make(id)
		raid["backpack"].append(inst)
	else:
		return {}
	_commit()
	return inst


## Moves a backpack item into a free Safe Pouch slot so it survives death.
func secure_backpack_item(uid: int) -> bool:
	var p := pouch_free_index()
	if not is_in_raid() or p < 0:
		return false
	var backpack: Array = raid["backpack"]
	for i in backpack.size():
		if backpack[i]["uid"] == uid:
			pouch[p] = backpack[i]
			backpack.remove_at(i)
			_commit()
			return true
	return false


func end_raid(extracted: bool, reason: String = "") -> Dictionary:
	if not is_in_raid():
		return {}
	var report := {
		"extracted": extracted,
		"reason": reason,
		"gained": [],
		"lost": [],
		"secured": [],
	}
	if extracted:
		for inst in raid["backpack"]:
			stash.append(inst)
			report["gained"].append(inst["id"])
	else:
		for slot in SLOTS:
			if equipped[slot] != null:
				report["lost"].append(equipped[slot]["id"])
				equipped[slot] = null
		for i in BELT_SIZE:
			if belt[i] != null:
				report["lost"].append(belt[i]["id"])
				belt[i] = null
		for inst in raid["backpack"]:
			report["lost"].append(inst["id"])
	for inst in pouch:
		if inst != null:
			report["secured"].append(inst["id"])
	raid = {}
	last_raid_report = report
	_commit()
	return report


func clear_report() -> void:
	last_raid_report = {}
	_commit()


# --- Persistence -----------------------------------------------------------------

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"next_uid": _next_uid,
		"stash": stash,
		"equipped": equipped,
		"pouch": pouch,
		"belt": belt,
		"raid": raid,
		"last_raid_report": last_raid_report,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Save file unreadable; starting a new game.")
		return false
	_next_uid = int(data.get("next_uid", 1))
	stash = _clean_list(data.get("stash", []), false)
	equipped = {}
	var eq = data.get("equipped", {})
	for slot in SLOTS:
		equipped[slot] = _clean_inst(eq.get(slot)) if typeof(eq) == TYPE_DICTIONARY else null
	pouch = _clean_list(data.get("pouch", []), true)
	pouch.resize(POUCH_SIZE)
	belt = _clean_list(data.get("belt", []), true)
	belt.resize(BELT_SIZE)
	raid = {}
	var r = data.get("raid", {})
	if typeof(r) == TYPE_DICTIONARY and not r.is_empty():
		raid = {"seed": int(r.get("seed", 0)), "backpack": _clean_list(r.get("backpack", []), false)}
	var rep = data.get("last_raid_report", {})
	last_raid_report = rep if typeof(rep) == TYPE_DICTIONARY else {}
	changed.emit()
	return true


# --- Internals -------------------------------------------------------------------

func _make(id: String) -> Dictionary:
	assert(ItemDB.has_item(id), "Unknown item id: %s" % id)
	var inst := {"uid": _next_uid, "id": id}
	_next_uid += 1
	return inst


func _commit() -> void:
	save_game()
	changed.emit()


## JSON turns ints into floats and may contain stale ids; normalise on load.
func _clean_inst(v) -> Variant:
	if typeof(v) != TYPE_DICTIONARY or not ItemDB.has_item(str(v.get("id", ""))):
		return null
	return {"uid": int(v.get("uid", 0)), "id": str(v["id"])}


func _clean_list(list, keep_nulls: bool) -> Array:
	var out: Array = []
	if typeof(list) != TYPE_ARRAY:
		return out
	for v in list:
		var inst = _clean_inst(v)
		if inst != null or keep_nulls:
			out.append(inst)
	return out
