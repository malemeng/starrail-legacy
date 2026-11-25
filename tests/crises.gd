extends SceneTree

const World = preload("res://world.gd")
const Crises = preload("res://scripts/campaign/crises.gd")
const Economy = preload("res://economy.gd")
const Battle = preload("res://combat.gd")
const Industry = preload("res://scripts/economy/industry.gd")
var failures := 0
var total := 0

func check(condition: bool, description: String) -> void:
	total += 1
	if not condition:
		failures += 1
		printerr("FAIL ",description)

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var world = World.new()
	world.new_game({"seed":"outer-challenge","systems":24,"factions":5,"avatar":{"name":"舰队主管","house":"群星"}})
	world.ensure_chunks_around(Vector2(3400,3600),0)
	var index: int = world.core_count
	world.mark_seen(index)
	var region: Dictionary = world.systems[index]
	var lead: Dictionary = world.ride()
	world.depart(lead)
	lead.system = index
	lead.pos = region.field
	lead.galpos = region.pos
	Economy.record_mining(world,index,100)
	world.tick(6)
	check(region.get("mine_signal","") == "active","normal daily tick activates region-specific mining signal")
	check(Crises.act(world,"investigate") and not Crises.act(world,"investigate"),"in-person sensor investigation reveals encounter exactly once")
	var enemies: Array = region.get("threat_units",[])
	check(enemies.size() >= 2,"hidden enemies materialize in current world")
	for id in enemies:
		var target: Dictionary = world.ships[id]
		check(Battle.available(target,index) and world.enemy(lead,target) and lead.pos.distance_to(target.pos)<255,"hidden hull enters standard combat acquisition range")
		target.hp = 0.1
		target.battle.armor = 0
		lead.heading = lead.pos.angle_to_point(target.pos)
		Battle.ensure_state(lead)
		check(Battle.group_fire(world,lead,1,target.pos,target.id)>0,"flagship fires installed weapon at encountered hull")
		for frame in range(110):
			Battle.project(world,index,1.0/60.0)
			Battle.tick(lead,1.0/60.0)
		check(not world.ships.has(id),"resolved projectile destroys hidden ship and leaves wreck")
	world.tick(6)
	check(region.mining_heat == 0 and region.get("recovery_until",0) > world.day,"destroyed group clears heat and starts cooldown")
	check(Crises.act(world,"swarm") and not Crises.act(world,"swarm"),"outer-sector factory activation")
	var machine: Dictionary = world.campaign.crises.swarm
	var tender: Dictionary = world.ships[machine.miner]
	var from: Vector2 = tender.pos
	var moving := {}
	Crises.move_visible(world,index,true,0.25,moving)
	check(moving.is_empty() and tender.pos==from,"local tender stays off the hyperspace movement clock")
	Crises.move_visible(world,index,false,0.25,moving)
	var quarter: Vector2 = tender.pos
	check(moving.has(tender.id) and is_equal_approx(from.distance_to(quarter),float(Crises.rules.swarm.miner_units_per_day)*0.25),"the actual tender moves a fractional day in view")
	Crises.daily(world,moving)
	check(tender.pos==quarter,"daily mining logic leaves the rendered tender's actual position alone")
	var initial: int = region.ore
	world.tick(110)
	check(machine.built > 0 and region.ore < initial and not machine.escorts.is_empty(),"manufacturing actually mines, transfers, consumes resources and builds a combat hull")
	var factory: Dictionary = world.ships[machine.factory]
	world.destruction(machine.miner)
	factory.cargo[Industry.Ware.ORE] = 0
	var old_built: int = machine.built
	world.tick(90)
	check(machine.built == old_built,"destroying the miner blocks the next replacement")
	world.destruction(machine.factory)
	world.tick()
	check(machine.status == "defeated","factory destruction terminates reproduction")
	var port_id: int = world.port(0,"外环要塞",Vector2(340,-80),world.NEUTRAL,world.player,Industry.Module.YARD)
	world.berth(lead,port_id)
	world.active().wallet = 25000
	check(Crises.act(world,"challenge",port_id),"wealthy colony triggers coalition")
	var embargo: Dictionary = world.campaign.crises.blockade
	var distant: Dictionary = world.ships[embargo.forces[0]]
	distant.layer = true
	distant.system = 1
	distant.galpos = world.systems[0].pos+Vector2(30,0)
	moving.clear()
	Crises.move_visible(world,0,true,0.25,moving)
	check(moving.has(distant.id) and is_equal_approx(distant.galpos.distance_to(world.systems[0].pos),20.0),"coalition warship approaches the beacon continuously in hyperspace")
	Crises.daily(world,moving)
	check(distant.layer and is_equal_approx(distant.galpos.distance_to(world.systems[0].pos),20.0),"daily mobilization retains the subday hyperspace position")
	Crises.move_visible(world,0,true,0.5,moving)
	check(not distant.layer and distant.system==0,"coalition ship crosses the physical target beacon into the local system")
	from = distant.pos
	Crises.move_visible(world,0,false,0.25,moving)
	check(is_equal_approx(from.distance_to(distant.pos),float(Crises.rules.blockade.patrol_units_per_day)*0.25),"local blockade approach uses the same fraction of a campaign day")
	world.tick(38)
	var port: Dictionary = world.ports[port_id]
	check(embargo.status == "active" and port.get("coalition_blockade",false),"mobilized ships arrive to enforce a physical blockade")
	check(not Economy.allowed(world,lead,port) and not embargo.forces.is_empty(),"public trade halts during blockade")
	var patrol: Dictionary = world.ships[embargo.forces[0]]
	check(world.enemy(lead,patrol) and world.enemy({"ship":patrol.id,"flag":patrol.flag,"raid":-1},lead),"coalition hostility applies to own ships and projectile contacts")
	check(Crises.act(world,"negotiate") and not Crises.act(world,"negotiate"),"negotiation lifts blockade only once")
	check(Economy.allowed(world,lead,port),"public trade restored")
	print("Crisis checks %d/%d" % [total-failures,total])
	quit(1 if failures else 0)
