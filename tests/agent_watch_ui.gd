extends SceneTree

const Game = preload("res://game.tscn")
const Watch = preload("res://scripts/ui/agent_watch.gd")
const Notice = preload("res://scripts/economy/freight_notice.gd")
var checks := 0
var failures := 0
var button_clicks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",reason)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280,720)
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	if game.agent_bridge!=null:
		await check_bridge_mode(game)
		finish(game)
		return
	var world = game.world
	world.new_game({"seed":"anchor","systems":16,"factions":4,"avatar":{"noble":false,"origin":0}})
	var source: Dictionary = world.ports[world.systems[2].ports[0]]
	world.berth(world.ride(),source.id)
	game.run_bridge()
	game.set_physics_process(false)
	await process_frame
	check(game.find_child("AgentWatch",true,false)==null,"ordinary play does not construct a spectator panel")
	var underneath := Button.new()
	underneath.size = Vector2(120,50)
	underneath.pressed.connect(func(): button_clicks+=1)
	game.add_child(underneath)
	var view := Watch.new()
	view.present({"intent":"核对本港市场"})
	game.add_child(view)
	view.bind_game(game)
	await process_frame
	underneath.global_position = view.global_position
	check(view.intent.text=="核对本港市场" and not view.action.get_parent().visible and not view.history.visible,"a state received before mounting displays without placeholder fields")
	var controls := view.find_children("*","Control",true,false)
	check(view.mouse_filter==Control.MOUSE_FILTER_IGNORE and controls.all(func(c):return c.mouse_filter==Control.MOUSE_FILTER_IGNORE and c.focus_mode==Control.FOCUS_NONE),"all spectator content ignores pointer and keyboard focus")
	var point := underneath.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for down in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		root.push_input(click,true)
	check(view.get_global_rect().has_point(point) and button_clicks==1,"pointer input reaches a real button behind the overlay")
	underneath.free()
	var notice := Notice.offer(world,source)
	if notice.is_empty():
		check(false,"the observed session has a real freight order")
	else:
		var dest: Dictionary = world.ports[notice.target]
		var history: Array[Dictionary] = [{"action":"检查采购委托","result":dest.name}]
		var signed := Notice.accept(world,notice)
		check(signed,"accept a real cross-system delivery for the observed state")
		history.append({"action":"接受委托","result":"%d 单位%s" % [notice.quantity,world.WARES[notice.ware]]})
		var before: int = world.active().wallet
		var units: int = world.Economy.trade(world,source.id,notice.ware,notice.quantity)
		check(units==notice.quantity,"the observed purchase physically fills the ship")
		history.append({"action":"购入%s" % world.WARES[notice.ware],"result":"支出 ¢%d" % (before-world.active().wallet)})
		world.depart(world.ride())
		game.refresh()
		var point_of_jump: Vector2 = world.Celestial.gravity_point(world.systems[source.system])
		var initial: float = world.ride().pos.distance_to(point_of_jump)
		game.set_waypoint(point_of_jump,"恒星引力点")
		game.set_speed(1)
		for i in 90:
			game.flight.step(1.0/60.0)
		var remaining: float = world.ride().pos.distance_to(point_of_jump)
		game.update_bridge(0)
		check(remaining<initial,"the observed ship actually moves toward its visible navigation marker")
		var state := {"intent":"运送%s到%s" % [world.WARES[notice.ware],dest.name],"target":world.systems[dest.system].name+" · "+dest.name,
			"action":"向恒星引力点推进","result":"距引力点 %d" % roundi(remaining),
			"history":history,"progress":1.0-remaining/initial,"progress_text":"至引力点  %d / %d" % [roundi(initial-remaining), roundi(initial)]}
		view.present(state)
		for i in 60:
			view.present(state)
		await process_frame
		await process_frame
		check(view.intent.text==state.intent and view.target.text==state.target and view.action.text==state.action and view.result.text==state.result and view.progress_text.text==state.progress_text and absf(view.progress_bar.value-state.progress)<0.001,"current intention, destination, action, result and distance progress follow the supplied state")
		check(view.history_rows[0].text.contains("购入") and view.history_rows[2].text.contains("检查采购委托") and view.find_children("*","Control",true,false).size()==controls.size(),"repeated progress snapshots reuse a fixed number of history rows in newest-first order")
		var bounds := view.get_global_rect()
		check(view.intent.size.y>=view.intent.get_line_height() and bounds.encloses(view.intent.get_global_rect()),"the full headline is visibly laid out and fits the panel")
		check(game.canvas.get_global_rect().encloses(bounds) and bounds.end.x<game.canvas.get_global_rect().get_center().x and bounds.size.y<root.size.y*0.5,"at 1280x720 the watch panel fits inside the scene with the central ship, radar and right sidebar clear")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var path := OS.get_temp_dir().path_join("starrail-agent-watch-1280x720.png")
			check(root.get_texture().get_image().save_png(path)==OK,"capture the 1280x720 composed game viewport")
			print("Watch UI capture ",path)
		history.append(history.back())
		history.append({"action":state.action,"result":state.result})
		view.present(state)
		check(view.history_rows[0].text.contains("购入") and view.history_rows[1].text.contains("接受委托"),"the current command and adjacent repeated results do not crowd out history")
		state.intent = "将已购买的引擎组件运抵收货港，按最新收购价结算并核对星系财政收取的关税。"
		state.result = "已从收货港结算整批货款和约定运费，共计四百一十九信用点。"
		view.present(state)
		await process_frame
		await process_frame
		check(view.intent.get_visible_line_count()==2 and view.result.get_visible_line_count()==2
				and view.get_global_rect().encloses(view.result.get_global_rect()) and view.get_global_rect().size.x==Watch.PANEL_WIDTH,
			"long Chinese intentions and outcomes wrap on two lines without widening the panel")
	view.present({})
	await process_frame
	await process_frame
	check(not view.history.visible and not view.progress_bar.visible and view.intent.text=="等待 Agent 下达指令","a fresh observation clears earlier results, history and navigation estimates")
	view.present({"action":"补充燃料","result":"已完成补给"})
	check(view.intent.text=="补充燃料" and not view.action.get_parent().visible and view.result.text=="已完成补给",
		"a legacy agent's confirmed action gets the headline once when no intention was supplied")
	finish(game)

