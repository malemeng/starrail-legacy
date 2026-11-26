extends SceneTree

const Game = preload("res://game.tscn")
const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
const Geometry = preload("res://scripts/models/station_geometry.gd")
var checks := 0
var failures := 0
var game
var film := "--siege-film" in OS.get_cmdline_user_args()
var solo := "--solo-siege" in OS.get_cmdline_user_args()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
	return ok

func hold(frames: int) -> void:
	if film:
		for frame in frames:
			await process_frame

func frame_battle(lead: Dictionary, site: Dictionary, wing: Dictionary = {}, follow: int = -1) -> void:
	if not film:
		return
	var bounds: Rect2 = Geometry.layout(site).bounds
	bounds = bounds.expand(lead.pos).grow(95.0)
	var canvas = game.canvas
	canvas.camera = bounds.get_center()
	canvas.zoom = clampf(minf(canvas.size.x / bounds.size.x,canvas.size.y / bounds.size.y),0.30,1.9)
	if not wing.is_empty() and follow in range(620):
		var blend := clampf(minf(follow/35.0,(620-follow)/35.0),0,1)
		canvas.camera = Vector2(canvas.camera).lerp(wing.pos,blend)
		canvas.zoom = lerpf(canvas.zoom,1.85,blend)
	canvas.queue_redraw()

func treaty_equity() -> void:
	var w = preload("res://world.gd").new()
	w.new_game({"seed":"treaty-site-equity","systems":12,"factions":3,"overrides":[{"regime":4},{"regime":4}]})
	var port_id: int = w.factions[1].capital
	var site: Dictionary = w.ports[port_id]
	site.modules.assign([w.Industry.Module.MINE,w.Industry.Module.SOLAR,w.Industry.Module.REFINERY])
	site.design_cells = [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]
	w.Industry.update_market(site)
	var before: Dictionary = w.StationEquity.cap_table(w,site)
	w.set_treaty(0,1,-1)
	w.WarPeace.occupy(w,port_id,0)
	check(w.StationEquity.cap_table(w,site) == before and site.occupied_from == 1,"temporary occupation leaves the share register intact")
	w.set_treaty(0,1,0)
	check(site.flag == 1 and not site.has("occupied_from") and w.StationEquity.cap_table(w,site)==before,"returning an occupied port restores sovereignty and shares")
	w.set_treaty(0,1,-1)
	w.WarPeace.occupy(w,port_id,0)
	w.WarPeace.add_score(w,0,1,70)
	check(w.WarPeace.sign_peace(w,0,1,[port_id]),"annex in the actual peace negotiation")
	var after: Dictionary = w.StationEquity.cap_table(w,site)
	check(after.factions.get(0,0) == before.company_units and after.company_units==0 and after.total==before.total,"treaty settles the former operator's station shares with the winner")
	check(preload("res://world.gd").new().load_state(w.snapshot()),"winner's public shares can be saved and loaded")

