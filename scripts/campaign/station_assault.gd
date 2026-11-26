extends RefCounted

const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
const Geometry = preload("res://scripts/models/station_geometry.gd")
const Armament = preload("res://scripts/economy/station_armament.gd")
const APPROACH_RANGE := 1800.0
const SURRENDER_RANGE := 150.0

static func defending_company(world, site: Dictionary) -> int:
	if site.owner == world.player:
		var table: Dictionary = world.StationEquity.cap_table(world,site)
		if table.company_units * 2 > table.total - table.treasury_units and not world.oversees(world.firms.get(table.company,{}).get("director",0)):
			return int(table.company)
	return int(site.firm)

static func start(world, site: Dictionary, lead: Dictionary, flag: int, contract: bool) -> void:
	var actor: Dictionary = world.active()
	if not site.get("assault",{}).is_empty():
		return
	if flag >= 0 and site.flag >= 0 and site.flag != flag and not world.hostile(flag,site.flag):
		world.set_treaty(flag,site.flag,-1)
		world.WarPeace.on_war_declared(world,flag,site.flag)
		world.event("【宣战】%s 对 %s 宣战，进攻%s。" % [world.flag_name(flag),world.flag_name(site.flag),site.name])
	var claimant := defending_company(world,site)
	var war: String = world.CompanyWars.asset_incident(world,claimant,lead,actor,flag)
	var assault := {"actor":actor.id,"ship":lead.id,"flag":flag,"original_flag":site.flag,"firm":claimant,"operator":site.firm,
		"contract":contract,"company_war":war,"nodes":[],"disabled":[],"started":world.day}
	site.assault = assault
	var geom := Geometry.layout(site)
	for i in geom.parts.size():
		var part: Dictionary = geom.parts[i]
		if part.pending:
			continue
		var kind := Armament.profile(site,i)
		var damage: Dictionary = site.get("module_damage",{}).get(i,{})
		var elapsed := maxi(0, int(world.day)-int(damage.get("day",world.day)))
		var repair := clampf(elapsed/30.0,0.0,1.0)
		var readiness := minf(1.0,float(damage.get("hull",1.0)) + repair)
		if readiness <= 0.0:
			assault.disabled.append(i)
			continue
		var at: Vector2 = geom.center + Vector2(part.center).rotated(geom.angle)
		var sid: int = world.ship(kind,0,0,site.flag,site.system,at)
		var gun: Dictionary = world.ships[sid]
		gun.defense_port = site.id
		gun.defense_module = i
		gun.module_size = part.size
		gun.module_art = part.kind
		gun.module_outline = Armament.module_outline(part)
		gun.mount_offsets = Armament.mount_offsets(part)
		gun.fit = Armament.fitting(site,i)
		gun.hp *= readiness
		gun.battle.armor *= minf(1.0,float(damage.get("armor",1.0)) + repair)
		if elapsed == 0:
			gun.battle.hard_flux = float(damage.get("hard_flux",0.0))
			gun.battle.soft_flux = float(damage.get("soft_flux",0.0))
			gun.battle.overload = float(damage.get("overload",0.0))
		gun.heading = geom.angle
		gun.job = {"kind":"模块站防","label":Armament.label(world,site,i)}
		gun.locked = true
		# Shield and guns use the ordinary flux, cooldown, projectile and armour systems.
		Battle.shield(gun,true,lead.pos)
		gun.battle.shield_arc_live = TAU
		assault.nodes.append(sid)
	for guard: Dictionary in world.ships.values():
		if guard.system != site.system or guard.layer or guard.captain in [0,actor.id] or guard.job.get("kind","") not in ["护航","巡逻","私掠"]:
			continue
		var belongs: bool = guard.get("station_owner",0) == site.id or (claimant > 0 and guard.get("firm",0) == claimant) or (site.flag >= 0 and guard.flag == site.flag)
		if not belongs or guard.dock not in [0,site.id] or guard.pos.distance_to(site.pos) > 510.0 or world.can_operate(guard):
			continue
		if guard.dock == site.id:
			world.depart(guard)
		world.engage_ship(lead,guard,actor.id)
		guard.locked = true
	lead.locked = true
	world.event("%s 拉响战斗警报，%d 个模块独立升盾迎战。" % [site.name,assault.nodes.size()])

