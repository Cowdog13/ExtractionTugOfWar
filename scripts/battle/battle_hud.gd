class_name BattleHud
extends CanvasLayer
## In-raid UI: HP, minimap, portal belt, backpack (with "Secure in pouch"),
## extraction progress, messages and the pause menu.

var battle: Node

var _hp_bar: ProgressBar
var _hp_label: Label
var _info: Label
var _belt_buttons: Array[Button] = []
var _backpack_box: VBoxContainer
var _pouch_label: Label
var _message: Label
var _msg_t := 0.0
var _extract_bar: ProgressBar
var _extract_label: Label
var _minimap: Minimap
var _pause: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_status(root)
	_build_minimap(root)
	_build_backpack(root)
	_build_belt(root)
	_build_center(root)
	_build_help(root)
	_build_pause(root)
	GameState.changed.connect(_refresh_inventory)
	_refresh_inventory()


## Pins `c` so its `pivot` point (0..1 of its own size) sits at screen `anchor` + `offset`;
## the control then grows from there to fit its contents.
func _anchor(c: Control, anchor: Vector2, pivot: Vector2, offset: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.grow_horizontal = _grow(pivot.x)
	c.grow_vertical = _grow(pivot.y)
	c.offset_left = offset.x
	c.offset_right = offset.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y


func _grow(pivot: float) -> Control.GrowDirection:
	if pivot <= 0.0:
		return Control.GROW_DIRECTION_END
	if pivot >= 1.0:
		return Control.GROW_DIRECTION_BEGIN
	return Control.GROW_DIRECTION_BOTH


func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.12, 0.85)
	style.border_color = Color("3a3456")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _label(text := "", size := 14, color := Color("e6e0ff")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_status(root: Control) -> void:
	var panel := _panel(root)
	_anchor(panel, Vector2(0, 0), Vector2(0, 0), Vector2(12, 12))
	panel.custom_minimum_size = Vector2(260, 0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_hp_label = _label("", 14)
	box.add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(240, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("6fdc8c")
	_hp_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_hp_bar)
	_info = _label("", 12, Color("a9a2c8"))
	box.add_child(_info)


func _build_minimap(root: Control) -> void:
	var panel := _panel(root)
	_anchor(panel, Vector2(1, 0), Vector2(1, 0), Vector2(-12, 12))
	_minimap = Minimap.new()
	_minimap.battle = battle
	_minimap.custom_minimum_size = Vector2(192, 128)
	panel.add_child(_minimap)


func _build_backpack(root: Control) -> void:
	var panel := _panel(root)
	_anchor(panel, Vector2(1, 0.5), Vector2(1, 0.5), Vector2(-12, 20))
	panel.custom_minimum_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_label("Backpack  (lost on death)", 14, Color("bfb3ff")))
	_backpack_box = VBoxContainer.new()
	box.add_child(_backpack_box)
	box.add_child(HSeparator.new())
	box.add_child(_label("Safe Pouch  (always kept)", 14, Color("8fffb0")))
	_pouch_label = _label("", 12)
	box.add_child(_pouch_label)


func _build_belt(root: Control) -> void:
	var bar := HBoxContainer.new()
	_anchor(bar, Vector2(0.5, 1), Vector2(0.5, 1), Vector2(0, -34))
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	for i in GameState.BELT_SIZE:
		var b := Button.new()
		b.custom_minimum_size = Vector2(158, 52)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): battle.ready_belt_slot(i))
		bar.add_child(b)
		_belt_buttons.append(b)


func _build_center(root: Control) -> void:
	_message = _label("", 18)
	_anchor(_message, Vector2(0.5, 0), Vector2(0.5, 0), Vector2(0, 70))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(800, 0)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.add_theme_constant_override("outline_size", 6)
	root.add_child(_message)

	var box := VBoxContainer.new()
	_anchor(box, Vector2(0.5, 0.5), Vector2(0.5, 0), Vector2(0, 90))
	box.custom_minimum_size = Vector2(300, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	_extract_label = _label("EXTRACTING...", 16, Color("8fffb0"))
	_extract_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_extract_label)
	_extract_bar = ProgressBar.new()
	_extract_bar.show_percentage = false
	_extract_bar.custom_minimum_size.y = 12
	_extract_bar.max_value = battle.EXTRACT_TIME
	box.add_child(_extract_bar)


