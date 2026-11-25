extends AcceptDialog

const Hulls = preload("res://hull_catalog.gd")
const WarPeace = preload("res://scripts/campaign/war_peace.gd")
const Hyperspace = preload("res://scripts/campaign/hyperspace.gd")

class MapCanvas:
	extends Control

	var owner_dialog
	var pan := Vector2.ZERO
	var zoom := 0.24
	var dragging := false
	var drag_moved := false
	var selected_port_id := 0
	var selected_ship_id := 0
	var hovered_port_id := 0
	var node_rects: Dictionary = {}
	var ship_rects: Dictionary = {}
	var context_regions: Array = []

	func context_at(pos: Vector2) -> Dictionary:
		for i in range(context_regions.size()-1,-1,-1):
			if context_regions[i].rect.has_point(pos):
				return context_regions[i].entity
		return {}

	func map_caption(font: Font, pos: Vector2, text: String, color: Color, kind: String, id: int, marker: Rect2) -> void:
		var rect := Rect2(pos-Vector2(0,font.get_ascent(11)),font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11))
		var entity: Dictionary = owner_dialog.game.entity_menus.ref_for(kind,id)
		context_regions.append({"rect":marker,"entity":entity})
		context_regions.append({"rect":rect,"entity":entity})
		draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,11,color)

	func _world_to_screen(pos: Vector2) -> Vector2:
		return size * 0.5 + (pos + pan) * zoom

	func _screen_to_world(screen: Vector2) -> Vector2:
		return (screen - size * 0.5) / maxf(0.05, zoom) - pan

	func _station_world_pos(world, station: Dictionary) -> Vector2:
		var region: Dictionary = world.systems[station.system]
		var ports_in_sys: Array = []
		for pid in region.ports:
			var st: Dictionary = world.ports.get(pid, {})
			if not st.is_empty() and st.build == 0:
				ports_in_sys.append(int(pid))
		var idx := ports_in_sys.find(int(station.id))
		if idx < 0 or ports_in_sys.size() <= 1:
			return Vector2(region.pos) + Vector2(0, -18)
		var angle := TAU * float(idx) / float(ports_in_sys.size()) - PI * 0.5
		var ring := 90.0 / maxf(0.15, zoom) * 0.32
		return Vector2(region.pos) + Vector2.from_angle(angle) * maxf(55.0, ring)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				var before := _screen_to_world(event.position)
				zoom = clampf(zoom * (1.18 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.18), 0.08, 1.4)
				var after := _screen_to_world(event.position)
				pan += after - before
				queue_redraw()
				accept_event()
				return
			if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
				if event.pressed:
					dragging = true
					drag_moved = false
				else:
					var clicked: bool = not drag_moved and event.button_index == MOUSE_BUTTON_LEFT
					dragging = false
					if clicked:
						_pick_at(event.position)
				accept_event()
				return
		if event is InputEventMouseMotion:
			if dragging:
				if event.relative.length_squared() > 1.0:
					drag_moved = true
				pan += event.relative / maxf(0.05, zoom)
				queue_redraw()
				accept_event()
				return
			var hit := _port_at(event.position)
			if hit != hovered_port_id:
				hovered_port_id = hit
				queue_redraw()

	func _port_at(pos: Vector2) -> int:
		for pid in node_rects:
			var rect: Rect2 = node_rects[pid]
			if rect.grow(6.0).has_point(pos):
				return int(pid)
		return 0

	func _ship_at(pos: Vector2) -> int:
		for sid in ship_rects:
			var rect: Rect2 = ship_rects[sid]
			if rect.grow(6.0).has_point(pos):
				return int(sid)
		return 0

	func _pick_at(pos: Vector2) -> void:
		var hit_ship := _ship_at(pos)
		if hit_ship != 0:
			selected_ship_id = hit_ship
			owner_dialog._on_ship_clicked(hit_ship)
			queue_redraw()
			return
		var hit := _port_at(pos)
		if hit != 0:
			selected_port_id = hit
			selected_ship_id = 0
			owner_dialog._on_station_clicked(hit)
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.09, 1.0))
		if owner_dialog == null or owner_dialog.game == null or owner_dialog.game.world == null:
			return
		var world = owner_dialog.game.world
		context_regions.clear()
		node_rects.clear()
		ship_rects.clear()
		# Diplomatic relationship lines between faction capitals
		for key: Vector2i in world.relations:
			var fa: Dictionary = world.factions.get(key.x, {})
			var fb: Dictionary = world.factions.get(key.y, {})
			if not fa.get("alive", false) or not fb.get("alive", false):
				continue
			var cap_a: Dictionary = world.ports.get(int(fa.get("capital", 0)), {})
			var cap_b: Dictionary = world.ports.get(int(fb.get("capital", 0)), {})
			if cap_a.is_empty() or cap_b.is_empty():
				continue
			var pa := _world_to_screen(_station_world_pos(world, cap_a))
			var pb := _world_to_screen(_station_world_pos(world, cap_b))
			var pact: Dictionary = world.relations[key]
			if int(pact.get("state", 0)) == -1:
				draw_dashed_line(pa, pb, Color(0.95, 0.30, 0.30, 0.65), 1.8, 7.0)
			elif int(pact.get("state", 0)) == 1:
				draw_line(pa, pb, Color(0.32, 0.85, 0.48, 0.55), 1.6, true)
			elif WarPeace.in_truce(world, key.x, key.y):
				draw_dashed_line(pa, pb, Color(0.88, 0.78, 0.35, 0.45), 1.2, 5.0)
		# System discs and names
		var font := ThemeDB.fallback_font
		for sys_idx in range(world.systems.size()):
			var region: Dictionary = world.systems[sys_idx]
			var center := _world_to_screen(region.pos)
			var sov: int = world.sovereign(sys_idx)
			var sys_col: Color = world.flag_color(sov) if sov >= 0 else Color(0.45, 0.50, 0.58)
			draw_circle(center, 18.0, Color(sys_col, 0.14))
			draw_arc(center, 18.0, 0.0, TAU, 24, Color(sys_col, 0.40), 1.2)
			draw_circle(center, 4.5, sys_col.darkened(0.15))
			map_caption(font,center+Vector2(-28,18),region.name,Color(0.68,0.76,0.85,0.85),"system",sys_idx,Rect2(center-Vector2(5,5),Vector2(10,10)))
		# Active war siege fleets
		for ship in world.ships.values():
			if ship.job.get("kind", "") == "攻城":
				var target_st: Dictionary = world.ports.get(ship.job.get("target", 0), {})
				if not target_st.is_empty():
					var p0 := _world_to_screen(ship.galpos if ship.layer else world.systems[ship.system].pos)
					var p1 := _world_to_screen(_station_world_pos(world, target_st))
					draw_dashed_line(p0, p1, world.flag_color(ship.flag).lightened(0.2), 1.6, 5.0)
		# Individual stations
		var peace_enemy := int(owner_dialog.current_war_enemy)
		var my_flag := int(owner_dialog.my_flag)
		for port_id in world.ports:
			var st: Dictionary = world.ports[port_id]
			if st.build != 0:
				continue
			var wp := _station_world_pos(world, st)
			var sp := _world_to_screen(wp)
			var region_pos := _world_to_screen(world.systems[st.system].pos)
			draw_line(region_pos, sp, Color(0.32, 0.40, 0.50, 0.45), 1.0)
			var owner_flag := int(st.flag)
			var col: Color = world.flag_color(owner_flag) if owner_flag >= 0 else Color(0.55, 0.60, 0.65)
			var is_capital := owner_flag >= 0 and int(world.factions.get(owner_flag, {}).get("capital", 0)) == int(port_id)
			var r := 9.0 if is_capital else 6.5
			if owner_dialog.map_mode == "peace" and peace_enemy >= 0:
				var rel_ok := owner_flag == my_flag or owner_flag == peace_enemy or int(st.get("occupied_from", -1)) in [my_flag, peace_enemy]
				if not rel_ok:
					col.a = 0.28
			if st.has("occupied_from"):
				var orig_flag := int(st.occupied_from)
				var orig_col: Color = world.flag_color(orig_flag) if orig_flag >= 0 else Color(0.5, 0.5, 0.5)
				draw_circle(sp, r, orig_col)
				draw_arc(sp, r, -PI * 0.5, PI * 0.5, 16, col, r, true)
				draw_arc(sp, r + 1.5, 0.0, TAU, 24, col, 2.0)
			else:
				draw_circle(sp, r, col)
				if is_capital:
					draw_arc(sp, r + 3.0, 0.0, TAU, 24, Color(0.98, 0.86, 0.45, 0.9), 1.6)
			if int(port_id) in owner_dialog.annex_selection:
				draw_arc(sp, r + 5.5, 0.0, TAU, 24, Color(1.0, 0.85, 0.25, 1.0), 2.5)
			elif int(port_id) in owner_dialog.release_selection:
				draw_arc(sp, r + 5.5, 0.0, TAU, 24, Color(0.35, 0.92, 0.72, 1.0), 2.5)
			elif int(port_id) == selected_port_id or int(port_id) == hovered_port_id:
				draw_arc(sp, r + 4.5, 0.0, TAU, 24, Color(0.95, 0.98, 1.0, 0.9), 1.8)
			node_rects[int(port_id)] = Rect2(sp - Vector2(r + 2, r + 2), Vector2((r + 2) * 2.0, (r + 2) * 2.0))
			var tag: String = st.name
			if int(port_id) in owner_dialog.annex_selection:
				tag += " [割让]"
			elif int(port_id) in owner_dialog.release_selection:
				tag += " [自由港]"
			elif st.has("occupied_from"):
				tag += " [占领]"
			var text_col := Color(0.95, 0.97, 1.0, 0.92 if col.a > 0.5 else 0.35)
			map_caption(font,sp+Vector2(r+4,4),tag,text_col,"port",port_id,node_rects[port_id])
		# Player-owned ships in flight
		for ship in world.ships.values():
			if ship.dock != 0 or not world.oversees(ship.owner):
				continue
			var wp_ship: Vector2 = Vector2(ship.galpos) if ship.layer else (Vector2(world.systems[ship.system].pos) + Vector2(ship.pos) * 0.04)
			var sp_ship := _world_to_screen(wp_ship)
			var scol := Color(0.40, 0.92, 0.98, 0.95)
			draw_circle(sp_ship, 4.5, scol)
			if int(ship.id) == selected_ship_id:
				draw_arc(sp_ship, 8.0, 0.0, TAU, 16, Color(1.0, 0.95, 0.45, 0.95), 1.8)
			ship_rects[int(ship.id)] = Rect2(sp_ship - Vector2(6, 6), Vector2(12, 12))
			map_caption(font,sp_ship+Vector2(7,4),"#%d %s" % [ship.id,world.HULLS[ship.kind]],scol,"ship",ship.id,ship_rects[ship.id])