static func attacks(world, unit: Dictionary, gun: Dictionary) -> bool:
	var battle: Dictionary = world.ports.get(gun.get("defense_port",0),{}).get("assault",{})
	return not battle.is_empty() and (unit.get("id",0) == battle.ship or world.ship_principal(unit) == battle.actor or unit.get("commander_id",0) == battle.ship)

static func fire(world, gun: Dictionary, lead: Dictionary, delta: float) -> void:
	var site: Dictionary = world.ports.get(gun.defense_port,{})
	if site.is_empty():
		return
	var geom := Geometry.layout(site)
	var part: Dictionary = geom.parts[gun.defense_module]
	gun.pos = Vector2(geom.center) + Vector2(part.center).rotated(geom.angle)
	gun.heading = geom.angle
	gun.battle.motion = Vector2.ZERO
	var target: Dictionary = lead
	var nearest := INF
	if Battle.available(lead,site.system) and world.enemy(gun,lead):
		nearest = gun.pos.distance_squared_to(lead.pos)
	for other: Dictionary in world.ships.values():
		if other.id == gun.id or not Battle.available(other,site.system) or not world.enemy(gun,other):
			continue
		var gap: float = gun.pos.distance_squared_to(other.pos)
		if gap < nearest:
			nearest = gap
			target = other
	var reach := maxf(maxf(620.0,gun.battle.longest_weapon),Battle.Wings.operation_range(gun))
	gun.locked = nearest < reach*reach
	gun.battle.target_id = int(target.id) if gun.locked else 0
	gun.battle.ai = "站防交战" if gun.locked else "站防警戒"
	Battle.shield(gun,gun.locked,target.pos)
	if gun.locked:
		Battle.train(gun,target.pos,delta)
		Battle.auto_fire(world,gun,target)

static func disable(world, gun: Dictionary) -> void:
	var site: Dictionary = world.ports.get(gun.defense_port,{})
	gun.hp = 0.0
	world.ships.erase(gun.id)
	if not site.has("assault"):
		return
	site.assault.nodes.erase(gun.id)
	site.assault.disabled.append(gun.defense_module)
	remember_damage(world,site,gun)
	world.combat_event("rupture",gun.pos,gun.system)
	if site.assault.nodes.is_empty():
		world.event("%s 的站防炮台全部失能，击退守舰后可在泊位接收投降。" % site.name)

static func remember_damage(world, site: Dictionary, gun: Dictionary) -> void:
	var damage: Dictionary = site.get_or_add("module_damage",{})
	damage[gun.defense_module] = {"day":world.day,"hull":clampf(float(gun.hp)/Hulls.MODELS[gun.kind].hp,0,1),
		"armor":clampf(float(gun.battle.armor)/maxf(1,Hulls.COMBAT[gun.kind].armor),0,1),
		"hard_flux":gun.battle.hard_flux,"soft_flux":gun.battle.soft_flux,"overload":gun.battle.overload}

static func clear(world, site: Dictionary) -> void:
	for sid in site.get("assault",{}).get("nodes",[]):
		var gun: Dictionary = world.ships.get(sid,{})
		if gun.get("defense_port",0) == site.id:
			remember_damage(world,site,gun)
			gun.hp = 0.0
			world.ships.erase(sid)
	site.erase("assault")

static func daily(world) -> void:
	for site: Dictionary in world.ports.values():
		if not site.has("assault"):
			continue
		var siege: Dictionary = site.assault
		var lead: Dictionary = world.ships.get(siege.ship,{})
		if lead.is_empty() or lead.captain != siege.actor or lead.system != site.system or lead.layer or lead.dock != 0 or lead.pos.distance_to(site.pos) > APPROACH_RANGE + 600.0 or site.flag != siege.original_flag or site.firm != siege.operator:
			clear(world,site)
		elif siege.flag >= 0 and site.flag >= 0 and site.flag != siege.flag and not world.hostile(siege.flag,site.flag):
			clear(world,site)
		elif world.campaign.get("company_wars",{}).has(siege.company_war):
			world.campaign.company_wars[siege.company_war].last_action = world.day
