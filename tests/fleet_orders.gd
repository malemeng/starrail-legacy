extends SceneTree

const SCENE = preload("res://game.tscn")
const World = preload("res://world.gd")
const Economy = preload("res://economy.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Bridge = preload("res://agent_bridge.gd")
const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
var checks := 0
var failures := 0

class ScanProbe extends "res://flight.gd":
	var radii := []

	func target(vessel: Dictionary, radius: float, first_visible: bool = false) -> int:
		radii.append(radius)
		return super(vessel,radius,first_visible)

func expect(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",reason)

func _initialize() -> void:
	call_deferred("verify")

func button(root_node: Node, caption: String) -> Button:
	for node in root_node.find_children("*","Button",true,false):
		if node.text == caption:
			return node
	return null

func verify_combat_roles(game, lead: Dictionary, escort: Dictionary) -> void:
	var world: World = game.world
	world.depart(lead)
	world.depart(escort)
	lead.pos = Vector2(600,600)
	escort.pos = lead.pos + Vector2(-65,0)
	var far_id := world.ship(0,0,0,world.RAIDERS,lead.system,lead.pos + Vector2(85,0))
	var near_id := world.ship(0,0,0,world.RAIDERS,lead.system,lead.pos + Vector2(-80,0))
	var attacker: Dictionary = world.ships[far_id]
	Battle.ensure_state(attacker)
	expect(Economy.assign_role(world,escort.id,lead.id,"ATTACK"),"assign attack role")
	game.selected_target = far_id
	escort.battle.order = 1
	game.flight.drive_ai(escort,lead,0.01,[],[])
	expect(escort.battle.target_id == far_id,"attack follows flagship's selected target over a closer enemy")
	game.selected_target = near_id
	Economy.assign_role(world,escort.id,lead.id,"DEFEND")
	game.flight.drive_ai(escort,lead,0.01,[],[])
	expect(escort.battle.target_id == 0 and not escort.locked,"defender ignores nearby hostiles without a hostile shot")
	attacker.heading = PI
	Battle.train(attacker,lead.pos,1.0)
	for group in range(1,4):
		Battle.group_fire(world,attacker,group,lead.pos,lead.id)
	expect(lead.battle.get("fleet_attackers",{}).has(far_id),"actual aimed shot registers its source")
	game.flight.drive_ai(escort,lead,0.01,[],[])
	expect(escort.battle.target_id == far_id and escort.locked,"defender engages recorded attacker over another hostile")
	Battle.tick(lead,5.2,world)
	game.flight.drive_ai(escort,lead,0.01,[],[])
	expect(escort.battle.target_id == 0,"defender returns to formation when fire ceases")
	var stray := {"damage":1,"type":0,"ship":near_id,"credit":0,"target":0,"system":lead.system,"vel":Vector2.RIGHT}
	Battle.impact(world,stray,{"ship":lead,"point":lead.pos,"shield":false})
	expect(lead.battle.fleet_attackers.has(near_id),"untargeted hit also records the shooter")

	attacker.hp = Hulls.MODELS[attacker.kind].hp*0.20
	attacker.battle.system_cd = 20.0
	var existing_shots: Array = world.projectiles.duplicate()
	world.projectiles.clear()
	world.projectiles.append({"system":attacker.system,"flag":lead.flag,"raid":world.NEUTRAL,"pos":attacker.pos+Vector2(40,0),"vel":Vector2(-10,0)})
	game.flight._engage_target(attacker,lead,0.01)
	expect(attacker.battle.ai == "脱离交战" and attacker.battle.shield and not attacker.battle.vent,"a damaged cool ship covers its retreat when it detects an incoming shot")
	world.projectiles.assign(existing_shots)

	var pd_ship: Dictionary = {}
	for kind in Hulls.MODELS.size():
		var fit = Hulls.stock_fit(kind)
		if fit.weapons.any(func(key): return Hulls.WEAPONS.get(key,{}).get("pd",false)):
			var captain := world.random_person(world.NEUTRAL,0)
			var id := world.ship(kind,world.player,captain,world.NEUTRAL,lead.system,lead.pos)
			pd_ship = world.ships[id]
			break
	expect(not pd_ship.is_empty(),"fleet has a standard point-defense fitting")
	if pd_ship.is_empty():
		return
	Economy.assign_role(world,pd_ship.id,lead.id,"INTERCEPT")
	Battle.ensure_state(pd_ship)
	var slot: int = pd_ship.battle.pd_slots[0]
	var mount := Hulls.slot_spec(pd_ship.kind,slot)
	var axis := Vector2.from_angle(pd_ship.heading + deg_to_rad(mount.facing))
	var muzzle := Battle.slot_position(pd_ship,slot)
	var point := muzzle + axis * 24
	lead.pos = point + axis * 95
	var shot := {"missile":true,"hp":100,"system":lead.system,"flag":world.RAIDERS,"raid":world.NEUTRAL,"ship":far_id,"target":lead.id,"pos":point,"vel":axis*100}
	game.flight.drive_ai(pd_ship,lead,0.01,[shot],[])
	expect(pd_ship.battle.ai == "截击来袭目标" and pd_ship.battle.ai_thrust.dot(axis) > 0.0,"interceptor maneuvers onto an incoming missile's path")
	Battle.point_defense(world,pd_ship,[shot],[])
	expect(shot.hp == 100,"ordinary self-defense ignores missile already moving away")
	Battle.point_defense(world,pd_ship,[shot],[],lead)
	expect(shot.hp < 100,"real mount shoots crossing missile to defend flagship")
	pd_ship.battle.cooldowns.fill(0)
	var fighter := {"hp":100.0,"sortie":true,"pos":point}
	attacker.battle.fighter_wings = [fighter]
	game.flight.drive_ai(pd_ship,lead,0.01,[],[attacker])
	Battle.point_defense(world,pd_ship,[],[attacker],lead)
	expect(pd_ship.battle.ai == "截击来袭目标" and fighter.hp < 100,"sortied hostile wing is pursued and hit by mounted point defense")
	attacker.battle.fighter_wings = []
	var fallback: int = game.flight.ai_target(pd_ship,500)
	game.flight.drive_ai(pd_ship,lead,0.01,[],[])
	expect(pd_ship.battle.ai != "截击来袭目标" and pd_ship.battle.target_id == fallback,"interceptor falls back to ship combat without airborne contacts")

func verify_lock_boundaries(game, lead: Dictionary) -> void:
	var world: World = game.world
	for id in world.ships.keys():
		if id != lead.id:
			world.ships.erase(id)
	world.projectiles.clear()
	world.depart(lead)
	lead.pos = Vector2.ZERO
	lead.locked = false
	lead.fit.auto.fill(false)
	var id := world.ship(0,0,0,world.RAIDERS,lead.system,Vector2(255,0))
	var foe: Dictionary = world.ships[id]
	foe.fit.weapons.fill("")
	var probe := ScanProbe.new()
	probe.game = game
	probe.sensor_countdown = 1.0
	probe.sensor_reading = {"strength":1000.0,"profile":1000.0,"burn":9.0}
	game.flight = probe
	probe.combat(lead,0.001)
	expect(not lead.locked,"contact exactly 255 away does not initiate combat")
	foe.pos = Vector2(254.9,0)
	probe.sensor_reading.profile = 0.0
	probe.combat(lead,0.001)
	expect(not lead.locked,"a visible hostile that cannot detect the flagship does not initiate combat")
	probe.sensor_reading.profile = 1000.0
	probe.combat(lead,0.001)
	expect(lead.locked,"detecting hostile just inside 255 initiates combat")
	foe.pos = Vector2(519.9,0)
	probe.radii.clear()
	probe.combat(lead,0.001)
	expect(lead.locked and 520.0 in probe.radii and 255.0 not in probe.radii,"current lock checks the outer radius only")
	foe.pos = Vector2(520,0)
	probe.combat(lead,0.001)
	expect(not lead.locked,"contact exactly 520 away releases the lock")
	game.speed = 1
	world.attention = false
	game.waypoint_live = false
	probe.radii.clear()
	probe.step(0.001)
	expect(260.0 not in probe.radii,"manual flight skips unused waypoint scan")
	foe.pos = Vector2(30,0)
	probe.sensor_reading.clear()
	probe.radii.clear()
	probe.step(0.001)
	expect(260.0 in probe.radii and not probe.sensor_reading.is_empty(),"cold manual flight still initializes sensors before movement")
	game.waypoint_live = true
	game.waypoint = Vector2(950,0)
	probe.radii.clear()
	probe.step(0.001)
	expect(260.0 in probe.radii,"active waypoint still checks engagement before flying")

func verify() -> void:
	var game = SCENE.instantiate()
	game.test_profile = true
	root.add_child(game)
	var bridge := Bridge.new()
	bridge.game = game
	expect(bridge.dispatch("new_game",{"seed":"fifo-at-berth"}).ok,"start actual game")
	var world: World = game.world
	var lead := world.ride()
	var home: Dictionary = world.ports[lead.dock]
	var depot_id := world.port(home.system,"舰队仓库",Vector2(620,-380),world.NEUTRAL,world.player,Industry.Module.YARD)
	var depot: Dictionary = world.ports[depot_id]
	var captain := world.random_person(world.NEUTRAL,home.id)
	var id := world.ship(1,world.player,captain,world.NEUTRAL,home.system,home.pos,home.id)
	var ship: Dictionary = world.ships[id]
	world.active().wallet = 50000
	expect(Economy.assign_role(world,id,lead.id,"DEFEND"),"set standing escort")
	expect(game.flight.escort(ship,lead),"default escort follows flagship")

	game.tab = "事务"
	game.campaign_panel.section = 2
	game.campaign_panel.fleet_ship = id
	game.campaign_panel.fleet_port = home.id
	game.refresh()
	var add := button(game.body,"加入队尾")
	expect(add != null and not add.disabled,"real fleet panel accepts orders")
	if add:
		add.pressed.emit()
	expect(ship.order_queue == [{"kind":"dock","port":home.id,"issuer":world.player}],"button appends a signed order for selected ship and port")
	expect(not game.flight.escort(ship,lead),"explicit order suppresses jump and docking with flagship")
	var cancel := button(game.body,"撤单")
	expect(cancel != null,"queued order visible for cancellation")
	if cancel:
		cancel.pressed.emit()
	expect(ship.order_queue.is_empty() and game.flight.escort(ship,lead),"cancel button restores escort")
	game.tab = "港口"

	var ore := Industry.Ware.ORE
	home.stock[ore] = 40
	ship.cargo.fill(0)
	var args := {"ship":id,"port":home.id,"kind":"buy","ware":ore,"quantity":7}
	expect(bridge.dispatch("queue_fleet_order",args).ok,"protocol buy")
	args.kind = "sell"
	args.quantity = 2
	expect(bridge.dispatch("queue_fleet_order",args).ok,"protocol sell")
	args.kind = "unload"
	args.port = depot.id
	args.quantity = 4
	expect(bridge.dispatch("queue_fleet_order",args).ok,"protocol warehouse transfer")
	expect(bridge.dispatch("queue_dock",{"ship":id,"port":home.id}).ok,"original dock action appends")
	var view: Array = bridge.observe().ship.fleet.filter(func(row): return row.id == id)
	expect(view.size() == 1 and view[0].order_queue == ship.order_queue and view[0].fleet_role == "DEFEND","protocol observes effective queue and standing role")
	var quote := Economy.price(home,ore,true)
	var wallet: int = world.active().wallet
	Economy.step_ship(world,ship)
	expect(ship.cargo[ore] == 7 and home.stock[ore] == 33 and world.active().wallet <= wallet - 6 * quote,"purchase moves inventory and pays current quote")
	Economy.step_ship(world,ship)
	expect(ship.cargo[ore] == 5 and home.stock[ore] == 35,"sale runs after purchase")
	Economy.step_ship(world,ship)
	expect(ship.travel.get("port",0) == depot_id and ship.dock == 0,"ordered freighter leaves berth")
	var saved := World.new()
	expect(saved.load_state(world.snapshot()),"save mid-route")
	var restored: Dictionary = saved.ships[id]
	var stock: int = saved.ports[depot_id].stock[ore]
	for day in 30:
		Economy.transit_day(saved)
		if restored.dock == depot_id:
			break
	expect(restored.dock == depot_id and restored.cargo[ore] == 1 and saved.ports[depot_id].stock[ore] == stock + 4,"restored travel reaches destination and unloads once")
	expect(restored.last_order.moved == 4 and restored.order_queue.size() == 1,"receipt and remaining order survive arrival")
	var cargo_before: int = restored.cargo[ore]
	Economy.step_ship(saved,restored)
	expect(not restored.travel.is_empty() and Economy.cancel_order(saved,id,0),"cancel a trip already in progress")
	expect(restored.travel.is_empty() and restored.cargo[ore] == cargo_before and restored.job.kind == "护航","in-flight cancellation preserves physical cargo and duty")
	expect(Economy.cancel_order(world,id,1) and not ship.travel.is_empty(),"removing a later order preserves active route")
	expect(bridge.dispatch("cancel_fleet_order",{"ship":id,"index":0}).ok,"protocol cancels by ordinal")
	expect(not Economy.queue_order(world,id,home.id,"buy",Industry.Ware.LUXURY,1),"legal trade respects restricted commodity")
	var foreign: Dictionary = world.ports.values().filter(func(st): return not world.oversees(st.owner) and Economy.allowed(world,ship,st))[0]
	expect(not Economy.queue_order(world,id,foreign.id,"load",ore,1),"other owners' warehouses reject free withdrawals")
	world.berth(ship,depot.id)
	depot.stock[ore] = 2
	var balance: int = world.active().wallet
	expect(Economy.queue_order(world,id,depot.id,"load",ore,5),"partial load accepted")
	Economy.step_ship(world,ship)
	expect(ship.last_order.moved == 2 and ship.last_order.result == "部分完成" and world.active().wallet == balance,"limited stock produces exact receipt without credits")

	world.berth(ship,home.id)
	expect(Economy.queue_order(world,id,depot.id,"escort_to") and game.flight.escort(ship,lead),"temporary escort joins flagship")
	expect(bridge.dispatch("set_default_behavior",{"ship":id,"kind":"停泊待命","source":home.id}).ok and ship.order_queue.size() == 1,"changing default preserves explicit escort")
	game.flight.dock()
	expect(ship.dock == 0 and lead.dock == 0,"temporary escort launches with flagship")
	lead.pos = depot.pos
	ship.pos = depot.pos + Vector2(35,0)
	game.flight.dock()
	expect(ship.order_queue.is_empty() and ship.dock == depot.id and ship.last_order.result == "已护送到港","normal flagship docking completes escort without waiting a tick")
	Economy.step_ship(world,ship)
	expect(ship.travel.get("port",0) == home.id,"queue exhaustion resumes newly assigned standing behavior")
	expect(Economy.queue_order(world,id,home.id) and Economy.assign_role(world,id,lead.id,"SUPPLY") and ship.order_queue.size() == 1,"assigning fleet role during explicit command preserves it")
	expect(not Economy.queue_order(world,lead.id,home.id),"flagship cannot be given a subordinate order")
	expect(bridge.dispatch("set_default_behavior",{"ship":id,"kind":"自动采矿"}).ok and ship.default_behavior.automatic,"automatic mining available without preselected trade route")
	expect(Economy.cancel_order(world,id,0),"cancel before testing patrol")
	expect(bridge.dispatch("set_default_behavior",{"ship":id,"kind":"巡逻","source":depot.id}).ok,"patrol assigned through protocol")
	var position: Vector2 = ship.pos
	Economy.step_ship(world,ship)
	expect(ship.dock == 0 and position != ship.pos,"patrol physically advances toward system field")
	verify_combat_roles(game,lead,ship)
	verify_lock_boundaries(game,lead)
	game.free()
	print("Fleet order checks %d/%d" % [checks - failures,checks])
	quit(1 if failures else 0)
