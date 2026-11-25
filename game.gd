extends Control

const Saves = preload("res://scripts/services/save_manager.gd")
const World = preload("res://world.gd")
const Portrait = preload("res://portrait.gd")
const Flight = preload("res://flight.gd")
const Sector = preload("res://sector_view.gd")
const CampaignPanel = preload("res://scripts/ui/campaign_panel.gd")
const Society = preload("res://scripts/campaign/society.gd")
const UI = preload("res://panels.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")
const Economy = preload("res://economy.gd")
const AgentArena = preload("res://scripts/services/agent_arena.gd")
const Dock = preload("res://dock_view.gd")
const Story = preload("res://frontier.gd")
const Art = preload("res://presentation.gd")
const Battle = preload("res://combat.gd")
const InputController = preload("res://scripts/services/input_controller.gd")
const Hulls = preload("res://hull_catalog.gd")
const Celestial = preload("res://celestial.gd")
const AgentBridge = preload("res://agent_bridge.gd")
const StrategicMap = preload("res://scripts/ui/strategic_map.gd")
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
var entity_menus := preload("res://scripts/ui/entity_menus.gd").new()
var campaign_panel := CampaignPanel.new()
var dock_view := Dock.new()
var canvas: Control
var layout: VBoxContainer
var body: VBoxContainer
var header: Label
var footer: Label
var status: Label
var tabs: HBoxContainer
var campaign_button: Button
var galaxy := false
var flight_zoom := 0.96
var galaxy_zoom := 0.67
var system_chart := false
var chart_scale := 1.0
var chart_pan := Vector2.ZERO
var chart_target: Dictionary = {}
var chart_button: Button
var speed := 0
var speed_buttons: Array[Button] = []
var watch_ship_id := 0
var watch_button: Button
var watch_pan := Vector2.ZERO
var watch_drag := false
const COMBAT_TACTICS := ["激进突击", "稳健接战", "游击拉扯", "护盾抗线", "避战撤离"]
var autopilot := false
var autopilot_button: Button
var combat_tactic := 1
var tactic_button: Button
var strategic_map: StrategicMap
var waypoint := Vector2.ZERO
var waypoint_label := ""
var waypoint_tracking := Callable()
var waypoint_arrived := Callable()
var waypoint_live := false
var tactical_hidden: Array[Control] = []
var tactics: HBoxContainer
var tactics_button: Button
var selected_target := 0
var last_port := -1
var fire_requested := false
var playing := false
var tab := "港口"
var trade_table
var last_player := 0
var last_day := -1
var creator := {}
var portrait: Control
var notice_text := ""
var quick_actions: HFlowContainer
var test_profile := false
var agent_bridge: RefCounted
var agent_overlay: CanvasLayer
var cli_agent_mode := false
var takeover_button: Button
var location_banner: Label
var jump_button: Button
@onready var glossary := preload("res://scripts/ui/nested_tooltip.gd").new()
var audio: Node
var audio_button: Button
var last_audio_serial := 0
var side_panel: Control
var side_toggle: Button
var side_collapsed := false
var toast_panel: PanelContainer
var toast_label: Label
var toast_timer := 0.0
var dock_action_btn: Button
var nav_button: Button
var header_portrait: Control
var nav_target_port := 0
var nav_query := ""
var nav_auto_dock := true
var alerts_button: Button
var smolagents_pid := -1
var arena: Node
var arena_button: Button
var mobile_play := OS.has_feature("android")
var touch_deck: Control
var mobile_was_docked := false
const MobileModelAgent = preload("res://scripts/services/mobile_model_agent.gd")
var mobile_runner: MobileModelAgent
var mobile_background := false
var arena_display_suspended := false
var arena_refresh_requested := false

func _ready() -> void:
	if mobile_play:
		get_window().content_scale_size = Vector2i(1280,800)
		get_tree().quit_on_go_back = false
		get_tree().node_added.connect(_configure_touch_scroll)
	for binding in [[&"left", KEY_A], [&"right", KEY_D], [&"up", KEY_W], [&"down", KEY_S]]:
		if not InputMap.has_action(binding[0]):
			InputMap.add_action(binding[0])
			var key := InputEventKey.new()
			key.physical_keycode = binding[1]
			InputMap.action_add_event(binding[0], key)
	theme = preload("res://scripts/ui/bridge_theme.tres")
	add_child(glossary)
	flight.game = self
	hud.game = self
	entity_menus.setup(self)
	campaign_panel.game = self
	dock_view.game = self
	audio = AudioSys.new()
	add_child(audio)
	arena = AgentArena.new()
	add_child(arena)
	if "--battle-benchmark" in OS.get_cmdline_user_args():
		test_profile = true
		show_creator()
		run_benchmark.call_deferred()
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--agent-dir="):
			var bridge := AgentBridge.new()
			bridge.game = self
			if not bridge.start(argument.trim_prefix("--agent-dir="),"--agent-watch" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"):
				printerr("Agent bridge requires an existing, empty, absolute session directory.")
				get_tree().quit(2)
				return
			agent_bridge = bridge
			cli_agent_mode = true
			if bridge.watch_mode:
				agent_overlay = CanvasLayer.new()
				add_child(agent_overlay)
				bridge.attach_watch(agent_overlay)
			test_profile = true
			show_creator()
			say("代理会话 · 本地命令驱动，不使用普通存档。")
			return
	if test_profile: show_creator()
	else: show_title()

func run_benchmark() -> void:
	var benchmark := preload("res://scripts/benchmark/fleet_benchmark.gd").new()
	await benchmark.run(self)

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

func key_caption(label: String, key: String) -> String:
	return label if mobile_play else label + "  " + key

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
		action.call(), CONNECT_DEFERRED if mobile_play else 0)
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

func _configure_touch_scroll(node: Node) -> void:
	if node is ScrollContainer and is_ancestor_of(node) and not node.get_window() is PopupMenu:
		node.scroll_deadzone = maxi(node.scroll_deadzone, 10)
		return
	if not (node is BaseButton or node is PanelContainer or node is Panel):
		return
	var parent := node.get_parent()
	while parent is Control and not parent is ScrollContainer:
		parent = parent.get_parent()
	if not parent is ScrollContainer or not is_ancestor_of(parent):
		return
	# Let Godot's scroll gesture cancel the button press once the finger moves.
	if node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	if node is BaseButton:
		node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

func clear(parent: Node) -> void:
	for child in parent.get_children():
		if child == audio or child == glossary or child == agent_overlay or child == arena:
			continue
		parent.remove_child(child)
		child.queue_free()

func reset_layout() -> void:
	trade_table = null
	entity_menus.covered_panels.clear()
	if glossary.is_node_ready():
		glossary.hide_card()
	tactical_hidden.clear()
	clear(self)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	layout = vbox(margin)

func show_creator() -> void:
	if arena != null and arena.active:
		arena.stop_arena(false)
	playing = false
	reset_layout()
	var random := RandomNumberGenerator.new()
	random.randomize()
	creator = {"look": Portrait.random_look(random), "inputs": [], "overrides": []}
	title(layout, "边 疆 航 务 局     /     D E E P   F R O N T I E R", 15, GOLD)
	title(layout, "星 轨 遗 产", 52)
	title(layout, "断航两百年后，没有人等你拯救银河。晨曦自由港只问：你的名字，以及你的泊位账单。", 17, DIM)
	var columns := preload("res://scripts/ui/creator_screen.tscn").instantiate()
	if mobile_play:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		layout.add_child(scroll)
		columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(columns)
	else:
		layout.add_child(columns)
	var draft: VBoxContainer = columns.get_node("Dossier/Fields")
	title(draft, "01   海 关 登 记", 19, GOLD)
	portrait = Portrait.new()
	portrait.custom_minimum_size = Vector2(175,140) if mobile_play else Vector2(240,270)
	portrait.look = creator.look.duplicate()
	draft.add_child(portrait)
	creator.name = field(draft, "林遥", 16)
	creator.gender = choice(draft, ["男", "女"])
	creator.house = field(draft, "远岚", 16)
	creator.house.placeholder_text = "贵族家族名"
	creator.house.editable = false
	creator.noble = choice(draft, ["平民  /  航务局配舰", "贵族  /  家产船与血亲继承"])
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
	creator.role = choice(draft, ["舰长开局（驾驶旗舰）", "独立站长（自有港口，不驾船）", "受雇站长（效忠阵营，不驾船）"])
	button(draft, "随机外貌", func():
		creator.look = Portrait.random_look_for_gender(random, creator.gender.selected)
		for entry in creator.inputs:
			entry.node.select(creator.look[entry.key])
		portrait.look = creator.look.duplicate())
	var face: VBoxContainer = columns.get_node("Appearance/Fields")
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
	var sector: VBoxContainer = columns.get_node("Sector/Fields")
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
	var presets := vbox(sector) if mobile_play else scroller(sector)
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
	if not test_profile: button(lower,"返回主菜单",show_title)
	button(lower, "继续上次存档", func(): load_game(SAVE), agent_bridge == null and FileAccess.file_exists(SAVE))
	button(lower, "读取自动存档", func(): load_game(AUTO), agent_bridge == null and FileAccess.file_exists(AUTO))
	button(lower, "读取接班前", func(): load_game(BEFORE), agent_bridge == null and FileAccess.file_exists(BEFORE))
	button(lower, "引擎许可与鸣谢", show_licenses)
	title(lower, "断航后的边疆", 14, DIM)
	footer = title(layout, "", 15, GOLD)

func show_title() -> void:
	if cli_agent_mode:
		show_creator()
		return
	if is_instance_valid(mobile_runner):
		_stop_takeover()
	if arena != null and arena.active: arena.stop_arena(false)
	playing = false
	reset_layout()
	var menu := preload("res://scripts/ui/title_menu.gd").new()
	add_child(menu)
	menu.open(self)

