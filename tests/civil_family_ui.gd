extends SceneTree

const Game = preload("res://game.tscn")
var game
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
	return ok

func action(container: Node, caption: String) -> Button:
	for button: Button in container.find_children("*","Button",true,false):
		if button.text==caption:
			return button
	return null

func has_label(container: Node, caption: String) -> bool:
	for label: Label in container.find_children("*","Label",true,false):
		if label.text==caption:
			return true
	return false

func click(button: Button) -> bool:
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"a visible, enabled action is available"):
		return false
	var scroller := game.body.get_parent() as ScrollContainer
	if scroller.is_ancestor_of(button):
		scroller.ensure_control_visible(button)
	await process_frame
	var point:=button.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		root.push_input(event,true)
	await process_frame
	return true

func capture(area: Button) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var screen:=root.get_texture().get_image()
	var sidebar: Rect2i=Rect2i(game.tabs.get_global_rect().merge(area.get_global_rect()).grow(10))
	var crop:=sidebar.intersection(Rect2i(Vector2i.ZERO,screen.get_size()))
	check(screen.get_region(crop).save_png(OS.get_temp_dir().path_join("starrail-civil-family.png"))==OK,"save the visible family action and its navigation tab")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.size=Vector2i(1440,900)
	game=Game.instantiate()
	game.test_profile=true
	root.add_child(game)
	var world=game.world
	world.new_game({"seed":"civil-family-ui","systems":12,"factions":3,"avatar":{"name":"柳棠","gender":0,"noble":false}})
	game.run_bridge()
	game.set_physics_process(false)
	await process_frame
	var actor: Dictionary=world.active()
	var target: Dictionary={}
	for person: Dictionary in world.people.values():
		if person.loc==actor.loc and not person.noble and world.Politics.marriage_terms(world,actor.id,person.id).accepted:
			target=person
			break
	if not check(not target.is_empty(),"the ordinary starting port has a willing single commoner") or not await click(action(game.tabs,"人物")):
		finish()
		return
	var propose:=action(game.body,"求婚")
	if not check(game.tab=="人物" and has_label(game.body,"家庭") and propose!=null,"the character tab shows the ordinary family section and propose action"):
		finish()
		return
	var picker:=propose.get_parent().find_children("*","OptionButton",false,false).front() as OptionButton
	var idx:=-1
	for i in picker.item_count:
		if picker.get_item_text(i)==target.name+" · 平民":
			idx=i
			break
	if not check(idx>=0,"the selected commoner is visible in the home's public list"):
		finish()
		return
	if idx!=picker.selected:
		await click(picker)
		var popup:=picker.get_popup()
		popup.set_focused_item(idx)
		var input:=InputEventKey.new()
		input.keycode=KEY_ENTER
		input.pressed=true
		popup.push_input(input,true)
		input.pressed=false
		popup.push_input(input,true)
		await process_frame
	if not check(picker.selected==idx,"the selector shows the consenting resident"):
		finish()
		return
	await capture(propose)
	await click(propose)
	var spouse:=action(game.body,"配偶　"+str(target.name))
	check(actor.spouse==target.id and target.spouse==actor.id and spouse!=null and action(game.body,"求婚")==null,"one physical button click registers both spouses and removes repeat proposals")
	if await click(spouse):
		var partner_link := action(game.body,"配偶：%s" % actor.name)
		if check(game.hud.dossier.person_id==target.id and partner_link!=null and action(game.body,"求婚")==null,"the spouse's dossier links back to the registered partner and offers no second wedding") and await click(partner_link):
			check(game.hud.dossier.person_id==actor.id,"the family link opens the player's actual dossier")
	finish()

func finish() -> void:
	game.queue_free()
	print("Civil family UI %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
