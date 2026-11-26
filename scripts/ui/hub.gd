extends Control
## The Waking Hall: equip the Dreamseeker, fill the Safe Pouch and Portal Belt,
## then enter the dream. UI is built in code so it is easy to read and restyle.

const BATTLE_SCENE := "res://scenes/battle.tscn"
const BG := Color("14121f")

var _equip_buttons := {}          # slot -> Button
var _pouch_buttons: Array[Button] = []
var _belt_buttons: Array[Button] = []
var _stats_label: RichTextLabel
var _stash_list: ItemList
var _detail: RichTextLabel
var _actions: HFlowContainer
var _selected_uid := -1


func _ready() -> void:
	_build()
	GameState.changed.connect(_refresh)
	_refresh()
	if not GameState.last_raid_report.is_empty():
		_show_report.call_deferred(GameState.last_raid_report)
		GameState.clear_report()


# --- Layout ----------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "THE WAKING HALL"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("d9c8ff"))
	header.add_child(title)
	var sub := Label.new()
	sub.text = "   Prepare your Dreamseeker. What you bring may not come back."
	sub.add_theme_color_override("font_color", Color("8a84a6"))
	sub.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(sub)
	var reset := Button.new()
	reset.text = "Reset Save"
	reset.pressed.connect(_confirm_reset)
	header.add_child(reset)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	cols.add_child(_build_seeker_panel())
	cols.add_child(_build_middle_panel())
	cols.add_child(_build_stash_panel())


func _panel(title: String, ratio: float) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1e1b2e")
	style.border_color = Color("3a3456")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_heading(title))
	return [panel, box]


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("bfb3ff"))
	return l


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("8a84a6"))
	return l


func _slot_button(min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return b


func _build_seeker_panel() -> Control:
	var p := _panel("Dreamseeker", 1.0)
	var box: VBoxContainer = p[1]
	box.add_child(_hint("Equipped gear is AT RISK. Click a slot to unequip."))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)
	for slot in GameState.SLOTS:
		var l := Label.new()
		l.text = GameState.SLOT_NAMES[slot]
		l.custom_minimum_size.x = 80
		grid.add_child(l)
		var b := _slot_button(Vector2(210, 34))
		b.pressed.connect(func(): GameState.unequip(slot))
		grid.add_child(b)
		_equip_buttons[slot] = b
	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(_stats_label)
	return p[0]


func _build_middle_panel() -> Control:
	var p := _panel("Safe Pouch", 1.0)
	var box: VBoxContainer = p[1]
	box.add_child(_hint("4 slots. Anything here survives death. Find something great mid-raid? Secure it here."))
	var pouch_grid := GridContainer.new()
	pouch_grid.columns = 2
	box.add_child(pouch_grid)
	for i in GameState.POUCH_SIZE:
		var b := _slot_button(Vector2(150, 48))
		b.pressed.connect(func(): GameState.move_from_pouch(i))
		pouch_grid.add_child(b)
		_pouch_buttons.append(b)

	box.add_child(HSeparator.new())
	box.add_child(_heading("Portal Belt"))
	box.add_child(_hint("Dreamshape portals to bring into battle (keys 1–4). Each is consumed when opened. Unused ones are lost if you die."))
	var belt_grid := GridContainer.new()
	belt_grid.columns = 2
	box.add_child(belt_grid)
	for i in GameState.BELT_SIZE:
		var b := _slot_button(Vector2(150, 48))
		b.pressed.connect(func(): GameState.move_from_belt(i))
		belt_grid.add_child(b)
		_belt_buttons.append(b)

	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(spacer)
	var enter := Button.new()
	enter.text = "ENTER THE DREAM"
	enter.custom_minimum_size.y = 56
	enter.add_theme_font_size_override("font_size", 20)
	enter.pressed.connect(_confirm_enter)
	box.add_child(enter)
	return p[0]


func _build_stash_panel() -> Control:
	var p := _panel("Stash", 1.2)
	var box: VBoxContainer = p[1]
	box.add_child(_hint("Safe storage. Select an item to equip it, pouch it or belt it."))
	_stash_list = ItemList.new()
	_stash_list.size_flags_vertical = SIZE_EXPAND_FILL
	_stash_list.item_selected.connect(_on_stash_selected)
	box.add_child(_stash_list)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.custom_minimum_size.y = 130
	box.add_child(_detail)
	_actions = HFlowContainer.new()
	box.add_child(_actions)
	return p[0]


# --- Refresh -----------------------------------------------------------------------