func open_cheat_console() -> void:
	if cli_agent_mode or not playing:
		return
	var dialog := AcceptDialog.new()
	dialog.title = "作弊码 / 调试控制台 (F12)"
	dialog.ok_button_text = "关闭"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(540, 320)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	var input_row := HBoxContainer.new()
	box.add_child(input_row)
	var code_input := LineEdit.new()
	code_input.placeholder_text = "输入作弊码，如: money 100000 / ship 7 / pop 500 / day 30"
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(code_input)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "可用指令: money [数] | fuel | repair | pop [数] | goods [数] | build | ship [编号] | reveal | peace | war | bounty | day [数]"
	var run_code := func(txt: String):
		var msg := apply_cheat(txt)
		status.text = msg
		say(msg)
		refresh()
	code_input.text_submitted.connect(func(txt: String): run_code.call(txt))
	button(input_row, "执行", func(): run_code.call(code_input.text))
	var quick := GridContainer.new()
	quick.columns = 4
	box.add_child(quick)
	var cheat_toggle: Button = UIKit.action_button(box, "作弊模式：开（允许右键切换任意角色）" if bool(world.campaign.get("cheat_mode", false)) else "作弊模式：关（点击开启，允许右键切换任意角色）", func():
		var on := not bool(world.campaign.get("cheat_mode", false))
		world.campaign["cheat_mode"] = on
		say("作弊模式已开启：现在可在人物右键菜单中切换任意角色。" if on else "作弊模式已关闭。")
		dialog.queue_free()
		refresh(), "primary" if bool(world.campaign.get("cheat_mode", false)) else "ghost", true, "", true)
	for pair in [
		["+10万信用点", "money 100000"], ["加满燃料", "fuel"], ["全队满血", "repair"], ["解锁全图", "reveal"],
		["当前站+500人口", "pop 500"], ["当前站+200物资", "goods 200"], ["一键竣工", "build"], ["送战列舰", "ship 7"],
		["全局停战", "peace"], ["触发战争", "war"], ["刷新赏金", "bounty"], ["快进30天", "day 30"]
	]:
		button(quick, pair[0], func(): run_code.call(pair[1]), true, true)
	box.add_child(status)
	button(box,"舰船运行诊断",func(): dialog.queue_free(); hud.open_diagnostics())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	code_input.grab_focus()

func open_arena_dialog() -> void:
	if cli_agent_mode or not playing or arena == null:
		return
	if arena.active:
		var dialog := AcceptDialog.new()
		dialog.ok_button_text = "关闭"
		dialog.title = "多 Agent 同宇宙竞技榜"
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(640, 420)
		box.add_theme_constant_override("separation", 8)
		dialog.add_child(box)
		var list := scroller(box)
		var rows: Array[Dictionary] = arena.standings()
		for i in range(rows.size()):
			var r: Dictionary = rows[i]
			var card := UIKit.card(list, UIKit.GOLD if i == 0 else UIKit.CYAN, true)
			var head := hbox(card)
			var lbl := title(head, "#%d %s (%s)  ·  净资产 ¢%d  ·  现金 ¢%d  ·  %d船/%d站" % [
				i + 1, r.name, r.model, int(r.net_worth), int(r.credits), int(r.ships), int(r.ports)], 14, UIKit.INK)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var aid := int(r.actor_id)
			UIKit.action_button(head, "档案", func():
				dialog.queue_free()
				hud.dossier.open(self, aid), "ghost")
			title(card, "思考：" + str(r.thought), 12, DIM, true)
		UIKit.action_button(box, "停止多 Agent 竞技", func():
			arena.stop_arena()
			if is_instance_valid(arena_button):
				arena_button.text = "竞技场"
			say("已停止多 Agent 同宇宙竞技。")
			dialog.queue_free(), "danger", true, "", true)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.close_requested.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered()
		return
	var cfg_dlg := ConfirmationDialog.new()
	cfg_dlg.title = "多 Agent 同宇宙竞技配置（白手起家公平赛跑）"
	cfg_dlg.ok_button_text = "投放并启动同宇宙竞技"
	cfg_dlg.cancel_button_text = "取消"
	var base_cfg := _load_smolagents_cfg()
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(660, 400)
	box.add_theme_constant_override("separation", 8)
	cfg_dlg.add_child(box)
	title(box, "可为每个 Agent 选择已保存的模型预设（在「托管」中点击「保存模型配置」即可新增预设）", 12, DIM)
	var list := scroller(box)
	var profiles := _load_model_profiles()
	var has_base := false
	for pr in profiles:
		if pr is Dictionary and str(pr.get("model", "")) == str(base_cfg.model):
			has_base = true
			break
	if not has_base and not str(base_cfg.model).is_empty():
		profiles.insert(0, {"model": str(base_cfg.model), "api_base": str(base_cfg.api_base), "api_key": str(base_cfg.api_key)})
	var presets := _load_arena_cfg(base_cfg)
	var slot_inputs: Array[Dictionary] = []
	for p_item in presets:
		if not (p_item is Dictionary):
			continue
		var card := UIKit.card(list, UIKit.CYAN, true)
		var r1 := hbox(card)
		var en := CheckButton.new()
		en.text = "启用"
		en.button_pressed = bool(p_item.get("enabled", true))
		r1.add_child(en)
		var n_in := field(r1, str(p_item.get("name", "Agent")), 24)
		var m_in := field(r1, str(p_item.get("model", base_cfg.model)), 60)
		var slot_state := {
			"enabled": en,
			"name": n_in,
			"model": m_in,
			"api_base": str(p_item.get("api_base", base_cfg.api_base)),
			"api_key": str(p_item.get("api_key", base_cfg.api_key)),
		}
		if not profiles.is_empty():
			var opt := OptionButton.new()
			opt.custom_minimum_size.x = 160
			var sel_idx := 0
			for pi in range(profiles.size()):
				var prof: Dictionary = profiles[pi]
				opt.add_item(str(prof.get("model", "")), pi)
				if str(prof.get("model", "")) == m_in.text:
					sel_idx = pi
			opt.select(sel_idx)
			opt.item_selected.connect(func(idx: int):
				if idx >= 0 and idx < profiles.size():
					var chosen_prof: Dictionary = profiles[idx]
					m_in.text = str(chosen_prof.get("model", ""))
					slot_state["api_base"] = str(chosen_prof.get("api_base", base_cfg.api_base))
					slot_state["api_key"] = str(chosen_prof.get("api_key", base_cfg.api_key)))
			r1.add_child(opt)
		var g_in := field(card, str(p_item.get("goal", "")), 160)
		g_in.placeholder_text = "留空则由 Agent 自主决定发展路线与目标"
		slot_state["goal"] = g_in
		slot_inputs.append(slot_state)
	UIKit.action_button(box, "保存竞技场配置", func():
		_save_arena_cfg(slot_inputs)
		say("已保存竞技场模型与角色配置。"), "ghost")
	cfg_dlg.confirmed.connect(func():
		_save_arena_cfg(slot_inputs)
		var chosen: Array[Dictionary] = []
		for si in slot_inputs:
			if si.enabled.button_pressed:
				var ep := str(si.get("api_base", "")).strip_edges()
				var ak := str(si.get("api_key", "")).strip_edges()
				chosen.append({
					"name": si.name.text,
					"model": si.model.text.strip_edges(),
					"api_base": str(base_cfg.api_base) if ep.is_empty() else ep,
					"api_key": str(base_cfg.api_key) if ak.is_empty() else ak,
					"goal": si.goal.text.strip_edges(),
					"max_steps": int(base_cfg.max_steps),
					"auto_launch": true,
				})
		cfg_dlg.queue_free()
		if chosen.is_empty():
			say("请至少启用 1 个 Agent 槽位。")
		elif arena.start_arena(self, chosen, _smolagents_script()):
			if is_instance_valid(arena_button):
				arena_button.text = "竞技场: 开"
			say("已投放 %d 个 Agent 进入同宇宙竞技！可在顶栏「竞技场: 开」查看净资产榜与实时思考。" % chosen.size())
			refresh()
		else:
			say("启动竞技场失败，请先在「托管」保存模型地址和名称，再为每个槽位选择预设。" if mobile_play else "启动多 Agent 竞技失败，请检查模型配置或 Python 环境。"))
	cfg_dlg.canceled.connect(cfg_dlg.queue_free)
	cfg_dlg.close_requested.connect(cfg_dlg.queue_free)
	add_child(cfg_dlg)
	cfg_dlg.popup_centered()

