extends SceneTree

const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")

class Arena extends RefCounted:
	var ships := {}
	var projectiles: Array = []
	var events: Array = []
	var people := {}
	var day := 1
	var attention := false
	var succession := false

	func enemy(a, b):
		return a.flag != b.flag

	func combat_event(kind, pos, _system, _dir = Vector2.ZERO, _strength = 1):
		events.append([kind,pos])

	func destruction(id, _credit):
		ships.erase(id)

var failed := 0
var checked := 0

func check(ok: bool, label: String) -> void:
	checked += 1
	if not ok:
		failed += 1
		if failed <= 15:
			printerr("COLLISION FAIL ",label)

func add_ship(arena: Arena, kind: int, id: int, pos: Vector2, team: int) -> Dictionary:
	var ship := {"id":id,"flag":team,"system":0,"kind":kind,"owner":id,"raid":-1,"captain":0,"locked":true,
		"dock":0,"pos":pos,"heading":0.0,"layer":false,"hp":100000.0,"crew":200,"cargo":[],
		"fit":Hulls.stock_fit(kind),"battle":Hulls.battle_state(kind)}
	Battle.ensure_state(ship)
	arena.ships[id] = ship
	return ship

func shot(at: Vector2, to: Vector2, damage: float) -> Dictionary:
	return {"ship":1,"system":0,"flag":1,"raid":-1,"credit":0,"pos":at,"vel":to-at,
		"hp":20.0,"damage":damage,"type":2,"life":1.0,"missile":false,"target":0}

func compare_rays() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 81925
	for kind in Hulls.MODELS.size():
		var arena := Arena.new()
		var body := add_ship(arena,kind,2,Vector2(13,-21),2)
		body.heading = rng.randf_range(-PI,PI)
		body.battle.shield = true
		body.battle.shield_offset = .6
		body.battle.shield_arc_live = 1.7
		Battle.prepare_collision(arena,0)
		var radius: float = Battle.Defenses.geometry(kind).module_radius + 15
		for j in 32:
			var a := Vector2(body.pos)+Vector2.from_angle(rng.randf_range(-PI,PI))*rng.randf_range(0,radius*1.4)
			var b := Vector2(body.pos)+Vector2.from_angle(rng.randf_range(-PI,PI))*rng.randf_range(0,radius*1.4)
			var bullet := shot(a,b,1)
			var reference := Battle.trace(arena,bullet,a,b)
			var actual := Battle.native_contact(arena,bullet,a,b,{})
			var same := reference.is_empty() == actual.is_empty()
			if same and not actual.is_empty():
				same = actual.shield == reference.shield and actual.get("module",{}).get("mount","") == reference.get("module",{}).get("mount","") and actual.point.distance_to(reference.point) < .025
			check(same,"%s ray %d %s -> %s" % [Hulls.hull_id(kind),j,a,b])

func encounter(scenario: String) -> Dictionary:
	var arena := Arena.new()
	var ally := add_ship(arena,Hulls.kind_for_reference("kite"),5,Vector2(100,0),1)
	var near := add_ship(arena,Hulls.kind_for_reference("kite"),2,Vector2(200,0),2)
	var far := add_ship(arena,Hulls.kind_for_reference("kite"),3,Vector2(300,0),2)
	var a := Vector2.ZERO
	var b := Vector2(450,0)
	match scenario:
		"shield":
			near.battle.shield = true
			near.battle.shield_arc_live = TAU
			near.battle.shield_offset = PI
			near.battle.soft_flux = Hulls.capacity(near) - .2
		"module":
			near = add_ship(arena,Hulls.kind_for_reference("onslaught_mk1"),2,Vector2(190,0),2)
			var part: Dictionary = Hulls.MODELS[near.kind].modules[0]
			a = Vector2(near.pos)+Vector2(part.offset)
			b = a + Vector2(0,1)
		"mine":
			var mine := shot(near.pos,near.pos,10)
			mine.mine = true
			mine.arming = 0.1
			arena.projectiles.append(mine)
		"screen":
			var screen := Battle.Abilities.Ordnance.spawn(arena,far,"screen",Vector2(150,0),Vector2.ZERO,2.0,12.0)
			screen.hp = 5.0
		"casualty":
			near.hp = .01
	for i in 3:
		arena.projectiles.append(shot(a,b,15000.0 if scenario=="module" else 50.0))
	Battle.project(arena,0,1.0)
	return {"near_hp":near.hp,"far_hp":far.hp,"ally_hp":ally.hp,"armor":near.battle.armor,"flux":near.battle.hard_flux,
		"overload":near.battle.overload,"parts":near.battle.get("module_integrity",{}),"events":arena.events,"live":arena.ships.keys(),"shots":arena.projectiles.size()}

