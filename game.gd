extends Control

const World = preload("res://world.gd")
const Portrait = preload("res://portrait.gd")
const Flight = preload("res://flight.gd")
const Sector = preload("res://sector_view.gd")
const UI = preload("res://panels.gd")
const Dock = preload("res://dock_view.gd")
const Story = preload("res://frontier.gd")
const Art = preload("res://presentation.gd")
const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
const Celestial = preload("res://celestial.gd")
const AgentBridge = preload("res://agent_bridge.gd")
const AudioSys = preload("res://audio.gd")
const SAVE := "user://frontier.save"
const BEFORE := "user://succession.save"
const AUTO := "user://arrival.save"
const INK := Color("acd6e5")
const GOLD := Color("e9b977")
const DIM := Color("849daf")

var world := World.new()
var flight := Flight.new()
var hud := UI.new()
var dock_view := Dock.new()
var canvas: Control
var layout: VBoxContainer
var body: VBoxContainer
var header: Label
var footer: Label
var status: Label
var tabs: HBoxContainer
var galaxy := false
var speed := 0
var waypoint := Vector2.ZERO
var waypoint_live := false
var tactics: HBoxContainer
var tactics_button: Button
var selected_target := 0
var fire_requested := false
var playing := false
var tab := "港口"
var last_player := 0
var last_day := -1
var creator := {}
var portrait: Control
var notice_text := ""
var quick_actions: HBoxContainer
var test_profile := false
var agent_bridge: RefCounted
var location_banner: Label
var jump_button: Button
var audio: Node
var audio_button: Button
var last_audio_serial := 0

