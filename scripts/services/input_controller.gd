extends RefCounted

const Battle = preload("res://combat.gd")
const Celestial = preload("res://celestial.gd")
const MIN_FLIGHT_ZOOM := 0.18
const MAX_FLIGHT_ZOOM := 1.65

static func _handle_canvas_zoom(game, event: InputEvent) -> bool:
	if not (event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		return false
	if not (game.canvas.visible and not game.tactics.visible and game.canvas.get_global_rect().has_point(game.get_global_mouse_position())):
		return false
	if game.canvas.chart_mode:
		var cursor: Vector2 = game.canvas.get_local_mouse_position()
		var before: Vector2 = game.canvas.location(cursor)
		game.chart_scale = clampf(game.chart_scale * (1.3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.3), 1.0, 40.0)
		game.update_bridge(0)
		game.chart_pan = Vector2.ZERO if game.chart_scale <= 1.0 else game.chart_pan + before - game.canvas.location(cursor)
		game.update_bridge(0)
		game.get_viewport().set_input_as_handled()
		return true
	var scale_factor := 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
	if game.canvas.galaxy:
		game.galaxy_zoom = clampf(game.galaxy_zoom * scale_factor, 0.18, 1.35)
		game.canvas.zoom = game.galaxy_zoom
	else:
		game.flight_zoom = clampf(game.flight_zoom * scale_factor, MIN_FLIGHT_ZOOM, MAX_FLIGHT_ZOOM)
		game.canvas.zoom = game.flight_zoom
	game.canvas.queue_redraw()
	game.get_viewport().set_input_as_handled()
	return true

static func _handle_watch_input(game, event: InputEvent) -> void:
	if DisplayServer.get_name() == "headless" or not game.playing:
		game.get_viewport().set_input_as_handled()
		return
	if game.glossary.handle(event):
		game.get_viewport().set_input_as_handled()
		return
	if _handle_canvas_zoom(game, event):
		return
	if event is InputEventMouseButton:
		var in_canvas: bool = game.canvas.visible and not game.tactics.visible and game.canvas.get_global_rect().has_point(event.position)
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed and in_canvas:
				game.watch_drag = true
				if game.system_chart and event.button_index == MOUSE_BUTTON_LEFT:
					var selected: Dictionary = game.canvas.chart_pick(game.canvas.get_local_mouse_position())
					if not selected.is_empty():
						game.select_chart_target(selected)
				game.get_viewport().set_input_as_handled()
				return
			elif not event.pressed and game.watch_drag:
				game.watch_drag = false
				game.get_viewport().set_input_as_handled()
				return
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and in_canvas:
			game.watch_pan = Vector2.ZERO
			game.chart_pan = Vector2.ZERO
			game.watch_drag = false
			game.update_bridge(0)
			game.get_viewport().set_input_as_handled()
			return
		# Allow UI clicks/scrolls outside canvas (e.g. side panel tabs, takeover button)
		return
	if event is InputEventMouseMotion:
		if game.watch_drag:
			var delta_pan: Vector2 = -event.relative / maxf(0.18, game.canvas.zoom)
			if game.canvas.chart_mode:
				game.chart_pan += delta_pan
			else:
				game.watch_pan += delta_pan
			game.update_bridge(0)
			game.get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			return
		if event.pressed and not event.echo:
			match key:
				KEY_C:
					game.toggle_system_chart()
					game.watch_pan = Vector2.ZERO
				KEY_ESCAPE:
					if game.system_chart:
						game.toggle_system_chart()
				KEY_R, KEY_HOME:
					game.watch_pan = Vector2.ZERO
					game.chart_pan = Vector2.ZERO
					game.watch_ship_id = 0
					game.update_bridge(0)
		game.get_viewport().set_input_as_handled()
		return
	game.get_viewport().set_input_as_handled()

static func handle(game, event: InputEvent) -> void:
	var world = game.world
	var flight = game.flight
	if game.agent_bridge != null:
		_handle_watch_input(game, event)
		return
	if not game.playing:
		return
	if game.glossary.handle(event):
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.canvas) and game.canvas.has_method("tactical_input") and game.canvas.tactical_input(event):
		game.get_viewport().set_input_as_handled()
		return
	if _handle_canvas_zoom(game, event):
		return
	if game.system_chart and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and game.canvas.get_global_rect().has_point(game.get_global_mouse_position()):
		var cursor: Vector2 = game.canvas.get_local_mouse_position()
		var selected: Dictionary = game.canvas.chart_pick(cursor)
		if selected.is_empty() and event.button_index == MOUSE_BUTTON_RIGHT:
			selected = {"kind":"point","id":0,"pos":game.canvas.location(cursor),"name":"自定航点"}
		game.select_chart_target(selected)
		if event.button_index == MOUSE_BUTTON_RIGHT and world.ride().get("dock",-1) == 0:
			game.navigate_chart_target()
		game.get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var vessel: Dictionary = world.ride()
		if game.canvas.visible and game.canvas.get_global_rect().has_point(game.get_global_mouse_position()):
			var cursor: Vector2 = game.canvas.get_local_mouse_position()
			var world_pos: Vector2 = game.canvas.location(cursor)
			var zoom_val: float = maxf(0.15, float(game.canvas.zoom))
			if game.galaxy:
				var hit_sys := -1
				var best_d := 26.0 / zoom_val
				for sid in range(world.systems.size()):
					var d := world_pos.distance_to(world.systems[sid].pos)
					if d <= best_d:
						best_d = d
						hit_sys = sid
				if hit_sys >= 0:
					game.hud.open_location_menu(0, hit_sys)
					game.get_viewport().set_input_as_handled()
					return
			else:
				var sys_id := int(game.current_system())
				var region: Dictionary = world.systems[sys_id]
				var ship_r := maxf(24.0, 26.0 / zoom_val)
				var hit_ship: int = flight.target_at(vessel, world_pos, ship_r, true) if not vessel.is_empty() else 0
				if hit_ship != 0:
					game.hud.open_ship_menu(hit_ship)
					game.get_viewport().set_input_as_handled()
					return
				for pid in region.ports:
					var st: Dictionary = world.ports[pid]
					if world_pos.distance_to(st.pos) <= maxf(38.0, 32.0 / zoom_val):
						game.hud.open_location_menu(int(pid), sys_id)
						game.get_viewport().set_input_as_handled()
						return
				for wid in world.wrecks:
					var wr: Dictionary = world.wrecks[wid]
					if int(wr.get("system", -1)) == sys_id and (wr.stock.max() > 0 or int(wr.get("hull", -1)) >= 0) and world_pos.distance_to(wr.pos) <= maxf(28.0, 24.0 / zoom_val):
						game.hud.open_space_object_menu("wreck", int(wid), sys_id)
						game.get_viewport().set_input_as_handled()
						return
				for p_idx in range(region.planets.size()):
					var pl: Dictionary = region.planets[p_idx]
					if world_pos.distance_to(pl.pos) <= maxf(float(pl.radius) + 14.0, 26.0 / zoom_val):
						game.hud.open_location_menu(int(pl.get("port_id", 0)), sys_id, p_idx)
						game.get_viewport().set_input_as_handled()
						return
				if world_pos.distance_to(region.field) <= maxf(42.0, 30.0 / zoom_val):
					game.hud.open_space_object_menu("field", 0, sys_id)
					game.get_viewport().set_input_as_handled()
					return
				if world_pos.distance_to(Celestial.gravity_point(region)) <= maxf(44.0, 30.0 / zoom_val):
					game.hud.open_space_object_menu("gravity", 0, sys_id)
					game.get_viewport().set_input_as_handled()
					return
			if not vessel.is_empty() and vessel.dock == 0:
				game.set_waypoint(world_pos)
				game.get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var vessel: Dictionary = world.ride()
		if game.canvas.visible and not game.system_chart and not game.galaxy and not vessel.is_empty() and vessel.dock == 0 and game.canvas.get_global_rect().has_point(game.get_global_mouse_position()):
			var aim: Vector2 = game.canvas.location(game.canvas.get_local_mouse_position())
			var id: int = flight.target_at(vessel,aim,52.0,true)
			if id != 0:
				game.selected_target = id
			game.fire_requested = game.speed > 0
	if event is InputEventKey and event.pressed and not event.echo:
		var focused: Control = game.get_viewport().gui_get_focus_owner()
		if focused is LineEdit or (focused is OptionButton and focused.get_popup().visible):
			return
		var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var vessel: Dictionary = world.ride()
		var local: bool = not game.galaxy and not vessel.is_empty() and vessel.dock == 0
		match key:
			KEY_W, KEY_A, KEY_S, KEY_D:
				if game.autopilot:
					game.set_autopilot(false, true)
					game.say("已切回手动驾驶。")
				if game.watch_ship_id > 0:
					game.watch_ship_id = 0
					game.refresh()
					game.say("已切回旗舰视角操控。")
				return
			KEY_SPACE: game.toggle_pause()
			KEY_C: game.toggle_system_chart()
			KEY_M: flight.change_layer()
			KEY_E: flight.dock()
			KEY_G: flight.salvage()
			KEY_F5: game.save_game(game.SAVE)
			KEY_F9: game.load_game(game.SAVE)
			KEY_F12:
				game.open_cheat_console()
				game.get_viewport().set_input_as_handled()
			KEY_TAB:
				game.toggle_tactics()
				game.get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if game.system_chart:
					game.toggle_system_chart()
				else:
					game.set_tactics(false)
			KEY_V:
				if local and game.speed == 1 and Battle.vent(vessel):
					world.combat_event("vent",vessel.pos,vessel.system)
					game.say("主动排散：武器和护盾下线。")
			KEY_F:
				if local and game.speed == 1 and not game.tactics.visible:
					var aim := Vector2.INF
					var preferred: int = game.selected_target
					var spec := Battle.Abilities.profile(vessel)
					if game.canvas.get_global_rect().has_point(game.get_global_mouse_position()):
						aim = game.canvas.location(game.canvas.get_local_mouse_position())
						var pointed: int = flight.target_at(vessel, aim, 8.0, spec.effect == "lash")
						if pointed != 0:
							preferred = pointed
					var direction := Input.get_vector(&"left", &"right", &"up", &"down")
					var switching_off: bool = spec.get("toggle",false) and vessel.battle.system_time > 0.0
					if Battle.system(world, vessel, direction, aim, preferred):
						game.say(("已关闭" if switching_off else "已启动") + Battle.system_label(vessel))
			KEY_1, KEY_2, KEY_3:
				if local:
					var group := key - int(KEY_1) + 1
					if flight.select_group(vessel,group,event.shift_pressed) and event.shift_pressed:
						game.say("编组 %d 自动索敌：%s" % [group, "开" if vessel.fit.auto[group-1] else "关"])
			KEY_0, KEY_Q:
				if local:
					flight.select_group(vessel, 0, event.shift_pressed)
					if event.shift_pressed:
						game.say("全部武器组自动索敌：%s" % ("开" if vessel.fit.auto[0] else "关"))
					else:
						game.say("武器模式：%s" % ("全武器组齐射" if vessel.battle.group == 0 else "单组 %d" % vessel.battle.group))
			KEY_H:
				if not vessel.is_empty() and vessel.dock == 0:
					vessel.battle.silent_running = not vessel.battle.get("silent_running",false)
					game.say("已转入静默航行。" if vessel.battle.silent_running else "已恢复标准航行。")
			KEY_T:
				if not vessel.is_empty() and vessel.dock == 0:
					vessel.transponder = not vessel.transponder
					game.say("应答器已开启：正规港允许停靠。" if vessel.transponder else "应答器已关闭：雷达特征降低，正规港禁止停靠。")
					game.update_header()
			KEY_R:
				flight.sensor_ping()
			KEY_U:
				game.toggle_autopilot()
			KEY_N:
				game.open_station_navigator()
			_: return
		game.get_viewport().set_input_as_handled()