func compare_fire_control() -> void:
	var scanner := Battle.fire_control
	check(scanner != null,"Windows fire control is registered")
	if scanner == null:
		return
	var arena := Arena.new()
	var ship := add_ship(arena,Hulls.kind_for_reference("onslaught"),2,Vector2(26,-32),2)
	var reference := ship.duplicate(true)
	var hostile := shot(ship.pos+Vector2(45,0),ship.pos,1)
	var missiles: Array = scanner.begin_frame(arena.projectiles,0)
	check(missiles.is_empty() and not scanner.imminent(arena,ship,arena.projectiles),"empty threat index")
	arena.projectiles.append(hostile)
	check(scanner.imminent(arena,ship,arena.projectiles),"a shot fired later in the tick is visible")
	hostile.vel = -hostile.vel
	check(not scanner.imminent(arena,ship,arena.projectiles),"index honors a changed course")
	for i in ship.battle.cooldowns.size():
		ship.battle.cooldowns[i] = .75
		reference.battle.cooldowns[i] = .75
	for target in [Vector2(70,-20),Vector2(-80,3),Vector2(-90,-34)]:
		Battle.fire_control = null
		Battle.train(reference,target,.17)
		Battle.tick(reference,.17)
		Battle.fire_control = scanner
		Battle.train(ship,target,.17)
		Battle.tick(ship,.17)
		for i in ship.battle.cooldowns.size():
			check(absf(angle_difference(ship.battle.turret_angles[i],reference.battle.turret_angles[i]))<.00001 and is_equal_approx(ship.battle.cooldowns[i],reference.battle.cooldowns[i]),"turret %d aim and cooldown" % i)

func _initialize() -> void:
	var has_native := Battle.prepare_collision(Arena.new(),0)
	if not has_native and OS.get_name() == "Windows" and "--script-collision" not in OS.get_cmdline_user_args():
		check(false,"native backend must load on Windows x86_64")
	if has_native:
		compare_rays()
		compare_fire_control()
	var engine := Battle.collision_engine
	for scenario in ["nearest","shield","module","mine","screen","casualty"]:
		Battle.collision_engine = null
		var reference := encounter(scenario)
		Battle.collision_engine = engine
		var actual := encounter(scenario)
		for key in ["near_hp","far_hp","ally_hp","armor","flux","overload"]:
			check(is_equal_approx(reference[key],actual[key]),scenario+" "+key)
		for key in ["parts","live","shots"]:
			check(reference[key]==actual[key],scenario+" "+key)
		check(reference.events.size()==actual.events.size(),scenario+" events")
		for i in mini(reference.events.size(),actual.events.size()):
			check(reference.events[i][0]==actual.events[i][0] and actual.events[i][1].distance_to(reference.events[i][1])<.025,scenario+" event %d"%i)
		match scenario:
			"nearest": check(actual.near_hp<100000 and actual.far_hp==100000 and actual.ally_hp==100000,"nearest hostile")
			"shield": check(actual.overload>0 and actual.near_hp<100000,"shield overloaded then hull hit")
			"module": check(not actual.parts.is_empty() and actual.parts.values()[0].hp==0,"module destroyed")
			"mine": check(actual.events.any(func(e):return e[0]=="rupture"),"area mine detonated")
			"screen": check(actual.events.any(func(e):return e[0]=="intercept"),"screen intercepted")
			"casualty": check(2 not in actual.live and actual.far_hp<100000,"same-frame removal exposes next hull")
	print("COLLISION_PARITY native=",has_native," checks=",checked," failed=",failed)
	quit(1 if failed else 0)