func skin(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _ready() -> void:
	for binding in [[&"left", KEY_A], [&"right", KEY_D], [&"up", KEY_W], [&"down", KEY_S]]:
		if not InputMap.has_action(binding[0]):
			InputMap.add_action(binding[0])
			var key := InputEventKey.new()
			key.physical_keycode = binding[1]
			InputMap.action_add_event(binding[0], key)
	var interface := Theme.new()
	var font := SystemFont.new()
	font.font_names = ["Microsoft YaHei UI", "Microsoft YaHei", "DengXian", "SimHei"]
	interface.default_font = font
	interface.default_font_size = 15
	for type in ["Button", "OptionButton", "LineEdit", "CheckButton"]:
		interface.set_stylebox("normal", type, skin(Color("14273a"), Color("385469")))
		interface.set_stylebox("hover", type, skin(Color("213c50"), Color("6cbdcb")))
		interface.set_stylebox("pressed", type, skin(Color("2d4e61"), Color("9cd7de")))
		interface.set_stylebox("disabled", type, skin(Color("14202c"), Color("293a49")))
		interface.set_color("font_color", type, INK)
		interface.set_color("font_hover_color", type, Color("e3f6fa"))
	interface.set_stylebox("panel", "PanelContainer", skin(Color("0f1c2b"), Color("30485d")))
	interface.set_constant("separation", "VBoxContainer", 7)
	interface.set_constant("separation", "HBoxContainer", 7)
	theme = interface
	flight.game = self
	hud.game = self
	dock_view.game = self
	audio = AudioSys.new()
	add_child(audio)
	show_creator()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--agent-dir="):
			var bridge := AgentBridge.new()
			bridge.game = self
			if not bridge.start(argument.trim_prefix("--agent-dir=")):
				printerr("Agent bridge requires an existing, empty, absolute session directory.")
				get_tree().quit(2)
				return
			agent_bridge = bridge
			test_profile = true
			show_creator()
			say("代理会话 · 本地命令驱动，不使用普通存档。")
			break

func vbox(parent: Node = null) -> VBoxContainer:
	var result := VBoxContainer.new()
	if parent != null:
		parent.add_child(result)
	return result

func hbox(parent: Node) -> HBoxContainer:
	var result := HBoxContainer.new()
	parent.add_child(result)
	return result

func title(parent: Node, caption: String, point: int = 15, tone: Color = INK, wrap: bool = false) -> Label:
	var result := Label.new()
	result.text = caption
	result.add_theme_font_size_override("font_size", point)
	result.add_theme_color_override("font_color", tone)
	if wrap:
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result.custom_minimum_size.x = 150
	parent.add_child(result)
	return result

func button(parent: Node, caption: String, action: Callable, enabled: bool = true, expanded: bool = false) -> Button:
	var result := Button.new()
	result.text = caption
	result.disabled = not enabled
	result.focus_mode = Control.FOCUS_NONE
	result.custom_minimum_size.y = 32
	if expanded:
		result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(func():
		if audio != null:
			audio.play("click")
		action.call())
	parent.add_child(result)
	return result

func choice(parent: Node, items: Array, selected: int = 0) -> OptionButton:
	var result := OptionButton.new()
	for item in items:
		result.add_item(str(item))
	result.select(selected)
	parent.add_child(result)
	return result

func field(parent: Node, start: String, limit: int = 20) -> LineEdit:
	var result := LineEdit.new()
	result.text = start
	result.max_length = limit
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

func frame(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	return panel

func scroller(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var rows := vbox(scroll)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rows

func clear(parent: Node) -> void:
	for child in parent.get_children():
		if child == audio:
			continue
		parent.remove_child(child)
		child.queue_free()

func reset_layout() -> void:
	clear(self)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	layout = vbox(margin)

func show_creator() -> void:
	playing = false
	reset_layout()
	var random := RandomNumberGenerator.new()
	random.randomize()
	creator = {"look": Portrait.random_look(random), "inputs": [], "overrides": []}
	title(layout, "边 疆 航 务 局     /     D E E P   F R O N T I E R", 15, GOLD)
	title(layout, "星 轨 遗 产", 52)
	title(layout, "断航两百年后，没有人等你拯救银河。晨曦自由港只问：你的名字，以及你的泊位账单。", 17, DIM)
	var columns := hbox(layout)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dossier := frame(columns)
	dossier.custom_minimum_size.x = 307
	var draft := vbox(dossier)
	title(draft, "01   海 关 登 记", 19, GOLD)
	portrait = Portrait.new()
	portrait.custom_minimum_size = Vector2(240, 270)
	portrait.look = creator.look.duplicate()
	draft.add_child(portrait)
	creator.name = field(draft, "林遥", 16)
	creator.house = field(draft, "远岚", 16)
	creator.house.placeholder_text = "贵族家族名"
	creator.house.editable = false
	creator.noble = choice(draft, ["平民  /  无血亲继承", "贵族  /  开启家谱与联姻"])
	creator.noble.item_selected.connect(func(index): creator.house.editable = index == 1)
	var years := hbox(draft)
	title(years, "起始年龄")
	var age_input := SpinBox.new()
	age_input.min_value = 18
	age_input.max_value = 65
	age_input.value = 26
	years.add_child(age_input)
	creator.age = age_input
	creator.origin = choice(draft, World.ORIGINS)
	creator.trait = choice(draft, World.TRAITS)
	button(draft, "随机外貌", func():
		creator.look = Portrait.random_look(random)
		for entry in creator.inputs:
			entry.node.select(creator.look[entry.key])
		portrait.look = creator.look.duplicate())
	var face_panel := frame(columns)
	face_panel.custom_minimum_size.x = 289
	var face := vbox(face_panel)
	title(face, "02   外 貌 档 案", 19, GOLD)
	title(face, "外貌由分层画像绘制；子女可能继承双亲特征。非遗传项目：服饰、义体、疤痕。", 14, DIM, true)
	var labels := ["脸型", "肤色", "发型", "发色", "眼形", "眼色", "鼻型", "唇形", "衣装", "特征"]
	var index := 0
	for key in Portrait.OPTIONS:
		var row := hbox(face)
		title(row, labels[index]).custom_minimum_size.x = 50
		var input := choice(row, Portrait.OPTIONS[key], creator.look[key])
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		creator.inputs.append({"node": input, "key": key})
		input.item_selected.connect(func(selection):
			creator.look[key] = selection
			portrait.look = creator.look.duplicate())
		index += 1
	var sector_panel := frame(columns)
	sector_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sector := vbox(sector_panel)
	title(sector, "03   航 区 参 数", 19, GOLD)
	var seed_row := hbox(sector)
	title(seed_row, "种子")
	creator.seed = field(seed_row, str(random.randi()), 40)
	button(seed_row, "随机", func(): creator.seed.text = str(random.randi()))
	var size_row := hbox(sector)
	for config in [["systems", "星系", 12, 48, 24], ["factions", "势力", 3, 8, 5]]:
		title(size_row, config[1])
		var input := SpinBox.new()
		input.min_value = config[2]
		input.max_value = config[3]
		input.value = config[4]
		size_row.add_child(input)
		creator[config[0]] = input
	title(sector, "核心势力预设  /  地盘和外交仍由种子生成；可自订", 14, DIM)
	var presets := scroller(sector)
	for number in range(8):
		var row := hbox(presets)
		title(row, "%02d" % (number + 1), 13, DIM)
		var name_field := field(row, "", 16)
		name_field.placeholder_text = World.CANON[number][0]
		var government := choice(row, ["默认：" + World.REGIMES[World.CANON[number][1]]] + World.REGIMES)
		var style := choice(row, ["默认：" + World.STYLES[World.CANON[number][2]]] + World.STYLES)
		var dye := choice(row, ["默认色", "赭橙", "冰青", "晶紫", "军绿", "金黄", "玫红", "海蓝", "岩灰"])
		creator.overrides.append({"row": row, "name": name_field, "style": style, "regime": government, "color": dye})
	creator.factions.value_changed.connect(func(value):
		for slot in range(creator.overrides.size()):
			creator.overrides[slot].row.visible = slot < int(value))
	for slot in range(5, 8):
		creator.overrides[slot].row.hide()
	var lower := hbox(layout)
	button(lower, "启航  /  创建宇宙", start_game)
	button(lower, "继续上次存档", func(): load_game(SAVE), agent_bridge == null and FileAccess.file_exists(SAVE))
	button(lower, "读取自动存档", func(): load_game(AUTO), agent_bridge == null and FileAccess.file_exists(AUTO))
	button(lower, "读取接班前", func(): load_game(BEFORE), agent_bridge == null and FileAccess.file_exists(BEFORE))
	button(lower, "引擎许可与鸣谢", show_licenses)
	title(lower, "断航后的边疆", 14, DIM)
	footer = title(layout, "", 15, GOLD)

func show_licenses() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Godot Engine / 开源许可"
	var credits := RichTextLabel.new()
	credits.custom_minimum_size = Vector2(650, 380)
	credits.text = "Godot Engine\nhttps://godotengine.org/license/\n\n" + Engine.get_license_text()
	for license_name in Engine.get_license_info():
		credits.text += "\n\n" + license_name + "\n" + Engine.get_license_info()[license_name]
	dialog.add_child(credits)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func start_game() -> void:
	var options := {"seed": creator.seed.text.strip_edges(), "systems": int(creator.systems.value), "factions": int(creator.factions.value),
		"avatar": {"name": creator.name.text.strip_edges(), "house": creator.house.text.strip_edges(),
			"age": int(creator.age.value), "origin": creator.origin.selected, "trait": creator.trait.selected,
			"look": creator.look, "noble": creator.noble.selected == 1}, "overrides": []}
	if options.seed.is_empty() or options.avatar.name.is_empty() or (options.avatar.noble and options.avatar.house.is_empty()):
		say("请填写种子、角色名和贵族的家族名。")
		return
	for item in creator.overrides:
		options.overrides.append({"name": item.name.text, "style": item.style.selected - 1, "regime": item.regime.selected - 1, "color": item.color.selected - 1})
	if not world.new_game(options):
		say("地图需要至少为每个势力预留 3 个星系。")
		return
	run_bridge()
	if not test_profile:
		save_game(AUTO, true)

func run_bridge() -> void:
	playing = true
	last_player = world.player
	speed = 0
	galaxy = world.ride().get("layer", false)
	notice_text = ""
	flight.reset(true)
	world.before_death = Callable() if agent_bridge != null else func(): save_game(BEFORE, true)
	reset_layout()
	dock_view.reset()
	last_audio_serial = world.combat_serial
	selected_target = 0
	fire_requested = false
	var top := hbox(layout)
	title(top, "星轨遗产", 29, GOLD)
	header = title(top, "", 16, INK)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_button = button(top, "静音" if audio != null and audio.muted else "音效", toggle_mute)
	button(top, "保存", func(): save_game(SAVE), agent_bridge == null)
	button(top, "读档", func(): load_game(SAVE), agent_bridge == null)
	button(top, "标题", confirm_title)
	var interior := hbox(layout)
	interior.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var flight_panel := vbox(interior)
	flight_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var toolbar := hbox(flight_panel)
	button(toolbar, "暂停 / 继续", toggle_pause)
	for level in range(1, 6):
		button(toolbar, "档 %d" % level, func(): set_speed(level))
	jump_button = button(toolbar, "引力点跃迁  M", flight.change_layer)
	status = title(toolbar, "", 13, GOLD)
	canvas = Sector.new()
	canvas.game = self
	canvas.clip_contents = true
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(610, 420)
	flight_panel.add_child(canvas)
	dock_view.stage = Control.new()
	dock_view.stage.custom_minimum_size = Vector2(610, 590)
	dock_view.stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock_view.stage.clip_contents = true
	flight_panel.add_child(dock_view.stage)
	quick_actions = hbox(flight_panel)
	button(quick_actions, "停靠 / 离港  E", flight.dock)
	button(quick_actions, "采矿 / 打捞  G", flight.salvage)
	var auto := button(quick_actions, "自动舰战", flight.auto_battle)
	auto.tooltip_text = "仅限交火前，350 距离内的孤立敌舰。按船型和剩余船体计算预计损伤。"
	button(quick_actions, "求援拖航", flight.tow)
	tactics_button = button(quick_actions, "战术  Tab", toggle_tactics)
	tactics = hbox(flight_panel)
	for index in range(Battle.ORDERS.size()):
		button(tactics, Battle.ORDERS[index], func():
			var sent := flight.issue(index, selected_target)
			say("已指挥 %s 艘僚舰：%s" % [sent, Battle.ORDERS[index]] if sent > 0 else "没有可接令僚舰，或尚未选定有效目标。"), true, true)
	tactics.hide()
	title(flight_panel, "WASD 驾驶 · 左键开火 · Shift 护盾 · V 排散 · F 系统 · 1–3 编组 · Tab 战术 · T 应答器 · R 脉冲", 14, DIM)
	location_banner = title(flight_panel, "", 15, GOLD)
	var side := frame(interior)
	side.custom_minimum_size.x = 467
	var sidebar := vbox(side)
	tabs = hbox(sidebar)
	for label in ["港口", "人物", "资产", "疆域", "纪事"]:
		button(tabs, label, func(): tab = label; refresh(), true, true)
	body = scroller(sidebar)
	footer = title(layout, "从港口开始。可在暂停中交易、任命和查看情报。", 15, GOLD)
	refresh()

func confirm_title() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "返回标题"
	dialog.dialog_text = "返回前要继续当前进度，请先保存。"
	dialog.confirmed.connect(show_creator)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func say(message: String) -> void:
	notice_text = message
	if is_instance_valid(footer):
		footer.text = message

func current_system() -> int:
	var vessel: Dictionary = world.ride()
	if not vessel.is_empty():
		return vessel.system
	return world.ports.get(world.active().get("loc", 0), {}).get("system", 0)

func toggle_pause() -> void:
	set_speed(1 if speed == 0 else 0)

func toggle_mute() -> void:
	if audio == null:
		return
	var is_muted: bool = audio.toggle_mute()
	if is_instance_valid(audio_button):
		audio_button.text = "静音" if is_muted else "音效"
	say("已静音。" if is_muted else "音效已开启。")

func toggle_tactics() -> void:
	var vessel := world.ride()
	if not galaxy and not vessel.is_empty() and vessel.dock == 0 and not world.succession:
		tactics.visible = not tactics.visible

func set_speed(new_speed: int) -> void:
	if world.succession:
		return
	var vessel: Dictionary = world.ride()
	if new_speed > 1 and not vessel.is_empty() and vessel.dock == 0 and (vessel.locked or not waypoint_live):
		say("手操或交火只能用一档。停靠或右键设航点后可加速。")
		return
	world.attention = false
	speed = new_speed
	update_header()

func set_waypoint(point: Vector2, label: String = "") -> void:
	waypoint = point
	waypoint_live = true
	if not label.is_empty():
		say("自动航点：" + label)

func update_header() -> void:
	var vessel: Dictionary = world.ride()
	var actor: Dictionary = world.active()
	var hull := "未登舰"
	if not vessel.is_empty():
		hull = "%s  船体 %d/%d  燃料 %d  余仓 %d" % [world.HULLS[vessel.kind], ceili(vessel.hp), world.HULL_HP[vessel.kind], floori(vessel.fuel), world.cargo_free(vessel)]
	header.text = "  %s    %s    %s    ¢%s    %s" % [world.date_label(), world.name_of(world.player), world.flag_name(actor.get("flag", -1)), actor.get("wallet", 0), hull]
	var location: String = "超空间航行" if galaxy else world.systems[current_system()].name
	status.text = "%s  |  %s" % [location, ("已暂停" if speed == 0 else "速度 %d" % speed)]
	if vessel.get("locked", false):
		status.text += "  /  交火"
	jump_button.text = "跃入星系  M" if galaxy else "引力点跃迁  M"
	jump_button.tooltip_text = "靠近星系信标后跃入。" if galaxy else "离港后前往恒星附近的引力点；必须进入 %d 范围。" % Celestial.JUMP_RANGE
	var objective := Story.objective(world)
	location_banner.text = objective if not objective.is_empty() else Art.ENVIRONMENTS[Art.variation(current_system())]

func refresh() -> void:
	if not playing:
		return
	clear(body)
	update_header()
	var docked := dock_view.sync()
	quick_actions.visible = not docked
	tactics_button.visible = not galaxy and not world.succession
	if docked or galaxy or world.succession:
		tactics.hide()
	if world.succession:
		hud.successor(body)
		if is_instance_valid(canvas):
			canvas.queue_redraw()
		return
	match tab:
		"港口":
			if docked:
				if dock_view.mode != "market" or dock_view.rendered != "market":
					dock_view.paint(world.ports[dock_view.station_id])
				dock_view.sidebar(body, world.ports[dock_view.station_id])
			else:
				hud.port(body)
		"人物": hud.person(body)
		"资产": hud.assets(body)
		"疆域": hud.powers(body)
		"纪事": hud.history(body)
	if docked and tab != "港口" and dock_view.rendered.is_empty():
		dock_view.paint(world.ports[dock_view.station_id])

func _physics_process(delta: float) -> void:
	if agent_bridge != null:
		agent_bridge.poll(delta)
	if not playing:
		return
	var cursor := canvas.visible and canvas.get_global_rect().has_point(get_global_mouse_position())
	var point: Vector2 = canvas.location(canvas.get_local_mouse_position()) if cursor else Vector2.ZERO
	if agent_bridge == null:
		flight.step(delta, Input.get_vector(&"left", &"right", &"up", &"down"), Input.is_physical_key_pressed(KEY_SHIFT),
			cursor and (fire_requested or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)), point, cursor)
	fire_requested = false
	if world.player != last_player:
		last_player = world.player
		galaxy = world.ride().get("layer", false)
		flight.reset()
		tab = "人物"
		refresh()
	if world.attention and speed != 0:
		speed = 0
		if not world.chronicle.is_empty():
			say(world.chronicle[0][1])
		refresh()
	if world.day != last_day:
		last_day = world.day
		update_header()
		if world.day % 6 == 0 and tab == "港口" and world.active().get("loc", 0) != 0 and dock_view.mode == "market":
			refresh()
	if audio != null and world.combat_serial > last_audio_serial:
		var active_system := current_system()
		for ev in world.combat_events:
			if int(ev.serial) <= last_audio_serial:
				continue
			if int(ev.system) == active_system or ev.kind in ["trade", "dock"]:
				audio.play(str(ev.kind), float(ev.strength))
		last_audio_serial = world.combat_serial
	if world.player != 0 and canvas.visible:
		var vessel: Dictionary = world.ride()
		canvas.galaxy = galaxy
		canvas.zoom = 0.67 if galaxy else 0.96
		canvas.camera = vessel.get("galpos", Vector2.ZERO) if galaxy else (vessel.pos if not vessel.is_empty() else Vector2.ZERO)
		canvas.queue_redraw()

func assets_changed() -> void:
	if tab == "资产" or tab == "港口":
		refresh()

func _input(event: InputEvent) -> void:
	if agent_bridge != null:
		get_viewport().set_input_as_handled()
		return
	if not playing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var vessel: Dictionary = world.ride()
		if canvas.visible and not vessel.is_empty() and vessel.dock == 0 and canvas.get_global_rect().has_point(get_global_mouse_position()):
			set_waypoint(canvas.location(canvas.get_local_mouse_position()))
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var vessel: Dictionary = world.ride()
		if canvas.visible and not galaxy and not vessel.is_empty() and vessel.dock == 0 and canvas.get_global_rect().has_point(get_global_mouse_position()):
			var aim: Vector2 = canvas.location(canvas.get_local_mouse_position())
			var id := flight.target_at(vessel, aim)
			if id != 0:
				selected_target = id
			fire_requested = speed > 0
	if event is InputEventKey and event.pressed and not event.echo:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit or (focused is OptionButton and focused.get_popup().visible):
			return
		var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var vessel: Dictionary = world.ride()
		var local: bool = not galaxy and not vessel.is_empty() and vessel.dock == 0
		match key:
			KEY_SPACE: toggle_pause()
			KEY_M: flight.change_layer()
			KEY_E: flight.dock()
			KEY_G: flight.salvage()
			KEY_F5: save_game(SAVE)
			KEY_F9: load_game(SAVE)
			KEY_TAB:
				toggle_tactics()
			KEY_V:
				if local and speed == 1 and Battle.vent(vessel):
					say("主动排散：武器和护盾下线。")
			KEY_F:
				if local and speed == 1 and Battle.system(world, vessel, Input.get_vector(&"left", &"right", &"up", &"down")):
					say("已启动" + Hulls.SYSTEM_NAMES[Hulls.COMBAT[vessel.kind].system])
			KEY_1, KEY_2, KEY_3:
				if local:
					var group := key - int(KEY_1) + 1
					if flight.select_group(vessel,group,event.shift_pressed) and event.shift_pressed:
						say("编组 %d 自动索敌：%s" % [group, "开" if vessel.fit.auto[group-1] else "关"])
			KEY_T:
				if not vessel.is_empty() and vessel.dock == 0:
					vessel.transponder = not vessel.transponder
					say("应答器已开启：正规港允许停靠。" if vessel.transponder else "应答器已关闭：雷达特征降低，正规港禁止停靠。")
					update_header()
			KEY_R:
				if not vessel.is_empty() and vessel.dock == 0:
					vessel.ping = 3.5
					if audio != null:
						audio.play("ping")
					say("已发射主动传感器脉冲：探测范围扩大，自身信号暴露。")
			_: return
		get_viewport().set_input_as_handled()

func save_game(path: String, silent: bool = false) -> bool:
	if not playing or agent_bridge != null:
		return false
	if world.ride().get("locked", false) and path != BEFORE:
		if not silent:
			say("交火中不能保存。")
		return false
	var state := world.snapshot().duplicate(true)
	if path == BEFORE:
		for vessel in state.ships.values():
			vessel.locked = false
			vessel.hp = maxf(vessel.hp, 1.0)
			vessel.battle.shield = false
	var temp := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if temp == null:
		say("写入存档失败。")
		return false
	temp.store_var(state)
	temp.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		say("替换存档失败。")
		return false
	if not silent:
		say("已保存航区。")
	return true

func load_game(path: String) -> bool:
	if agent_bridge != null:
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		say("未找到存档。")
		return false
	var state: Variant = file.get_var()
	if not state is Dictionary or not world.load_state(state):
		say("存档损坏或版本不兼容。")
		return false
	run_bridge()
	say("已恢复同一宇宙；时间已暂停。")
	return true
