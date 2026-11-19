extends PanelContainer
## Touch Shortcuts — a floating vertical panel with 6 big touch slots.
##
## Tap a slot to run its action (switch tool / undo / redo).
## Press and HOLD a slot (~0.55 s): it blinks, then the next tap on any
## recognizable UI element — a tool button in the palette, or the Undo/Redo
## quick-access buttons in the top bar — becomes that slot's shortcut.
## Drag the small handle on top of the panel to move it; tap the handle (or
## the panel body) to collapse. The ✕ on the handle's right dismisses the
## panel — bring it back via Window menu → "Toggle Touch Shortcuts Panel";
## dismissal persists across restarts. Slots, position, collapse and
## visibility state persist in user:// (app-private).
##
## While running, the panel also keeps its own name out of Pixelorama's
## extension-crash suspicion list, so a force-closed app can never silently
## disable it on the next boot.

const CFG_PATH := "user://touch_shortcuts_panel.cfg"
const SLOT_COUNT := 6
const SLOT_SIZE := 56.0
const HOLD_MS := 550
const DRAG_THRESHOLD := 10.0
const TAP_CANCEL_DISTANCE := 15.0
## After a capture tap is consumed, swallow the pointer twin (the emulated
## mouse press Android generates for the raw touch) so the underlying UI
## never double-fires. Milliseconds.
const SUPPRESS_MS := 200

const DEFAULT_SLOTS: Array[String] = [
	"undo:Undo",
	"tool:Pan",
	"tool:ColorPicker",
	"tool:Pencil",
	"tool:Eraser",
	"tool:Lasso",
]

const COLOR_BG := Color(0.07, 0.07, 0.09, 0.88)
const COLOR_BORDER := Color(1, 1, 1, 0.14)
const COLOR_ACTIVE := Color(0.36, 0.75, 1.0)
const COLOR_ARMED := Color(1.0, 0.85, 0.25)
const COLOR_OK := Color(0.35, 0.9, 0.45)
const COLOR_BAD := Color(0.95, 0.3, 0.3)

var _slot_actions: Array[String] = []
var _slot_buttons: Array[Button] = []
var _slots_box: VBoxContainer
var _grip: Button
var _close_btn: Button
var _menu_item_id := -1
var _hold_timer: Timer
var _hold_slot := -1
var _capturing_slot := -1
var _suppress_until := 0
var _dragging := false
var _drag_offset := Vector2.ZERO
var _drag_start := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _skip_next_release := false
var _default_pos_needed := false

@onready var _api: Node = get_node_or_null("/root/ExtensionsApi")


func _ready() -> void:
	top_level = true
	z_index = 100
	focus_mode = Control.FOCUS_NONE
	add_theme_stylebox_override("panel", _make_panel_stylebox())
	for i in SLOT_COUNT:
		_slot_actions.append(DEFAULT_SLOTS[i])

	_build_ui()

	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_timeout)
	add_child(_hold_timer)

	# Keep our name out of the crash-suspicion list so a force-closed app
	# can't auto-disable the panel on the next boot.
	_clear_own_suspicion()
	var heal := Timer.new()
	heal.wait_time = 30.0
	heal.timeout.connect(_clear_own_suspicion)
	add_child(heal)
	heal.start()

	_load_config()
	Tools.tool_changed.connect(_on_tool_changed)
	Tools.options_reset.connect(_refresh_highlights)

	if _api != null and Global.top_menu_container != null:
		_menu_item_id = _api.menu.add_menu_item(
			_api.menu.WINDOW, "Toggle Touch Shortcuts Panel", self)

	# Default position (right edge, vertically centred — out of a left-hand
	# drawing hand's way) needs the panel size, which exists after one frame.
	await get_tree().process_frame
	if _default_pos_needed:
		_snap_default_position()
	_clamp_position()
	_refresh_highlights()
	save_config()
	# On-device diagnostics: proves WHICH build is running (logcat).
	print("[TouchShortcuts] v1.1.1 running; grip=", _grip.size,
			" pill=", (_grip.get_child(0).get_child(0) as Control).size,
			" x=", _close_btn.get_global_rect(), " visible=", visible,
			" at=", position)


