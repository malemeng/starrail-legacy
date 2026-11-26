extends PanelContainer

const PANEL_WIDTH := 340
const FLIGHT_POSITION := Vector2(30,118)
const HISTORY_LIMIT := 3
const INK := Color("#e1eced")
const DIM := Color("#a0b4bd")
const GOLD := Color("#e9b977")
const TEAL := Color("#80d5ca")

var intent: Label
var target: Label
var action: Label
var result: Label
var progress_text: Label
var progress_bar: ProgressBar
var history: VBoxContainer
var history_rows: Array[Label] = []
var cheat_toggle: CheckButton
var pending := {}
var game
var sidebar_slot: Control
var tracked_body: Control
var placement_pending := false

func _ready() -> void:
	name = "AgentWatch"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://scripts/ui/bridge_theme.tres")
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = FLIGHT_POSITION
	custom_minimum_size.x = PANEL_WIDTH
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#101d2aed")
	panel.border_color = Color("#527587")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(5)
	panel.content_margin_left = 15
	panel.content_margin_right = 15
	panel.content_margin_top = 11
	panel.content_margin_bottom = 12
	add_theme_stylebox_override("panel",panel)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation",4)
	add_child(body)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation",8)
	body.add_child(header)
	var indicator := ColorRect.new()
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.color = TEAL
	indicator.custom_minimum_size = Vector2(3,13)
	indicator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(indicator)
	add_label(header,"Agent 观战",16,TEAL)
	cheat_toggle = CheckButton.new()
	cheat_toggle.text = "允许作弊"
	cheat_toggle.focus_mode = Control.FOCUS_NONE
	cheat_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cheat_toggle.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cheat_toggle.add_theme_font_size_override("font_size", 12)
	cheat_toggle.add_theme_color_override("font_color", GOLD)
	cheat_toggle.toggled.connect(func(on: bool):
		if game != null and game.agent_bridge != null:
			game.agent_bridge.allow_cheats = on)
	header.add_child(cheat_toggle)
	_sync_cheat_toggle()
	intent = add_label(body,"",15,INK)
	intent.clip_text = false
	intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intent.max_lines_visible = 5
	target = detail(body,"目标",GOLD)
	action = detail(body,"动作",INK)
	result = detail(body,"结果",INK)
	result.clip_text = false
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.max_lines_visible = 2
	progress_text = add_label(body,"",15,TEAL)
	progress_bar = ProgressBar.new()
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.show_percentage = false
	progress_bar.max_value = 1.0
	progress_bar.step = 0.001
	progress_bar.custom_minimum_size.y = 4
	for style_name in ["background","fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#2a4050") if style_name=="background" else TEAL
		style.set_corner_radius_all(2)
		progress_bar.add_theme_stylebox_override(style_name,style)
	body.add_child(progress_bar)
	history = VBoxContainer.new()
	history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.add_theme_constant_override("separation",2)
	body.add_child(history)
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.add_child(divider)
	add_label(history,"最近动作",14,DIM)
	for i in HISTORY_LIMIT:
		history_rows.append(add_label(history,"",15,DIM))
	body.minimum_size_changed.connect(schedule_placement)
	get_viewport().size_changed.connect(schedule_placement)
	present(pending)
	pending = {}

func _sync_cheat_toggle() -> void:
	if not is_instance_valid(cheat_toggle):
		return
	var has_bridge: bool = game != null and game.agent_bridge != null
	cheat_toggle.visible = has_bridge
	cheat_toggle.mouse_filter = Control.MOUSE_FILTER_STOP if has_bridge else Control.MOUSE_FILTER_IGNORE
	cheat_toggle.set_pressed_no_signal(has_bridge and bool(game.agent_bridge.allow_cheats))

func bind_game(session) -> void:
	game = session
	_sync_cheat_toggle()
	schedule_placement()

func schedule_placement() -> void:
	if not placement_pending:
		placement_pending = true
		update_placement.call_deferred()

