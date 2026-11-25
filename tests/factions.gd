extends SceneTree

const World = preload("res://world.gd")
const Society = preload("res://scripts/campaign/society.gd")
const Politics = preload("res://politics.gd")
const Hulls = preload("res://hull_catalog.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	call_deferred("run")

func scenario(kind: String, player_ruler: bool = false) -> Dictionary:
	var world := World.new()
	world.new_game({"seed":"interior-"+kind,"systems":24,"factions":5,"avatar":{"name":"政治验收"}})
	var group: Dictionary = world.factions[0]
	var seat: Dictionary = world.ports[group.capital]
	var sites := world.systems_owned(0)
	sites.erase(seat.id)
	var port: Dictionary = world.ports[sites.pop_front()]
	for id in sites:
		world.ports[id].flag = world.NEUTRAL
	if player_ruler:
		group.leader = world.player
		world.active().flag = 0
	var leader: Dictionary = world.people[group.leader]
	var official: Dictionary = world.people[port.manager]
	leader.personality.boldness = 65
	leader.legitimacy = 2
	leader.spouse = 0
	seat.owner = group.leader
	port.owner = 0
	official.opinions[group.leader] = -85
	official.birth = -35*360
	official.noble = false
	group.regime = 1
	if kind == "independence":
		port.owner = official.id
		official.personality.boldness = 45
	elif kind == "claimant":
		group.regime = 0
		official.noble = true
		leader.legitimacy = 0
		leader.designated_heir = official.id
	elif kind == "shareholders":
		group.regime = 4
		var holding := world.Equity.establish(world,0)
		for member in world.people.values():
			member.shares.erase(holding)
		official.shares[holding] = 60
		leader.shares[holding] = 40
	seat.defense = 40
	port.defense = 44
	for ship in world.ships.values():
		if ship.flag == 0:
			ship.flag = world.NEUTRAL
	var guard_id := 0
	for site in [seat,port]:
		var captain := world.random_person(0,site.id)
		var vessel := world.ship(Hulls.kind_for_reference("wolf"),0,captain,0,site.system,site.pos)
		world.ships[vessel].job = {"kind":"护航","system":site.system}
		if site.id == port.id:
			guard_id = vessel
	return {"world":world,"group":group,"leader":leader,"port":port,"seat":seat,"official":official,"guard":guard_id}

func month(case: Dictionary) -> void:
	case.world.day += 30
	Society.advance_movement(case.world,0)

func demand(case: Dictionary) -> Dictionary:
	for _month in range(26):
		month(case)
		var bloc: Dictionary = case.world.campaign.movements.get(0,{})
		if bloc.get("ultimatum",false):
			return bloc
	return {}

func treasury(world) -> int:
	var total := 0
	for group in world.factions.values():
		total += int(group.treasury)
	return total

func run() -> void:
	var camp := scenario("autonomy",true)
	var world = camp.world
	camp.seat.defense = 1400
	for _month in range(15):
		month(camp)
	check(world.campaign.movements[0].discontent == 0,"fleet and garrison strength below eighty percent cannot issue demands")
	camp.seat.defense = 40
	camp.leader.dread = 100
	camp.official.personality.boldness = -10
	month(camp)
	check(not world.campaign.movements.has(0),"terrified station manager leaves the faction")
	camp.leader.dread = 0
	camp.official.personality.boldness = 45
	camp.leader.hooks[camp.official.id] = {"kind":"smuggling","strength":2,"expires":world.day+720}
	month(camp)
	check(not world.campaign.movements.has(0),"strong hook prevents enrollment")
	check(Society.use_hook(world,camp.official.id),"ruler can spend hook to bind an official")
	for _month in range(5):
		month(camp)
	check(not world.campaign.movements.has(0),"bound official stays out after spending hook")
	camp.official.bound_until = world.day-1
	var motion := demand(camp)
	check(motion.get("kind","") == "autonomy" and camp.guard in motion.get("ships",[]),"actual manager and local fleet present an autonomy ultimatum")
	var old_rate: float = camp.port.tax_rate
	month(camp)
	check(world.campaign.movements[0].ultimatum and camp.port.tax_rate == old_rate,"player's response stays open")
	var saved = World.new()
	check(saved.load_state(world.snapshot()) and saved.campaign.movements[0].ultimatum,"live ultimatum survives saving")
	check(Society.answer_ultimatum(saved,0,true) and saved.ports[camp.port.id].tax_rate < old_rate and not Society.answer_ultimatum(saved,0,true),"concession lowers actual rate once")
	for kind in ["independence","claimant","shareholders"]:
		camp = scenario(kind)
		world = camp.world
		var count: int = world.factions.size()
		var budget := treasury(world)
		var hulls: int = world.ships.size()
		camp.leader.personality.boldness = -75
		motion = demand(camp)
		check(motion.get("kind","") == kind and motion.get("candidate",0) == camp.official.id,"NPC subjects organize "+kind)
		check(not Society.answer_ultimatum(world,0,false),"player cannot answer for an NPC ruler")
		month(camp)
		if kind == "independence":
			check(camp.port.flag != 0 and not world.hostile(0,camp.port.flag) and world.ships[camp.guard].flag == camp.port.flag,"NPC can grant peaceful independence with existing port and guard")
		else:
			check(camp.group.leader == camp.official.id and world.factions.size() == count,"concession transfers the existing public office "+kind)
			if kind == "shareholders":
				check(world.firms[camp.group.firm].director == camp.official.id and camp.official.shares[camp.group.firm] == 60,"shareholders remove the board chair without minting shares")
		check(treasury(world) == budget and world.ships.size() == hulls,"no new money or ships on concession "+kind)
	camp = scenario("autonomy")
	world = camp.world
	var budget := treasury(world)
	var hulls: int = world.ships.size()
	motion = demand(camp)
	check(not motion.is_empty(),"NPC receives credible ultimatum")
	month(camp)
	var rebel: int = camp.port.flag
	check(rebel != 0 and world.hostile(0,rebel) and Politics.rival(world,rebel,camp.port).id == camp.seat.id,"refusal starts a civil war aimed at loyalist capital")
	check(world.ships[camp.guard].flag == rebel and world.ships.size() == hulls and treasury(world) == budget,"civil war reallocates real forces and treasury")
	if rebel != 0:
		var rate: float = camp.port.tax_rate
		check(world.ships[camp.guard].job.get("target",0) == camp.seat.id,"a participating guard mobilizes against the loyalist seat")
		for flag in world.factions:
			world.factions[flag].npc = flag == rebel
		camp.seat.defense = 1
		world.day += 60
		Politics.military(world)
		check(world.ships[camp.guard].job.get("arrived",false),"rebel guard arrives for the siege")
		world.day += 30
		Politics.military(world)
		check(not world.factions[rebel].alive and camp.port.flag == 0 and world.ships[camp.guard].flag == 0 and camp.port.tax_rate < rate,"rebel victory reunifies the state and enacts its charter")
		check(treasury(world) == budget and world.ships.size() == hulls,"war settlement conserves treasury and fleets")
		var last_count: int = world.factions.size()
		camp.seat.defense = 40
		world.ships[camp.guard].system = camp.port.system
		world.ships[camp.guard].job = {"kind":"护航","system":camp.port.system}
		world.day += 721
		demand(camp)
		month(camp)
		check(camp.port.flag == rebel and world.factions.size() == last_count,"repeated rebellion from the same seat reuses its political identity")
		Politics.conquer(world,camp.port.id,0)
		check(not world.factions[rebel].alive and not world.hostile(0,rebel) and camp.port.flag == 0 and treasury(world) == budget,"loyalist military victory ends war")
	if "--soak" in OS.get_cmdline_user_args():
		var live := World.new()
		live.new_game({"seed":"industrial-soak","systems":24,"factions":5,"avatar":{"name":"旁观员"}})
		live.tick(10000)
		check(live.day == 10000 and live.factions.size() <= 5+live.ports.size(),"ten thousand normal simulation days with bounded polity count")
		for flag in live.factions:
			var group: Dictionary = live.factions[flag]
			check(group.treasury >= 0 and (not group.alive or live.people[group.leader].alive and live.ports[group.capital].flag == flag),"surviving government controls its capital")
	print("Faction checks %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