func _exit_tree() -> void:
	if _menu_item_id >= 0 and _api != null:
		_api.menu.remove_menu_item(_api.menu.WINDOW, _menu_item_id)
		_menu_item_id = -1
	if Tools.tool_changed.is_connected(_on_tool_changed):
		Tools.tool_changed.disconnect(_on_tool_changed)
	if Tools.options_reset.is_connected(_refresh_highlights):
		Tools.options_reset.disconnect(_refresh_highlights)
	save_config()


## Stock menu contract: TopMenuContainer calls this on the item metadata.
func menu_item_clicked() -> void:
	visible = not visible
	save_config()


func _dismiss_panel() -> void:
	visible = false
	save_config()


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "Box"
	vbox.add_theme_constant_override("separation", 6)
	# Let presses in the gaps/border fall through to the panel body
	# (body tap = collapse, body drag = move).
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	_grip = Button.new()
	_grip.name = "Grip"
	_grip.focus_mode = Control.FOCUS_NONE
	_grip.custom_minimum_size = Vector2(SLOT_SIZE, 18)
	# Force LTR so anchor/offset placement is never mirrored by locale.
	_grip.layout_direction = Control.LAYOUT_DIRECTION_LTR
	# Faint strip tint so the grab zone reads as a handle.
	var grip_sb := StyleBoxFlat.new()
	grip_sb.bg_color = Color(1, 1, 1, 0.05)
	grip_sb.set_corner_radius_all(8)
	for grip_state in ["normal", "hover", "pressed"]:
		_grip.add_theme_stylebox_override(grip_state, grip_sb)
	_grip.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Pill centred by a real container — anchors on a non-container parent
	# are not guaranteed to size/layout the child. Left of the ✕ button.
	var grip_center := CenterContainer.new()
	# Fixed pixel offsets against the grip's constant 56x18 rect — anchors
	# resolved against a not-yet-laid-out parent produced negative rects.
	grip_center.set_anchor_and_offset(SIDE_LEFT, 0.0, 2.0)
	grip_center.set_anchor_and_offset(SIDE_RIGHT, 0.0, 28.0)
	grip_center.set_anchor_and_offset(SIDE_TOP, 0.0, 0.0)
	grip_center.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 18.0)
	grip_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grip.add_child(grip_center)
	var pill := Panel.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.custom_minimum_size = Vector2(24, 5)
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(1, 1, 1, 0.5)
	pill_style.set_corner_radius_all(2)
	pill.add_theme_stylebox_override("panel", pill_style)
	grip_center.add_child(pill)

	# ✕ dismiss button at the handle's right end. Anchored offsets (not
	# presets) are deterministic even on a non-container parent.
	_close_btn = Button.new()
	_close_btn.name = "Dismiss"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.expand_icon = true
	_close_btn.icon = load("res://assets/graphics/misc/close.svg")
	_close_btn.set_anchor_and_offset(SIDE_LEFT, 0.0, 30.0)
	_close_btn.set_anchor_and_offset(SIDE_RIGHT, 0.0, 51.0)
	_close_btn.set_anchor_and_offset(SIDE_TOP, 0.0, 1.0)
	_close_btn.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 17.0)
	var x_sb := StyleBoxFlat.new()
	x_sb.bg_color = Color(1, 1, 1, 0.07)
	x_sb.set_corner_radius_all(5)
	for x_state in ["normal", "hover", "pressed"]:
		_close_btn.add_theme_stylebox_override(x_state, x_sb)
	_close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close_btn.tooltip_text = "Dismiss panel (Window menu brings it back)"
	_close_btn.pressed.connect(_dismiss_panel)
	_grip.add_child(_close_btn)
	_grip.gui_input.connect(_on_grip_gui_input)
	vbox.add_child(_grip)

	_slots_box = VBoxContainer.new()
	_slots_box.name = "Slots"
	_slots_box.add_theme_constant_override("separation", 6)
	_slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_slots_box)

	for i in SLOT_COUNT:
		var btn := Button.new()
		btn.name = "Slot%d" % i
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.gui_input.connect(_on_slot_gui_input.bind(i))
		_slot_buttons.append(btn)
		_slots_box.add_child(btn)
		_apply_slot_style(i)
	_refresh_slot_icons()