func _build_help(root: Control) -> void:
	var l := _label("LMB/RMB move  •  1-4 ready portal, then click rally point  •  R rally allies to cursor  •  Wheel zoom  •  Esc menu",
			12, Color("8a84a6"))
	_anchor(l, Vector2(0, 1), Vector2(0, 1), Vector2(12, -8))
	root.add_child(l)


func _build_pause(root: Control) -> void:
	_pause = _panel(root)
	_anchor(_pause, Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2.ZERO)
	_pause.custom_minimum_size = Vector2(320, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_pause.add_child(box)
	box.add_child(_label("The dream holds its breath.", 18))
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_toggle_pause)
	box.add_child(resume)
	var abandon := Button.new()
	abandon.text = "Abandon raid (counts as death)"
	abandon.pressed.connect(func():
		_toggle_pause()
		battle.abandon())
	box.add_child(abandon)
	_pause.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if battle.aiming_uid >= 0 and not get_tree().paused:
			battle.aiming_uid = -1
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	_pause.visible = get_tree().paused


func show_message(text: String, color := Color("e6e0ff")) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_msg_t = 3.0


func _process(delta: float) -> void:
	var p: Dreamseeker = battle.player
	if is_instance_valid(p):
		_hp_bar.max_value = p.max_hp
		_hp_bar.value = p.hp
		_hp_label.text = "Dreamseeker   %d / %d HP" % [ceili(p.hp), int(p.max_hp)]
	var secs := int(battle.elapsed)
	_info.text = "Time %d:%02d   Instability ×%.2f\nAllies %d   Hostiles %d" % [
			secs / 60, secs % 60, battle.danger(), battle.allies_alive(), battle.enemies_alive()]
	_msg_t -= delta
	_message.modulate.a = clampf(_msg_t, 0.0, 1.0)
	var extracting: bool = battle.extract_progress > 0.0
	_extract_bar.get_parent().visible = extracting
	_extract_bar.value = battle.extract_progress
	for i in _belt_buttons.size():
		var inst = GameState.belt[i]
		var b := _belt_buttons[i]
		b.modulate = Color(1.3, 1.1, 1.6) if inst != null and battle.aiming_uid == inst["uid"] else Color.WHITE
	_minimap.queue_redraw()


func _refresh_inventory() -> void:
	for i in _belt_buttons.size():
		var inst = GameState.belt[i]
		var b := _belt_buttons[i]
		if inst == null:
			b.text = "%d: —" % (i + 1)
			b.disabled = true
			b.tooltip_text = ""
		else:
			var item := GameState.item_of(inst)
			b.text = "%d: %s" % [i + 1, item.display_name.trim_prefix("Dreamshape: ")]
			b.add_theme_color_override("font_color", item.rarity_color())
			b.tooltip_text = item.describe_plain()
			b.disabled = false

	for c in _backpack_box.get_children():
		c.queue_free()
	var backpack: Array = GameState.raid.get("backpack", [])
	if backpack.is_empty():
		_backpack_box.add_child(_label("(empty)", 12, Color("6b6585")))
	var pouch_full := GameState.pouch_free_index() < 0
	for inst in backpack:
		var item := GameState.item_of(inst)
		var row := HBoxContainer.new()
		var name := _label(item.display_name, 12, item.rarity_color())
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		name.tooltip_text = item.describe_plain()
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name)
		if item.is_portal():
			row.add_child(_small_button("Open", func(): battle.ready_portal(inst["uid"])))
		var secure := _small_button("Secure", func(): GameState.secure_backpack_item(inst["uid"]))
		secure.disabled = pouch_full
		row.add_child(secure)
		_backpack_box.add_child(row)
	var names: Array = []
	for inst in GameState.pouch:
		names.append("—" if inst == null else GameState.item_of(inst).display_name)
	_pouch_label.text = "\n".join(names)


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


class Minimap extends Control:
	var battle: Node

	func _draw() -> void:
		if battle == null or battle.map_texture == null:
			return
		var map: DreamMap = battle.map
		var s := size / Vector2(map.width * DreamMap.TILE, map.height * DreamMap.TILE)
		draw_texture_rect(battle.map_texture, Rect2(Vector2.ZERO, size), false)
		for p in battle.extraction_points:
			draw_circle(p * s, 5.0, Color("8fffb0"))
		for u in battle.units:
			if u == battle.player:
				continue
			draw_circle(u.position * s, 1.5, Color("9be7ff") if u.team == Unit.Team.PLAYER else Color("ff5d6c"))
		if is_instance_valid(battle.player):
			draw_circle(battle.player.position * s, 3.0, Color.WHITE)