func apply_cheat(raw: String) -> String:
	var parts := raw.strip_edges().split(" ", false)
	if parts.is_empty():
		return "请输入作弊码。"
	var cmd := parts[0].to_lower()
	var arg := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 0
	var actor := world.active()
	var dock_id := int(actor.get("loc", 0))
	var station: Dictionary = world.ports.get(dock_id, {})
	match cmd:
		"cheat", "debug":
			var on := not bool(world.campaign.get("cheat_mode", false))
			if parts.size() > 1:
				on = parts[1].to_lower() in ["1", "on", "true"]
			world.campaign["cheat_mode"] = on
			return "作弊模式已开启：人物右键菜单已解锁「切换为此角色」。" if on else "作弊模式已关闭。"
		"money", "rich", "cash":
			var amount := arg if arg != 0 else 100000
			world.credit(world.player, amount, {}, "作弊码")
			return "作弊码生效：信用点 %+d（当前 ¢%d）。" % [amount, actor.wallet]
		"fuel":
			var count := 0
			for s: Dictionary in world.ships.values():
				if world.can_operate(s):
					s.fuel = 100.0
					count += 1
			return "作弊码生效：已为 %d 艘己方舰船加满燃料。" % count
		"repair", "heal":
			var count := 0
			for s: Dictionary in world.ships.values():
				if world.oversees(s.owner):
					s.hp = int(world.Hulls.MODELS[s.kind].hp)
					count += 1
			return "作弊码生效：已修复 %d 艘己方舰船。" % count
		"pop":
			if station.is_empty():
				return "请先停靠在一个空间站再使用 pop。"
			var add := arg if arg > 0 else 500
			station.pop_cap = maxi(int(station.pop_cap), int(station.pop) + add)
			station.pop += add
			return "作弊码生效：%s 人口 +%d（当前 %d，%s）。" % [station.name, add, station.pop, world.Economy.market_size_label(station)]
		"goods", "stock":
			if station.is_empty():
				return "请先停靠在一个空间站再使用 goods。"
			var add := arg if arg > 0 else 200
			for i in range(station.stock.size()):
				station.stock[i] += add
			return "作弊码生效：%s 全品类库存 +%d。" % [station.name, add]
		"build":
			var sys := int(world.ride().get("system", 0))
			var done_count := 0
			for p: Dictionary in world.ports.values():
				if p.system == sys and p.build > 0:
					p.build = 0
					if not p.has("equity"):
						world.Capital.register_site(p)
					world.Economy.Industry.update_market(p)
					done_count += 1
				if p.system == sys and p.extension > 0:
					p.extension = 0
					done_count += 1
			return "作弊码生效：当前星系 %d 项工程已立即竣工。" % done_count
		"ship":
			var kind := clampi(arg if parts.size() > 1 else 2, 0, world.Hulls.MODELS.size() - 1)
			var ride := world.ride()
			var sys := int(ride.get("system", 0))
			var pos := Vector2(ride.get("pos", Vector2(200, 200))) + Vector2(140, 0)
			var cap: int = world.random_person(actor.flag, dock_id)
			var sid: int = world.ship(kind, world.player, cap, actor.flag, sys, pos, dock_id)
			return "作弊码生效：已生成 %s（#%d）。" % [world.HULLS[kind], sid]
		"reveal", "scan":
			for p: Dictionary in world.ports.values():
				p.scan = true
			return "作弊码生效：已解锁全星区空间站情报。"
		"peace":
			for f: int in world.factions:
				if f != actor.flag:
					world.set_treaty(actor.flag, f, 0)
			return "作弊码生效：已与所有势力恢复停战。"
		"war":
			for f: int in world.factions:
				if world.factions[f].alive and world.factions[f].npc:
					world.factions[f].last_war = -999
			world.Politics.military(world)
			return "作弊码生效：已触发 NPC 势力军事宣战与出征。"
		"bounty":
			world.campaign.bounties = []
			world.Bounties.advance(world)
			return "作弊码生效：已刷新星区自动赏金。"
		"day":
			var days := clampi(arg if arg > 0 else 30, 1, 365)
			world.tick(days)
			return "作弊码生效：时间快进 %d 天（当前第 %d 天）。" % [days, world.day]
		_:
			return "未知作弊码：%s" % cmd

func show_licenses() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Godot Engine / 开源许可"
	var credits := RichTextLabel.new()
	credits.custom_minimum_size = Vector2(650, 380)
	credits.text = "Godot Engine\nhttps://godotengine.org/license/\n\n" + Engine.get_license_text()
	if FileAccess.file_exists("res://LICENSE"):
		credits.text += "\n\n星轨遗产 · 原创源代码授权\n" + FileAccess.get_file_as_string("res://LICENSE")
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
			"gender": creator.gender.selected,
			"age": int(creator.age.value), "origin": creator.origin.selected, "trait": creator.trait.selected,
			"look": creator.look, "noble": creator.noble.selected == 1, "station_master": creator.role.selected}, "overrides": []}
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
	if not cli_agent_mode and arena != null and not arena.active:
		var saved_slots: Variant = world.campaign.get("arena_slots", [])
		if saved_slots is Array and not saved_slots.is_empty():
			arena.resume_arena(self, _smolagents_script(), _resolve_model_creds, true)
	if not world.market_updated.is_connected(hud.market_updated):
		world.market_updated.connect(hud.market_updated)
	if not world.event_offered.is_connected(refresh_pending_decisions):
		world.event_offered.connect(refresh_pending_decisions, CONNECT_DEFERRED)
	if not world.merchant_attacked.is_connected(say):
		world.merchant_attacked.connect(say)
	if not world.watched_activity.is_connected(say):
		world.watched_activity.connect(say)
	speed = 0
	if mobile_play:
		mobile_was_docked = world.active().get("loc",0) != 0
		side_collapsed = not mobile_was_docked
	galaxy = world.ride().get("layer", false)
	notice_text = ""
	flight.reset(true)
	world.before_death = Callable() if cli_agent_mode else func(): save_game(BEFORE, true)
	reset_layout()
	dock_view.reset()
	system_chart = false
	hud.report_open = false
	hud.diagnostics_open = false
	hud.equity.mode = ""
	hud.dossier.person_id = 0
	hud.report_asset = 0
	last_audio_serial = world.combat_serial
	selected_target = 0
	fire_requested = false
	var top_card := PanelContainer.new()
	top_card.add_theme_stylebox_override("panel", UIKit._card_style(UIKit.CYAN))
	layout.add_child(top_card)
	var top := hbox(top_card)
	top.add_theme_constant_override("separation", 6)
	title(top, "星轨遗产", 18, GOLD)
	header_portrait = Portrait.new()
	header_portrait.custom_minimum_size = Vector2(30, 34)
	top.add_child(header_portrait)
	header = title(top, "", 14, INK, true)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_button = button(top, "静音" if audio != null and audio.muted else "音效", toggle_mute)
	if not cli_agent_mode:
		takeover_button = button(top, "托管: 开" if agent_bridge != null else "托管: 关", toggle_agent_takeover)
		takeover_button.toggle_mode = true
		takeover_button.button_pressed = agent_bridge != null
		takeover_button.tooltip_text = "随时开启/关闭本地 Agent 托管当前正在进行的游戏。\n会话目录：" + takeover_dir()
		arena_button = button(top, "竞技场: 开" if (arena != null and arena.active) else "竞技场", open_arena_dialog)
	button(top, "保存", func(): save_game(SAVE), not cli_agent_mode)
	button(top, "读档", func(): load_game(SAVE), not cli_agent_mode)
	button(top, "标题", confirm_title)
	alerts_button = UIKit.action_button(top, "✓ 正常", open_alerts_popup, "ghost")
	alerts_button.tooltip_text = "查看舰船低血量/低燃料、空间站缺粮/封锁、就绪战争借口与待决事务。"
	side_toggle = button(top, "展开面板" if side_collapsed else "收起面板", toggle_side_panel)
	var interior := hbox(layout)
	interior.size_flags_vertical = Control.SIZE_EXPAND_FILL
	interior.add_theme_constant_override("separation", 10)
	var flight_panel := vbox(interior)
	flight_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flight_panel.add_theme_constant_override("separation", 6)
	var toolbar_card := PanelContainer.new()
	toolbar_card.add_theme_stylebox_override("panel", UIKit._card_style(Color.TRANSPARENT, UIKit.SUBCARD_BG))
	flight_panel.add_child(toolbar_card)
	var toolbar_flow := HFlowContainer.new()
	toolbar_flow.add_theme_constant_override("h_separation", 6)
	toolbar_card.add_child(toolbar_flow)
	var toolbar := hbox(toolbar_flow)
	toolbar.add_theme_constant_override("separation", 5)
	speed_buttons.clear()
	var pause_btn: Button = button(toolbar, "暂停", toggle_pause, true, true)
	pause_btn.toggle_mode = true
	speed_buttons.append(pause_btn)
	for level in range(1, 6):
		var sbtn: Button = button(toolbar, "%dx" % level, func(): set_speed(level), true, true)
		sbtn.toggle_mode = true
		speed_buttons.append(sbtn)
	jump_button = button(toolbar, "跃迁 M", flight.change_layer)
	chart_button = button(toolbar, "星图 C", toggle_system_chart)
	button(toolbar, "战略地图", func(): open_strategic_map("strategic"))
	status = title(toolbar_flow, "", 13, GOLD, true)
	status.custom_minimum_size.x = 200
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var stage_wrap := Control.new()
	stage_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_wrap.custom_minimum_size = Vector2(560,235) if mobile_play else Vector2(610,420)
	flight_panel.add_child(stage_wrap)
	canvas = Sector.new()
	canvas.game = self
	canvas.clip_contents = true
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_wrap.add_child(canvas)
	if agent_bridge != null and DisplayServer.get_name() == "headless":
		canvas.set_process(false)
		canvas.visible = false
	dock_view.stage = preload("res://scripts/ui/dock_overlay.tscn").instantiate()
	if mobile_play:
		dock_view.stage.custom_minimum_size = Vector2(550,400)
	dock_view.stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_wrap.add_child(dock_view.stage)
	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", UIKit._card_style(GOLD, Color(0.035, 0.067, 0.114, 0.94)))
	toast_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toast_panel.offset_left = -390
	toast_panel.offset_top = 12
	toast_panel.offset_right = -12
	toast_panel.offset_bottom = 56
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.hide()
	stage_wrap.add_child(toast_panel)
	toast_label = title(toast_panel, "", 13, GOLD, true)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mobile_play:
		touch_deck = preload("res://scripts/ui/touch_flight.gd").new()
		touch_deck.game = self
		flight_panel.add_child(touch_deck)
	var dock_card := PanelContainer.new()
	dock_card.add_theme_stylebox_override("panel", UIKit._card_style(Color.TRANSPARENT, UIKit.SUBCARD_BG))
	flight_panel.add_child(dock_card)
	quick_actions = HFlowContainer.new()
	quick_actions.add_theme_constant_override("h_separation", 6)
	dock_card.add_child(quick_actions)
	dock_action_btn = button(quick_actions, "停靠 / 离港  E", flight.dock)
	nav_button = button(quick_actions, key_caption("直达导航","N"), open_station_navigator)
	nav_button.tooltip_text = "选择星区中任意已知空间站，自动规划本星系或跨星系超空间直达航线。"
	button(quick_actions, key_caption("采矿 / 打捞","G"), flight.salvage)
	var field_fix := button(quick_actions, "应急抢修", flight.field_repair)
	field_fix.tooltip_text = "非交火状态下在太空抢修旗舰与护航舰：消耗船体部件/合金/废料，或无料应急恢复至 45% 船体。"
	autopilot_button = button(quick_actions, key_caption("战斗托管: 关","U"), toggle_autopilot)
	autopilot_button.toggle_mode = true
	autopilot_button.tooltip_text = "开启后由 AI 接管旗舰的实时战斗走位、护盾、技能与开火（按 U 或移动键随时切换）。"
	tactic_button = button(quick_actions, "托管战术: %s" % COMBAT_TACTICS[combat_tactic], cycle_combat_tactic)
	tactic_button.tooltip_text = "切换旗舰战斗托管战术：激进突击 / 稳健接战 / 游击拉扯 / 护盾抗线 / 避战撤离。"
	button(quick_actions, "求援拖航", flight.tow)
	tactics_button = button(quick_actions, key_caption("战术","Tab"), toggle_tactics)
	tactics = hbox(flight_panel)
	button(tactics,"旗舰自动攻击",func():
		say("旗舰已接令攻击 #%d。" % selected_target if flight.attack_target(selected_target) else "先右键选择本地可见舰船。"))
	for index in range(Battle.ORDERS.size()):
		button(tactics, Battle.ORDERS[index], func():
			var sent := flight.issue(index, selected_target)
			say("已指挥 %s 艘僚舰：%s" % [sent, Battle.ORDERS[index]] if sent > 0 else "没有可接令僚舰，或尚未选定有效目标。"), true, true)
	button(tactics, key_caption("返回舰桥","Esc"), func(): set_tactics(false))
	tactics.hide()
	var keys_row := hbox(flight_panel)
	var keys_hint := title(flight_panel, "WASD 驾驶 · 左键开火 · Q 全武器齐射 · 1–3/Shift 编组自动 · 滚轮缩放 · Ctrl 助推 · Shift 护盾/相位 · V 排散 · F 系统 · N 直达导航 · Tab 战术 · R 脉冲 · U 战斗托管", 12, DIM, true)
	keys_hint.hide()
	if mobile_play:
		keys_hint.text = "左侧摇杆驾驶。选「航点」后点目的地，选「开火」后按住目标瞄准射击。护盾和助推可与摇杆同时按住。「查看」打开目标菜单。"
	var keys_btn: Button = button(keys_row, "? 键位", func():
		keys_hint.visible = not keys_hint.visible)
	if mobile_play:
		keys_btn.text = "触屏操作"
	keys_btn.toggle_mode = true
	location_banner = title(keys_row, "", 13, GOLD, true)
	location_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	watch_button = button(keys_row, "返回旗舰视角", func():
		watch_ship_id = 0
		refresh())
	watch_button.hide()
	side_panel = preload("res://scripts/ui/side_panel.tscn").instantiate()
	side_panel.visible = not side_collapsed
	interior.add_child(side_panel)
	tabs = side_panel.get_node("Column/Tabs")
	for label in ["港口", "人物", "资产", "疆域", "纪事", "事务"]:
		var tab_button := button(tabs, label, func():
			system_chart = false
			tab = label
			if tab == "人物":
				hud.dossier.person_id = 0
			if tab == "事务" and Society.pending_count(world) > 0:
				campaign_panel.section = 0
			refresh(), true, true)
		tab_button.toggle_mode = true
		if label == "事务":
			campaign_button = tab_button
	body = side_panel.get_node("Column/Scroll/Body")
	footer = title(layout, "", 13, DIM, true)
	refresh()

