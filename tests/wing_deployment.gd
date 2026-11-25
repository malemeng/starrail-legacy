extends SceneTree

const Game = preload("res://game.tscn")
const Agent = preload("res://agent_bridge.gd")
const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")
const Industry = Economy.Industry
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	var api := Agent.new()
	api.game = game
	check(api.dispatch("new_game",{"seed":"wing-workshop","systems":12,"factions":3}).ok,"create a normal campaign")
	var world = game.world
	var port: int = world.active().loc
	var listing: Dictionary = api.observe().ports.filter(func(p): return p.id == port)[0]
	check(listing.wing_catalog.size() == 31,"31 real workshop listings in port")
	var kind := Hulls.kind_for_reference("condor")
	world.active().wallet = int(Economy.ship_quote(world.ports[port],kind).price) + 10000
	var purchase := api.dispatch("buy_ship",{"hull_id":Hulls.hull_id(kind)})
	check(purchase.ok,"purchase an open-bay Condor from the shipyard's generated inventory")
	if not purchase.ok:
		quit(1)
		return
	check(api.dispatch("pilot_ship",{"ship":purchase.result.ship}).ok,"board purchased carrier via the public bridge")
	var carrier: Dictionary = world.ride()
	var original: String = carrier.fit.wings[0]
	var wanted := "cobra_wing"
	var shop := VBoxContainer.new()
	root.add_child(shop)
	game.dock_view.wing_workshop(shop,world.ports[port],carrier)
	var choices := shop.find_children("*","OptionButton",true,false)
	var button: Button = shop.get_child(-1)
	check(choices.size() == 2 and choices[1].item_count == 31,"dock UI exposes bay and all squadron options")
	var index := Hulls.wing_ids().find(wanted)
	choices[1].select(index)
	choices[1].item_selected.emit(index)
	button.pressed.emit()
	check(carrier.fit.wings[0] == wanted,"the dock UI manufactures and installs the selected wing")
	shop.queue_free()
	verify_rejections(world,api,carrier,port)
	var baseline: Dictionary = world.snapshot()
	for id in Hulls.wing_ids():
		world.load_state(baseline)
		carrier = world.ride()
		if carrier.fit.wings[0] == id:
			check(Economy.refit_wing(world,port,0,original),"clear the test bay before repurchasing "+id)
		var before: Array = world.ports[port].stock.duplicate()
		var wallet: int = world.active().wallet
		var quote := Economy.wing_exchange([carrier.fit.wings[0]],[id])
		var installed := api.dispatch("refit_wing",{"bay":0,"wing_id":id})
		check(installed.ok and installed.state.ship.fit.wings[0] == id,id+" public purchase")
		var expected := before.duplicate()
		for ware in quote.materials:
			expected[ware] -= int(quote.materials[ware])
		check(expected == world.ports[port].stock and world.active().wallet == wallet-quote.net,id+" ledger settlement")
		check(world.load_state(world.snapshot()) and world.ride().fit.wings[0] == id,id+" whole-world save/load")
		await process_frame
		check(api.dispatch("depart",{}).ok,id+" standard departure")
		var launched := exercise(world,id)
		check(launched,id+" sortie produces its assigned effect")
		if not launched:
			printerr("wing: ",world.ride().battle.fighter_wings[0])
	world.load_state(baseline)
	check(Economy.refit_wing(world,port,0,"construction_swarm_wing"),"install constructor")
	check(api.dispatch("depart",{}).ok,"depart with constructor")
	verify_live_construction(game)
	await process_frame
	game.queue_free()
	await process_frame
	print("Wing deployment 31 programs · %d/%d checks" % [checks-failures,checks])
	quit(1 if failures else 0)

func verify_rejections(world, api, carrier: Dictionary, port: int) -> void:
	var initial: Array = carrier.fit.wings.duplicate()
	var cash: int = world.active().wallet
	var eligible := "aspect_attack_wing"
	var station: Dictionary = world.ports[port]
	var stock: Array = station.stock.duplicate()
	var quote := Economy.wing_exchange([initial[0]],[eligible])
	world.active().wallet = quote.net-1
	check(not api.dispatch("refit_wing",{"bay":0,"wing_id":eligible}).ok and carrier.fit.wings == initial and station.stock == stock,"insufficient credits leave fitting and warehouse untouched")
	world.active().wallet = cash
	station.outbound[999] = {"ware":Industry.Ware.WAFER,"qty":station.stock[Industry.Ware.WAFER]}
	check(not api.dispatch("refit_wing",{"bay":0,"wing_id":eligible}).ok and carrier.fit.wings == initial and station.stock == stock and world.active().wallet == cash,"reserved components cannot be sold twice")
	station.outbound.erase(999)
	for args in [{"bay":-1,"wing_id":eligible},{"bay":0.5,"wing_id":eligible},{"bay":0,"wing_id":"bad"},{"bay":0,"wing_id":initial[0]}]:
		check(not api.dispatch("refit_wing",args).ok and carrier.fit.wings == initial and station.stock == stock and world.active().wallet == cash,"invalid bay, wing or duplicate rejected")
	var fixed: int = world.ship(Hulls.kind_for_reference("shepherd"),world.player,0,carrier.flag,carrier.system,station.pos,port)
	check(world.pilot(fixed) and not api.dispatch("refit_wing",{"bay":0,"wing_id":eligible}).ok,"built-in Shepherd bay stays locked")
	check(world.pilot(carrier.id),"board open-bay carrier again")

