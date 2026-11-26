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
	strafe_runs()
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

func strafe_runs() -> void:
	var w = preload("res://world.gd").new()
	w.new_game({"seed":"wing-turns","systems":12,"factions":3})
	var enemy: Dictionary = w.ride()
	w.depart(enemy)
	enemy.pos = Vector2(7000,4000)
	enemy.heading = PI
	enemy.battle.motion = Vector2(18,7)
	enemy.battle.shield = true
	enemy.battle.shield_arc_live = PI
	var carrier: Dictionary = w.ships[w.ship(Hulls.kind_for_reference("condor"),0,0,0,0,enemy.pos-Vector2(700,0))]
	Battle.ensure_state(carrier)
	Battle.ensure_state(enemy)
	var squad: Dictionary
	var phases := {}
	var volley := 0
	var max_passes := 0
	var fired_forward := true
	var launch_offsets := {}
	var fired_passes := {}
	var side_min := INF
	var side_max := -INF
	var min_gap := INF
	var max_gap := 0.0
	var split_headings := false
	for tick in 3000:
		if tick == 1100:
			enemy.battle.motion = Vector2(-12,-5)
		enemy.pos += Vector2(enemy.battle.motion)/60.0
		Battle.Wings.advance(w,carrier,enemy,1.0/60,Battle,[],[])
		squad = carrier.battle.fighter_wings.front()
		for unit in squad.craft:
			var run: Dictionary = unit.get("run",{})
			if not run.is_empty():
				phases[run.phase] = true
				max_passes = maxi(max_passes,int(run.passes))
				var lateral := float(unit.pos.y-enemy.pos.y)
				side_min = minf(side_min,lateral)
				side_max = maxf(side_max,lateral)
		var a: Dictionary = squad.craft[0]
		var b: Dictionary = squad.craft[1]
		if a.sortie and b.sortie:
			var gap := Vector2(a.pos).distance_to(b.pos)
			min_gap = minf(min_gap,gap)
			max_gap = maxf(max_gap,gap)
			split_headings = split_headings or absf(angle_difference(a.heading,b.heading))>0.6
		for shot in w.projectiles:
			if shot.get("bay",-1)==0:
				var shooter: Dictionary = squad.craft[int(shot.airframe)]
				if Vector2(shot.pos).is_equal_approx(shooter.pos):
					volley += 1
					launch_offsets[shooter.index] = true
					fired_passes[shooter.run.passes] = true
					fired_forward = fired_forward and Vector2.from_angle(shooter.heading).dot(Vector2(shot.vel).normalized())>0.65
		w.projectiles.clear()
	check(phases.has("flank") and phases.has("strafe") and phases.has("break") and max_passes>=2 and fired_passes.size()>=2,"moving target receives repeated attack runs separated by an actual break and turn")
	check(side_min < -35 and side_max > 35,"squadron sweeps both flanks instead of hovering at a firing point")
	check(volley>0 and launch_offsets.size()>=2 and fired_forward,"individual surviving aircraft fire forward from their displayed positions")
	check(split_headings and max_gap-min_gap>75 and phases.has("rally"),"airframes separate by changing distances and headings, then rendezvous between passes")
	print("Airframe manoeuvres: wingmate separation %.1f..%.1f, completed passes %d, firing airframes %d" % [min_gap,max_gap,max_passes,launch_offsets.size()])
	enemy.pos = Vector2(carrier.pos)+Vector2(400,20)
	for tick in 90:
		Battle.Wings.advance(w,carrier,enemy,1.0/60,Battle,[],[])
		if squad.sortie and Vector2(squad.pos).distance_to(carrier.pos)>70:
			break
	var damaged: Dictionary = squad.craft.front()
	damaged.hp = damaged.max_hp*0.3
	Battle.Wings.advance(w,carrier,enemy,1.0/60,Battle,[],[])
	check(damaged.returning and squad.craft.any(func(unit): return unit.hp>0 and not unit.returning),"one badly damaged aircraft returns while its squadmates stay on mission")

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
