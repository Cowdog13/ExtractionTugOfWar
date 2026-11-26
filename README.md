# Dreamseeker (working title)

An extraction game in Godot 4.3. Gear up your **Dreamseeker**, carry **Dreamshape portals**
into a procedural dream, summon streams of allies, grab loot, and reach an exit.
Die, and you lose everything except your **4-slot Safe Pouch**.

## Run it
Open the folder in Godot 4.3+ and press F5. Main scene: `scenes/hub.tscn`.

Headless tests:
```bash
godot --headless --path . res://tests/test_flow.tscn
```

## Core loop
1. **Waking Hall (hub)**: equip 7 slots (Main/Off hand, Head, Body, Legs, 2 Trinkets), fill the
   **Safe Pouch** (4) and **Portal Belt** (4) from your stash.
2. **Enter the Dream**: a new procedural map with **2 extraction points** far from the spawn and from each other.
3. **Battle (real-time)**
   - Click to move; the Dreamseeker auto-attacks anything in reach.
   - Press **1–4** to ready a belt portal, then click a **rally point**. The portal opens beside you and
     streams Dreamshapes that march there on their own, fighting whatever they meet. **R** re-rallies all allies.
   - Portals are **consumed** when opened. More are **hidden** around the map (they fade in when you're close;
     Lucidity widens that range). Found portals fill empty belt slots.
   - **Enemy patrols** loop through rooms and respawn from their nests. **Endless enemy streams** pour from
     hostile portals and flow across the map.
   - **Every Dreamshape is timed** (the ring around it is its remaining life) and dissolves when time runs out.
   - Enemies get stronger the longer you stay (**Instability**).
   - Loot caches and enemy drops go into your backpack; **Secure** moves an item into the Safe Pouch mid-raid.
   - Stand in an extraction circle for 4 seconds to wake up.
4. **Outcome**
   - Extract: keep gear, unused portals and all loot.
   - Die / abandon / quit the game mid-raid: lose equipped gear, belt and backpack. **Pouch is kept.**

## Code map
| Path | What |
|---|---|
| `scripts/autoload/item_db.gd` | Item catalog, Dreamshape unit stats (`SHAPES`), loot/portal rolls |
| `scripts/autoload/game_state.gd` | Stash/loadout/pouch/belt, raid lifecycle, JSON save (`user://save.json`) |
| `scripts/data/item_data.gd` | `ItemData` resource definition |
| `scripts/ui/hub.gd` | Hub UI (built in code) |
| `scripts/battle/dream_map.gd` | Procedural map: rooms, corridors, exits, streams, patrols, pickups |
| `scripts/battle/battle.gd` | Raid orchestrator: pathfinding (AStarGrid2D), spawning, input, extraction |
| `scripts/battle/unit.gd` | Shared unit logic: move, target, attack, damage, lifetime |
| `scripts/battle/dreamshape.gd` | Dreamshape AI: rally / patrol / stream |
| `scripts/battle/dreamseeker.gd` | Player unit |
| `scripts/battle/portal_stream.gd` | An open portal emitting units (finite for the player, endless for enemies) |
| `scripts/battle/pickup.gd` | Hidden portals, caches, drops |
| `scripts/battle/battle_hud.gd` | HUD, minimap, belt, backpack, pause menu |

### Adding content
- **New item**: add an `_add(...)` line in `item_db.gd`.
- **New Dreamshape**: add an entry to `ItemDB.SHAPES`, then a portal that summons it in `_register_portals()`.
- **Enemy mix**: `ENEMY_STREAM_POOL` / `PATROL_POOL` in `battle.gd`.

All visuals are placeholder shapes drawn in code, so you can swap in sprites one unit at a time by
replacing each `_draw()`.