func update_campaign_button() -> void:
	var count := Society.pending_count(world)
	campaign_button.text = "事务 (%d)" % count if count else "事务"

func refresh_pending_decisions() -> void:
	if not playing or not is_instance_valid(campaign_button):
		return
	if tab == "事务" and campaign_panel.section == 0:
		refresh()
	else:
		update_campaign_button()

func confirm_title() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "返回标题"
	dialog.dialog_text = "返回前要继续当前进度，请先保存。"
	dialog.confirmed.connect(show_title)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func say(message: String) -> void:
	notice_text = message
	if arena_display_suspended:
		return
	if is_instance_valid(footer):
		footer.text = message
	if is_instance_valid(toast_panel) and is_instance_valid(toast_label) and not message.is_empty():
		toast_label.text = message
		toast_panel.show()
		toast_panel.modulate.a = 1.0
		toast_timer = 4.2

func viewed_ship() -> Dictionary:
	if watch_ship_id > 0:
		var watched: Dictionary = world.ships.get(watch_ship_id, {})
		if not watched.is_empty() and world.can_operate(watched):
			return watched
		watch_ship_id = 0
	return world.ride()

func current_system() -> int:
	var vessel: Dictionary = viewed_ship()
	if not vessel.is_empty():
		return vessel.system
	var actor: Dictionary = world.active()
	var port_id: int = actor.get("journey", {}).get("origin", actor.get("loc", 0))
	return world.ports.get(port_id, {}).get("system", 0)

func takeover_dir() -> String:
	return OS.get_user_data_dir().path_join("agent_takeover")

func set_autopilot(enabled: bool, quiet: bool = false) -> void:
	autopilot = enabled
	if is_instance_valid(autopilot_button):
		autopilot_button.text = key_caption("战斗托管: 开" if autopilot else "战斗托管: 关","U")
		autopilot_button.button_pressed = autopilot
	if not quiet:
		say("已开启旗舰战斗托管（AI 接管走位、护盾、技能与开火，按 U 或移动键可随时接管）。" if autopilot else "已关闭旗舰战斗托管。")

func toggle_autopilot() -> void:
	set_autopilot(not autopilot)

func set_combat_tactic(index: int, quiet: bool = false) -> void:
	combat_tactic = clampi(index, 0, COMBAT_TACTICS.size() - 1)
	if is_instance_valid(tactic_button):
		tactic_button.text = "托管战术: %s" % COMBAT_TACTICS[combat_tactic]
	if not quiet:
		say("旗舰托管战术已切换为：%s。" % COMBAT_TACTICS[combat_tactic])

func cycle_combat_tactic() -> void:
	set_combat_tactic((combat_tactic + 1) % COMBAT_TACTICS.size())

func _exit_tree() -> void:
	if is_instance_valid(mobile_runner):
		mobile_runner.stop()
	if arena != null:
		arena.stop_arena(false)
	if smolagents_pid > 0 and OS.is_process_running(smolagents_pid):
		OS.kill(smolagents_pid)
		smolagents_pid = -1
	if agent_bridge != null:
		agent_bridge.publish("shutdown.json", {"ok": true, "reason": "game_exited"})

func _smolagents_script() -> String:
	if mobile_play:
		return ""
	var path := OS.get_executable_path().get_base_dir().path_join("tools/smolagents_runner.py")
	if OS.has_feature("editor"):
		path = ProjectSettings.globalize_path("res://tools/smolagents_runner.py")
	return path if FileAccess.file_exists(path) else ""

func launch_agent_runner(args: PackedStringArray) -> int:
	var bundled := args[0].get_base_dir().path_join("agent-runtime/pythonw.exe")
	var interpreter := bundled
	if not FileAccess.file_exists(bundled):
		if not OS.has_feature("editor"):
			return -1
		interpreter = "python"
	return OS.create_process(interpreter, PackedStringArray(["-B", "-X", "utf8"]) + args, false)

func start_mobile_runner(bridge, cfg: Dictionary, rivals: String = "") -> MobileModelAgent:
	var runner := MobileModelAgent.new()
	arena.add_child(runner)
	runner.suspended = mobile_background
	runner.start(bridge,cfg,rivals)
	return runner

func _mobile_takeover_finished(note: String, runner: MobileModelAgent) -> void:
	if runner == mobile_runner:
		_stop_takeover()
		say(note)

func _load_smolagents_cfg() -> Dictionary:
	var def := {
		"api_base": "" if mobile_play else "http://localhost:11434/v1",
		"model": "" if mobile_play else "qwen2.5:7b",
		"api_key": "" if mobile_play else "ollama",
		"goal": "通过高利润跑商、买船建队、建站与创办企业最大化净资产",
		"max_steps": 0,
		"auto_launch": true,
	}
	if FileAccess.file_exists("user://smolagents_config.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://smolagents_config.json"))
		if parsed is Dictionary:
			def.merge(parsed, true)
	return def

func _save_smolagents_cfg(cfg: Dictionary) -> void:
	var f := FileAccess.open("user://smolagents_config.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(cfg, "\t"))

func _load_model_profiles() -> Array:
	if FileAccess.file_exists("user://model_profiles.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://model_profiles.json"))
		if parsed is Array:
			return parsed
	return []

func _resolve_model_creds(model_name: String) -> Dictionary:
	var base := _load_smolagents_cfg()
	var out := {
		"api_base": str(base.get("api_base", "")),
		"api_key": str(base.get("api_key", "")),
		"max_steps": int(base.get("max_steps", 0)),
	}
	for prof in _load_model_profiles():
		if prof is Dictionary and str(prof.get("model", "")) == model_name:
			var ep := str(prof.get("api_base", "")).strip_edges()
			var ak := str(prof.get("api_key", "")).strip_edges()
			if not ep.is_empty():
				out["api_base"] = ep
			if not ak.is_empty():
				out["api_key"] = ak
			return out
	for item in _load_arena_cfg(base):
		if item is Dictionary and str(item.get("model", "")) == model_name:
			var ep := str(item.get("api_base", "")).strip_edges()
			var ak := str(item.get("api_key", "")).strip_edges()
			if not ep.is_empty():
				out["api_base"] = ep
			if not ak.is_empty():
				out["api_key"] = ak
			return out
	return out