func run() -> void:
	game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.set_physics_process(false)
	var w = game.world
	w.new_game({"seed":"independent-station-battle","systems":12,"factions":3,"avatar":{"name":"许遥","age":32}})
	var home: Dictionary = w.ports[w.ride().dock]
	var owner_id: int = w.random_person(w.NEUTRAL,home.id)
	var port_id: int = w.port(0,"远岬轨道站",Vector2(5200,3500),w.NEUTRAL,owner_id,0)
	var site: Dictionary = w.ports[port_id]
	var firm_id: int = w.incorporate("远岬航运",owner_id,port_id)
	var investor: int = w.random_person(w.NEUTRAL,port_id)
	var table: Dictionary = w.StationEquity.cap_table(w,site)
	table.company_units -= 1
	table.people[investor] = 1
	site.equity = table
	var units := int(table.company_units)
	var guard_id: int = w.ship(Hulls.kind_for_reference("wolf"),0,w.random_person(w.NEUTRAL,port_id),w.NEUTRAL,0,site.pos,port_id)
	var guard: Dictionary = w.ships[guard_id]
	guard.firm = firm_id
	guard.job = {"kind":"巡逻","source":port_id}
	var stranger: Dictionary = w.ships[w.ship(0,investor,investor,w.NEUTRAL,0,site.pos+Vector2(1200,0))]
	var lead_id: int = w.ride().id
	if not solo:
		lead_id = w.ship(Hulls.kind_for_reference("onslaught"),w.player,0,w.NEUTRAL,0,home.pos,home.id)
		w.pilot(lead_id)
	var lead: Dictionary = w.ride()
	w.depart(lead)
	var axis: Vector2 = Geometry.layout(site).outward
	lead.pos = Vector2(site.pos) + axis * 1400.0
	lead.heading = (-axis).angle()
	var escorts: Array[int] = []
	for i in (0 if solo else 2):
		var captain: int = w.random_person(w.NEUTRAL,home.id)
		var pos: Vector2 = lead.pos + axis.orthogonal()*(125.0 if i==0 else -125.0)
		var ship: int = w.ship(Hulls.kind_for_reference("eagle" if i==0 else "dominator"),w.player,captain,w.NEUTRAL,0,pos)
		w.ships[ship].heading = lead.heading
		w.ships[ship].job = {"kind":"护航","system":0}
		escorts.append(ship)
	game.run_bridge()
	game.flight_zoom = 0.36 if film else 1.14
	if not game.side_collapsed:
		game.toggle_side_panel()
	game.update_bridge(0)
	frame_battle(lead,site)
	game.say("距泊位 1,400。中立舰队开始接近远岬航运的轨道站。")
	await hold(55)
	game.hud.attack(port_id)
	var war_key: String = site.get("assault",{}).get("company_war","")
	if not check(w.campaign.get("company_wars",{}).has(war_key) and w.campaign.company_wars[war_key].opponent == w.player,"neutral captain is the named opponent of the newly founded company"):
		game.free()
		quit(1)
		return
	var guns: Array = site.assault.nodes.duplicate()
	var gun: Dictionary = w.ships[guns.front()]
	check(guard.dock == 0 and w.enemy(guard,lead) and not w.enemy(guard,stranger),"company guard sorties against the attacker, other neutrals stay neutral")
	check(guns.size()==site.modules.size()+1 and guns.all(func(id): return w.ships[id].battle.shield and w.ships[id].fit.weapons.size()>0),"every completed module and the core deploy a separate shield and ship weapon slots")
	var adjacent: Dictionary = w.ships[guns[1]]
	check(not is_same(gun.battle,adjacent.battle) and not is_same(gun.fit,adjacent.fit) and not gun.pos.is_equal_approx(adjacent.pos),"module damage, equipment and positions are independent")
	game.hud.attack(port_id)
	check(site.owner == owner_id and site.assault.nodes == guns and site.equity.company_units == units,"repeated capture clicks do not damage defences or transfer shares")
	var resumed = preload("res://world.gd").new()
	check(resumed.load_state(w.snapshot()) and resumed.ships.has(gun.id) and resumed.enemy(resumed.ships[gun.id],resumed.ride()),"siege survives save and reload")
	var shield_hit := false
	var station_fired := false
	var flagship_hit := false
	var sortie := false
	var fighter_fired := false
	var peak_aircraft := 0
	var follow_start := -1
	var chase_camera := {}
	var defeated_at := -1
	var start_hp := float(lead.hp)
	var target_id := 0
	for frame in 7200:
		if not w.ships.has(lead_id) or w.succession:
			break
		var target: Dictionary = {}
		if not site.assault.nodes.is_empty():
			target = w.ships[site.assault.nodes.front()]
		elif w.ships.has(guard_id) and w.enemy(lead,guard):
			target = guard
		if not target.is_empty() and target_id != int(target.id):
			target_id = int(target.id)
			game.selected_target = target_id
			game.flight.issue(2,target_id,escorts)
		var aim: Vector2 = target.get("pos",site.pos)
		var travel: Vector2 = Vector2(site.pos) - Vector2(lead.pos)
		var move := travel.normalized() if travel.length() > 100.0 else Vector2.ZERO
		game.step_simulation(move,true,not target.is_empty(),aim,true)
		if film:
			game.flight_zoom = lerpf(1.65,0.36,clampf((travel.length()-220.0)/1150.0,0,1))
		game.update_bridge(1.0/60)
		if gun.battle.get("shield_flash",0.0) > 0:
			shield_hit = true
		if gun.battle.get("last_fired_target",0) != 0 or w.projectiles.any(func(p): return p.ship in guns):
			station_fired = true
		if not sortie and gun.battle.get("fighter_wings",[]).any(func(wing): return wing.sortie and Vector2(wing.pos).distance_to(gun.pos)>15):
			sortie = true
			print("Hangar launch frame ",frame," distance ",roundi(travel.length()))
		var airborne := 0
		var tracked := {}
		for squad in gun.battle.get("fighter_wings",[]):
			if squad.sortie:
				airborne += int(squad.get("airborne",squad.get("count_live",0)))
				if tracked.is_empty() or squad.count_live > tracked.count_live:
					tracked = squad
		peak_aircraft = maxi(peak_aircraft,airborne)
		if airborne >= 18 and follow_start < 0:
			follow_start = frame
			print("Main air group frame ",frame," aircraft ",airborne)
			if not film:
				check(resumed.load_state(w.snapshot()) and resumed.ships[gun.id].battle.fighter_wings==gun.battle.fighter_wings,"airframe positions, separate runs and cooldowns survive mid-sortie save/load")
		if film and not tracked.is_empty() and (chase_camera.is_empty() or chase_camera.hp<=0 or not chase_camera.sortie or chase_camera.returning):
			for unit in tracked.get("craft",[]):
				if unit.sortie and unit.hp>0 and not unit.returning:
					chase_camera = unit
					break
		frame_battle(lead,site,chase_camera,frame-follow_start if follow_start >= 0 else -1)
		if not fighter_fired and w.projectiles.any(func(p): return p.ship in guns and p.has("wing_id")):
			fighter_fired = true
			print("Wing attack frame ",frame)
		if lead.battle.get("shield_flash",0.0)>0 or lead.hp < start_hp:
			flagship_hit = true
		if site.assault.nodes.is_empty() and game.flight.target(lead,510.0)==0 and travel.length()<=148.0:
			game.hud.attack(port_id)
			if not site.has("assault"):
				defeated_at = frame
				break
		if film and frame % 2 == 0:
			await process_frame
	check(station_fired and flagship_hit,"real station fire hit the fleet")
	check(sortie and fighter_fired,"station air groups actually launch and fire on the approaching fleet")
	if solo:
		check(defeated_at < 0 and site.owner == owner_id and (not w.ships.has(lead_id) or lead.hp < start_hp),"unsupported starter cannot claim the defended station")
		print("Lone starter ",checks-failures,"/",checks," captured=",defeated_at>=0," flagship survives=",w.ships.has(lead_id))
		game.free()
		quit(1 if failures else 0)
		return
	check(shield_hit,"incoming fire strikes the station shield")
	check(defeated_at >= 0 and site.owner == w.player and site.firm == 0,"neutral squadron can accept surrender after winning the battle")
	var final: Dictionary = w.StationEquity.cap_table(w,site)
	check(final.people.get(w.player,0)==units and final.people.get(investor,0)==1 and final.company_units==0,"station stake changes hands and minority investor keeps their share")
	check(w.firms.has(firm_id) and w.people[owner_id].shares.has(firm_id) and resumed.load_state(w.snapshot()),"company shares and completed capture survive reload")
	check(w.CompanyWars.end_asset_war(w,war_key) and not w.enemy(guard,lead) and not w.campaign.company_wars.has(war_key),"ceasefire removes the conflict between company and neutral captain")
	print("Siege frames ",defeated_at," shield hits=",shield_hit," station fired=",station_fired," flagship hit=",flagship_hit," modules=",guns.size()," peak aircraft=",peak_aircraft," fleet_hp=",lead.hp," shares=",units)
	if defeated_at>=0 and film:
		game.set_speed(0)
		game.say("远岬轨道站已投降：许遥取得原企业持有的 %d 股本站股份。" % units)
		game.update_bridge(0)
		frame_battle(lead,site)
		await hold(110)
	if not film:
		treaty_equity()
	game.free()
	print("Company station battle ", checks-failures, "/", checks)
	quit(1 if failures else 0)

func _initialize() -> void:
	run.call_deferred()
