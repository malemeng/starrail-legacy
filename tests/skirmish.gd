extends SceneTree

const Game = preload("res://game.tscn")
const Hulls = preload("res://hull_catalog.gd")
const Menu = preload("res://scripts/ui/skirmish_menu.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
	return ok

func find_button(parent: Node, caption: String) -> Button:
	for item: Button in parent.find_children("*","Button",true,false):
		if item.text==caption and item.is_visible_in_tree():
			return item
	return null

func pointer(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event:=InputEventMouseButton.new()
	event.position=point
	event.button_index=button
	event.pressed=pressed
	root.push_input(event,true)

func touch(point: Vector2, index: int, pressed: bool) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=index
	event.position=point
	event.pressed=pressed
	root.push_input(event,true)

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.world.new_game({"seed":"preserve-skirmish","factions":3,"systems":12})
	var initial := var_to_bytes(game.world.snapshot())
	game.show_title()
	var title_button := find_button(game,"战斗沙盘")
	if not check(title_button!=null,"main menu offers skirmish"):
		quit(1)
		return
	title_button.pressed.emit()
	await process_frame
	var menu: Menu = game.find_child("Skirmish",true,false)
	if not check(menu!=null,"enter lineup editor via title button"):
		quit(1)
		return
	for side in 2:
		menu.rosters[side].clear()
		menu.refresh_roster(side)
	check(menu.start_button.disabled,"two empty teams cannot start")
	check(menu.grid.get_child_count()==menu.PAGE_SIZE and menu.grid.get_child(0).find_children("*","TextureRect",true,false).size()==1,"first gallery page presents actual ship silhouettes")
	menu.next_page.pressed.emit()
	check(menu.page==1,"catalog pagination browses further hulls")
	menu.search.text="condor"
	menu.search.text_changed.emit("condor")
	menu.grid.get_child(0).pressed.emit()
	check(menu.matches.size()>0 and menu.wings.visible,"tap a matching carrier card to inspect its bays")
	for i in menu.wings.item_count:
		if menu.wings.get_item_metadata(i)=="claw_wing": menu.wings.select(i)
	menu.qty.value=2
	menu.add_buttons[0].pressed.emit()
	check(menu.rosters[0].size()==1 and menu.rosters[0][0].count==2 and menu.rosters[0][0].wing=="claw_wing","selected hull quantity and wing loadout recorded")
	var right: Dictionary=menu.controls[1]
	menu.search.text="no-such-hull"
	menu.search.text_changed.emit(menu.search.text)
	check(menu.matches.is_empty() and menu.add_buttons[1].disabled,"empty search cannot add a phantom hull")
	right.station.select(1)
	right.station.item_selected.emit(1)
	check(not menu.start_button.disabled,"station alone is a valid opposing force")
	menu.start_button.pressed.emit()
	await process_frame
	var b=menu.battle
	b.set_physics_process(false)
	check(b.world!=game.world and b.tally(0).ships==2 and b.tally(1).modules==3,"exact selected ships and station modules entered an isolated battle")
	check(b.world.ships.values().all(func(ship): return ship.flag!=b.world.NEUTRAL or ship.fit.wings.all(func(id): return id=="claw_wing")),"actual deployed carriers use selected squadrons")
	var fired := false
	var airborne := false
	for frame in 600:
		b._physics_process(1.0/60)
		fired = fired or not b.world.projectiles.is_empty()
		airborne = airborne or b.tally(0).aircraft>0 or b.tally(1).aircraft>0
	check(fired and airborne,"two AI sides fight and launch actual aircraft")
	menu.pause_button.pressed.emit()
	var previous: float=b.elapsed
	b._physics_process(1.0/60)
	check(b.paused and b.elapsed==previous,"pause freezes simulation")
	var follow: Dictionary=b.world.ships.values().filter(func(s): return s.flag==b.world.NEUTRAL).front()
	var at: Vector2=b.get_global_transform_with_canvas() * (b.space.transform * Vector2(follow.pos))
	var move:=InputEventMouseMotion.new()
	move.position=at
	root.push_input(move,true)
	pointer(at,MOUSE_BUTTON_LEFT,true)
	pointer(at,MOUSE_BUTTON_LEFT,false)
	check(b.tracked_id==follow.id and b.view_center.is_equal_approx(follow.pos),"clicking a unit locks the camera to that exact ship")
	var scale_before: float=b.space.scale.x
	pointer(at,MOUSE_BUTTON_WHEEL_UP,true)
	pointer(at,MOUSE_BUTTON_WHEEL_UP,false)
	check(b.space.scale.x>scale_before and b.tracked_id==follow.id,"mouse wheel enlarges a locked ship while paused")
	var center: Vector2=b.get_global_rect().get_center()
	touch(center-Vector2(40,0),0,true)
	touch(center+Vector2(40,0),1,true)
	var pinch:=InputEventScreenDrag.new()
	pinch.index=1
	pinch.position=center+Vector2(85,0)
	pinch.relative=Vector2(45,0)
	scale_before=b.space.scale.x
	root.push_input(pinch,true)
	touch(center+Vector2(85,0),1,false)
	touch(center-Vector2(40,0),0,false)
	check(b.space.scale.x>scale_before and b.tracked_id==follow.id,"two-finger pinch zooms and never changes lock on release")
	menu.pause_button.pressed.emit()
	for tick in 30: b._physics_process(1.0/60)
	check(b.view_center.is_equal_approx(follow.pos) and menu.camera_picker.get_item_metadata(menu.camera_picker.selected).ship==follow.id,"camera and visible selector track the moving ship")
	find_button(menu,"全景").pressed.emit()
	check(b.tracked_id==0 and b.camera_mode==0 and b.zoom_override==0,"overview resets tracking and manual magnification")
	find_button(menu,"同阵容重赛").pressed.emit()
	check(menu.battle!=b and menu.battle.tally(0).ships==2 and menu.battle.elapsed==0,"rematch starts with the same selected forces")
	find_button(menu,"调整阵容").pressed.emit()
	check(menu.rosters[0][0].count==2 and menu.station_types[1]==1,"return to editing retains both teams")
	menu.rosters[0]=[menu.entry("wolf",24)]
	menu.rosters[1]=[menu.entry("wolf",1)]
	menu.station_types=[0,0]
	menu.begin()
	b=menu.battle
	b.set_physics_process(false)
	check(b.tally(0).ships==20 and b.tally(0).reserve==4,"large lineups retain exact reinforcements")
	var ally: Dictionary=b.world.ships.values().filter(func(sh):return sh.flag==b.world.NEUTRAL).front()
	b.set_view(b.View.SHIP,ally.id)
	b.world.destruction(ally.id)
	b._physics_process(1.0/60)
	check(b.camera_mode==b.View.FREE and b.tracked_id==0,"camera remains at the wreck when its target is destroyed")
	check(b.tally(0).ships==20 and b.tally(0).reserve==3,"one loss consumes one selected reserve")
	for ship: Dictionary in b.world.ships.values():
		if ship.flag==b.world.RAIDERS: b.world.destruction(ship.id)
	b._physics_process(1.0/60)
	check(b.ended and menu.outcome.text=="蓝方胜利","victory is declared once the opposing army is exhausted")
	var victory_time: float=b.elapsed
	b._physics_process(0.25)
	check(b.elapsed>victory_time and not b.paused and not menu.pause_button.disabled,"victory leaves the live battlefield and manual pause control running")
	menu.pause_button.pressed.emit()
	var stopped: float=b.elapsed
	b._physics_process(0.25)
	check(b.paused and b.elapsed==stopped and menu.outcome.text=="蓝方胜利","manual pause still works after a result")
	menu.rosters[0]=[menu.entry("onslaught",1)]
	menu.rosters[1]=[menu.entry("kite",1)]
	menu.begin()
	b=menu.battle
	b.set_physics_process(false)
	for tick in 14400:
		if b.ended: break
		b._physics_process(1.0/60)
	check(b.ended and menu.outcome.text=="蓝方胜利" and b.tally(1).ships==0,"autonomous matchup reaches victory using only live combat damage")
	find_button(menu,"返回主菜单").pressed.emit()
	await process_frame
	check(game.has_node("TitleMenu") and var_to_bytes(game.world.snapshot())==initial,"leaving sandbox preserves the original universe exactly")
	game.free()
	print("Skirmish ",checks-failures,"/",checks)
	quit(1 if failures else 0)

func _initialize() -> void:
	run.call_deferred()