var game
var map_mode := "strategic"
var my_flag := -1
var current_war_enemy := -1
var annex_selection: Array[int] = []
var release_selection: Array[int] = []
var demand_reparations := false
var open_trade_term := false
var canvas: MapCanvas
var info_box: VBoxContainer
var war_picker: OptionButton
var summary_label: Label
var station_label: Label
var terms_label: Label
var rep_check: CheckBox
var trade_check: CheckBox
var sign_btn: Button
var white_peace_btn: Button
var waypoint_btn: Button
var spectate_btn: Button
var mode_btn: Button

func setup(owner_game, initial_mode: String = "strategic", focus_enemy: int = -1) -> void:
	game = owner_game
	map_mode = initial_mode
	current_war_enemy = focus_enemy
	title = "战略地图与空间站局势" if map_mode == "strategic" else "和平谈判地图"
	min_size = Vector2i(980, 620)
	if canvas == null:
		_build_ui()
	_refresh_state()

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(left)

	var top_bar := HBoxContainer.new()
	left.add_child(top_bar)
	mode_btn = Button.new()
	mode_btn.pressed.connect(func():
		map_mode = "peace" if map_mode == "strategic" else "strategic"
		title = "战略地图与空间站局势" if map_mode == "strategic" else "和平谈判地图"
		_refresh_state())
	top_bar.add_child(mode_btn)

	var center_btn := Button.new()
	center_btn.text = "重置视角"
	center_btn.pressed.connect(_center_camera)
	top_bar.add_child(center_btn)

	var legend := Label.new()
	legend.text = "  拖拽平移 · 滚轮缩放 · 绿线=同盟 红线=交战 金虚线=休战 · 双色半圆=占领"
	legend.add_theme_font_size_override("font_size", 12)
	top_bar.add_child(legend)

	canvas = MapCanvas.new()
	canvas.owner_dialog = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(600, 500)
	left.add_child(canvas)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	info_box = VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 8)
	scroll.add_child(info_box)

	war_picker = OptionButton.new()
	war_picker.item_selected.connect(func(idx: int):
		current_war_enemy = war_picker.get_item_id(idx)
		annex_selection.clear()
		release_selection.clear()
		demand_reparations = false
		open_trade_term = false
		_refresh_state())
	info_box.add_child(war_picker)

	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(summary_label)

	station_label = Label.new()
	station_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(station_label)

	waypoint_btn = Button.new()
	waypoint_btn.text = "设为航行目标"
	waypoint_btn.pressed.connect(func():
		if canvas.selected_port_id > 0 and game != null:
			var st: Dictionary = game.world.ports.get(canvas.selected_port_id, {})
			if not st.is_empty():
				var ship: Dictionary = game.world.ride()
				if not ship.is_empty() and ship.dock == 0 and st.system == ship.system and not game.galaxy:
					game.set_waypoint(st.pos, st.name)
				else:
					game.set_waypoint(game.world.systems[st.system].pos, game.world.systems[st.system].name)
				game.say("已设定航点前往 " + st.name))
	info_box.add_child(waypoint_btn)

	spectate_btn = Button.new()
	spectate_btn.text = "实况观战该舰"
	spectate_btn.pressed.connect(func():
		if canvas.selected_ship_id > 0 and game != null:
			game.watch_ship_id = canvas.selected_ship_id
			game.refresh()
			hide())
	info_box.add_child(spectate_btn)

	terms_label = Label.new()
	terms_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(terms_label)

	rep_check = CheckBox.new()
	rep_check.text = "索要战争赔款（+18 分）"
	rep_check.toggled.connect(func(on: bool):
		demand_reparations = on
		_refresh_terms())
	info_box.add_child(rep_check)

	trade_check = CheckBox.new()
	trade_check.text = "解除商业禁运（+12 分）"
	trade_check.toggled.connect(func(on: bool):
		open_trade_term = on
		_refresh_terms())
	info_box.add_child(trade_check)

	sign_btn = Button.new()
	sign_btn.text = "签署和约"
	sign_btn.pressed.connect(func(): _submit_peace(false))
	info_box.add_child(sign_btn)

	white_peace_btn = Button.new()
	white_peace_btn.text = "提议白和平停战"
	white_peace_btn.pressed.connect(func(): _submit_peace(true))
	info_box.add_child(white_peace_btn)

	_center_camera()