func exercise(world, id: String) -> bool:
	var carrier: Dictionary = world.ride()
	carrier.pos += Vector2(4500,4500)
	var spec := Hulls.wing_spec(id)
	var job: String = spec.get("service","")
	var screen: bool = spec.get("manifestation",{}).get("kind","") == "screen"
	var target: Dictionary = {}
	var old_hp := 0.0
	if job == "repair":
		var ally: int = world.ship(0,world.player,0,carrier.flag,carrier.system,carrier.pos+Vector2(100,0))
		target = world.ships[ally]
		target.hp -= 23.0
		old_hp = target.hp
		carrier.cargo[Industry.Ware.HULL_PARTS] = 1
	elif job == "salvage":
		world.wreck(carrier.system,carrier.pos+Vector2(118,0),1,0)
	else:
		var victim: int = world.ship(0,0,0,world.RAIDERS,carrier.system,carrier.pos+Vector2(128,0))
		target = world.ships[victim]
		old_hp = target.hp
	var alloy: int = carrier.cargo[Industry.Ware.ALLOY]
	Battle.ensure_state(carrier)
	var launched := false
	for frame in 360:
		Battle.Wings.advance(world,carrier,target if job.is_empty() else {},1.0/60.0,Battle)
		var wing: Dictionary = carrier.battle.fighter_wings[0]
		launched = launched or (wing.id == id and wing.sortie and Vector2(wing.pos).distance_squared_to(carrier.pos) > 1.0)
		if job == "repair":
			if target.hp > old_hp and carrier.cargo[Industry.Ware.HULL_PARTS] == 0:
				return launched
		elif job == "salvage":
			if carrier.cargo[Industry.Ware.ALLOY] == alloy+1:
				return launched
		else:
			# Isolate hits from this bay so the Condor's other squadron cannot satisfy the check.
			world.projectiles = world.projectiles.filter(func(p): return p.get("wing_id","") == id)
			if screen and not world.projectiles.is_empty():
				var cloud: Dictionary = world.projectiles[0]
				var shot := Battle.Abilities.Ordnance.payload(target,"",cloud.pos+Vector2(20,0),Vector2(-200,0),1.0,6.0)
				var contact := Battle.trace(world,shot,shot.pos,cloud.pos-Vector2(20,0))
				if contact.has("screen"):
					var hp: float = cloud.hp
					Battle.impact(world,shot,contact)
					return launched and cloud.hp == hp-shot.damage
			Battle.project(world,carrier.system,1.0/60.0)
			if target.hp < old_hp or target.battle.armor < Hulls.COMBAT[target.kind].armor:
				return launched
	return false

func verify_live_construction(game) -> void:
	var world = game.world
	var carrier: Dictionary = world.ride()
	carrier.pos += Vector2(4400,4400)
	var plan: Dictionary = Hulls.wing_spec("construction_swarm_wing").construction
	for material in plan.materials:
		carrier.cargo[Industry.WARE_ID[material]] = int(plan.materials[material])
	var foe: int = world.ship(Hulls.kind_for_reference("buffalo"),0,0,world.RAIDERS,carrier.system,carrier.pos+Vector2(320,0))
	world.ships[foe].battle.vent = true
	var deployed := false
	var constructed := false
	for frame in 360:
		# The normal flight loop supplies the target and advances the construction entity.
		game.flight.combat(carrier,1.0/60.0)
		deployed = deployed or bool(carrier.battle.fighter_wings[0].sortie)
		for unit in world.ships.values():
			if unit.battle.get("constructor_id",0) == carrier.id:
				constructed = unit.flag == carrier.flag and Hulls.MODELS[unit.kind].reference == plan.unit
		if constructed:
			break
	check(deployed and constructed,"normal flight AI and physics build a real allied ship")
	for material in plan.materials:
		check(carrier.cargo[Industry.WARE_ID[material]] == 0,"construction consumed "+material)
