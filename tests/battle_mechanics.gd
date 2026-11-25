extends SceneTree

const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
const ShipVisual = preload("res://scripts/battle/ship_visual.gd")
const Sensors = preload("res://scripts/battle/sensors.gd")
var failures := 0
var checks := 0

class Arena:
	extends RefCounted
	var ships := {}
	var projectiles: Array = []
	var events: Array = []
	var people := {}
	var day := 54
	var succession := false
	var attention := false
	func combat_event(kind, point, system, direction = Vector2.RIGHT, strength = 1.0):
		events.append([kind, point, system, direction, strength])
	func enemy(a, b):
		return a.flag != b.flag
	func destruction(id, _credit):
		ships.erase(id)

func vessel(id: int, team: int) -> Dictionary:
	return {"id":id,"flag":team,"system":0,"kind":0,"owner":id,"raid":-1,"captain":0,"locked":true,"dock":0,
		"pos":Vector2.ZERO,"heading":0.0,"layer":false,"travel":{},"hp":1000.0,"crew":40,"cargo":[],
		"fit":Hulls.stock_fit(0),"battle":Hulls.battle_state(0)}

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func design(arena: Arena,reference: String,id: int,team: int,at: Vector2) -> Dictionary:
	var ship := vessel(id,team)
	ship.kind = Hulls.kind_for_reference(reference)
	ship.fit = Hulls.stock_fit(ship.kind)
	ship.battle = Hulls.battle_state(ship.kind)
	ship.hp = Hulls.MODELS[ship.kind].hp
	ship.pos = at
	ship.galpos = at
	arena.ships[id] = ship
	Battle.ensure_state(ship)
	return ship

func systems_and_campaign() -> void:
	var arena := Arena.new()
	var seen := {}
	for model in Hulls.MODELS:
		var source: String = model.get("source_system","")
		if source.is_empty() or seen.has(source):
			continue
		seen[source] = true
		var ship := design(arena,model.reference,1,1,Vector2.ZERO)
		var foe := design(arena,"kite",2,2,Vector2(95,0))
		ship.fit.caps = 99
		var has_spec := Battle.Abilities.profiles.has(source)
		var fired := Battle.system(arena,ship,Vector2.RIGHT)
		check(has_spec and fired and ship.battle.system_cd > 0 and not Battle.system(arena,ship,Vector2.RIGHT),"active system "+source)
		if source == "entropyamplifier":
			check(foe.battle.get("vulnerability",0) > 1 and foe.battle.get("vulnerability_time",0)>0,"entropy field changes target damage")
		arena.projectiles.clear()
	check(seen.size() == 43, "all 43 source system ids execute")
	var doom := design(arena,"doom",1,1,Vector2.ZERO)
	var foe := design(arena,"kite",2,2,Vector2(105,0))
	Battle.shield(doom,true)
	check(Battle.phased(doom) and Battle.system(arena,doom,Vector2.RIGHT) and arena.projectiles[0].mine,"Doom uses mine strike while sustaining phase")
	var before: float = foe.hp
	Battle.project(arena,0,0.2)
	check(foe.hp == before,"mine observes arming time")
	Battle.project(arena,0,0.6)
	check(foe.hp < before and arena.projectiles.is_empty(),"armed mine detonates at a hostile hull")
	var rig := design(arena,"crig",3,1,Vector2.ZERO)
	arena.projectiles.append({"system":0,"ship":2,"flag":2,"missile":true,"pos":Vector2(15,0),"hp":15.0})
	Battle.system(arena,rig,Vector2.RIGHT)
	check(arena.projectiles[0].hp == 15 and arena.projectiles[1].ordnance == "flare" and rig.pos == Vector2.ZERO,"salvage rig launches physical decoys before a missile collides")
	var modular := design(arena,"onslaught_mk1",4,1,Vector2.ZERO)
	var part: Dictionary = Hulls.MODELS[modular.kind].modules[0]
	var where: Vector2 = part.offset
	var surface := Battle.Defenses.module_contact(modular,where,where+Vector2(0,10))
	var chassis: float = modular.hp
	var hit := {"ship":2,"system":0,"damage":part.hp+float(part.armor)*0.5,"type":1,"vel":Vector2.UP,"credit":2,"flag":2}
	if surface.has("module"):
		Battle.impact(arena,hit,{"ship":modular,"point":surface.point,"shield":false,"module":surface.module})
	check(surface.has("module") and modular.battle.get("module_integrity",{}).get(part.mount,{}).get("hp",1)==0 and modular.hp==chassis,"independent outer module absorbs damage and breaks")
	check(Battle.Defenses.module_contact(modular,where,where+Vector2(0,10)).is_empty(),"destroyed module clears its collision shape")
	foe.captain = 901
	arena.people[901] = {"injured_until":-1}
	foe.hp = Hulls.MODELS[foe.kind].hp * 0.25 + 1.0
	Battle.hit(arena,foe,8,1,foe.pos,Vector2.UP)
	check(foe.hp>0 and arena.people[901].injured_until==arena.day+30,"surviving captain is wounded by critical hull damage")
	var contact := design(arena,"kite",5,2,Vector2(190,0))
	var lead := design(arena,"kite",6,1,Vector2.ZERO)
	contact.transponder = true
	var bright := Sensors.npc_contact(lead,contact)
	contact.transponder = false
	contact.battle.silent_running = true
	check(bright and not Sensors.npc_contact(lead,contact),"silent running breaks passive hostile detection")
	lead.ping = 2.0
	check(Sensors.npc_contact(lead,contact),"active ping reveals a silent contact")
	var ai_gunner := design(arena, "hammerhead", 7, 1, Vector2.ZERO)
	var phased_foe := design(arena, "doom", 8, 2, Vector2(95, 0))
	ai_gunner.heading = 0.0
	Battle.shield(phased_foe, true)
	arena.projectiles.clear()
	Battle.auto_fire(arena, ai_gunner, phased_foe)
	check(arena.projectiles.is_empty() and ai_gunner.battle.soft_flux == 0.0, "AI auto_fire does not waste shots on phased target")
	Battle.shield(phased_foe, false)
	ai_gunner.battle.soft_flux = Hulls.capacity(ai_gunner) * 0.96
	var flux_before: float = ai_gunner.battle.soft_flux
	Battle.auto_fire(arena, ai_gunner, phased_foe)
	check(ai_gunner.battle.soft_flux == flux_before and ai_gunner.battle.overload == 0.0, "AI auto_fire avoids self-overload when flux is near cap")
	var entropy_ship := design(arena, "afflictor", 9, 1, Vector2.ZERO)
	Battle.shield(phased_foe, true)
	check(not Battle.Abilities.ai_use(entropy_ship, phased_foe, 80.0, false, true), "AI does not cast entropy on phased target")