func _center_camera() -> void:
	if game == null or game.world == null or game.world.systems.is_empty():
		return
	var avg := Vector2.ZERO
	for s in game.world.systems:
		avg += Vector2(s.pos)
	canvas.pan = -(avg / float(game.world.systems.size()))
	canvas.zoom = 0.24
	canvas.queue_redraw()

func _refresh_state() -> void:
	if game == null or game.world == null:
		return
	var world = game.world
	var actor: Dictionary = world.active()
	my_flag = int(actor.get("flag", -1))
	mode_btn.text = "切换到谈判地图" if map_mode == "strategic" else "切换到战略地图"
	var wars: Array[Dictionary] = []
	if my_flag >= 0:
		wars = WarPeace.active_wars(world, my_flag)
	war_picker.clear()
	for w in wars:
		war_picker.add_item("对 %s 之战" % world.flag_name(w.enemy), w.enemy)
	if not wars.is_empty():
		var found := -1
		for i in range(war_picker.item_count):
			if war_picker.get_item_id(i) == current_war_enemy:
				found = i
				break
		if found < 0:
			found = 0
			current_war_enemy = war_picker.get_item_id(0)
		war_picker.select(found)
	else:
		current_war_enemy = -1
	var in_peace := map_mode == "peace"
	war_picker.visible = in_peace and not wars.is_empty()
	terms_label.visible = in_peace
	rep_check.visible = in_peace and current_war_enemy >= 0
	trade_check.visible = in_peace and current_war_enemy >= 0
	sign_btn.visible = in_peace and current_war_enemy >= 0
	white_peace_btn.visible = in_peace and current_war_enemy >= 0
	waypoint_btn.visible = not in_peace and canvas.selected_port_id > 0
	spectate_btn.visible = canvas.selected_ship_id > 0

	if map_mode == "strategic":
		var lines: Array[String] = ["【全星域势力总览】"]
		for f_id in world.factions:
			var f: Dictionary = world.factions[f_id]
			if not f.alive:
				continue
			var count: int = world.systems_owned(f_id).size()
			var war_list: Array[String] = []
			for other_id in world.factions:
				if other_id != f_id and world.factions[other_id].alive:
					if world.hostile(f_id, other_id):
						war_list.append("战:" + world.flag_name(other_id))
					elif WarPeace.in_truce(world, f_id, other_id):
						war_list.append("休:" + world.flag_name(other_id))
			var tag := "（" + " ".join(war_list) + "）" if not war_list.is_empty() else ""
			lines.append("%s：%d 站 · 国库 %d %s" % [f.name, count, int(f.treasury), tag])
		summary_label.text = "\n".join(lines)
	else:
		if wars.is_empty():
			summary_label.text = "当前阵营未处于任何战争状态。"
		else:
			var active_w: Dictionary = {}
			for w in wars:
				if w.enemy == current_war_enemy:
					active_w = w
					break
			summary_label.text = "【战局详情：%s】\n已开战 %d 日\n己方战分 %.0f vs 敌方战分 %.0f\n己方厌战 %.0f%% | 敌方厌战 %.0f%%\n可用谈判预算：%d 分\n占领敌站：%d 座" % [
				world.flag_name(current_war_enemy), active_w.days,
				active_w.my_score, active_w.enemy_score,
				active_w.my_exhaustion, active_w.enemy_exhaustion,
				active_w.budget, active_w.occupied_by_me.size()]
	_refresh_station_info()
	_refresh_terms()
	canvas.queue_redraw()

