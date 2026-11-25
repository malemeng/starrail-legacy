extends SceneTree

const Game = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
const Battle = preload("res://combat.gd")
const World = preload("res://world.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var world: World = game.world
	world.new_game({"seed":"local-incident","systems":12,"factions":3})
	game.run_bridge()
	var bridge := Bridge.new()
	bridge.game = game
	var lead := world.ride()
	var actor := world.active()
	world.depart(lead)
	lead.pos = Vector2(30000,30000)
	lead.heading = 0.0
	lead.flag = 0
	actor.flag = 0
	var id := world.ship(1,0,0,0,lead.system,lead.pos+Vector2(95,0))
	var target: Dictionary = world.ships[id]
	var bystander: Dictionary = world.ships[world.ship(1,0,0,0,lead.system,lead.pos+Vector2(95,90))]
	check(not world.enemy(lead,target) and bridge.visible_target(lead,id) and not bridge.visible_target(lead,lead.id),"same-faction ship can be selected, own flagship cannot")
	game.selected_target = game.flight.target_at(lead,target.pos,20,true)
	check(game.selected_target == id and world.faction_trust(0,actor.id) == 0,"selection is peaceful")
	var armor: float = target.battle.armor
	var hp: float = target.hp
	lead.battle.group = 0
	Battle.train(lead,target.pos,2.0)
	check(game.flight.fire(lead,target.pos) > 0 and world.enemy(lead,target) and world.enemy(target,lead),"a real shot starts local combat against the selected ally")
	for frame in 35:
		Battle.project(world,lead.system,1.0/60)
	check(target.hp < hp or target.battle.armor < armor,"the projectile struck the selected hull")
	check(not world.enemy(lead,bystander) and world.faction_trust(0,actor.id) == -25 and world.faction_trust(1,actor.id) == 0,"only one faction penalizes the actual instigator")
	world.engage_ship(lead,target,actor.id)
	check(world.faction_trust(0,actor.id) == -25,"continued fire does not repeat the incident")
	var office: Dictionary = world.ports[world.systems[1].ports[0]]
	office.flag = 0
	office.manager = 0
	check(not world.Politics.employ_as_manager(world,actor.id,office.id),"distrusted applicant is refused an appointment")
	world.change_faction_trust(0,actor.id,4,"完成货运委托")
	var saved := World.new()
	check(saved.load_state(world.snapshot()) and saved.faction_trust(0,actor.id) == -21 and saved.enemy(saved.ships[lead.id],saved.ships[id]),"incident and character-specific trust survive load")
	var records: Dictionary = bridge.dispatch("faction_trust",{}).result
	check(records.factions.filter(func(f): return f.flag == 0 and f.score == -21 and f.last_change.change == 4).size() == 1,"bridge exposes score and reason")
	saved.day += 31
	check(not saved.enemy(saved.ships[lead.id],saved.ships[id]),"the local incident can expire independently of trust")
	var neutral: Dictionary = world.ships[world.ship(0,0,0,world.NEUTRAL,lead.system,lead.pos+Vector2(100,40))]
	check(bridge.dispatch("attack_target",{"target":neutral.id}).ok and game.autopilot and game.flight._autopilot_target(lead) == neutral.id,"flagship autopilot engages an explicitly selected neutral contact")
	game.queue_free()
	print("Target selection and faction trust ",checks-failures,"/",checks)
	quit(1 if failures else 0)