func _initialize() -> void:
	main.call_deferred()

func main() -> void:
	var arena := Arena.new()
	var ship := vessel(1, 1)
	var attacker := vessel(2, 2)
	attacker.pos = Vector2(160, 0)
	arena.ships = {1:ship,2:attacker}
	var old: Dictionary = Hulls.MODELS[0]
	var config := old.duplicate(true)
	# Concave twin booms enclosing a slot open at the stern, with the nose to +X.
	config.bounds = PackedVector2Array([Vector2(30,-15),Vector2(30,15),Vector2(-30,15),Vector2(-30,6),Vector2(10,6),Vector2(10,-6),Vector2(-30,-6),Vector2(-30,-15)])
	config.merge({"shield_type":"FRONT","shield_arc":120.0,"shield_efficiency":1.0,"shield_turn_rate":90.0,"phase":false,"shield_center":Vector2.ZERO,"fighter_bays":1,"wings":["bomber"]}, true)
	Hulls.MODELS[0] = config
	Battle.Defenses.shapes.erase(0)
	Battle.ensure_state(ship)
	check(not Battle.Defenses.hull_contact(ship, Vector2(-60,0),Vector2(-8,0)).is_finite(), "inward notch admits a shot")
	check(Battle.Defenses.hull_contact(ship, Vector2(60,0),Vector2(-60,0)).is_equal_approx(Vector2(30,0)), "swept contact uses first surface")
	Battle.shield(ship, true)
	Battle.tick(ship, 0.01)
	check(ship.battle.shield_arc_live > 0 and ship.battle.shield_arc_live < deg_to_rad(120), "shield unfolds over time")
	Battle.tick(ship, 1.0)
	var shot := {"system":0,"flag":2,"ship":2,"damage":16.0,"type":2,"vel":Vector2.LEFT,"credit":2,"emp":0.0}
	var fore := Battle.trace(arena, shot, Vector2(60,0), Vector2(-60,0))
	check(fore.shield and fore.point.x > 30, "front arc intercepts before the bow")
	var aft := Battle.trace(arena, shot, Vector2(-60,10), Vector2(60,10))
	check(not aft.shield and aft.point.x < -29, "undefended rear contact")
	var original: PackedFloat32Array = ship.battle.armor_grid.duplicate()
	Battle.impact(arena,shot,fore,true)
	check(ship.battle.soft_flux > 0 and ship.battle.hard_flux == 0 and ship.battle.armor_grid == original, "beam on shield produces soft flux")
	Battle.impact(arena,shot,aft)
	check(ship.battle.armor_grid[34] == original[34] and ship.battle.armor_grid != original, "damage is local; opposite armor intact")
	var damaged: PackedFloat32Array = ship.battle.armor_grid.duplicate()
	Battle.tick(ship, 0.02)
	check(ship.battle.armor_grid == damaged, "ordinary tick preserves damage pattern")
	shot.emp = 35.0
	Battle.impact(arena, shot, aft)
	check(ship.battle.disabled_slots.max() > 0 or ship.battle.engine_disabled > 0, "EMP takes a subsystem offline")
	Battle.tick(ship, 8.0)
	check(ship.battle.disabled_slots.max() == 0 and ship.battle.engine_disabled == 0, "temporary EMP expires")
	config.phase = true
	Battle.shield(ship, true)
	var before: float = ship.battle.hard_flux
	Battle.tick(ship, 0.2)
	check(Battle.phased(ship) and ship.battle.hard_flux > before, "sustained phase consumes capacity")
	check(Battle.trace(arena, shot,Vector2(60,0),Vector2(-60,0)).is_empty(),"phased hull cannot be struck")
	Battle.shield(ship,false)
	check(not Battle.phased(ship), "releasing defense exits phase")
	Battle.Wings.advance(arena,ship,attacker,1.0,Battle)
	check(ship.battle.fighter_wings.size() == 1 and ship.battle.fighter_wings[0].sortie, "carrier dispatches assigned wing")
	var wing: Dictionary = ship.battle.fighter_wings[0]
	wing.hp = 0
	Battle.Wings.advance(arena,ship,attacker,0.1,Battle)
	check(ship.battle.replacement_rate < 1.0 and wing.refit > 0.0, "lost wing delays replacement")
	var visual := ShipVisual.new()
	root.add_child(visual)
	visual.sync(ship, Color.CORAL)
	check(visual.get_child_count() == 7 and visual.hull.texture != null, "ship visual mounts seven layers")
	visual.queue_free()
	await process_frame
	Hulls.MODELS[0] = old
	Battle.Defenses.shapes.erase(0)
	systems_and_campaign()
	print("Battle checks ", checks, " · failures ", failures)
	quit(1 if failures else 0)