func _refresh_station_info() -> void:
	if canvas.selected_ship_id > 0 and game.world.ships.has(canvas.selected_ship_id):
		var ship: Dictionary = game.world.ships[canvas.selected_ship_id]
		var loc_txt: String = "超空间" if ship.layer else game.world.systems[ship.system].name
		station_label.text = "【#%d %s】\n位置：%s | 任务：%s\n船体：%.0f/%.0f | 船长：%s" % [
			ship.id, game.world.HULLS[ship.kind], loc_txt, ship.job.get("kind", "待命"),
			float(ship.hp), float(game.world.HULL_HP[ship.kind]), game.world.name_of(ship.captain)]
		waypoint_btn.visible = false
		spectate_btn.visible = true
		return
	spectate_btn.visible = false
	if canvas.selected_port_id <= 0 or not game.world.ports.has(canvas.selected_port_id):
		station_label.text = "点击左侧地图上的空间站或青色船只查看详情" + ("（点击占领站循环：归还→割让→释放自由港）" if map_mode == "peace" else "")
		waypoint_btn.visible = false
		return
	var world = game.world
	var st: Dictionary = world.ports[canvas.selected_port_id]
	var occ_info := ""
	if st.has("occupied_from"):
		occ_info = "\n状态：战时占领（原属 %s）" % world.flag_name(int(st.occupied_from))
	var cost_info := ""
	if map_mode == "peace" and current_war_enemy >= 0 and int(st.get("occupied_from", -1)) == current_war_enemy and int(st.flag) == my_flag:
		cost_info = "\n割让 %d 分 | 释放自由港 %d 分" % [
			WarPeace.station_peace_cost(world, st.id, current_war_enemy),
			WarPeace.release_peace_cost(world, st.id, current_war_enemy)]
	station_label.text = "【%s】(%s)\n控制方：%s%s\n人口：%d | 稳定度：%.0f%% | 防御：%d%s" % [
		st.name, world.systems[st.system].name, world.flag_name(int(st.flag)),
		occ_info, int(st.pop), float(st.stability), int(st.defense), cost_info]
	waypoint_btn.visible = map_mode == "strategic"