func _save_model_profile(cfg: Dictionary) -> void:
	var model_name := str(cfg.get("model", "")).strip_edges()
	if model_name.is_empty():
		return
	var profiles := _load_model_profiles()
	var entry := {
		"model": model_name,
		"api_base": str(cfg.get("api_base", "")).strip_edges(),
		"api_key": str(cfg.get("api_key", "")).strip_edges(),
	}
	var replaced := false
	for i in range(profiles.size()):
		if profiles[i] is Dictionary and str(profiles[i].get("model", "")) == model_name:
			profiles[i] = entry
			replaced = true
			break
	if not replaced:
		profiles.append(entry)
	var f := FileAccess.open("user://model_profiles.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(profiles, "\t"))

func _load_arena_cfg(base_cfg: Dictionary) -> Array:
	if FileAccess.file_exists("user://arena_config.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://arena_config.json"))
		if parsed is Array and not parsed.is_empty():
			return parsed
	var def_model := str(base_cfg.get("model", "qwen2.5:7b"))
	return [
		{"enabled": true, "name": "阿尔法", "model": def_model, "goal": ""},
		{"enabled": true, "name": "深空探索者", "model": def_model, "goal": ""},
		{"enabled": true, "name": "星海开拓者", "model": def_model, "goal": ""},
	]

func _save_arena_cfg(slot_inputs: Array[Dictionary]) -> void:
	var out: Array = []
	for si in slot_inputs:
		out.append({
			"enabled": si.enabled.button_pressed,
			"name": si.name.text.strip_edges(),
			"model": si.model.text.strip_edges(),
			"api_base": str(si.get("api_base", "")).strip_edges(),
			"api_key": str(si.get("api_key", "")).strip_edges(),
			"goal": si.goal.text.strip_edges(),
		})
	var f := FileAccess.open("user://arena_config.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "\t"))

func toggle_agent_takeover() -> void:
	if cli_agent_mode or not playing:
		return
	if agent_bridge == null:
		if is_instance_valid(takeover_button):
			takeover_button.button_pressed = false
		_open_smolagents_dialog()
	else:
		_stop_takeover()

func _start_takeover(cfg: Dictionary) -> void:
	if mobile_play:
		var issue := MobileModelAgent.config_issue(cfg)
		if not issue.is_empty():
			say(issue)
			return
	var dir := takeover_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	for fname in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(fname))
	var bridge := AgentBridge.new()
	bridge.game = self
	if not bridge.start(dir, true):
		if is_instance_valid(takeover_button):
			takeover_button.text = "托管: 关"
			takeover_button.button_pressed = false
		say("未能启动本地托管会话。")
		return
	agent_bridge = bridge
	if not is_instance_valid(agent_overlay):
		agent_overlay = CanvasLayer.new()
		add_child(agent_overlay)
		bridge.attach_watch(agent_overlay)
	if is_instance_valid(takeover_button):
		takeover_button.text = "托管: 开"
		takeover_button.button_pressed = true
	if mobile_play:
		mobile_runner = start_mobile_runner(bridge,cfg)
		mobile_runner.finished.connect(_mobile_takeover_finished.bind(mobile_runner), CONNECT_DEFERRED)
		say("正在连接 "+str(cfg.model)+"，再点「托管: 开」可收回控制。")
		refresh()
	elif bool(cfg.get("auto_launch", true)):
		var script := _smolagents_script()
		if script.is_empty():
			say("已开启托管会话（未找到 tools/smolagents_runner.py，可手动连接：" + dir + "）")
			return
		var py_args := PackedStringArray([
			script, "--session-dir", dir,
			"--api-base", str(cfg.get("api_base", "")),
			"--api-key", str(cfg.get("api_key", "")),
			"--model", str(cfg.get("model", "")),
			"--max-steps", str(int(cfg.get("max_steps", 40))),
			"--goal", str(cfg.get("goal", "")),
		])
		smolagents_pid = launch_agent_runner(py_args)
		if smolagents_pid > 0:
			say("已启动 smolagents 全流程托管（PID %d · 模型 %s），日志保存于会话目录。" % [smolagents_pid, str(cfg.get("model", ""))])
		else:
			say("托管程序启动失败，请检查发行包中的 tools/agent-runtime 目录。")
	else:
		say("已开启外部 Agent 桥接目录：" + dir)

func _stop_takeover() -> void:
	if is_instance_valid(mobile_runner):
		mobile_runner.stop()
		mobile_runner.queue_free()
		mobile_runner = null
	if smolagents_pid > 0 and OS.is_process_running(smolagents_pid):
		OS.kill(smolagents_pid)
	smolagents_pid = -1
	var dir := takeover_dir()
	for fname in ["ready.json", "request.json", "response.json", "client.lock"]:
		var fpath := dir.path_join(fname)
		if FileAccess.file_exists(fpath):
			DirAccess.remove_absolute(fpath)
	if agent_bridge != null:
		agent_bridge.active_step.clear()
		agent_bridge = null
	watch_pan = Vector2.ZERO
	watch_drag = false
	if is_instance_valid(agent_overlay):
		agent_overlay.queue_free()
		agent_overlay = null
	set_speed(0)
	if is_instance_valid(takeover_button):
		takeover_button.text = "托管: 关"
		takeover_button.button_pressed = false
	say("已停止模型托管，恢复手动操作。")
	refresh()

func _open_smolagents_dialog() -> void:
	var cfg := _load_smolagents_cfg()
	var dialog := AcceptDialog.new()
	dialog.title = "模型托管配置" if mobile_play else "smolagents 全流程托管配置"
	dialog.ok_button_text = "取消"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 340)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	var ep_row := hbox(box)
	title(ep_row, "API 地址", 14, DIM).custom_minimum_size.x = 88
	var ep_in := field(ep_row, str(cfg.api_base), 160)
	if mobile_play:
		ep_in.placeholder_text = "模型服务地址，含 /v1"
	var mod_row := hbox(box)
	title(mod_row, "模型名称", 14, DIM).custom_minimum_size.x = 88
	var mod_in := field(mod_row, str(cfg.model), 80)
	if mobile_play:
		mod_in.placeholder_text = "填写服务商提供的模型 ID"
	var key_row := hbox(box)
	title(key_row, "API Key", 14, DIM).custom_minimum_size.x = 88
	var key_in := field(key_row, str(cfg.api_key), 160)
	key_in.secret = true
	if mobile_play:
		key_in.placeholder_text = "按服务要求填写"
	var goal_row := hbox(box)
	title(goal_row, "经营目标", 14, DIM).custom_minimum_size.x = 88
	var goal_in := field(goal_row, str(cfg.goal), 240)
	var opt_row := hbox(box)
	title(opt_row, "最大轮次", 14, DIM).custom_minimum_size.x = 88
	var step_in := SpinBox.new()
	step_in.min_value = 0
	step_in.max_value = 999999
	step_in.suffix = " (0=不限)"
	step_in.value = int(cfg.max_steps)
	opt_row.add_child(step_in)
	var auto_cb := CheckButton.new()
	auto_cb.text = "自动拉起游戏内 smolagents"
	auto_cb.button_pressed = bool(cfg.auto_launch)
	opt_row.add_child(auto_cb)
	auto_cb.visible = not mobile_play
	var instructions := "填写兼容 Chat Completions、支持工具调用的模型服务。局域网电脑模型请填电脑 IP（含 /v1）。启动后会向该服务发送游戏状态；点「托管: 开」即可停止。" if mobile_play else "点击启动后将在后台自动运行 HuggingFace smolagents 并接管操作，无需切换窗口；再次点击顶栏「托管: 开」即可随时收回控制权。"
	title(box,instructions,12,DIM,true)
	var profiles := _load_model_profiles()
	if not profiles.is_empty():
		var prof_row := hbox(box)
		title(prof_row, "已保存模型", 13, DIM).custom_minimum_size.x = 88
		for prof in profiles:
			if prof is Dictionary:
				var pm := str(prof.get("model", ""))
				var pb := str(prof.get("api_base", ""))
				var pk := str(prof.get("api_key", ""))
				UIKit.action_button(prof_row, pm, func():
					ep_in.text = pb
					mod_in.text = pm
					key_in.text = pk, "ghost")
	var btn_row := hbox(box)
	UIKit.action_button(btn_row, "保存模型配置", func():
		var saved_cfg := {
			"api_base": ep_in.text.strip_edges(),
			"model": mod_in.text.strip_edges(),
			"api_key": key_in.text.strip_edges(),
			"goal": goal_in.text.strip_edges(),
			"max_steps": int(step_in.value),
			"auto_launch": auto_cb.button_pressed,
		}
		_save_smolagents_cfg(saved_cfg)
		_save_model_profile(saved_cfg)
		say("已保存模型配置与预设：" + str(saved_cfg.model)), "ghost")
	UIKit.action_button(btn_row, "启动全流程托管", func():
		var next_cfg := {
			"api_base": ep_in.text.strip_edges(),
			"model": mod_in.text.strip_edges(),
			"api_key": key_in.text.strip_edges(),
			"goal": goal_in.text.strip_edges(),
			"max_steps": int(step_in.value),
			"auto_launch": auto_cb.button_pressed,
		}
		if mobile_play:
			var issue := MobileModelAgent.config_issue(next_cfg)
			if not issue.is_empty():
				dialog.title = issue
				if mod_in.text.strip_edges().is_empty():
					mod_in.grab_focus()
				else:
					ep_in.grab_focus()
				return
		_save_smolagents_cfg(next_cfg)
		_save_model_profile(next_cfg)
		dialog.queue_free()
		_start_takeover(next_cfg), "primary", true, "", true)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

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
		set_tactics(not tactics.visible)