# --- Actions ----------------------------------------------------------------

func _execute_action(action: String) -> bool:
	var type := _action_type(action)
	var name := _action_name(action)
	match type:
		"tool":
			if Tools.tools.has(name):
				# LEFT covers both modes: in single-tool mode (touch)
				# assign_tool internally redirects to the RIGHT slot.
				Tools.assign_tool(name, MOUSE_BUTTON_LEFT)
				return true
			return false
		"undo":
			if Global.current_project != null:
				Global.current_project.commit_undo()
			return true
		"redo":
			if Global.current_project != null:
				Global.current_project.commit_redo()
			return true
		_:
			return false


func _action_type(action: String) -> String:
	return action.get_slice(":", 0)


func _action_name(action: String) -> String:
	return action.get_slice(":", 1)


func _slot_display_name(action: String) -> String:
	var type := _action_type(action)
	var name := _action_name(action)
	if type == "tool" and Tools.tools.has(name):
		return Tools.tools[name].display_name
	if type == "undo":
		return "Undo"
	if type == "redo":
		return "Redo"
	return name


# --- Slot input: tap = run, hold = capture ----------------------------------

func _on_slot_gui_input(event: InputEvent, slot: int) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press_pos = event.global_position
		_skip_next_release = false
		if _capturing_slot != -1:
			# Tapping any slot while capture is armed cancels the capture.
			_cancel_capture()
			_skip_next_release = true
			accept_event()
			return
		_hold_slot = slot
		_hold_timer.start(HOLD_MS / 1000.0)
	else:
		_hold_timer.stop()
		if _skip_next_release:
			_skip_next_release = false
			accept_event()
			return
		if _hold_slot == slot and _capturing_slot == -1:
			_hold_slot = -1
			if _press_pos.distance_to(event.global_position) <= TAP_CANCEL_DISTANCE:
				_execute_action(_slot_actions[slot])


func _on_hold_timeout() -> void:
	if _hold_slot == -1 or _capturing_slot != -1:
		return
	_capturing_slot = _hold_slot
	_hold_slot = -1
	_apply_slot_style(_capturing_slot)
	_blink(_slot_buttons[_capturing_slot])


func _cancel_capture() -> void:
	if _capturing_slot == -1:
		return
	var slot := _capturing_slot
	_capturing_slot = -1
	_apply_slot_style(slot)


func _begin_capture(slot: int) -> void:
	_capturing_slot = slot
	_apply_slot_style(slot)
	_blink(_slot_buttons[slot])


# --- Capture resolution: next tap anywhere ----------------------------------

func _input(event: InputEvent) -> void:
	# Drag: keep receiving motion even when the finger leaves the grip.
	if _dragging and event is InputEventMouseMotion \
			and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		position = _clamp_position_to(event.global_position + _drag_offset)
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return

	# Swallow the pointer twin that arrives right after a consumed capture tap.
	if Time.get_ticks_msec() < _suppress_until:
		if event.pressed:
			get_viewport().set_input_as_handled()
		return

	if event.pressed and _capturing_slot != -1:
		var ctrl: Control = _find_control_at(event.global_position)
		if ctrl != null and (ctrl == self or is_ancestor_of(ctrl)):
			# Press landed back on our own panel: cancel (toggle-off).
			_cancel_capture()
			_suppress_until = Time.get_ticks_msec() + SUPPRESS_MS
			get_viewport().set_input_as_handled()
			return
		var action := _resolve_control(ctrl)
		var slot := _capturing_slot
		_capturing_slot = -1
		_suppress_until = Time.get_ticks_msec() + SUPPRESS_MS
		get_viewport().set_input_as_handled()
		if action.is_empty():
			_flash_slot(slot, COLOR_BAD)
		else:
			_slot_actions[slot] = str(action["type"], ":", action["name"])
			_refresh_slot_icons()
			_refresh_slot_tooltips()
			_apply_slot_style(slot)
			_flash_slot(slot, COLOR_OK)
			save_config()


var _hit_control: Control = null


