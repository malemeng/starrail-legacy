extends SceneTree

const Combat = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
const Flight = preload("res://flight.gd")
const Harness = preload("res://tests/battle_mechanics.gd")

class Arena extends Harness.Arena:
	func ride() -> Dictionary:
		return ships[1]

	func ship(kind: int,owner: int,_captain: int,team: int,system: int,pos: Vector2) -> int:
		var id:=ships.size()+1
		var template: Dictionary=ships[1].duplicate(true)
		template.merge({"id":id,"kind":kind,"owner":owner,"flag":team,"system":system,"pos":pos,"fit":Hulls.stock_fit(kind),"battle":Hulls.battle_state(kind)},true)
		ships[id]=template
		return id

var assertions:=0
var errors:=0
var source: String

func expect(value: bool,message: String) -> void:
	assertions+=1
	if not value:
		printerr(source," · ",message)
		errors+=1

func hull(arena: Arena,reference: String,id: int,team: int,point: Vector2) -> Dictionary:
	var kind:=Hulls.kind_for_reference(reference)
	var v:={"id":id,"flag":team,"system":0,"kind":kind,"owner":id,"raid":-1,"captain":0,"dock":0,"layer":false,
		"crew":Hulls.crew_limits(kind).x,"cargo":[],"locked":true,"pos":point,"heading":0.0,"hp":Hulls.MODELS[kind].hp,
		"battle":Hulls.battle_state(kind),"fit":Hulls.stock_fit(kind)}
	v.fit.caps=99
	Combat.ensure_state(v)
	arena.ships[id]=v
	return v

func pulse(arena: Arena,vessel: Dictionary,duration: float) -> void:
	for i in ceili(duration*30.0):
		Combat.tick(vessel,1.0/30.0,arena)
		Combat.project(arena,0,1.0/30.0)

func missile(arena: Arena,foe: Dictionary,where: Vector2,vel: Vector2) -> Dictionary:
	var shot:=Combat.Abilities.Ordnance.spawn(arena,foe,"test",where,vel,4,2)
	shot.missile=true
	shot.target=1
	return shot