func set_tactics(expanded: bool) -> void:
	if expanded:
		system_chart = false
	if expanded == tactics.visible:
		return
	if expanded:
		var branch: Control = canvas
		while branch != layout:
			var container: Control = branch.get_parent()
			for sibling in container.get_children():
				if sibling != branch and sibling != tactics and sibling is Control and sibling.visible:
					tactical_hidden.append(sibling)
					sibling.hide()
			branch = container
	else:
		for control in tactical_hidden:
			if is_instance_valid(control):
				control.show()
		tactical_hidden.clear()
	tactics.visible = expanded

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

func set_waypoint(point: Vector2, label: String = "", tracking: Callable = Callable(), arrived: Callable = Callable()) -> void:
	waypoint = point
	waypoint_label = label
	waypoint_tracking = tracking
	waypoint_arrived = arrived
	waypoint_live = true
	if not label.is_empty():
		say("自动航点：" + label)

func track_port(station: Dictionary, auto_dock: bool = false) -> void:
	var ship := world.ride()
	var approach_range := world.StationGeometry.docking_range(ship.kind)
	var pid := int(station.id)
	var reached := func(gap: float) -> bool:
		var ok := gap <= approach_range and flight.nearby_port(ship) == pid
		if ok and auto_dock and waypoint_live and int(world.ride().get("dock", 0)) == 0 and not world.ride().get("locked", false):
			waypoint_live = false
			flight.dock()
		return ok
	set_waypoint(station.pos, station.name + (" [自动停靠]" if auto_dock else ""), func(): return station.pos, reached)

func track_planet(index: int, landing: bool = true) -> void:
	var ship: Dictionary = world.ride()
	var region: Dictionary = world.systems[ship.system]
	var body_data: Dictionary = region.planets[index]
	if landing and body_data.has("port_id"):
		track_port(world.ports[body_data.port_id])
		return
	var point := func() -> Vector2:
		return world.PlanetPorts.point(body_data) if landing else Celestial.survey_point(body_data,ship.pos)
	var reached := Callable()
	if landing:
		var approach_range := world.StationGeometry.docking_range(ship.kind)
		reached = func(gap: float) -> bool: return gap <= approach_range and flight.nearby_port(ship) == 0
	set_waypoint(point.call(),world.PlanetPorts.caption(world,ship.system,index) if landing else body_data.name,point,reached)

func track_construction_orbit(index: int) -> void:
	var ship: Dictionary = world.ride()
	var region: Dictionary = world.systems[ship.system]
	var planet: Dictionary = region.planets[index]
	var relative := Celestial.build_orbit_point(region,index,ship.pos) - Vector2(planet.pos)
	var point := func() -> Vector2: return Vector2(planet.pos) + relative
	set_waypoint(point.call(),planet.name+" 建站轨道",point)

func toggle_side_panel() -> void:
	side_collapsed = not side_collapsed
	if is_instance_valid(side_panel):
		side_panel.visible = not side_collapsed
	if is_instance_valid(side_toggle):
		side_toggle.text = "展开面板" if side_collapsed else "收起面板"

## One-click direct station navigation (intra-system or cross-system hyperspace).
func navigate_to_station(port_id: int) -> bool:
	var station: Dictionary = world.ports.get(port_id, {})
	var vessel: Dictionary = world.ride()
	if station.is_empty() or station.get("build", 0) > 0:
		say("目标空间站不存在或尚未竣工。")
		return false
	if vessel.is_empty():
		say("当前角色未驾驶旗舰，无法进行空间站导航。")
		return false
	if vessel.get("locked", false):
		say("交火锁定中，脱离战斗后才能启动直达导航。")
		return false
	if int(vessel.get("dock", 0)) == port_id:
		say("已停靠在 %s。" % station.name)
		return true
	if int(vessel.get("dock", 0)) != 0:
		flight.dock()
		if int(world.ride().get("dock", 0)) != 0:
			return false
	system_chart = false
	nav_target_port = port_id
	var target_sys := int(station.system)
	if not galaxy and int(vessel.system) == target_sys:
		track_port(station, nav_auto_dock)
		set_speed(maxi(1, speed))
		refresh()
		return true
	var enter_target := func() -> void:
		if not galaxy:
			return
		var s := world.ride()
		if s.is_empty():
			return
		if flight.nearby_system(s) == target_sys:
			flight.change_layer()
			if not galaxy and int(world.ride().system) == target_sys:
				track_port(world.ports[port_id], nav_auto_dock)
	if galaxy:
		set_waypoint(Vector2(world.systems[target_sys].pos), "超空间 → %s" % station.name, func(): return Vector2(world.systems[target_sys].pos), func(gap: float) -> bool:
			if gap <= 26.0 and flight.nearby_system(world.ride()) == target_sys:
				enter_target.call()
				return false
			return false)
		set_speed(maxi(1, speed))
		refresh()
		return true
	var grav: Vector2 = Celestial.gravity_point(world.systems[int(vessel.system)])
	set_waypoint(grav, "引力点跃迁 → %s" % station.name, func(): return grav, func(gap: float) -> bool:
		if gap <= float(Celestial.JUMP_RANGE) * 0.85:
			flight.change_layer()
			if galaxy:
				set_waypoint(Vector2(world.systems[target_sys].pos), "超空间 → %s" % station.name, func(): return Vector2(world.systems[target_sys].pos), func(hgap: float) -> bool:
					if hgap <= 26.0 and flight.nearby_system(world.ride()) == target_sys:
						enter_target.call()
						return false
					return false)
			return false
		return false)
	set_speed(maxi(1, speed))
	refresh()
	return true

func open_station_navigator() -> void:
	if not playing or world.succession:
		return
	var vessel: Dictionary = world.ride()
	if vessel.is_empty():
		say("当前未驾驶旗舰，无法使用直达导航。")
		return
	var dialog := AcceptDialog.new()
	dialog.title = "星区空间站直达导航"
	dialog.ok_button_text = "关闭"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 440)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	var top_opt := hbox(box)
	var search := LineEdit.new()
	search.text = nav_query
	search.placeholder_text = "输入空间站名或星系名筛选..."
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_opt.add_child(search)
	var auto_dock_cb := CheckButton.new()
	auto_dock_cb.text = "到达后自动停靠"
	auto_dock_cb.button_pressed = nav_auto_dock
	auto_dock_cb.toggled.connect(func(on: bool): nav_auto_dock = on)
	top_opt.add_child(auto_dock_cb)
	var model: Dictionary = Hulls.MODELS[vessel.kind]
	var cur_fuel := float(vessel.fuel)
	var list_box := scroller(box)
	var paint_list := func(q_raw: String) -> void:
		nav_query = q_raw.strip_edges()
		clear(list_box)
		var ports_arr: Array[Dictionary] = []
		for st in world.ports.values():
			if st.get("build", 0) > 0 or st.get("landing_only", false):
				continue
			var sname := "%s %s" % [st.name, world.systems[st.system].name]
			if not nav_query.is_empty() and nav_query not in sname:
				continue
			ports_arr.append(st)
		var cur_sys := int(vessel.system)
		ports_arr.sort_custom(func(a, b):
			var da := 0.0 if int(a.system) == cur_sys else world.distance(cur_sys, int(a.system))
			var db := 0.0 if int(b.system) == cur_sys else world.distance(cur_sys, int(b.system))
			if not is_equal_approx(da, db):
				return da < db
			return Vector2(vessel.pos).distance_to(a.pos) < Vector2(vessel.pos).distance_to(b.pos))
		for st in ports_arr.slice(0, mini(35, ports_arr.size())):
			var pid := int(st.id)
			var is_local := (not galaxy and int(st.system) == cur_sys)
			var hop_dist := 0.0 if is_local else (Vector2(vessel.galpos).distance_to(Vector2(world.systems[st.system].pos)) if galaxy else world.distance(cur_sys, int(st.system)))
			var fuel_need := 0.0 if is_local else Economy.Hyperspace.fuel_for_distance(model, hop_dist)
			var fuel_tone := "ok" if (is_local or cur_fuel >= fuel_need * 2.0) else ("warn" if cur_fuel >= fuel_need else "danger")
			var fuel_txt := "本星系免油" if is_local else ("耗油 %.0f · 充足" % fuel_need if fuel_tone == "ok" else ("耗油 %.0f · 仅单程" % fuel_need if fuel_tone == "warn" else "耗油 %.0f · 燃料不足" % fuel_need))
			var card := UIKit.card(list_box, UIKit.DANGER if world.hostile(int(vessel.flag), int(st.flag)) else (UIKit.OK if is_local else Color.TRANSPARENT), true)
			var row := hbox(card)
			var dist_txt := "本星系" if is_local else ("跨星系 %.0f" % hop_dist)
			var info_lbl := title(row, "%s · %s · %s（%s）" % [st.name, world.systems[st.system].name, world.flag_name(int(st.flag)), dist_txt], 13, INK)
			info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UIKit.badge(row, fuel_txt, fuel_tone)
			UIKit.action_button(row, "直达导航", func():
				dialog.queue_free()
				navigate_to_station(pid), "primary" if fuel_tone != "danger" else "danger")
	search.text_changed.connect(paint_list)
	paint_list.call(nav_query)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _collect_alerts() -> Array[Dictionary]:
	var alerts: Array[Dictionary] = []
	var actor: Dictionary = world.active()
	if actor.is_empty():
		return alerts
	var pending := Society.pending_count(world)
	if pending > 0:
		alerts.append({"tone": "gold", "label": "有 %d 项待决事务等待处理" % pending, "action_text": "去事务", "cb": func():
			system_chart = false; tab = "事务"; campaign_panel.section = 0; side_collapsed = false
			if is_instance_valid(side_panel): side_panel.show()
			refresh()})
	for ship in world.ships.values():
		if not world.can_operate(ship):
			continue
		var max_hp := float(world.HULL_HP[ship.kind])
		if float(ship.hp) < max_hp * 0.5:
			alerts.append({"tone": "danger", "label": "舰船 #%d %s 船体受损 (%d/%d)" % [ship.id, world.HULLS[ship.kind], ceili(ship.hp), int(max_hp)], "action_text": "查资产", "cb": func():
				system_chart = false; tab = "资产"; side_collapsed = false
				if is_instance_valid(side_panel): side_panel.show()
				refresh()})
		elif float(ship.fuel) < 18.0:
			alerts.append({"tone": "warn", "label": "舰船 #%d %s 燃料偏低 (%.0f)" % [ship.id, world.HULLS[ship.kind], float(ship.fuel)], "action_text": "查资产", "cb": func():
				system_chart = false; tab = "资产"; side_collapsed = false
				if is_instance_valid(side_panel): side_panel.show()
				refresh()})
	for st in world.ports.values():
		if st.build > 0 or st.get("landing_only", false):
			continue
		if not (world.oversees(st.owner) or int(st.get("manager", 0)) == world.player):
			continue
		var pid := int(st.id)
		if st.get("blockaded", false):
			alerts.append({"tone": "danger", "label": "空间站 %s 正遭封锁" % st.name, "action_text": "导航前往", "cb": func(): navigate_to_station(pid)})
		elif Economy.Industry.available(st, Economy.Industry.Ware.RATIONS) == 0:
			alerts.append({"tone": "warn", "label": "空间站 %s 缺乏口粮医疗" % st.name, "action_text": "导航前往", "cb": func(): navigate_to_station(pid)})
	for cb in world.campaign.get("casus_belli", {}).values():
		var fid := int(cb.get("firm_id", 0))
		if bool(cb.get("ready", false)) and int(world.firms.get(fid, {}).get("director", 0)) == world.player:
			alerts.append({"tone": "ok", "label": "%s 对 %s 的战争借口已就绪" % [world.firms[fid].name, world.flag_name(int(cb.target_flag))], "action_text": "去疆域", "cb": func():
				system_chart = false; tab = "疆域"; side_collapsed = false
				if is_instance_valid(side_panel): side_panel.show()
				refresh()})
	return alerts

