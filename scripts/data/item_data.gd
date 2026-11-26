class_name ItemData
extends Resource
## Static definition of an item (one per item type, shared by all copies).
## Individual copies the player owns are lightweight "instances":
## { "uid": int, "id": String } dictionaries managed by GameState.

enum Kind { WEAPON, OFFHAND, ARMOR, TRINKET, PORTAL, MATERIAL }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const KIND_NAMES := ["Weapon", "Off-hand", "Armor", "Trinket", "Dreamshape Portal", "Material"]
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [
	Color("c8c8d0"), Color("6fdc8c"), Color("5aa9ff"), Color("c77dff"), Color("ffb347"),
]
const STAT_NAMES := {
	"max_hp": "Max HP",
	"attack": "Attack",
	"defense": "Defense",
	"crit": "Crit %",
	"lucidity": "Lucidity",
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
## Loadout slots this item may be equipped into (see GameState.SLOTS).
@export var equip_slots: PackedStringArray = PackedStringArray()
## Stat bonuses while equipped, e.g. { "attack": 5, "crit": 3 }.
@export var stats: Dictionary = {}
@export var value: int = 0

@export_group("Portal")
## Dreamshape type this portal streams out (key in ItemDB.SHAPES).
@export var summon_shape: String = ""
## How many Dreamshapes come through before the portal closes.
@export var stream_count: int = 0
## Seconds between each Dreamshape emerging.
@export var stream_interval: float = 1.0
## Seconds each summoned Dreamshape lives before dissolving.
@export var shape_lifetime: float = 20.0


func is_portal() -> bool:
	return kind == Kind.PORTAL


func is_equippable() -> bool:
	return not equip_slots.is_empty()


func rarity_color() -> Color:
	return RARITY_COLORS[rarity]


## BBCode description used by tooltips/detail panels.
func describe_bbcode() -> String:
	var lines: Array[String] = []
	lines.append("[color=#%s][b]%s[/b][/color]" % [rarity_color().to_html(false), display_name])
	lines.append("[i]%s %s[/i]" % [RARITY_NAMES[rarity], KIND_NAMES[kind]])
	for key in stats:
		var v: int = stats[key]
		lines.append("%s%d %s" % ["+" if v >= 0 else "", v, STAT_NAMES.get(key, key)])
	if is_portal():
		var shape: Dictionary = ItemDB.SHAPES.get(summon_shape, {})
		lines.append("Streams %d× %s (one every %.1fs)" % [stream_count, shape.get("name", summon_shape), stream_interval])
		lines.append("Each lasts %ds  •  HP %d  •  ATK %d" % [shape_lifetime, shape.get("hp", 0), shape.get("attack", 0)])
		lines.append("[color=#f88]Consumed when opened in battle[/color]")
	if description != "":
		lines.append("[color=#aaa]%s[/color]" % description)
	if value > 0:
		lines.append("Value: %d shards" % value)
	return "\n".join(lines)


## Plain-text description (for Button tooltips, which don't render BBCode).
func describe_plain() -> String:
	var regex := RegEx.new()
	regex.compile("\\[.*?\\]")
	return regex.sub(describe_bbcode(), "", true)