func scenario(reference: String) -> void:
	var a:=Arena.new()
	var v:=hull(a,reference,1,1,Vector2.ZERO)
	var enemy:=hull(a,"lasher",2,2,Vector2(95,0))
	var spec:=Combat.Abilities.profile(v)
	var s: Dictionary=v.battle
	var next:=Vector2(30,25)
	var target_id:=2
	var kinetic: Dictionary=Hulls.WEAPONS.rail
	var energy: Dictionary=Hulls.WEAPONS.pulse
	var flight:=Flight.new()
	flight.game = {"world":a,"autopilot":false}
	if source in ["displacer","displacer_threat","displacer_degraded"]: s.motion=Vector2.UP*75
	if source in ["orion_device","nova_burst"]: enemy.pos=Vector2.LEFT*float(spec.reach)*0.7
	if source in ["forgevats","forgevats_station","fastmissileracks","extraction_protocol"]:
		# A launcher with empty magazines exposes the difference between reload and cooldown.
		v.fit.weapons[0]="missile"
		Combat.ensure_state(v)
		s.cooldowns[0]=4.0
		s.magazines[0]=0.0
		if source=="extraction_protocol": s.soft_flux=Combat.Hulls.capacity(v)*.6
	if source in ["targetingfeed","reservewing","recalldevice","drone_strike"]:
		Combat.Wings.advance(a,v,enemy,0,Combat)
		if source in ["targetingfeed","reservewing","recalldevice"] and s.fighter_wings.is_empty():
			v.fit.wings=["broadsword_wing"]
			Combat.Wings.advance(a,v,enemy,0,Combat)
		if source=="recalldevice":
			s.fighter_wings[0].pos=Vector2.RIGHT*300
			s.fighter_wings[0].cool=4
	var drone_hp: float=s.fighter_wings[0].hp if source=="drone_strike" else 0
	if source=="mine_strike": Combat.shield(v,true)
	if source=="energy_lash": enemy.battle.phase_active=true
	if source=="damper_omega": s.engine_disabled=3; s.disabled_slots[0]=3
	if source in ["temporalshell","incursion_mode"]: s.cooldowns[0]=4
	var before_hp: float=enemy.hp
	var before_armor: float=enemy.battle.armor
	var activated:=Combat.system(a,v,Vector2.RIGHT,next,target_id)
	expect(activated,"activates")
	if not activated: return
	match source:
		"maneuveringjets","plasmajets":
			flight.maneuver(v,Vector2.UP,.15,1)
			expect(s.motion.y< -8 and v.heading>0,"directional thrust and turn both respond")
		"burndrive","microburn","microburn_omega","combat_burn":
			flight.maneuver(v,Vector2.UP,.16,0)
			expect(s.motion.x>0 and is_zero_approx(s.motion.y),"forward thrust overrides lateral orders")
			if source=="burndrive" or source=="combat_burn":
				Combat.shield(v,true)
				expect(not s.shield,"shields locked")
				Combat.tick(v,.4)
				expect(Combat.system(a,v,Vector2.RIGHT) and s.system_time==0,"manual disengage")
		"orion_device","nova_burst":
			expect(s.motion.x>=300 and enemy.battle.armor<before_armor,"immediate impulse and aft blast")
		"convulsive_lunge":
			flight.maneuver(v,Vector2.LEFT,.25,0)
			expect(s.motion.x>0 and not Combat.Abilities.allowed(v,kinetic,0),"locked lunge vector and withheld fire")
		"temporalshell":
			Combat.tick(v,.25)
			expect(s.cooldowns[0]<3.5,"ship's local timers advance faster")
		"displacer","displacer_degraded","displacer_threat":
			expect(v.pos.is_equal_approx(Vector2.UP*float(spec.reach)) and Combat.phased(v),"moves along actual velocity")
			Combat.tick(v,spec.duration+.01)
			expect(Combat.system(a,v,Vector2.RIGHT),"second stored charge redeploys")
		"phaseteleporter": expect(v.pos==next,"lands at selected world coordinate")
		"flarelauncher","flarelauncher_active","flarelauncher_fighter":
			var flare: Dictionary=a.projectiles[0]
			var inbound:=missile(a,enemy,Vector2(flare.pos)+Vector2(65,18),Vector2.LEFT*35)
			Combat.Abilities.Ordnance.advance(a,flare,.1,Combat)
			expect(inbound.hp>0 and inbound.has("decoy_point")==(source!="flarelauncher_fighter"),"missile diversion only for capable flare")
			expect(flare.missile and (flare.vel.length()>80)==(source=="flarelauncher_active"),"PD can target flare and active flare pursues")
		"canister_flak":
			var container: Dictionary=a.projectiles[0]
			var incoming:=missile(a,enemy,Vector2(container.pos)+Vector2(15,0),Vector2.LEFT*45)
			Combat.Abilities.Ordnance.advance(a,container,.05,Combat)
			expect(incoming.hp<=0 and a.events.any(func(e):return e[0]=="rupture"),"interceptor detonates at close enemy missile")
		"ammofeed":
			expect(Combat.Abilities.weapon_mod(v,kinetic,"rate")==.5 and Combat.Abilities.weapon_mod(v,kinetic,"weapon_flux")==.5 and Combat.Abilities.weapon_mod(v,energy,"rate")==1,"ballistic-only ROF and flux")
		"highenergyfocus":
			expect(Combat.Abilities.weapon_mod(v,energy,"damage")==1.5 and Combat.Abilities.weapon_mod(v,kinetic,"damage")==1,"energy-only damage")
		"fastmissileracks": expect(s.cooldowns[0]==0 and s.magazines[0]==0,"instant reload cycle without added ammunition")
		"targetingfeed","reservewing":
			Combat.Wings.advance(a,v,enemy,.02,Combat)
			var wing: Dictionary=s.fighter_wings[0]
			if source=="reservewing":
				expect(wing.reserve_count>0 and wing.count_live>wing.count,"additional flight actually deploys")
				Combat.tick(v,spec.duration+.01)
				Combat.Wings.advance(a,v,enemy,.02,Combat)
				expect(wing.reserve_count==0,"reserves expire")
			else:
				expect(Combat.Abilities.weapon_mod(v,energy,"damage")==1 and s.active_profile.wing_damage>1,"wings receive targeting bonus while hull output stays normal")
		"recalldevice": expect(s.fighter_wings[0].pos==v.pos and s.fighter_wings[0].returning and s.fighter_wings[0].cool<1,"teleports and prepares flight")
		"lidararray":
			var fixed_slot: int=-1
			var turret: int=-1
			for i in v.fit.weapons.size():
				if Hulls.slot_spec(v.kind,i).type=="固定": fixed_slot=i
				else: turret=i
			expect(Combat.Abilities.allowed(v,kinetic,fixed_slot) and not Combat.Abilities.allowed(v,kinetic,turret) and not Combat.Abilities.allowed(v,{"beam":true},fixed_slot),"hardpoints only; turrets and beams stand down")
			expect(Combat.Abilities.weapon_mod(v,kinetic,"range",fixed_slot)>=2,"hardpoint range")
			Combat.tick(v,spec.duration)
			expect(Combat.Abilities.weapon_mod(v,kinetic,"range",turret)>1,"passive range returns")
		"fortressshield":
			Combat.tick(v,.5,a)
			expect(s.shield and s.hard_flux>0 and not Combat.Abilities.allowed(v,energy,0),"fortress spends hard flux and prevents fire")
		"damper","damper_omega":
			Combat.shield(v,true)
			var normal:=hull(a,reference,3,1,Vector2.ZERO)
			Combat.hit(a,v,40,2,v.pos,Vector2.RIGHT)
			Combat.hit(a,normal,40,2,normal.pos,Vector2.RIGHT)
			expect(not s.shield and (s.armor>normal.battle.armor or v.hp>normal.hp),"field reduces incoming damage")
			expect(Combat.Abilities.allowed(v,kinetic,0)==(source=="damper_omega"),"distinct weapon lock")
			if source=="damper_omega":
				var old: float=s.soft_flux
				Combat.add_flux(a,v,10)
				expect(is_equal_approx(s.soft_flux-old,5),"halves generated flux")
				Combat.tick(v,.4)
				expect(s.engine_disabled<2 and s.disabled_slots[0]<2,"accelerated repairs")
		"emp":
			var incoming:=missile(a,enemy,Vector2(70,0),Vector2.LEFT*50)
			Combat.tick(v,.1,a)
			expect(incoming.hp<=0 and not Combat.Abilities.allowed(v,energy,0) and a.events.any(func(e):return e[0]=="emp"),"pulse affects ordnance and hostile equipment")
		"acausaldisruptor": expect(enemy.battle.overload>0 and not Combat.ready(enemy),"target enters overload")
		"darkened_gaze":
			Combat.tick(v,.1,a)
			expect(s.shield and not Combat.Defenses.covered(v,Vector2(100,0)) and enemy.battle.armor<before_armor,"beam strikes forward through frontal shield gap")
		"entropyamplifier":
			var normal:=hull(a,"lasher",3,2,enemy.pos)
			Combat.hit(a,enemy,30,2,enemy.pos,Vector2.RIGHT)
			Combat.hit(a,normal,30,2,normal.pos,Vector2.RIGHT)
			expect(enemy.battle.armor<normal.battle.armor or enemy.hp<normal.hp,"target actually takes amplified damage")
		"mine_strike":
			expect(Combat.phased(v) and a.projectiles[0].pos==next,"places mine under sustained phase")
			pulse(a,v,4)
			expect(enemy.hp<before_hp or enemy.battle.armor<before_armor,"mine tracks and detonates")
		"forgevats","forgevats_station": expect(s.magazines[0]==Hulls.WEAPONS.missile.ammo and s.cooldowns[0]>0,"restocks missile ammo independent of reload timer")
		"construction_swarm":
			pulse(a,v,spec.build_time+.1)
			expect(a.ships.size()==3 and a.ships[3].flag==v.flag and Hulls.MODELS[a.ships[3].kind].reference==spec.unit,"swarm completes a real allied hull")
		"extraction_protocol":
			flight.maneuver(v,Vector2.RIGHT,.1,0)
			Combat.tick(v,spec.duration+.01,a)
			expect(s.motion.x<0 and s.magazines[0]==Hulls.WEAPONS.missile.ammo and s.vent,"retreat ends in reload and vent")
		"drone_strike": expect(s.fighter_wings[0].hp<drone_hp and a.projectiles.back().ordnance=="terminator" and a.projectiles.back().target==enemy.id,"live drone converted into guided weapon")
		"mote_control":
			expect(a.projectiles.back().ordnance=="mote" and a.projectiles.back().target==enemy.id,"attractor redirects motes")
			pulse(a,v,1)
			expect(a.events.any(func(e):return e[0]=="emp"),"mote delivers EMP on contact")
		"fragment_volley":
			Combat.tick(v,.1,a)
			expect(not a.projectiles.is_empty() and not Combat.Abilities.eligible(v,Hulls.WEAPONS.missile,0,spec),"fires only non-PD fragment slots")
		"energy_lash": expect(enemy.battle.overload>0 and not Combat.phased(enemy),"arc reaches phased ship")
		"incursion_mode":
			s.soft_flux=100
			var old: float=s.soft_flux
			Combat.tick(v,.25,a)
			expect(old-s.soft_flux>Hulls.dissipation(v)*.4 and Combat.ai_mode(v,180)=="压进","dissipation and tactical aggression")
		"tenebrous_expulsion":
			flight.maneuver(v,Vector2.RIGHT,.1,0)
			Combat.project(a,0,.3)
			enemy.pos=Vector2.RIGHT*(Combat.Defenses.geometry(v.kind).radius+100.0)
			var shot:=Combat.Abilities.Ordnance.payload(enemy,"test",enemy.pos,Vector2.LEFT,1,30)
			var contact:=Combat.trace(a,shot,enemy.pos,Vector2.ZERO)
			expect(s.motion.x<0 and contact.has("screen"),"physical screen blocks incoming line of fire during retreat")
		_: expect(false,"missing scenario")
	if spec.has("charges"):
		expect(s.system_charges<spec.charges,"activation spends a charge")

