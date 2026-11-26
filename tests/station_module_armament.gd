extends SceneTree

const Game = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
const Armory = preload("res://scripts/ui/station_armory.gd")
const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
const Art = preload("res://scripts/ui/station_art.gd")
const World = preload("res://world.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
	return ok

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var w: World = game.world
	w.new_game({"seed":"module-loadout","systems":12,"factions":3,"avatar":{"station_master":1}})
	game.run_bridge()
	var site: Dictionary = w.ports[w.active().loc]
	for type in range(-1,w.MODULES.size()):
		var sample := {"modules":[type],"capital_yard":true}
		var index := 0 if type < 0 else 1
		var hull := w.StationArmament.profile(sample,index)
		var points: PackedVector2Array = w.StationArmament.mount_offsets({"kind":type,"size":Vector2(80,80)})
		var mask := Art.module_image(type,Color.WHITE)
		check(points.size() >= Hulls.MODELS[hull].mounts.size(),"station has room for all shared ship mounts")
		for i in Hulls.MODELS[hull].mounts.size():
			var at := Vector2i(points[i]+Vector2(40,40))
			var on_deck := true
			for dx in range(-2,3):
				for dy in range(-2,3):
					on_deck = on_deck and mask.get_pixelv(at+Vector2i(dx,dy)).a > 0.95
			check(on_deck,"module %s mount %s is entirely seated on the solid deck" % [type,i])
	w.active().wallet = 100000
	site.treasury = 100000
	site.stock.fill(250)
	var b := Bridge.new()
	b.game = game
	var catalog := b.dispatch("station_armament",{"port":site.id,"module":1})
	check(catalog.ok and catalog.result.modules.size()==site.modules.size()+1 and catalog.result.mounts.size()>0,"Agent sees each built module with its ship mounts")
	check(catalog.result.modules[0].aircraft==24 and catalog.result.modules[0].wings.size()==6,"core fields six real ship squadrons with 24 aircraft")
	var fit := w.StationArmament.fitting(site,1)
	var kind := w.StationArmament.profile(site,1)
	var slot := -1
	var chosen := ""
	var quote := {}
	for i in fit.weapons.size():
		for key in w.Economy.station_weapons(w,site):
			quote = w.StationArmament.quote(w,site,1,i,key)
			if quote.ok and key!=fit.weapons[i]:
				slot = i
				chosen = key
				break
		if slot >= 0:
			break
	if not check(slot>=0 and Hulls.weapon_compatible(kind,slot,chosen),"a real ship-market weapon fits a station mount"):
		game.free()
		quit(1)
		return
	var old: String = fit.weapons[slot]
	var credits: int = w.active().wallet
	var stock: Array = site.stock.duplicate()
	var payload := {"port":site.id,"module":1,"slot":slot,"weapon":chosen,"expected_current":old}
	var receipt := b.dispatch("refit_station_module",payload)
	check(receipt.ok and w.active().wallet==credits-int(quote.net),"authorized refit settles displayed net price")
	var materials := w.Economy.weapon_materials(chosen)
	check(materials.keys().all(func(k): return site.stock[k]==stock[k]-materials[k]),"installation consumes the same materials as ship fitting")
	check(w.StationArmament.fitting(site,1).weapons[slot]==chosen and not b.dispatch("refit_station_module",payload).ok,"installation persists and replay cannot charge again")
	Armory.open(game,site)
	var dlg = game.find_children("*","AcceptDialog",true,false).back()
	check(dlg.module.item_count==site.modules.size()+1 and dlg.slot.item_count>0,"touch armory lists the installed modules and individual sockets")
	dlg.module.select(1)
	dlg.module.item_selected.emit(1)
	dlg.slot.select(slot)
	dlg.slot.item_selected.emit(slot)
	check(dlg.current==chosen and dlg.offers.has(""),"armory reads the bridge's actual installation and allows removal")
	var restored := World.new()
	check(restored.load_state(w.snapshot()) and restored.StationArmament.fitting(restored.ports[site.id],1).weapons[slot]==chosen,"old defaults and customized slots round-trip in a campaign")
	var foreign := w.random_person(w.NEUTRAL,site.id)
	b.bound_actor_id = foreign
	check(not b.dispatch("refit_station_module",{"port":site.id,"module":1,"slot":slot,"weapon":""}).ok,"unrelated visitors cannot replace station weapons")
	var lead: Dictionary = w.ships[w.ship(0,foreign,foreign,w.NEUTRAL,site.system,site.pos)]
	var prev := w.player
	w.player = foreign
	w.StationAssault.start(w,site,lead,w.NEUTRAL,false)
	w.player = prev
	var module: Dictionary = w.ships[site.assault.nodes[1]]
	var core: Dictionary = w.ships[site.assault.nodes[0]]
	check(module.fit.weapons[slot]==chosen and Hulls.WEAPONS.has(chosen),"live module loads the exact installed shared weapon ID")
	check(not w.StationArmament.refit(w,site,1,slot,"").ok,"mid-battle fitting cannot reset a module")
	var point: Vector2 = module.pos + Vector2.RIGHT*Battle.Defenses.body_geometry(module).shield_radius
	Battle.hit(w,module,25.0,0,point,Vector2.LEFT,false,0.0,true)
	check(module.battle.hard_flux>0 and core.battle.hard_flux==0 and core.battle.shield,"hit applies only to the struck module's shield")
	for frame in 24:
		Battle.Wings.advance(w,core,lead,0.05,Battle)
	var wing: Dictionary = core.battle.fighter_wings.front()
	check(wing.sortie and wing.count_live>0,"a fitted hangar launches its real squadron")
	for frame in 200:
		Battle.Wings.advance(w,core,{},0.1,Battle)
	check(not wing.sortie and Vector2(wing.pos).distance_to(Battle.Wings.berth_for(core,0,core.fit.wings.size()))<7,"wing returns to its station hangar when contact ends")
	wing.hp = 0.0
	for frame in 1200:
		Battle.Wings.advance(w,core,{},0.1,Battle)
		if wing.hp>0:
			break
	check(wing.hp>0 and core.battle.replacement_rate<1.0,"losses consume the carrier replacement rate and replenish after refit time")
	print("Module ship weapon ",chosen," in slot ",slot," of ",module.job.label)
	game.free()
	print("Station module armament ",checks-failures,"/",checks)
	quit(1 if failures else 0)

func _initialize() -> void:
	run.call_deferred()