func _refresh_terms() -> void:
	if map_mode != "peace" or current_war_enemy < 0:
		terms_label.text = ""
		return
	var world = game.world
	var can_govern: bool = world.Society.player_governs(world, my_flag)
	var check := WarPeace.preview_peace(world, my_flag, current_war_enemy, annex_selection, demand_reparations, release_selection, open_trade_term)
	var names: Array[String] = []
	for pid in annex_selection:
		names.append("割让:%s(%d)" % [world.ports[pid].name, WarPeace.station_peace_cost(world, pid, current_war_enemy)])
	for pid in release_selection:
		names.append("自由港:%s(%d)" % [world.ports[pid].name, WarPeace.release_peace_cost(world, pid, current_war_enemy)])
	var annex_text := "无（未勾选占领站将归还）" if names.is_empty() else "、".join(names)
	terms_label.text = "谈判条款：%s\n总计需求：%d 分 / 预算：%d 分\n状态：%s%s" % [
		annex_text, check.cost, check.budget, check.reason,
		"" if can_govern else "\n（需担任本国统治者或摄政才可签署和约）"]
	sign_btn.disabled = not can_govern or not check.accepted
	var wp_check := WarPeace.preview_peace(world, my_flag, current_war_enemy, [], false, [], false)
	white_peace_btn.disabled = not can_govern or not wp_check.accepted

func _on_ship_clicked(_ship_id: int) -> void:
	_refresh_station_info()

func _on_station_clicked(port_id: int) -> void:
	if map_mode == "peace" and current_war_enemy >= 0:
		var st: Dictionary = game.world.ports.get(port_id, {})
		if int(st.flag) == my_flag and int(st.get("occupied_from", -1)) == current_war_enemy:
			if port_id in annex_selection:
				annex_selection.erase(port_id)
				release_selection.append(port_id)
			elif port_id in release_selection:
				release_selection.erase(port_id)
			else:
				annex_selection.append(port_id)
	_refresh_station_info()
	_refresh_terms()

func _submit_peace(white_peace: bool) -> void:
	if current_war_enemy < 0 or game == null:
		return
	var ok := WarPeace.sign_peace(game.world, my_flag, current_war_enemy,
		[] if white_peace else annex_selection,
		false if white_peace else demand_reparations,
		[] if white_peace else release_selection,
		false if white_peace else open_trade_term)
	if ok:
		annex_selection.clear()
		release_selection.clear()
		demand_reparations = false
		open_trade_term = false
		game.say("已签署停战和约，详见纪事。")
		game.refresh()
		_refresh_state()
	else:
		game.say("对方拒绝了当前和谈条款。")