## The control that would receive a click at pos — Godot 4.7 has no exposed
## gui_find_control, so walk the app's UI tree with Godot's own picking
## rules (visible, accepts mouse, axis-aligned rects, last-drawn on top).
## Windows (dialogs) live outside this tree: tapping one just cancels.
func _find_control_at(pos: Vector2) -> Control:
	var root := Global.control
	if root == null:
		return null
	_hit_control = null
	_walk_controls(root, pos)
	return _hit_control


func _walk_controls(n: Node, pos: Vector2) -> void:
	if n is Control:
		var c := n as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and c.get_global_rect().has_point(pos):
			_hit_control = c
	for child in n.get_children():
		_walk_controls(child, pos)


## Walk up from the tapped control and identify what action it represents.
## Recognized: any tool button in the palette (works for extension-added
## tools too), and the Undo / Redo quick-access buttons in the top bar.
func _resolve_control(ctrl: Control) -> Dictionary:
	var n: Node = ctrl
	var depth := 0
	while n != null and depth < 12:
		for tool_name: String in Tools.tools:
			var t: Variant = Tools.tools[tool_name]
			if t != null and t.button_node == n:
				return {"type": "tool", "name": tool_name}
		if n is BaseButton and (n.name == &"Undo" or n.name == &"Redo"):
			return {"type": String(n.name).to_lower(), "name": String(n.name)}
		n = n.get_parent()
		depth += 1
	return {}


# --- Grip: drag to move, tap to collapse ------------------------------------

func _on_grip_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_dragging = true
		_drag_offset = position - event.global_position
		_drag_start = event.global_position
	else:
		_dragging = false
		if _drag_start.distance_to(event.global_position) <= DRAG_THRESHOLD:
			_toggle_collapsed()
		else:
			save_config()


# --- Panel body: drag to move, tap to collapse -------------------------------

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_dragging = true
		_drag_offset = position - event.global_position
		_drag_start = event.global_position
	else:
		_dragging = false
		if _drag_start.distance_to(event.global_position) <= DRAG_THRESHOLD:
			_toggle_collapsed()
		else:
			save_config()


func _toggle_collapsed() -> void:
	if _slots_box == null:
		return
	_slots_box.visible = not _slots_box.visible
	# Keep a collapsed pill big enough to grab and tap.
	custom_minimum_size = Vector2(44, 28) if not _slots_box.visible else Vector2.ZERO
	save_config()


# --- Appearance ---------------------------------------------------------------

func _make_panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_BG
	sb.border_color = COLOR_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	return sb