func open_alerts_popup() -> void:
	if not playing:
		return
	var alerts := _collect_alerts()
	var dialog := AcceptDialog.new()
	dialog.title = "运营状态与异常告警"
	dialog.ok_button_text = "关闭"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 320)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	if alerts.is_empty():
		title(box, "当前舰队、空间站与公司运营一切正常，无待处理告警。", 14, UIKit.OK, true)
	else:
		var list_box := scroller(box)
		for item in alerts:
			var card := UIKit.card(list_box, UIKit.tone_color(str(item.tone)), true)
			var row := hbox(card)
			var lbl := title(row, str(item.label), 13, INK, true)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cb: Callable = item.cb
			UIKit.action_button(row, str(item.action_text), func():
				dialog.queue_free()
				cb.call(), "primary")
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func toggle_system_chart() -> void:
	if world.succession or galaxy:
		return
	set_tactics(false)
	system_chart = not system_chart
	chart_scale = 1.0
	chart_pan = Vector2.ZERO
	chart_target = {}
	refresh()
	update_bridge(0)

func select_chart_target(target: Dictionary) -> void:
	chart_target = target
	canvas.set("chart_selected",target)
	refresh()
	canvas.queue_redraw()

func navigate_chart_target() -> void:
	var ship := world.ride()
	if ship.is_empty() or chart_target.is_empty() or ship.system != current_system():
		return
	var destination := chart_target.duplicate()
	if destination.kind == "ship" and destination.id == ship.id:
		return
	if destination.kind == "port" and ship.dock == destination.id:
		say("旗舰已停靠在这里。")
		return
	if ship.dock != 0:
		flight.dock()
		if ship.dock != 0:
			return
	var region: Dictionary = world.systems[ship.system]
	match destination.kind:
		"port": track_port(world.ports[destination.id])
		"planet": track_planet(destination.id)
		"star","gravity": set_waypoint(Celestial.gravity_point(region),"恒星引力点")
		"field": set_waypoint(region.field,"矿带")
		"outlaw": set_waypoint(region.outlaw_base.pos,destination.name,func(): return region.outlaw_base.pos)
		"ship":
			var other: Dictionary = world.ships.get(destination.id,{})
			if other.is_empty() or other.id == ship.id:
				return
			set_waypoint(other.pos,destination.name,func(): return other.pos)
		"companion":
			var star: Dictionary = region.companion
			var side := Vector2(star.pos).direction_to(ship.pos)
			var approach := func() -> Vector2: return Vector2(star.pos)+side*(float(star.radius)+150.0)
			set_waypoint(approach.call(),destination.name,approach)
		_: set_waypoint(destination.pos,destination.name)
	set_speed(maxi(1,speed))
	refresh()

func update_chart_camera(region: Dictionary, ship_pos: Vector2) -> void:
	var frame: Rect2 = canvas.chart_bounds(region,ship_pos)
	canvas.zoom = minf(canvas.size.x/maxf(frame.size.x,1),canvas.size.y/maxf(frame.size.y,1))*0.85*chart_scale
	canvas.camera = frame.get_center()+chart_pan

func update_header() -> void:
	var vessel: Dictionary = world.ride()
	var actor: Dictionary = world.active()
	if is_instance_valid(header_portrait) and not actor.is_empty():
		header_portrait.look = Portrait.for_actor(world, actor)
	var hull := "未登舰"
	if not vessel.is_empty():
		hull = "#%d %s  船体 %d/%d  燃料 %d  余仓 %d" % [vessel.id, world.HULLS[vessel.kind], ceili(vessel.hp), world.HULL_HP[vessel.kind], floori(vessel.fuel), world.cargo_free(vessel)]
	header.text = "%s  ·  %s (%s)  ·  ¢%s  ·  %s" % [world.date_label(), world.name_of(world.player), world.flag_name(actor.get("flag", -1)), actor.get("wallet", 0), hull]
	var location: String = "超空间航行" if galaxy else world.systems[current_system()].name
	var wp_txt := ("  ·  航点: " + waypoint_label) if waypoint_live and not waypoint_label.is_empty() else ""
	status.text = "%s  |  %s%s" % [location, ("已暂停" if speed == 0 else "%dx" % speed), wp_txt]
	for i in range(speed_buttons.size()):
		if is_instance_valid(speed_buttons[i]):
			speed_buttons[i].button_pressed = (speed == i)
	if vessel.get("locked", false):
		status.text += "  [交火锁定]"
	if is_instance_valid(alerts_button):
		var alert_list := _collect_alerts()
		if alert_list.is_empty():
			alerts_button.text = "✓ 正常"
			alerts_button.add_theme_color_override("font_color", UIKit.OK)
		else:
			alerts_button.text = "⚠ %d" % alert_list.size()
			alerts_button.add_theme_color_override("font_color", UIKit.WARN)
	if is_instance_valid(dock_action_btn) and not vessel.is_empty():
		var near_pid := flight.nearby_port(vessel)
		if vessel.get("dock", 0) != 0:
			dock_action_btn.text = key_caption("离港","E")
		elif near_pid > 0 and world.ports.has(near_pid):
			dock_action_btn.text = key_caption("停靠 %s" % world.ports[near_pid].name,"E")
		else:
			dock_action_btn.text = key_caption("停靠 / 离港","E")
	if is_instance_valid(tabs):
		update_campaign_button()
		var ship_count := 0
		for owned in world.ships.values():
			if world.can_operate(owned):
				ship_count += 1
		for btn in tabs.get_children():
			if btn is Button and (btn.text == "资产" or btn.text.begins_with("资产 (")):
				btn.text = "资产 (%d)" % ship_count if ship_count > 0 else "资产"
	jump_button.text = key_caption("跃入星系" if galaxy else "引力点跃迁","M")
	jump_button.tooltip_text = "靠近星系信标后跃入。" if galaxy else "离港后前往恒星附近的引力点；必须进入 %d 范围。" % Celestial.JUMP_RANGE
	var objective := Story.objective(world)
	var watched := viewed_ship()
	if watch_ship_id > 0 and not watched.is_empty():
		location_banner.text = "实时视角：#%d %s（%s）" % [watched.id, world.HULLS[watched.kind], "超空间" if watched.get("layer", false) else world.systems[watched.system].name]
		if is_instance_valid(watch_button):
			watch_button.show()
	else:
		location_banner.text = Celestial.profile(world.systems[current_system()]).name
		if is_instance_valid(watch_button):
			watch_button.hide()

func refresh() -> void:
	if not playing:
		return
	if arena_display_suspended:
		arena_refresh_requested = true
		return
	var scroll_node: ScrollContainer = side_panel.get_node_or_null("Column/Scroll") if is_instance_valid(side_panel) else null
	if scroll_node != null:
		UIKit.scroll_pos[tab] = scroll_node.scroll_vertical
	clear(body)
	if not entity_menus.covered_panels.is_empty():
		button(body,"返回刚才的窗口",entity_menus.restore_panels)
	update_header()
	if is_instance_valid(tabs):
		for btn in tabs.get_children():
			if btn is Button:
				var is_cur: bool = btn.text == tab or btn.text.begins_with(tab + " (")
				btn.button_pressed = is_cur
				btn.add_theme_color_override("font_color", GOLD if is_cur else INK)
	var docked := dock_view.sync()
	if mobile_play and docked != mobile_was_docked:
		mobile_was_docked = docked
		if side_collapsed == docked:
			toggle_side_panel()
	if galaxy or world.succession:
		system_chart = false
	chart_button.visible = not galaxy and not world.succession
	chart_button.text = key_caption(("返回港口" if docked else "返回近景") if system_chart else "本星系星图","C")
	canvas.chart_mode = system_chart
	canvas.set("chart_selected",chart_target)
	tactics_button.visible = not galaxy and not world.succession
	if docked or galaxy or world.succession:
		set_tactics(false)
	quick_actions.visible = not docked and not tactics.visible
	if is_instance_valid(touch_deck):
		touch_deck.visible = agent_bridge == null and not docked and not tactics.visible and not system_chart and not world.succession and watch_ship_id == 0 and not world.ride().is_empty()
	if world.succession:
		hud.successor(body)
		if is_instance_valid(canvas):
			canvas.queue_redraw()
		return
	if system_chart:
		hud.chart(body)
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
		"事务": campaign_panel.show(body)
	if docked and tab != "港口" and dock_view.rendered.is_empty():
		dock_view.paint(world.ports[dock_view.station_id])
	if scroll_node != null:
		var saved_scroll := int(UIKit.scroll_pos.get(tab, 0))
		scroll_node.set_deferred("scroll_vertical", saved_scroll)