func charges_and_targeting() -> void:
	var a:=Arena.new()
	source="merlon"
	var merlon:=hull(a,"merlon",1,1,Vector2.ZERO)
	expect(Combat.Abilities.profile(merlon).id=="" and Combat.system_label(merlon)=="未配备舰载系统","explicit empty system remains unfitted")
	expect(not Combat.system(a,merlon,Vector2.RIGHT) and merlon.battle.system_cd==0,"cannot activate an unfitted system")
	var wolf:=hull(a,"wolf",1,1,Vector2.ZERO)
	source="displacer"
	for i in 3:
		expect(Combat.system(a,wolf,Vector2.RIGHT),"stored skimmer charge")
		Combat.tick(wolf,.71)
	expect(not Combat.system(a,wolf,Vector2.RIGHT),"fourth blink rejected before recharge")
	Combat.tick(wolf,10)
	expect(Combat.system(a,wolf,Vector2.RIGHT),"regenerated charge is usable")
	source="acausaldisruptor"
	var disruptor:=hull(a,"harbinger",1,1,Vector2.ZERO)
	var foe:=hull(a,"lasher",2,2,Vector2(800,0))
	expect(not Combat.system(a,disruptor,Vector2.RIGHT,foe.pos,foe.id) and disruptor.battle.soft_flux==0 and disruptor.battle.system_cd==0,"invalid target preserves activation costs")
	source="energy_lash"
	var overseer:=hull(a,"overseer_unit",1,1,Vector2.ZERO)
	var ally:=hull(a,"assault_unit",3,1,Vector2(50,0))
	ally.battle.system_charges=0.0
	expect(Combat.Abilities.lash_recipient(a,overseer,foe)==ally,"AI prioritizes depleted ally")
	expect(Combat.system(a,overseer,Vector2.RIGHT,ally.pos,ally.id) and ally.battle.system_time>0 and ally.battle.active_profile.effect=="incursion","friendly lash powers allied Threat system")
	source="mote_control"
	var carrier:=hull(a,"ziggurat",1,1,Vector2.ZERO)
	foe.pos=Vector2(90,0)
	expect(Combat.system(a,carrier,Vector2.UP,Vector2(0,-80),0) and carrier.battle.system_target==0 and carrier.battle.attractor_point==Vector2(0,-80),"can set attractor in empty space")
	source="drone_strike"
	var tempest:=hull(a,"tempest",1,1,Vector2.ZERO)
	Combat.Wings.advance(a,tempest,foe,0,Combat)
	tempest.battle.fighter_wings[0].hp=0.0
	expect(not Combat.system(a,tempest,Vector2.RIGHT,foe.pos,foe.id) and tempest.battle.system_cd==0,"requires living Terminator")
	source="targetingfeed"
	var heron:=hull(a,"heron",1,1,Vector2.ZERO)
	heron.fit.wings=["broadsword_wing","broadsword_wing","broadsword_wing"]
	Combat.Wings.advance(a,heron,foe,0,Combat)
	var initial: Array=heron.battle.fighter_wings.duplicate(true)
	var old := first_wing_round(a,heron,foe)
	heron.battle.fighter_wings=initial
	Combat.system(a,heron,Vector2.RIGHT)
	var boosted := first_wing_round(a,heron,foe)
	expect(old>0 and is_equal_approx(boosted,old*Combat.Abilities.profile(heron).wing_damage),"damage changes on a deployed fighter projectile")

func first_wing_round(arena, carrier: Dictionary, target: Dictionary) -> float:
	for frame in 1200:
		arena.projectiles.clear()
		Combat.Wings.advance(arena,carrier,target,1.0/60,Combat)
		for shot in arena.projectiles:
			if shot.get("bay",-1)==0 and shot.get("airframe",-1)==0:
				return float(shot.damage)
	return 0.0

func _initialize() -> void:
	var covered:={}
	for model in Hulls.MODELS:
		source=model.get("source_system","")
		if not source.is_empty() and not covered.has(source):
			covered[source]=true
			scenario(model.reference)
	expect(covered.size()==43 and covered.size()==Combat.Abilities.profiles.size(),"complete system coverage")
	charges_and_targeting()
	print("Ship systems ",covered.size()," · assertions ",assertions," · failures ",errors)
	quit(1 if errors else 0)