func update_placement() -> void:
	placement_pending = false
	if not is_inside_tree():
		return
	var details_open := false
	if is_instance_valid(game) and game.playing and is_instance_valid(game.body):
		if not is_instance_valid(tracked_body) or tracked_body!=game.body:
			tracked_body = game.body
			tracked_body.child_order_changed.connect(schedule_placement)
			game.canvas.item_rect_changed.connect(schedule_placement)
		details_open = game.tab=="港口" and game.world.ride().get("dock",0)>0 and game.dock_view.mode in ["yard","refit"]
	if details_open:
		var column: Control = game.tabs.get_parent()
		if not is_instance_valid(sidebar_slot) or sidebar_slot.get_parent()!=column:
			sidebar_slot = Control.new()
			sidebar_slot.name = "AgentWatchSlot"
			sidebar_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(sidebar_slot)
			column.move_child(sidebar_slot,game.tabs.get_index()+1)
			sidebar_slot.item_rect_changed.connect(schedule_placement)
		var visible_width := get_viewport_rect().end.x - sidebar_slot.global_position.x - 4.0
		custom_minimum_size.x = maxf(PANEL_WIDTH,minf(sidebar_slot.size.x,visible_width))
		reset_size()
		sidebar_slot.custom_minimum_size.y = size.y
		global_position = sidebar_slot.global_position
	else:
		if is_instance_valid(sidebar_slot):
			sidebar_slot.queue_free()
			sidebar_slot = null
		custom_minimum_size.x = PANEL_WIDTH
		if is_instance_valid(game) and game.playing and is_instance_valid(game.canvas):
			global_position = game.canvas.global_position + Vector2(12, 8)
		else:
			position = FLIGHT_POSITION
		reset_size()

func add_label(parent: Control, caption: String, point: int, tone: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size",point)
	label.add_theme_color_override("font_color",tone)
	label.text = caption
	parent.add_child(label)
	return label

func detail(body: Control, caption: String, tone: Color) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",6)
	body.add_child(row)
	var key := add_label(row,caption,15,DIM)
	key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	key.custom_minimum_size.x = 36
	return add_label(row,"",16,tone)

func single_line(value: Variant) -> String:
	return str(value).replace("\r"," ").replace("\n"," ").strip_edges()

## History is oldest first. The caller supplies confirmed actions and progress.
func present(state: Dictionary) -> void:
	if intent==null:
		pending = state.duplicate(true)
		return
	var intention := single_line(state.get("intent",""))
	for pair in [[target,"target"],[action,"action"],[result,"result"]]:
		var field: Label = pair[0]
		field.text = single_line(state.get(pair[1],""))
		field.get_parent().visible = not field.text.is_empty()
	progress_text.text = single_line(state.get("progress_text",""))
	progress_text.visible = not progress_text.text.is_empty()
	var fraction := float(state.get("progress",-1.0))
	progress_bar.visible = is_finite(fraction) and fraction>=0.0
	if progress_bar.visible:
		progress_bar.value = clampf(fraction,0.0,1.0)
	var entries: Array = state.get("history",[])
	intent.text = intention
	if intention.is_empty():
		action.get_parent().hide()
		if not action.text.is_empty():
			intent.text = action.text
		elif not target.text.is_empty():
			intent.text = target.text
			target.get_parent().hide()
		elif not result.text.is_empty():
			intent.text = result.text
			result.get_parent().hide()
		elif progress_text.visible or progress_bar.visible:
			intent.text = "行动进度"
		elif not entries.is_empty():
			intent.text = "行动记录"
		else:
			intent.text = "等待 Agent 下达指令"
	var shown := 0
	for index in range(entries.size()-1,-1,-1):
		var item: Dictionary = entries[index]
		var step := single_line(item.get("action",""))
		var outcome := single_line(item.get("result",""))
		if step.is_empty() or (shown==0 and step==action.text and outcome==result.text):
			continue
		var summary := step if outcome.is_empty() else "%s · %s" % [step,outcome]
		if shown>0 and history_rows[shown-1].text==summary:
			continue
		history_rows[shown].text = summary
		shown += 1
		if shown==HISTORY_LIMIT:
			break
	for i in HISTORY_LIMIT:
		history_rows[i].visible = i<shown
	history.visible = shown>0
	schedule_placement()
