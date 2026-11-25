extends SceneTree

const Game = preload("res://game.tscn")
var game
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func click(window: Window, pos: Vector2, side: int = MOUSE_BUTTON_RIGHT) -> void:
	var move := InputEventMouseMotion.new()
	move.position = pos
	window.push_input(move,true)
	var event := InputEventMouseButton.new()
	event.position = pos
	event.button_index = side
	event.pressed = true
	window.push_input(event,true)
	event.pressed = false
	window.push_input(event,true)

func active_menu(parent: Node) -> PopupMenu:
	for node in parent.find_children("*","PopupMenu",true,false):
		if node.has_meta("entity_popup") and node.visible and not node.is_queued_for_deletion():
			return node
	return null

func expect_menu(parent: Node, text: String, label: String) -> PopupMenu:
	var menu := active_menu(parent)
	check(menu != null and menu.get_item_text(0).contains(text),label)
	return menu

func point(label: Label, text: String) -> Vector2:
	var offset := label.text.find(text)
	return label.get_global_transform_with_canvas() * label.get_character_bounds(offset).get_center()

func run() -> void:
	game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var world = game.world
	world.new_game({"seed":"context-menus","systems":12,"factions":3})
	game.run_bridge()
	var ship: Dictionary = world.ride()
	var captain: Dictionary = world.active()
	captain.name = "冯望舒"
	var a: Dictionary = world.ports[ship.dock]
	var b: Dictionary = world.ports[world.systems[1].ports[0]]
	var other_id: int = world.random_person(world.NEUTRAL,a.id)
	var twin_id: int = world.random_person(world.NEUTRAL,a.id)
	world.people[other_id].name = "阮岑"
	world.people[twin_id].name = "阮岑"
	var cover := Panel.new()
	game.add_child(cover)
	cover.position = Vector2(60,100)
	cover.size = Vector2(290,330)
	var words: Label = game.title(cover,"%s 随行，目的地 %s。\n%s → %s\n阮岑 #%d · 阮岑" % [captain.name,b.name,a.name,b.name,other_id],18,Color.WHITE,true)
	words.size = Vector2(246,175)
	await process_frame
	await process_frame
	for data in [[captain.name,"查看角色档案"],[a.name,a.name],[b.name,b.name]]:
		click(root,point(words,data[0]))
		var menu := expect_menu(game,data[1],"actual right-click on "+str(data[0]))
		if menu: menu.hide()
		await process_frame
	var matching: Array = game.entity_menus.control_matches(words,words.get_character_bounds(words.text.find("阮岑")).get_center(),{})
	check(matching.size() == 1 and matching[0].id == other_id,"printed ID resolves namesakes")
	click(root,words.get_global_transform_with_canvas()*words.get_character_bounds(words.text.rfind("阮岑")).get_center())
	var chooser := active_menu(game)
	check(chooser != null and chooser.item_count == 2,"unqualified identical names require a choice")
	if chooser: chooser.hide()
	await process_frame
	var button: Button = game.button(cover,"#%d %s" % [ship.id,world.HULLS[ship.kind]],func(): cover.set_meta("left",true))
	button.position = Vector2(0,201)
	click(root,button.get_global_rect().get_center())
	var boat_menu := expect_menu(game,"#%d" % ship.id,"registry and model select the specific vessel")
	check(not cover.has_meta("left"),"right-click leaves primary action untouched")
	if boat_menu: boat_menu.hide()
	await process_frame
	click(root,button.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	check(cover.has_meta("left"),"left click still invokes the original action")
	var line := LineEdit.new()
	line.position = Vector2(0,250)
	line.size.x = 200
	line.text = captain.name
	cover.add_child(line)
	click(root,line.get_global_rect().get_center())
	check(active_menu(game) == null,"an editable name keeps its native editing menu")
	line.get_menu().hide()
	await process_frame
	var options: OptionButton = game.choice(cover,[a.name,b.name])
	options.position = Vector2(0,285)
	options.show_popup()
	await process_frame
	await process_frame
	var list := options.get_popup()
	click(list,Vector2(list.size.x*0.5,list.size.y*0.72))
	var listed := expect_menu(game,b.name,"expanded dropdown targets the row under the pointer")
	check(options.selected == 0,"inspecting an option preserves the selection")
	if listed: listed.hide()
	list.hide()
	await process_frame
	var dialog := AcceptDialog.new()
	game.add_child(dialog)
	var inner: Label = game.title(dialog,b.name)
	dialog.popup_centered(Vector2i(280,120))
	await process_frame
	await process_frame
	click(dialog,point(inner,b.name))
	var nested := expect_menu(dialog,b.name,"right-click works in a separate modal viewport")
	if nested: nested.hide()
	dialog.hide()
	dialog.queue_free()
	await process_frame
	game.open_trade_table("station",a.id)
	var table = game.trade_table
	var trade_person: Label = game.title(table,captain.name)
	trade_person.position = Vector2(60,60)
	await process_frame
	click(root,point(trade_person,captain.name))
	var trade_menu := expect_menu(game,"查看角色档案","trade window exposes character actions")
	if trade_menu:
		trade_menu.id_pressed.emit(1)
		check(not table.visible and game.hud.dossier.person_id == captain.id,"dossier appears above the suspended trade")
		game.entity_menus.restore_panels()
		check(table.visible and table == game.trade_table,"return restores the same trade session")
	table.close()
	cover.hide()
	world.depart(ship)
	game.refresh()
	ship.pos = Vector2(1000,1000)
	var other: Dictionary = world.ships[world.ship(1,0,0,world.NEUTRAL,ship.system,ship.pos+Vector2(120,0))]
	game.canvas.camera = ship.pos
	game.canvas.zoom = 1.0
	var local: Vector2 = game.canvas.screen(other.pos)
	check(game.canvas.context_at(local).get("id",0) == other.id,"local hull can be picked by shape")
	check(game.canvas.context_at(game.canvas.screen(ship.pos)).get("id",0) == ship.id,"own flagship can be inspected")
	var old_waypoint: bool = game.waypoint_live
	var old_target: int = game.selected_target
	await process_frame
	click(root,game.canvas.get_global_transform_with_canvas()*local)
	var contact := expect_menu(game,"#%d" % other.id,"a neutral ship gets its own menu")
	check(not world.enemy(ship,other) and game.selected_target == old_target and game.waypoint_live == old_waypoint,"inspection neither attacks, selects nor navigates")
	if contact: contact.hide()
	await process_frame
	game.set_tactics(true)
	await process_frame
	click(root,game.canvas.get_global_transform_with_canvas()*game.canvas.tactical_screen(other.pos))
	var tactical := expect_menu(game,"#%d" % other.id,"physical right-click on tactical ship")
	check(tactical != null and tactical.get_item_index(6) >= 0 and not world.enemy(ship,other),"tactical focus remains an explicit order")
	if tactical: tactical.hide()
	game.set_tactics(false)
	game.system_chart = true
	game.refresh()
	game.update_bridge(0.0)
	await process_frame
	game.canvas.update_chart_markers(world,world.systems[game.current_system()],ship)
	var marks = game.canvas.chart_markers
	var picked_planet := false
	for marker: Dictionary in marks:
		if marker.kind != "planet" or not Rect2(Vector2.ZERO,game.canvas.size).has_point(marker.at): continue
		click(root,game.canvas.get_global_transform_with_canvas()*marker.at)
		var chart := expect_menu(game,marker.name,"physical right-click on chart planet")
		picked_planet = chart != null
		if chart: chart.hide()
		break
	check(picked_planet,"chart includes a clickable planet")
	await process_frame
	if DisplayServer.get_name() != "headless":
		game.system_chart = false
		game.canvas.chart_mode = false
		game.canvas.galaxy = true
		game.canvas.camera = world.systems[1].pos
		game.canvas.zoom = 0.75
		game.canvas.queue_redraw()
		await RenderingServer.frame_post_draw
		var system_region := {}
		for hit in game.canvas.context_regions:
			if hit.entity.kind == "system" and hit.entity.id == 1: system_region = hit
		check(not system_region.is_empty(),"galaxy draws a selectable system label")
		if not system_region.is_empty():
			click(root,game.canvas.get_global_transform_with_canvas()*system_region.rect.get_center())
			var area_menu := expect_menu(game,world.systems[1].name,"galaxy label opens the named system")
			if area_menu: area_menu.hide()
		await process_frame
		game.open_strategic_map()
		var strategic = game.strategic_map
		var map = strategic.canvas
		map.pan = -map._station_world_pos(world,a)
		map.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var site_point: Vector2 = map.node_rects[a.id].get_center()
		# Stacked map markers follow the same draw order as ordinary mouse input.
		var drawn: Dictionary = map.context_at(site_point)
		click(strategic,map.get_global_transform_with_canvas()*site_point)
		var map_menu := expect_menu(strategic,game.entity_menus.entity_name(drawn),"strategic map opens the displayed marker")
		if map_menu: map_menu.hide()
		strategic.hide()
		await process_frame
	world.people[other_id].loc = b.id
	var old_wallet: int = captain.wallet
	var old_receiver: int = world.people[other_id].wallet
	game.hud.open_character_menu(other_id)
	var comm := active_menu(game)
	var gift_idx := -1
	for idx in comm.item_count:
		if comm.get_item_text(idx).contains("汇赠信用点"): gift_idx = idx
	check(gift_idx >= 0 and not comm.is_item_disabled(gift_idx),"remote gift is actionable while flying")
	if gift_idx >= 0: comm.id_pressed.emit(comm.get_item_id(gift_idx))
	var cost := int(world.Society.rules.personal_gift.cost)
	check(captain.wallet == old_wallet-cost and world.people[other_id].wallet == old_receiver+cost,"remote credit transfer balances both wallets")
	check(not world.Politics.influence(world,other_id,true),"remote gift honors the same cooldown")
	check(not world.Society.scheme(world,other_id,"find_secrets") and world.Society.scheme(world,other_id,"sway"),"remote diplomacy allows persuasion and keeps investigation local")
	var partner: Dictionary = world.people[other_id]
	partner.gender = 1-captain.gender
	partner.spouse = 0
	captain.spouse = 0
	partner.born = world.day-30*360
	partner.opinions[captain.id] = -100
	check(not world.Politics.marry(world,captain.id,other_id,true),"remote proposal honors a refusal")
	partner.opinions[captain.id] = 100
	var old_loc: int = partner.loc
	check(world.Politics.marry(world,captain.id,other_id,true) and captain.spouse == other_id and partner.loc == old_loc,"accepted remote proposal preserves location")
	game.free()
	print("Entity context menus ",checks-failures,"/",checks)
	quit(1 if failures else 0)