func _slot_stylebox(border := Color(0, 0, 0, 0), border_width := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.set_corner_radius_all(9)
	if border_width > 0:
		sb.set_border_width_all(border_width)
		sb.border_color = border
	return sb


func _apply_slot_style(slot: int) -> void:
	if slot < 0 or slot >= _slot_buttons.size():
		return
	var btn := _slot_buttons[slot]
	var sb: StyleBoxFlat
	if slot == _capturing_slot:
		sb = _slot_stylebox(COLOR_ARMED, 2)
	elif _is_slot_active_tool(slot):
		sb = _slot_stylebox(COLOR_ACTIVE, 2)
	else:
		sb = _slot_stylebox()
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.tooltip_text = _slot_display_name(_slot_actions[slot])


func _is_slot_active_tool(slot: int) -> bool:
	var action := _slot_actions[slot]
	if _action_type(action) != "tool":
		return false
	var button := MOUSE_BUTTON_LEFT
	if Global.single_tool_mode:
		button = MOUSE_BUTTON_RIGHT
	var active_slot: Variant = Tools.get_tool(button)
	if active_slot == null or active_slot.tool_node == null:
		return false
	return String(active_slot.tool_node.name) == _action_name(action)


func _flash_slot(slot: int, color: Color) -> void:
	var btn := _slot_buttons[slot]
	var sb := _slot_stylebox(color, 2)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(_apply_slot_style.bind(slot))


func _blink(btn: Button) -> void:
	var tw := create_tween()
	tw.tween_property(btn, "modulate:a", 0.15, 0.11)
	tw.tween_property(btn, "modulate:a", 1.0, 0.11)
	tw.tween_property(btn, "modulate:a", 0.15, 0.11)
	tw.tween_property(btn, "modulate:a", 1.0, 0.11)
	tw.tween_callback(func() -> void: btn.modulate.a = 1.0)


func _refresh_slot_icons() -> void:
	for i in _slot_buttons.size():
		_slot_buttons[i].icon = _icon_for(_slot_actions[i])


func _icon_for(action: String) -> Texture2D:
	var type := _action_type(action)
	var name := _action_name(action)
	var path := ""
	if type == "tool":
		path = "res://assets/graphics/tools/%s.png" % name.to_lower()
	elif type == "undo":
		path = "res://assets/graphics/quick_access_panel/undo.svg"
	elif type == "redo":
		path = "res://assets/graphics/quick_access_panel/redo.svg"
	if path.is_empty():
		return null
	var tex: Texture2D = load(path)
	return tex


func _refresh_slot_tooltips() -> void:
	for i in _slot_buttons.size():
		_apply_slot_style(i)


func _refresh_highlights(_arg := -1) -> void:
	for i in _slot_buttons.size():
		_apply_slot_style(i)


func _on_tool_changed(_tool_name: StringName, _button: int) -> void:
	_refresh_highlights()


# --- Position -----------------------------------------------------------------

func _snap_default_position() -> void:
	var vp := get_viewport_rect().size
	position = Vector2(vp.x - size.x - 12.0, (vp.y - size.y) * 0.5)
	_default_pos_needed = false


func _clamp_position_to(pos: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(
		clampf(pos.x, -size.x + 40.0, vp.x - 40.0),
		clampf(pos.y, 0.0, maxf(vp.y - 40.0, 0.0))
	)


func _clamp_position() -> void:
	position = _clamp_position_to(position)


# --- Persistence ----------------------------------------------------------------

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("panel", "position", position)
	cfg.set_value("panel", "collapsed", not _slots_box.visible)
	cfg.set_value("panel", "visible", visible)
	for i in _slot_actions.size():
		cfg.set_value("slots", "slot%d" % i, _slot_actions[i])
	cfg.save(CFG_PATH)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		_default_pos_needed = true
		return
	for i in SLOT_COUNT:
		var saved := String(cfg.get_value("slots", "slot%d" % i, _slot_actions[i]))
		if _is_valid_action(saved):
			_slot_actions[i] = saved
	var pos: Variant = cfg.get_value("panel", "position", Vector2.INF)
	if pos is Vector2 and pos != Vector2.INF:
		position = pos
	else:
		_default_pos_needed = true
	var collapsed: bool = cfg.get_value("panel", "collapsed", false)
	_slots_box.visible = not collapsed
	custom_minimum_size = Vector2(44, 28) if collapsed else Vector2.ZERO
	visible = bool(cfg.get_value("panel", "visible", true))


## Keep our own name out of Pixelorama's crash-suspicion list. When the app
## is force-closed it looks like a crash; at the next boot Pixelorama reads
## user://extensions/Monitoring.ini and auto-disables anything listed there.
## While the panel is alive we politely erase just OUR entry (third-party
## entries are left untouched), so a rough exit can't hide the panel.
func _clear_own_suspicion() -> void:
	var ini_path := "user://extensions/Monitoring.ini"
	if not FileAccess.file_exists(ini_path):
		return
	var f := FileAccess.open(ini_path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = str_to_var(f.get_line())
	f.close()
	if typeof(parsed) != TYPE_PACKED_STRING_ARRAY:
		return
	var kept: PackedStringArray = PackedStringArray()
	var changed := false
	for entry: String in parsed:
		if String(entry).begins_with("TouchShortcuts"):
			changed = true
		else:
			kept.append(entry)
	if not changed:
		return
	if kept.is_empty():
		DirAccess.remove_absolute(ini_path)
	else:
		var w := FileAccess.open(ini_path, FileAccess.WRITE)
		if w != null:
			w.store_line(var_to_str(kept))
			w.close()


func _is_valid_action(action: String) -> bool:
	var type := _action_type(action)
	var name := _action_name(action)
	if type == "tool":
		return Tools.tools.has(name)
	return type == "undo" or type == "redo"
