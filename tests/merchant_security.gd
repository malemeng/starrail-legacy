extends SceneTree

const Game = preload("res://game.tscn")
const Economy = preload("res://economy.gd")
const Security = preload("res://scripts/economy/merchant_security.gd")
const Combat = preload("res://combat.gd")
const World = preload("res://world.gd")
const Saves = preload("res://scripts/services/save_manager.gd")
var checks := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func day(world) -> void:
	world.day += 1
	Economy.transit_day(world)

func spawn_hauler(world, port: Dictionary, owner: int, flag: int) -> Dictionary:
	var captain: int = world.random_person(flag,port.id)
	var id: int = world.ship(world.Hulls.kind_for_reference("buffalo"),owner,captain,flag,port.system,port.pos,port.id)
	var ship: Dictionary = world.ships[id]
	ship.job = {"kind":"贸易"}
	return ship

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.creator.seed.text = "merchant-safety"
	game.start_game()
	game.set_physics_process(false)
	var world = game.world
	var chart := [Vector2.ZERO,Vector2(800,0),Vector2(780,470),Vector2(1550,0)]
	for i in range(world.core_count):
		var region: Dictionary = world.systems[i]
		region.pos = chart[i] if i < chart.size() else Vector2(20000+i*2000,20000)
		if i < chart.size():
			region.erase("outlaw_base")
			for port_id: int in region.ports:
				world.ports[port_id].flag = world.NEUTRAL
	world.init_core()
	var home: Dictionary = world.ports[world.systems[0].ports[0]]
	var destination: Dictionary = world.ports[world.systems[3].ports[0]]
	var intermediate: Dictionary = world.ports[world.systems[1].ports[0]]
	var alternative: Dictionary = world.ports[world.systems[2].ports[0]]
	var ship := spawn_hauler(world,home,world.player,0)
	var ship_id: int = ship.id
	var ally := spawn_hauler(world,home,0,2)
	var enemy := spawn_hauler(world,intermediate,0,1)
	intermediate.flag = 1
	world.set_treaty(0,1,-1)
	check(Economy.trip_plan(world,ship,0,home.pos,false,destination).route == [2,3],"a merchant diverts around the opposing faction's intermediate system")
	check(Economy.trip_plan(world,ally,0,home.pos,false,destination).route == [1,3],"a different flag still uses the shorter peaceful corridor")
	ship.flag = world.NEUTRAL
	check(Economy.trip_plan(world,ship,0,home.pos,false,destination).route == [2,3],"a neutral ensign takes the captain's actual allegiance into account")
	ship.flag = 0
	world.set_treaty(0,1,0)
	for org: String in ["rift_pirates","ember_cult"]:
		world.systems[1].outlaw_base = {"group":org,"reserve":1,"members":[]}
		check(Economy.trip_plan(world,ship,0,home.pos,false,destination).route == [2,3],"civilian traffic avoids an active "+org+" stronghold")
	world.systems[1].outlaw_base.reserve = 0
	check(Economy.trip_plan(world,ship,0,home.pos,false,destination).route == [1,3],"depleted outlaw control reopens its transit corridor")
	world.systems[1].erase("outlaw_base")
	var relay: Dictionary = world.systems[1]
	relay.wild = true
	relay.pirate = true
	relay.spawned = true
	var raider: int = world.ship(enemy.kind,0,0,world.RAIDERS,1,relay.field)
	world.Outlaws.assign(world.ships[raider],world.Outlaws.PIRATES,relay.field)
	relay.pirate_patrol = raider
	check(Security.dangerous(world,ship,1),"the actual patrol controls a charted pirate frontier")
	world.destruction(raider)
	check(not Security.dangerous(world,ship,1),"loss of the last controlling pirate vessel reopens a cleared frontier")
	relay.erase("pirate_patrol")
	relay.erase("wild")
	relay.erase("pirate")
	relay.erase("spawned")
	ship.cargo[0] = 12
	alternative.flag = 1
	world.set_treaty(0,1,-1)
	var departure_fuel: float = ship.fuel
	check(not Economy.reserve(world,ship,home,destination,0,12,false) and not destination.inbound.has(ship_id) and not destination.cash_holds.has(ship_id),"an unreachable destination cannot lock a buyer's money or storage")
	Economy.begin_trip(world,ship,destination)
	check(ship.dock == home.id and ship.fuel == departure_fuel and ship.has("route_hold"),"a captain without a safe route waits at the original berth")
	world.set_treaty(0,1,0)
	alternative.flag = world.NEUTRAL
	check(Economy.reserve(world,ship,home,destination,0,12,false),"loaded cargo gets a real inbound reservation")
	check(destination.cash_holds.get(ship_id,0) > 0,"the purchasing station reserves real funds for the expected cargo")
	Economy.begin_trip(world,ship,destination)
	check(ship.travel.waypoints == [1,3],"a merchant initially follows the shortest legal plan")
	for i in 120:
		day(world)
		if ship.layer and Vector2(ship.galpos).length() > 0:
			break
	var before: Vector2 = ship.galpos
	var fuel: float = ship.fuel
	var expiry: int = ship.reservation.expires
	world.set_treaty(0,1,-1)
	day(world)
	check(2 in ship.travel.waypoints and 1 not in ship.travel.waypoints and before.distance_to(ship.galpos) < 150,"war during a physical hop changes the remaining route without teleporting")
	check(ship.fuel < fuel and ship.reservation.expires >= expiry and destination.inbound[ship_id].expires == ship.reservation.expires,"the detour burns movement fuel and both copies of its booking agree")
	alternative.flag = 1
	before = ship.galpos
	fuel = ship.fuel
	for i in 3:
		day(world)
	check(ship.has("route_hold") and ship.galpos == before and ship.fuel == fuel and ship.cargo[0] == 12,"no safe corridor holds position, burn and the paid cargo")
	check(not ship.has("reservation") and not destination.inbound.has(ship_id) and not destination.cash_holds.has(ship_id),"indefinite waiting releases the matching port capacity and station cash hold")
	var path := OS.get_temp_dir().path_join("starrail-trade-hold-%d-%d.save" % [OS.get_process_id(),Time.get_ticks_usec()])
	var restored := World.new()
	check(Saves.write(world,path,false) and Saves.read(restored,path),"an interrupted voyage is a valid save state")
	DirAccess.remove_absolute(path)
	var held: Dictionary = restored.ships[ship_id]
	check(held.travel.hold and held.travel.rebook.qty == 12 and held.galpos == before and held.fuel == fuel,"reopening the save preserves the hold, original cargo booking intent and exact remaining fuel")
	restored.ports[alternative.id].flag = restored.NEUTRAL
	day(restored)
	check(held.has("reservation") and held.reservation.loaded and not held.has("route_hold"),"the restored journey can independently reroute and reclaim capacity")
	alternative.flag = world.NEUTRAL
	day(world)
	check(ship.has("reservation") and ship.reservation.loaded and destination.inbound[ship_id].qty == 12 and destination.cash_holds.get(ship_id,0) > 0,"resuming reserves the actual cargo and funds at the receiving port again")
	for i in 240:
		day(world)
		if ship.dock == destination.id:
			break
	check(ship.dock == destination.id and not ship.has("route_hold") and ship.cargo[0] == 12,"reopening a real corridor lets the waiting cargo reach its destination")
	check(ship.has("trade_attack") and ship.hp < world.HULL_HP[ship.kind],"physical out-of-sector patrol damage also reports a real incident")
	world.day += Security.INCIDENT_DAYS+1
	var saved_alerts: Array = []
	world.merchant_attacked.connect(func(message: String): saved_alerts.append(message))
	world.set_treaty(0,1,-1)
	ship.flag = 0
	world.depart(ship)
	enemy.system = ship.system
	world.depart(enemy)
	Combat.ensure_state(ship)
	game.set_speed(1)
	var shot := {"damage":1.0,"type":0,"vel":Vector2.RIGHT,"ship":enemy.id,"flag":enemy.flag,"raid":world.NEUTRAL,"credit":0}
	for n in 6:
		Combat.impact(world,shot,{"ship":ship,"point":ship.pos,"shield":false})
	check(saved_alerts.size() == 1 and game.notice_text.contains("#%d" % ship.id) and game.notice_text.contains(world.systems[ship.system].name) and game.speed == 1 and not world.attention,"real hostile hits show ship and system once without pausing")
	var second := spawn_hauler(world,destination,world.player,0)
	Security.report_attack(world,second,enemy)
	var rows: Array = world.chronicle.filter(func(row): return row[0] == world.day and String(row[1]).begins_with("商船遇袭"))
	check(rows.size() == 1 and rows[0][1].contains("#%d" % second.id) and rows[0][1].contains("#%d" % ship.id),"simultaneous distress from two owned merchant ships shares one journal entry")
	Security.report_attack(world,ally,enemy)
	Security.report_attack(world,ship,second)
	check(saved_alerts.size() == 2,"foreign traffic and friendly contacts produce no player alert")
	game.flight.dock()
	game.set_waypoint(intermediate.pos,"手动航点")
	check(game.waypoint_live and Security.exclusions(world,ship).has(1),"merchant restrictions leave the player's manual navigation controls available")
	game.free()
	print("Merchant security %d/%d" % [checks-failed,checks])
	quit(0 if failed == 0 else 1)
