extends SceneTree

const World = preload("res://world.gd")
const Society = preload("res://scripts/campaign/society.gd")
const Ops = preload("res://scripts/campaign/operations.gd")
const Politics = preload("res://politics.gd")
const Game = preload("res://game.gd")
var passed := 0
var failed := 0

func check(ok: bool, caption: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(caption)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := World.new()
	world.new_game({"seed":"campaign-integration","systems":24,"factions":5,"avatar":{"name":"测试","noble":true}})
	var actor := world.active()
	var vessel := world.ride()
	var site: Dictionary = world.ports[actor.loc]
	check(actor.stats.to_dict().size()==6 and actor.personality.size()==8,"complete character profile")
	check(Society.EventEngine.authored().all(Society.EventEngine.valid_template),"bundled decisions validate")
	check(Society.focus(world,"industry"),"choose a lifestyle")
	world.tick(150)
	check(Society.train(world) and actor.perks.industry==1,"time and learning unlock an actual rank")
	check(Society.pending(world).is_empty(),"five months of ordinary study leave no outstanding decisions")
	var target := world.random_person(0,site.id)
	check(Society.scheme(world,target,"find_secrets"),"investigation starts in same port")
	world.tick(210)
	# An NPC can uncover earlier secrets while the player's investigation is in progress.
	world.people[target].secrets.append({"kind":"smuggling","day":world.day})
	check(Society.resolve_scheme(world) and actor.hooks.has(target),"completed investigation produces a hook")
	check(Society.use_hook(world,target) and not Society.use_hook(world,target),"spending a hook binds the target once")
	Society.stress(world,actor,220)
	check(actor.break_level>=2 and actor.stress>=200,"pressure crosses two thresholds")
	site.owner = actor.id
	site.stock[1] += 20
	site.stock[12] += 10
	site.stock[10] += 100
	check(Ops.start_project(world,site.id,"lab") and not Ops.start_project(world,site.id,"lab"),"headquarters spends materials and rejects duplicate jobs")
	world.tick(96)
	check("lab" in world.campaign.unlocks.get(site.id,[]),"completed research is available at its station")
	check(Ops.expedition(world,"tour",site.id) and actor.ship==0 and vessel.dock==site.id,"traveller and ship have separate locations")
	world.tick(6)
	check(actor.loc==site.id and actor.ship==vessel.id,"round trip returns to the same docked ship")
	var snapshot := world.snapshot()
	var restored := World.new()
	check(restored.load_state(snapshot) and restored.active().perks==actor.perks and restored.campaign==world.campaign,"world, schemes, cargo and research survive save/load")
	var game := Game.new()
	root.add_child(game)
	game.world=restored
	game.run_bridge()
	for page in range(5):
		game.tab="事务"
		game.campaign_panel.section=page
		game.refresh()
		await process_frame
		check(game.body.get_child_count()>1,"playable campaign screen %d" % page)
	game.tab = "港口"
	game.dock_view.mode = "yard"
	game.dock_view.model_id = 7
	game.refresh()
	await process_frame
	check(game.dock_view.rendered == "yard","ordinary shipyard displays class comparison")
	game.dock_view.mode = "refit"
	game.refresh()
	game.glossary.open("op",Vector2(20,20))
	game.glossary.open("flux",Vector2(20,20))
	game.glossary.open("armor",Vector2(20,20))
	check(game.glossary.history.size() == 3 and game.glossary.panel.visible,"three levels of fitting rules")
	game.glossary.hide_card()
	game.queue_free()
	await process_frame
	print("Campaign verification: %d/%d" % [passed,passed+failed])
	quit(1 if failed else 0)
