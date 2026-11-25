extends SceneTree

const World = preload("res://world.gd")
const Economy = preload("res://economy.gd")
const Area = Economy.OperatingArea
const Industry = Economy.Industry
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := World.new()
	world.new_game({"seed":"fixed-homeport","systems":12,"factions":3})
	var home: Dictionary = world.ports[world.ride().dock]
	var other: Dictionary = world.ports[world.systems[1].ports[0]]
	var local: Dictionary = world.ports[world.systems[0].planets[0].port_id]
	var worker := world.random_person(world.NEUTRAL,home.id)
	var ship: Dictionary = world.ships[world.ship(1,world.player,worker,world.NEUTRAL,0,home.pos,home.id)]
	world.active().wallet += 2000
	world.people[worker].employer = world.player
	world.mark_seen(1)
	for p: Dictionary in world.ports.values():
		p.exports = []
		p.imports = []
	for region: Dictionary in world.systems:
		region.ore = 0
	other.stock[0] = 0
	home.stock[0] = 200
	home.exports = [0]
	other.imports = [0]
	check(Economy.assign(world,ship.id,worker,"自动贸易") and Area.settings(world,ship).port == home.id,"enabling automatic trade anchors the ship at its actual base")
	check(Area.configure(world,ship.id,home.id,0) and Area.coverage(world,ship).keys() == [0] and Economy.trade_plan(world,ship).is_empty(),"a same-system trader declines the only profitable sale across one jump")
	check(Area.configure(world,ship.id,home.id,1) and Economy.trade_plan(world,ship).get("target",0) == other.id,"one jump unlocks a profitable route without expanding the hold")
	world.berth(ship,other.id)
	check(Area.settings(world,ship).port == home.id and Area.settings(world,ship).system == 0,"landing at another market never moves the home port")
	var reachable := Economy.reachable_systems(world,0,1,[])
	var far: Dictionary = {}
	for p: Dictionary in world.ports.values():
		if not reachable.has(p.system):
			far = p
			break
	check(not far.is_empty() and Economy.trip_plan(world,ship,1,ship.pos,false,far).is_empty(),"an automatic voyage cannot target an out-of-area system")
	world.berth(ship,home.id)
	ship.job.merge({"source":home.id,"target":other.id,"ware":0,"phase":0},true)
	check(Economy.reserve(world,ship,home,other,0,3) and Economy.exchange(world,ship,home,0,3),"confirmed freight physically loads before a radius change")
	ship.job.phase = 1
	check(Area.configure(world,ship.id,home.id,0) and Area.settings(world,ship).jumps == 1 and ship.next_operating_area.jumps == 0 and other.inbound.has(ship.id),"shrinking the radius preserves the existing freight and its delivery booking")
	world.berth(ship,other.id)
	Economy.step_ship(world,ship)
	Economy.step_ship(world,ship)
	check(ship.cargo[0] == 0 and not other.inbound.has(ship.id) and Area.settings(world,ship).jumps == 0 and not ship.has("next_operating_area"),"after delivering the reserved cargo the next decision uses the new fixed radius")
	world.systems[1].ore = 200
	local.modules.append(Industry.Module.REFINERY)
	check(Economy.assign(world,ship.id,worker,"自动采矿") and Economy.mining_plan(world,ship).is_empty(),"mining checks both the extraction and sale systems against the home radius")
	check(Area.configure(world,ship.id,home.id,1) and not Economy.mining_plan(world,ship).is_empty(),"a mine within one safe jump becomes available")
	home.owner = world.player
	check(Economy.assign_station_duty(world,ship.id,home.id,"站属采矿") and not Area.configure(world,ship.id,other.id,1),"station-owned work uses the assigned port as its center")
	check(Area.configure(world,ship.id,home.id,0) and Economy.station_mining_plan(world,ship,home).is_empty(),"station miners also honor a same-system restriction")
	var restored := World.new()
	check(restored.load_state(world.snapshot()) and Area.settings(restored,restored.ships[ship.id]) == Area.settings(world,ship),"operating radius and home port survive a campaign reload")
	check(not Area.configure(world,ship.id,home.id,-1) and not Area.configure(world,ship.id,home.id,int(Industry.RULES.operating_area.maximum_jumps)+1),"invalid work radii cannot change the policy")
	print("Automatic trade and mining ranges ",checks-failures,"/",checks)
	quit(1 if failures else 0)