func step_simulation(move: Vector2, shield: bool, fire: bool, aim: Vector2, aiming: bool, boost: bool = false) -> void:
	flight.step(1.0 / 60.0, move, shield, fire, aim, aiming, boost)

func _physics_process(delta: float) -> void:
	if mobile_background:
		return
	if toast_timer > 0.0 and is_instance_valid(toast_panel):
		toast_timer -= delta
		if toast_timer <= 0.0:
			toast_panel.hide()
		elif toast_timer < 0.8:
			toast_panel.modulate.a = clampf(toast_timer / 0.8, 0.0, 1.0)
	if arena != null and arena.active:
		arena.poll(delta)
	if agent_bridge != null:
		agent_bridge.poll(delta)
	if not playing:
		return
	var cursor := canvas.visible and not tactics.visible and not system_chart and canvas.get_global_rect().has_point(get_global_mouse_position())
	var point: Vector2 = canvas.location(canvas.get_local_mouse_position()) if cursor else Vector2.ZERO
	if agent_bridge == null and is_instance_valid(touch_deck) and touch_deck.is_visible_in_tree():
		var aimed: bool = touch_deck.firing or fire_requested
		var touch_aim: Vector2 = touch_deck.world_point(touch_deck.aim_at) if aimed else Vector2.ZERO
		step_simulation(touch_deck.movement,touch_deck.shield,aimed,touch_aim,aimed,touch_deck.boost)
	elif agent_bridge == null:
		step_simulation(Input.get_vector(&"left", &"right", &"up", &"down"), Input.is_physical_key_pressed(KEY_SHIFT),
			cursor and (fire_requested or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)), point, cursor, Input.is_physical_key_pressed(KEY_CTRL))
	elif DisplayServer.get_name() != "headless" and canvas.visible and not tactics.visible:
		var pan_dir := Input.get_vector(&"left", &"right", &"up", &"down")
		if not pan_dir.is_zero_approx():
			var pan_speed := 420.0 / maxf(0.18, canvas.zoom if not canvas.chart_mode else chart_scale * 0.25)
			if canvas.chart_mode:
				chart_pan += pan_dir * pan_speed * delta
			else:
				watch_pan += pan_dir * pan_speed * delta
	fire_requested = false
	update_bridge(delta)

func update_bridge(delta: float) -> void:
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
	if world.active().get("loc", 0) != last_port:
		last_port = world.active().get("loc", 0)
		refresh()
	if world.day != last_day:
		last_day = world.day
		if tab == "事务" and campaign_panel.fleet_status_changed():
			refresh()
		else:
			update_header()
	if audio != null and world.combat_serial > last_audio_serial:
		var active_system := current_system()
		var listener: Vector2 = world.ride().get("pos",Vector2.ZERO)
		for i in range(maxi(0,world.combat_events.size() - (world.combat_serial - last_audio_serial)),world.combat_events.size()):
			var ev: Dictionary = world.combat_events[i]
			if int(ev.system) == active_system or ev.kind in ["trade", "dock"]:
				var offset: Vector2 = Vector2.ZERO if ev.kind in ["trade","dock"] else Vector2(ev.pos) - listener
				audio.play(str(ev.kind), float(ev.strength), offset)
		last_audio_serial = world.combat_serial
	if audio != null:
		var ship := world.ride()
		var fight: bool = ship.get("locked", false) and not galaxy and ship.get("dock", 0) == 0
		var pressure := 0.0
		if fight:
			var target: Dictionary = world.ships.get(ship.battle.get("target",selected_target),{})
			if not target.is_empty():
				pressure = clampf(float(Hulls.MODELS[target.kind].power)/maxf(1,Hulls.MODELS[ship.kind].power)*0.5,0,1)
		audio.mix_flight(fight,pressure,ship.get("battle",{}).get("vent",false) and speed != 0,delta)
	if world.player != 0 and canvas.visible and (agent_bridge == null or DisplayServer.get_name() != "headless"):
		var vessel: Dictionary = viewed_ship()
		var use_galaxy: bool = vessel.get("layer", false) if watch_ship_id > 0 else galaxy
		canvas.galaxy = use_galaxy
		canvas.chart_mode = system_chart and not use_galaxy
		canvas.zoom = galaxy_zoom if use_galaxy else flight_zoom
		var actor_port := int(world.active().get("loc", 0))
		var anchor_pos: Vector2 = world.ports[actor_port].pos if world.ports.has(actor_port) else Vector2.ZERO
		canvas.camera = (vessel.get("galpos", Vector2.ZERO) if use_galaxy else (vessel.pos if not vessel.is_empty() else anchor_pos)) + (watch_pan if agent_bridge != null and not canvas.chart_mode else Vector2.ZERO)
		if canvas.chart_mode:
			update_chart_camera(world.systems[current_system()],canvas.camera)
		canvas.queue_redraw()

func assets_changed() -> void:
	if tab == "资产" or tab == "港口":
		refresh()

func _input(event: InputEvent) -> void:
	if entity_menus.handle(get_window(),event):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(trade_table) and trade_table.is_visible_in_tree():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			trade_table.close()
			get_viewport().set_input_as_handled()
		return
	if mobile_play and playing and is_instance_valid(touch_deck) and touch_deck.is_visible_in_tree():
		if touch_deck.handle(event):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and canvas.get_global_rect().has_point(event.position):
			return
	if agent_bridge != null and mobile_play and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	InputController.handle(self,event)

func _notification(what: int) -> void:
	if not mobile_play or not is_inside_tree():
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_RESUMED]:
		mobile_background = what == NOTIFICATION_APPLICATION_PAUSED
		if is_instance_valid(arena):
			for child in arena.get_children():
				if child is MobileModelAgent:
					child.suspended = mobile_background
					if not mobile_background:
						child.request_time = Time.get_ticks_msec()
	if what == NOTIFICATION_APPLICATION_PAUSED and playing:
		if is_instance_valid(touch_deck):
			touch_deck.reset_input()
		set_speed(0)
		if not test_profile and not world.succession and not world.ride().get("locked",false):
			save_game(AUTO,true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var dialog := get_window().get_last_exclusive_window()
		if dialog != null and dialog != get_window():
			dialog.close_requested.emit()
		elif is_instance_valid(trade_table):
			trade_table.close()
		elif playing and tactics.visible:
			set_tactics(false)
		elif playing and system_chart:
			toggle_system_chart()
		elif playing:
			confirm_title()
		elif has_node("TitleMenu"):
			get_tree().quit()
		else:
			show_title()

func open_strategic_map(initial_mode: String = "strategic", enemy_flag: int = -1) -> void:
	if not playing or world.succession:
		return
	if not is_instance_valid(strategic_map):
		strategic_map = StrategicMap.new()
		add_child(strategic_map)
	strategic_map.setup(self, initial_mode, enemy_flag)
	if DisplayServer.get_name() != "headless":
		strategic_map.popup_centered()

func open_trade_table(kind: String = "station", id: int = -1, black: bool = false, ware: int = -1) -> void:
	open_trade_window(kind,id,black,ware,{})

func open_share_market(scope: String = "company", id: int = 0) -> void:
	open_trade_window("station",-1,false,-1,{"view":"market","scope":scope,"asset":id})

func open_equity_trade(scope: String, id: int, party: Variant = null, buying: bool = true, order_id: int = 0, price: int = 0, quantity: int = 1) -> void:
	open_trade_window("station",-1,false,-1,{"view":"order" if order_id > 0 else "negotiate","scope":scope,"asset":id,"party":party,"buying":buying,"order_id":order_id,"price":price,"quantity":quantity})

func open_equity_subscription(scope: String, id: int, offer_id: int, price: int, quantity: int = 1) -> void:
	open_trade_window("station",-1,false,-1,{"view":"subscription","scope":scope,"asset":id,"offer_id":offer_id,"price":price,"quantity":quantity})

func open_trade_window(kind: String, id: int, black: bool, ware: int, security: Dictionary) -> void:
	if not playing or world.succession or is_instance_valid(trade_table):
		return
	set_speed(0)
	trade_table = load("res://scripts/ui/trade_table.gd").new()
	add_child(trade_table)
	trade_table.open(self,kind,world.active().loc if id < 0 and kind == "station" else id,black,ware,security)

func save_game(path: String, silent: bool = false) -> bool:
	if not playing or cli_agent_mode:
		return false
	if world.ride().get("locked", false) and path != BEFORE:
		if not silent:
			say("交火中不能保存。")
		return false
	if mobile_play and arena != null and arena.active:
		arena._sync_campaign_slots()
	if not Saves.write(world, path, path == BEFORE):
		say("写入存档失败。")
		return false
	if not silent:
		say("已保存航区。")
	return true

func load_game(path: String) -> bool:
	if cli_agent_mode:
		return false
	if not Saves.read(world, path):
		say("读取失败。请选择本版本创建的有效存档。")
		return false
	if arena != null and arena.active:
		arena.stop_arena(false)
	if is_instance_valid(mobile_runner):
		_stop_takeover()
	run_bridge()
	say("已恢复同一宇宙；时间已暂停。")
	return true