func command(bridge, key: String, action: String, args: Dictionary = {}) -> Dictionary:
	if not bridge.publish("request.json",{"id":key,"action":action,"args":args}):
		return {}
	var response: String = bridge.directory.path_join("response.json")
	for i in 180:
		await physics_frame
		if FileAccess.file_exists(response):
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(response))
			DirAccess.remove_absolute(response)
			return data if data.get("id","")==key else {}
	return {}

func check_bridge_mode(game) -> void:
	var bridge = game.agent_bridge
	var watch_mode := "--agent-watch" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	var view := game.find_child("AgentWatch",true,false) as Watch
	check((view!=null)==watch_mode and bridge.watch_mode==watch_mode,"only a visible --agent-watch session installs the observer")
	var response := await command(bridge,"start","new_game",{"seed":"watch-real","systems":12,"factions":3})
	check(response.get("ok",false),"the normal bridge starts a session")
	if watch_mode:
		check(view.intent.text=="登记起航" and not view.action.get_parent().visible and view.result.text.contains("已停靠"),
			"a real command shows its action immediately even before the first explicit intention")
	response = await command(bridge,"intent","set_intent",{"text":"购入一批矿石","target":"晨曦自由港货栈"})
	check(response.get("ok",false),"the bridge accepts a declared intention")
	var wallet: int = game.world.active().wallet
	response = await command(bridge,"buy","trade",{"ware":0,"amount":1})
	var paid: int = wallet-game.world.active().wallet
	check(response.get("ok",false) and paid>0,"the normal command commits a real purchase")
	if watch_mode:
		check(view.intent.text=="购入一批矿石" and view.target.text=="晨曦自由港货栈" and view.action.text=="买入矿石"
				and view.result.text.contains("¢%d" % paid),"the actual command response appears with the real price and the declared destination")
		check(game.header.text.contains("¢%d" % game.world.active().wallet),
			"the visible bridge balance reflects the same settled purchase as the observer result")
		var row: Node = game.hud.market_rows[0].get_parent()
		check(game.dock_view.mode=="market" and row.get_node("ShipCargo").text==str(game.world.ride().cargo[0])
				and row.get_node("PortStock").text==str(game.world.ports[game.world.ride().dock].stock[0]),
			"the underlying warehouse shows the goods physically moved by the watched trade")
		var prior_result := view.result.text
		for i in 3:
			await command(bridge,"observe%d" % i,"observe")
		check(view.action.text=="买入矿石" and view.result.text==prior_result,"bridge observation polling does not erase activity or add history")
		response = await command(bridge,"frame","watch_frame")
		var image_path: String = bridge.directory.path_join("watch.png")
		check(response.get("ok",false) and FileAccess.file_exists(image_path),"the live watch command captures the composed panel")
		print("Live watch capture ",image_path)
		response = await command(bridge,"yard","ship_quote",{"hull_id":game.world.ride().hull_id})
		await process_frame
		await process_frame
		check(response.get("ok",false) and response.result.get("price",0)>0 and game.dock_view.mode=="yard"
				and view.action.text=="查看造船报价" and view.result.text.contains("¢%d" % response.result.price),
			"a live hull quote shows the shipyard and the exact quoted price")
		var panel_rect := view.get_global_rect()
		check(is_instance_valid(view.sidebar_slot) and view.sidebar_slot.get_global_rect().encloses(panel_rect)
				and not game.dock_view.stage.get_global_rect().intersects(panel_rect) and not game.body.get_parent().get_global_rect().intersects(panel_rect),
			"the shipyard reserves a sidebar slot, leaving the underlying ship details and scrollable controls visible")
		if "--capture" in OS.get_cmdline_user_args():
			var yard_path: String = bridge.directory.path_join("yard.png")
			await capture_live(yard_path)
			print("Live shipyard capture ",yard_path)
		await command(bridge,"route-intent","set_intent",{"text":"把矿石运到炉心转运站","target":"炉心转运站"})
		var departure := await command(bridge,"depart","depart")
		var waypoint := await command(bridge,"gravity","waypoint",{"kind":"gravity"})
		check(departure.get("ok",false) and waypoint.get("ok",false),"the real bridge undocks and sets a gravity-point waypoint")
		var sample := {"updates":0,"has_progress":false,"captured":false}
		var live_path: String = bridge.directory.path_join("flight.png")
		bridge.step_progress.connect(func(_processed: int, _ticks: int):
			sample.updates+=1
			if view.progress_bar.visible and view.progress_bar.value>0 and view.progress_text.text.begins_with("距航点"):
				sample.has_progress = view.action.text=="沿航线飞行" and view.target.text=="恒星引力点"
				if view.progress_bar.value>=0.07 and not sample.captured and "--capture" in OS.get_cmdline_user_args():
					sample.captured = true
					capture_live.call_deferred(live_path))
		response = await command(bridge,"fly","step",{"ticks":60,"speed":1,"stop":"never"})
		check(response.get("ok",false) and sample.has_progress and sample.updates>1 and sample.updates<60
				and view.result.text=="本段指令结束","a real flight shows intermediate route progress and its final result without logging every physics tick")
		if "--capture" in OS.get_cmdline_user_args():
			check(FileAccess.file_exists(live_path),"capture a rendered frame during the live route")
			print("Live flight capture ",live_path)
	else:
		check(game.agent_overlay==null and game.find_child("AgentWatch",true,false)==null,"the default private session performs commands without a spectator overlay")

func capture_live(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func finish(game) -> void:
	game.free()
	print("Agent spectator UI %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