func _refresh() -> void:
	for slot in GameState.SLOTS:
		_fill_slot(_equip_buttons[slot], GameState.equipped[slot], "— empty —")
	for i in GameState.POUCH_SIZE:
		_fill_slot(_pouch_buttons[i], GameState.pouch[i], "— free —")
	for i in GameState.BELT_SIZE:
		_fill_slot(_belt_buttons[i], GameState.belt[i], "%d: — empty —" % (i + 1), "%d: " % (i + 1))

	var st := GameState.get_stats()
	var lines := []
	for key in ItemData.STAT_NAMES:
		lines.append("%s: [b]%d[/b]" % [ItemData.STAT_NAMES[key], st.get(key, 0)])
	_stats_label.text = "[color=#bfb3ff]Stats[/color]\n" + "\n".join(lines)

	var items := GameState.stash.duplicate()
	items.sort_custom(func(a, b):
		var ia := GameState.item_of(a)
		var ib := GameState.item_of(b)
		if ia.kind != ib.kind:
			return ia.kind < ib.kind
		if ia.rarity != ib.rarity:
			return ia.rarity > ib.rarity
		return ia.display_name < ib.display_name)
	_stash_list.clear()
	var reselect := -1
	for inst in items:
		var item := GameState.item_of(inst)
		var idx := _stash_list.add_item("%s   [%s]" % [item.display_name, ItemData.KIND_NAMES[item.kind]])
		_stash_list.set_item_metadata(idx, inst["uid"])
		_stash_list.set_item_custom_fg_color(idx, item.rarity_color())
		_stash_list.set_item_tooltip(idx, item.describe_plain())
		if inst["uid"] == _selected_uid:
			reselect = idx
	if reselect >= 0:
		_stash_list.select(reselect)
	else:
		_selected_uid = -1
	_update_detail()


func _fill_slot(b: Button, inst, empty_text: String, prefix := "") -> void:
	if inst == null:
		b.text = empty_text
		b.tooltip_text = ""
		b.remove_theme_color_override("font_color")
		b.disabled = true
		return
	var item := GameState.item_of(inst)
	b.text = prefix + item.display_name
	b.tooltip_text = item.describe_plain() + "\n\n(click to return to stash)"
	b.add_theme_color_override("font_color", item.rarity_color())
	b.disabled = false


func _on_stash_selected(index: int) -> void:
	_selected_uid = _stash_list.get_item_metadata(index)
	_update_detail()


func _update_detail() -> void:
	for c in _actions.get_children():
		c.queue_free()
	var inst := GameState.get_stash_instance(_selected_uid)
	if inst.is_empty():
		_detail.text = "[color=#666]Select an item.[/color]"
		return
	var item := GameState.item_of(inst)
	_detail.text = item.describe_bbcode()
	for slot in item.equip_slots:
		var occupied = GameState.equipped[slot] != null
		_action("Equip → %s%s" % [GameState.SLOT_NAMES[slot], " (swap)" if occupied else ""],
				func(): GameState.equip_from_stash(inst["uid"], slot))
	if item.is_portal():
		_action("Add to Portal Belt", func(): GameState.move_to_belt(inst["uid"]),
				GameState.belt.find(null) < 0)
	_action("Move to Safe Pouch", func(): GameState.move_to_pouch(inst["uid"]),
			GameState.pouch_free_index() < 0)


func _action(text: String, cb: Callable, disabled := false) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(cb)
	_actions.add_child(b)


# --- Dialogs ------------------------------------------------------------------------

func _confirm_enter() -> void:
	var belt_count := GameState.belt.filter(func(x): return x != null).size()
	var msg := "Your equipped gear and Portal Belt are at risk.\nOnly the Safe Pouch is guaranteed to return.\n\n"
	if belt_count == 0:
		msg += "[!] Your Portal Belt is EMPTY — you will have no Dreamshapes to summon.\n\n"
	msg += "Reach one of the two extraction points to wake up with your loot."
	var d := ConfirmationDialog.new()
	d.title = "Enter the Dream?"
	d.dialog_text = msg
	d.ok_button_text = "Enter"
	d.confirmed.connect(func():
		if GameState.begin_raid():
			get_tree().change_scene_to_file(BATTLE_SCENE))
	add_child(d)
	d.popup_centered()


func _confirm_reset() -> void:
	var d := ConfirmationDialog.new()
	d.title = "Reset Save?"
	d.dialog_text = "Erase all progress and start over with the starter kit?"
	d.confirmed.connect(GameState.new_game)
	add_child(d)
	d.popup_centered()


func _show_report(report: Dictionary) -> void:
	var names := func(ids: Array) -> String:
		if ids.is_empty():
			return "  (nothing)"
		return "\n".join(ids.map(func(id): return "  • " + ItemDB.get_item(id).display_name))
	var text := ""
	if report.get("extracted", false):
		text = "You woke up safely.\n\nBrought back:\n%s" % names.call(report["gained"])
	else:
		text = "%s\n\nLost forever:\n%s" % [
			report.get("reason", "You were lost in the dream."), names.call(report["lost"])]
	text += "\n\nSafe Pouch:\n%s" % names.call(report["secured"])
	var d := AcceptDialog.new()
	d.title = "Extracted!" if report.get("extracted", false) else "Lost in the Dream"
	d.dialog_text = text
	add_child(d)
	d.popup_centered()
