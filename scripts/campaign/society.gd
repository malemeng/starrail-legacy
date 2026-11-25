extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const EventEngine = preload("res://scripts/campaign/event_engine.gd")
const Rules = preload("res://data/campaign/sector.json")
const Person = preload("res://scripts/models/person_data.gd")
static var rules: Dictionary = Rules.data
static var entries: Dictionary = {}
static var events_by_hook: Dictionary = {}
const DEMANDS := {"autonomy":"减税自治", "independence":"独立建国", "claimant":"拥立宣称者", "shareholders":"股东罢免"}
const CK_PERSONALITY_PAIRS := Person.PERSONALITY_PAIRS
const CK_CONGENITAL := ["聪慧", "强壮", "魅力非凡"]
const CK_TRAIT_MODS := {
	"勇敢": {"martial": 2, "prowess": 3},
	"怯懦": {"martial": -2, "intrigue": 2},
	"慷慨": {"diplomacy": 2, "stewardship": -1},
	"贪婪": {"stewardship": 3, "diplomacy": -1},
	"仁慈": {"diplomacy": 2, "learning": 1},
	"残忍": {"intrigue": 2, "prowess": 2, "diplomacy": -2},
	"勤勉": {"stewardship": 2, "learning": 2},
	"懒惰": {"stewardship": -1},
	"诚实": {"diplomacy": 2, "intrigue": -2},
	"狡诈": {"intrigue": 3, "diplomacy": -1},
	"狂热": {"martial": 2, "learning": 1},
	"愤世": {"intrigue": 2, "learning": 2},
	"聪慧": {"diplomacy": 2, "martial": 2, "stewardship": 2, "intrigue": 2, "learning": 3},
	"强壮": {"martial": 1, "prowess": 4},
	"魅力非凡": {"diplomacy": 3, "intrigue": 1},
	"隐士": {"learning": 2, "diplomacy": -1},
	"挥霍": {"diplomacy": 1, "stewardship": -1}
}

static func build_events() -> void:
	if not entries.is_empty():
		return
	var rows := EventEngine.authored()
	for event in Hulls.mod_events():
		rows.append(event if event.has("on_action") else EventEngine.from_legacy(event))
	for row in rows:
		if entries.has(row.id):
			continue
		entries[row.id] = row
		var actions: Array = row.on_action if row.on_action is Array else [row.on_action]
		for action in actions:
			events_by_hook.get_or_add(action, []).append(row)

static func initial_state() -> Dictionary:
	return {"houses": {}, "schemes": {}, "projects": {}, "unlocks": {}, "claims": {},
		"movements": {}, "events": {}, "last_event": {}, "courts": {}, "crises": {},
		"prestige": {}, "log": []}

static func valid_state(state: Dictionary) -> bool:
	for key in initial_state():
		if typeof(state.get(key)) != typeof(initial_state()[key]):
			return false
	build_events()
	for queue in state.events.values():
		if not queue is Array:
			return false
		for item in queue:
			if not item is Dictionary or not item.get("id") is String or not item.get("context") is Dictionary:
				return false
			if not item.get("action") is String or not item.get("day") is int:
				return false
	for history in state.last_event.values():
		if not history is Dictionary or not history.values().all(func(day): return day is int):
			return false
	return true

static func restore_events(state: Dictionary) -> void:
	# An outstanding encounter can have been removed from the game or its installed mods.
	for actor in state.events.keys():
		var queue: Array = state.events[actor]
		for index in range(queue.size() - 1, -1, -1):
			if not entries.has(queue[index].id):
				queue.remove_at(index)
		if queue.is_empty():
			state.events.erase(actor)
	for history: Dictionary in state.last_event.values():
		for key in history.keys():
			if not entries.has(key) and not events_by_hook.has(key):
				history.erase(key)

static func initialize_person(actor: Dictionary) -> void:
	var temperament: Dictionary = rules.traits[actor.trait]
	var stats := {}
	var personality := {}
	for i in range(rules.stats.size()):
		stats[rules.stats[i]] = 5 + int(temperament.stats[i]) + absi(hash([actor.id, actor.house, i])) % 5
	for i in range(rules.personality.size()):
		personality[rules.personality[i]] = int(temperament.vector[i])
	actor.merge({"stats": stats, "personality": personality, "ck_traits": [], "relations": {},
		"stress": 0, "break_level": 0,
		"secrets": [], "hooks": {}, "merit": 0, "prestige": 0, "legitimacy": 2,
		"focus": "", "experience": 0, "perks": {}, "faith": "星灯", "culture": actor.house,
		"last_decision": -90, "designated_heir": 0})
	var available := CK_PERSONALITY_PAIRS.duplicate()
	var trait_count := 2 + absi(hash([actor.id, actor.name])) % 2
	for k in range(trait_count):
		var index := (absi(hash([actor.id, k, "pair"])) + k) % available.size()
		var pair: Array = available.pop_at(index)
		var side := absi(hash([actor.id, actor.trait, k, "side"])) % pair.size()
		apply_trait_mod(actor,pair[side])
	if absi(hash([actor.id, actor.house, "congenital"])) % 100 < 8:
		apply_trait_mod(actor,CK_CONGENITAL[absi(hash([actor.id, "cong_idx"])) % CK_CONGENITAL.size()])

static func candidates(list: Array, id: String) -> Dictionary:
	for row in list:
		if row.id == id:
			return row
	return {}

static func trait_labels(actor: Dictionary) -> Array:
	return actor.get("ck_traits", [])

static func apply_trait_mod(actor: Dictionary, tname: String) -> void:
	var list: Array = actor.get("ck_traits", [])
	if not Person.can_add_trait(list,tname):
		return
	list.append(tname)
	actor.ck_traits = list
	var mods: Dictionary = CK_TRAIT_MODS.get(tname, {})
	for sk in mods:
		actor.stats[sk] = maxi(1, int(actor.stats.get(sk)) + int(mods[sk]))

static func relation_bonus(actor: Dictionary, target_id: int) -> int:
	var rel: String = actor.get("relations", {}).get(target_id, "")
	if rel == "lover":
		return 40
	if rel == "friend":
		return 30
	if rel == "rival":
		return -55
	return 0

static func set_relation(actor: Dictionary, target_id: int, kind: String) -> void:
	if not actor.has("relations"):
		actor.relations = {}
	actor.relations[target_id] = kind

static func trait_stress(world, actor: Dictionary, action_kind: String) -> void:
	var list: Array = actor.get("ck_traits", [])
	if action_kind == "gift":
		if "贪婪" in list:
			stress(world, actor, 12)
		elif "慷慨" in list:
			stress(world, actor, -10)
	elif action_kind == "scheme_secret":
		if "诚实" in list:
			stress(world, actor, 14)
		elif "狡诈" in list:
			stress(world, actor, -8)
	elif action_kind == "raid":
		if "仁慈" in list:
			stress(world, actor, 18)
		elif "残忍" in list:
			stress(world, actor, -12)

static func cope_stress(world, mode: String) -> bool:
	var actor: Dictionary = world.active()
	if actor.stress < 40:
		return false
	if mode == "feast":
		if actor.wallet < 40:
			return false
		world.credit(actor.id, -40)
		stress(world, actor, -65)
		apply_trait_mod(actor, "挥霍")
		world.event("%s 宴饮挥霍以排解压力。" % actor.name)
		return true
	if mode == "seclude":
		stress(world, actor, -45)
		apply_trait_mod(actor, "隐士")
		world.event("%s 闭门独处，逐渐平复心神。" % actor.name)
		return true
	return false

static func stress(world, actor: Dictionary, amount: int) -> void:
	var was: int = actor.stress
	actor.stress = clampi(was + amount, 0, 400)
	var level := mini(3, int(actor.stress / 100))
	if level > int(actor.break_level):
		actor.loyalty = maxi(0, actor.loyalty - level * 6)
		actor.lifespan = maxi(18 * 360, actor.lifespan - 90 * level)
		world.event("%s 压力达到 %d，经历 %d 级崩溃。" % [actor.name, actor.stress, level])
	actor.break_level = level

static func offer(world, action: String, context: Dictionary = {}) -> void:
	build_events()
	if events_by_hook.has(action):
		prune_pending(world)
		EventEngine.offer(world, action, context, events_by_hook[action])

static func prune_pending(world) -> void:
	if world.campaign.events.has(world.player):
		build_events()
		EventEngine.prune_pending(world, entries)

static func pending_count(world) -> int:
	prune_pending(world)
	return world.campaign.events[world.player].size() if world.campaign.events.has(world.player) else 0

static func pending(world) -> Dictionary:
	if pending_count(world) == 0:
		return {}
	return EventEngine.pending(world, entries)

static func pending_all(world) -> Array:
	if pending_count(world) == 0:
		return []
	return EventEngine.pending_all(world, entries)

static func decide(world, id: String, choice: int) -> bool:
	if pending_count(world) == 0 or not EventEngine.decide(world, entries, id, choice, stress):
		return false
	refresh_ruler(world, world.player)
	return true

static func focus(world, id: String) -> bool:
	if candidates(rules.lifestyles, id).is_empty():
		return false
	world.active().focus = id
	return true

static func train(world) -> bool:
	var actor: Dictionary = world.active()
	var track := candidates(rules.lifestyles, actor.focus)
	if track.is_empty():
		return false
	var rank: int = actor.perks.get(track.id, 0)
	var cost := 12 * (rank + 1)
	if rank >= 3 or actor.experience < cost:
		return false
	actor.experience -= cost
	actor.perks[track.id] = rank + 1
	actor.stats[track.stat] += 2
	if rank == 2:
		world.campaign.houses[actor.house] = int(world.campaign.houses.get(actor.house, 0)) + 1
	world.event("%s 完成%s第 %d 阶修习。" % [actor.name, track.name, rank + 1])
	return true

static func scheme(world, target_id: int, kind: String) -> bool:
	var actor: Dictionary = world.active()
	var other: Dictionary = world.people.get(target_id, {})
	if other.is_empty() or not other.alive or other.id == actor.id or world.campaign.schemes.has(actor.id):
		return false
	if kind not in ["sway", "find_secrets"] or (kind == "find_secrets" and (actor.loc == 0 or actor.loc != other.loc)):
		return false
	if kind == "find_secrets":
		trait_stress(world, actor, "scheme_secret")
	world.campaign.schemes[actor.id] = {"kind": kind, "target": target_id, "stage": 0, "progress": 0, "funded": 0}
	return true

static func fund_scheme(world) -> bool:
	var op: Dictionary = world.campaign.schemes.get(world.player, {})
	if op.is_empty() or op.funded >= 3 or world.active().wallet < 25:
		return false
	world.credit(world.player, -25)
	op.funded += 1
	return true

static func resolve_scheme(world) -> bool:
	var op: Dictionary = world.campaign.schemes.get(world.player, {})
	if op.is_empty() or op.stage < 3:
		return false
	var actor: Dictionary = world.active()
	var target: Dictionary = world.people.get(op.target, {})
	world.campaign.schemes.erase(actor.id)
	if target.is_empty() or not target.alive:
		return false
	if op.kind == "sway":
		target.opinions[actor.id] = mini(100, target.opinions.get(actor.id, 0) + 18 + actor.stats.diplomacy)
		if target.opinions[actor.id] >= 65 and not actor.get("relations", {}).has(target.id):
			set_relation(actor, target.id, "friend")
			set_relation(target, actor.id, "friend")
			world.event("%s 与 %s 结为挚友！" % [actor.name, target.name])
		else:
			world.event("%s 得到了 %s 的支持。" % [actor.name, target.name])
	elif not target.secrets.is_empty():
		var secret: Dictionary = target.secrets.pop_front()
		actor.hooks[target.id] = {"kind": secret.kind, "strength": 2, "expires": world.day + 720}
		refresh_ruler(world,actor.id)
		world.event("%s 掌握了 %s 的把柄。" % [actor.name, target.name])
	elif world.rng.randf() < 0.35:
		set_relation(actor, target.id, "rival")
		set_relation(target, actor.id, "rival")
		world.event("%s 刺探败露，与 %s 结下宿怨！" % [actor.name, target.name])
	else:
		actor.experience += 5
		world.event("调查结束，未发现 %s 的秘密。" % target.name)
	return true

static func use_hook(world, target_id: int) -> bool:
	var actor: Dictionary = world.active()
	var hook: Dictionary = actor.hooks.get(target_id, {})
	if hook.is_empty() or int(hook.expires) < world.day or not world.people.has(target_id) or not world.people[target_id].alive:
		return false
	actor.hooks.erase(target_id)
	var target: Dictionary = world.people[target_id]
	target.endorsement += 1
	target.bound_until = world.day + 360
	target.bound_by = actor.id
	target.loyalty = mini(100, target.loyalty + 15)
	refresh_ruler(world,actor.id)
	stress(world, actor, 20 if actor.personality.compassion > 0 else 5)
	world.event("%s 借把柄迫使 %s 退出反对派并背书。" % [actor.name, target.name])
	return true

static func refresh_ruler(world, ruler_id: int) -> void:
	for flag in world.campaign.movements.keys():
		if world.factions.get(flag,{}).get("leader",0) == ruler_id:
			advance_movement(world,flag,false)

static func player_governs(world, flag: int) -> bool:
	var ruler: int = world.factions.get(flag,{}).get("leader",0)
	return ruler != 0 and (ruler == world.player or ruler == world.regency and world.regent == world.player)

static func advance(world) -> void:
	var state: Dictionary = world.campaign
	for owner in state.schemes.keys():
		var op: Dictionary = state.schemes[owner]
		var actor: Dictionary = world.people.get(owner, {})
		if not actor.get("alive", false) or not world.people.get(op.target, {}).get("alive", false):
			state.schemes.erase(owner)
			continue
		if op.stage < 3:
			op.progress += 10 + actor.stats.intrigue + op.funded * 8
			while op.progress >= 30 and op.stage < 3:
				op.stage += 1
				op.progress -= 30
	if world.people.has(world.player) and world.active().alive:
		var active: Dictionary = world.active()
		if not active.focus.is_empty():
			active.experience += 3 + int(active.stats.learning / 5)
		offer(world, "on_monthly_pulse")
	for flag in world.factions.keys():
		advance_movement(world,flag)

static func can_oppose(world, official: Dictionary, leader: Dictionary) -> bool:
	if not official.get("alive",false) or official.id in [world.player,leader.id,leader.spouse] or world.day-official.birth < 18*360:
		return false
	if official.get("bound_until",0) > world.day and official.get("bound_by",leader.id) == leader.id:
		return false
	var hook: Dictionary = leader.hooks.get(official.id,{})
	if hook.get("strength",0) >= 2 and hook.get("expires",-1) >= world.day:
		return false
	if official.flag >= 0 and official.flag != leader.flag and world.treaty(official.flag,leader.flag).state == 1:
		return false
	return int(leader.get("dread",0)) - (int(official.personality.boldness) + 35) < 45

static func motion(world, port: Dictionary, official: Dictionary, group: Dictionary, leader: Dictionary) -> String:
	if not can_oppose(world,official,leader):
		return ""
	var resentment := -int(official.opinions.get(leader.id,0)) + (2-int(leader.legitimacy))*12
	resentment += mini(40,int(port.shortage)/3) + maxi(0,roundi((port.tax_rate-0.10)*220))
	if int(leader.get("dread",0)) - (int(official.personality.boldness)+35) >= 15:
		resentment /= 2
	if resentment < 30:
		return ""
	var company: int = world.Equity.company(world,group)
	if company != 0 and official.shares.get(company,0) > 0:
		return "shareholders"
	if group.regime == 0 and leader.legitimacy <= 1 and (official.noble or official.id == leader.designated_heir):
		return "claimant"
	if port.owner == official.id and port.id != group.capital and resentment >= 55:
		return "independence"
	return "autonomy"

static func enlist(coalitions: Dictionary, kind: String, official: Dictionary, port_id: int) -> void:
	if kind.is_empty():
		return
	if not coalitions.has(kind):
		coalitions[kind] = {"kind":kind,"demand":DEMANDS[kind],"people":[],"members":[],"ships":[],
			"candidate":official.id,"rebel_power":0.0,"loyal_power":0.0}
	var bloc: Dictionary = coalitions[kind]
	if official.id not in bloc.people:
		bloc.people.append(official.id)
	if port_id != 0 and port_id not in bloc.members:
		bloc.members.append(port_id)

static func strength(world, flag: int, owned: Array, bloc: Dictionary) -> void:
	var home_systems := {}
	for port_id in owned:
		var port: Dictionary = world.ports[port_id]
		var defense := maxf(1.0,float(port.defense))
		if port_id in bloc.members:
			bloc.rebel_power += defense
			home_systems[port.system] = true
		else:
			bloc.loyal_power += defense
	for ship in world.ships.values():
		if ship.flag != flag or ship.get("hp",0) <= 0:
			continue
		var hull: Dictionary = Hulls.MODELS[ship.kind]
		var power := float(hull.power)*clampf(float(ship.hp)/float(hull.hp),0.0,1.0)
		var garrison: bool = ship.owner == 0 and ship.job.get("kind","") == "护航" and home_systems.has(ship.job.get("system",ship.system))
		var ruler: int = world.factions[flag].leader
		if ship.owner not in [world.player,ruler] and ship.captain not in [world.player,ruler] and (ship.owner in bloc.people or ship.captain in bloc.people or garrison):
			bloc.ships.append(ship.id)
			bloc.rebel_power += power
		else:
			bloc.loyal_power += power

static func opposition(world, flag: int, group: Dictionary, leader: Dictionary) -> Dictionary:
	var owned: Array = world.systems_owned(flag)
	var coalitions := {}
	if owned.is_empty() or not world.ports.has(group.capital):
		return {}
	for port_id in owned:
		var port: Dictionary = world.ports[port_id]
		for id in [port.owner,port.manager]:
			var official: Dictionary = world.people.get(id,{})
			if not official.is_empty():
				enlist(coalitions,motion(world,port,official,group,leader),official,port_id)
	var company: int = world.Equity.company(world,group)
	if company != 0:
		var seat: Dictionary = world.ports[group.capital]
		if world.firms.has(company):
			var opposing_votes := 0
			var outstanding_votes := 0
			for official in world.people.values():
				var shares: int = official.shares.get(company,0)
				if not official.alive or shares <= 0:
					continue
				outstanding_votes += shares
				if motion(world,seat,official,group,leader) == "shareholders":
					enlist(coalitions,"shareholders",official,0)
					opposing_votes += shares
			if opposing_votes*2 <= outstanding_votes:
				coalitions.erase("shareholders")
			elif seat.id not in coalitions.shareholders.members:
				coalitions.shareholders.members.append(seat.id)
	var result := {}
	for bloc in coalitions.values():
		strength(world,flag,owned,bloc)
		if bloc.members.is_empty():
			continue
		if bloc.kind in ["claimant","shareholders"]:
			for id in bloc.people:
				var person: Dictionary = world.people[id]
				var current: Dictionary = world.people[bloc.candidate]
				if bloc.kind == "shareholders":
					if person.shares.get(company,0) > current.shares.get(company,0):
						bloc.candidate = id
				elif person.id == leader.designated_heir or (bloc.candidate != leader.designated_heir and person.legitimacy > current.legitimacy):
					bloc.candidate = id
		if result.is_empty() or bloc.rebel_power > result.rebel_power:
			result = bloc
	return result

static func advance_movement(world, flag: int, monthly: bool = true) -> void:
	var group: Dictionary = world.factions[flag]
	var movements: Dictionary = world.campaign.movements
	var leader: Dictionary = world.people.get(group.leader,{})
	if not group.alive or not leader.get("alive",false) or group.get("truce_until",0) > world.day:
		movements.erase(flag)
		return
	var enemy: int = group.get("civil_enemy",world.NEUTRAL)
	if enemy != world.NEUTRAL:
		if world.factions.get(enemy,{}).get("alive",false) and world.hostile(flag,enemy):
			return
		group.erase("civil_enemy")
		group.erase("civil_motion")
	var bloc := opposition(world,flag,group,leader)
	if bloc.is_empty():
		movements.erase(flag)
		return
	var previous: Dictionary = movements.get(flag,{})
	var continuous: bool = previous.get("kind","") == bloc.kind and previous.get("ruler",0) == leader.id
	bloc.ruler = leader.id
	bloc.discontent = int(previous.discontent) if continuous else 0
	bloc.ultimatum = continuous and previous.ultimatum
	bloc.issued = int(previous.get("issued",0)) if continuous else 0
	var ratio := float(bloc.rebel_power)/maxf(1.0,bloc.loyal_power)
	if ratio < 0.8:
		bloc.ultimatum = false
		bloc.discontent = maxi(0,bloc.discontent-6) if monthly else mini(99,bloc.discontent)
	elif monthly:
		bloc.discontent = mini(100,bloc.discontent + clampi(roundi(6+12*(ratio-0.8))+maxi(0,2-leader.legitimacy)*2,6,25))
	movements[flag] = bloc
	if not monthly or bloc.discontent != 100:
		return
	if not bloc.ultimatum:
		bloc.ultimatum = true
		bloc.issued = world.day
		world.event("%s 的%s派向 %s 递交了最后通牒。" % [group.name,bloc.demand,leader.name])
	elif not player_governs(world,flag) and world.day > bloc.issued:
		var threshold := 1.05 + float(leader.personality.boldness)*0.008 + float(leader.legitimacy)*0.06
		if bloc.kind == "autonomy":
			threshold -= 0.25
		_resolve_ultimatum(world,flag,ratio >= threshold)

static func install_ruler(world, flag: int, candidate: int, board: bool) -> void:
	var group: Dictionary = world.factions[flag]
	var previous: int = group.leader
	group.leader = candidate
	group.npc = candidate != world.player
	world.people[candidate].flag = flag
	world.people[candidate].employer = 0
	for port_id in world.systems_owned(flag):
		var port: Dictionary = world.ports[port_id]
		var manager: Dictionary = world.people.get(port.manager,{})
		if group.regime == 0 and port.owner == previous:
			world.StationEquity.freeze(world,port)
			port.owner = candidate
		if manager.get("employer",0) == previous:
			manager.employer = candidate
	if board:
		var company: int = world.Equity.company(world,group)
		if world.firms.has(company) and world.firms[company].director != candidate:
			world.firms[company].director = candidate
	if not world.campaign.get("equity_orders",{}).get("orders",{}).is_empty():
		world.EquityOrders.audit(world)
	world.event("%s 接替 %s 执掌%s。" % [world.name_of(candidate),world.name_of(previous),group.name])

static func charter(world, ports: Array, flag: int) -> void:
	for id in ports:
		var port: Dictionary = world.ports.get(id,{})
		if port.get("flag",world.NEUTRAL) == flag:
			port.tax_rate = minf(port.tax_rate, maxf(0.01,port.tax_rate*0.7))
			world.refresh_tariffs(port.system)

static func separate(world, flag: int, bloc: Dictionary, war: bool) -> int:
	var group: Dictionary = world.factions[flag]
	var owned: Array = world.systems_owned(flag)
	var sites: Array = bloc.members.duplicate()
	if sites.size() >= owned.size():
		sites.erase(group.capital)
	if sites.is_empty():
		return world.NEUTRAL
	var seat: Dictionary = {}
	for id in sites:
		var site: Dictionary = world.ports[id]
		var old_flag: int = site.get("rebellion_flag",world.NEUTRAL)
		if not world.factions.get(old_flag,{}).get("alive",false):
			seat = site
			break
	if seat.is_empty():
		return world.NEUTRAL
	var new_flag: int = seat.get("rebellion_flag",world.NEUTRAL)
	if new_flag == world.NEUTRAL:
		new_flag = world.uid()+10
		seat.rebellion_flag = new_flag
	else:
		for key in world.relations.keys():
			if key.x == new_flag or key.y == new_flag:
				world.relations.erase(key)
	var budget := floori(float(group.treasury)*sites.size()/owned.size())
	var retained: int = world.factions.get(new_flag,{}).get("treasury",0)
	var former_company: int = world.factions.get(new_flag,{}).get("firm",0)
	group.treasury -= budget
	world.factions[new_flag] = {"name":seat.name+"自治同盟","style":group.style,"regime":group.regime,
		"color":group.color,"leader":bloc.candidate,"capital":seat.id,"npc":true,"alive":true,
		"treasury":budget+retained,"last_war":world.day,"truce_until":world.day+720}
	if world.firms.has(former_company) and world.Equity.corporate(group.regime):
		world.factions[new_flag].firm = former_company
		world.firms[former_company].hq = seat.id
	for id in sites:
		var site: Dictionary = world.ports[id]
		site.flag = new_flag
		world.refresh_tariffs(site.system)
		site.since = world.day
		if site.owner == group.leader:
			world.StationEquity.freeze(world,site)
			site.owner = bloc.candidate if group.regime == 0 else 0
		var manager: Dictionary = world.people.get(site.manager,{})
		if not manager.is_empty() and manager.id != world.player and manager.flag == flag:
			manager.flag = new_flag
			manager.employer = bloc.candidate if manager.id != bloc.candidate else 0
	for id in bloc.people:
		if world.people[id].flag == flag:
			world.people[id].flag = new_flag
	world.people[bloc.candidate].flag = new_flag
	world.people[bloc.candidate].employer = 0
	for id in bloc.ships:
		var ship: Dictionary = world.ships[id]
		ship.flag = new_flag
		if world.people.has(ship.captain):
			world.people[ship.captain].flag = new_flag
	if group.capital in sites:
		group.capital = world.systems_owned(flag)[0]
		if group.has("firm"):
			world.firms[group.firm].hq = group.capital
	world.Equity.establish(world,new_flag)
	for id in sites:
		world.Equity.update_operator(world,world.ports[id])
	if war:
		group.civil_enemy = new_flag
		world.factions[new_flag].civil_enemy = flag
		world.factions[new_flag].civil_motion = bloc.duplicate(true)
		world.set_treaty(flag,new_flag,-1)
		for id in bloc.ships:
			var ship: Dictionary = world.ships[id]
			if ship.owner == 0 and not ship.locked and ship.job.get("kind","") == "护航":
				ship.job = {"kind":"攻城","target":group.capital,"eta":world.day+60}
				break
	else:
		world.set_treaty(flag,new_flag,0)
		world.treaty(flag,new_flag).truce_until = world.day + 720
	return new_flag

static func settle(world, flag: int, bloc: Dictionary) -> void:
	match bloc.kind:
		"autonomy":
			charter(world,bloc.members,flag)
		"claimant","shareholders":
			install_ruler(world,flag,bloc.candidate,bloc.kind == "shareholders")

static func _resolve_ultimatum(world, flag: int, concede: bool) -> bool:
	var bloc: Dictionary = world.campaign.movements.get(flag,{})
	if not bloc.get("ultimatum",false):
		return false
	var group: Dictionary = world.factions[flag]
	world.campaign.movements.erase(flag)
	group.truce_until = world.day+720
	if concede and bloc.kind != "independence":
		settle(world,flag,bloc)
		world.event("%s 接受了%s派的条件。" % [group.name,bloc.demand])
	elif separate(world,flag,bloc,not concede) != world.NEUTRAL:
		world.event("%s 批准成员港独立。" % group.name if concede else "%s 拒绝%s通牒，反对派舰队发动内战。" % [group.name,bloc.demand])
	else:
		# A garrison revolt in a one-port state can change government in the seat itself.
		install_ruler(world,flag,bloc.candidate,bloc.kind == "shareholders")
		if bloc.kind == "autonomy":
			charter(world,bloc.members,flag)
		world.event("%s 首都卫队倒戈，政权更替。" % group.name)
	return true

static func answer_ultimatum(world, flag: int, concede: bool) -> bool:
	if not player_governs(world,flag) or not world.campaign.movements.get(flag,{}).get("ultimatum",false):
		return false
	advance_movement(world,flag,false)
	return _resolve_ultimatum(world,flag,concede)

static func civil_capture(world, port_id: int, attacker: int) -> bool:
	var port: Dictionary = world.ports[port_id]
	var defender: int = port.flag
	var losing: Dictionary = world.factions.get(defender,{})
	var winning: Dictionary = world.factions.get(attacker,{})
	if winning.get("civil_enemy",world.NEUTRAL) != defender or losing.get("civil_enemy",world.NEUTRAL) != attacker:
		return false
	if losing.get("capital",0) != port_id or not world.hostile(attacker,defender):
		return false
	var rebels_won: bool = winning.has("civil_motion")
	var rebels := attacker if rebels_won else defender
	var realm := defender if rebels_won else attacker
	var rebel: Dictionary = world.factions[rebels]
	var group: Dictionary = world.factions[realm]
	var bloc: Dictionary = rebel.civil_motion
	world.set_treaty(realm,rebels,0)
	world.treaty(realm,rebels).truce_until = world.day+720
	group.erase("civil_enemy")
	rebel.erase("civil_enemy")
	rebel.erase("civil_motion")
	group.truce_until = world.day+720
	if rebels_won and bloc.kind == "independence":
		world.people[group.leader].legitimacy = maxi(0,world.people[group.leader].legitimacy-1)
		world.event("%s 攻入首都，%s 承认其独立。" % [rebel.name,group.name])
		return true
	for site in world.ports.values():
		if site.flag == rebels:
			site.flag = realm
			world.Equity.update_operator(world,site)
	for ship in world.ships.values():
		if ship.flag == rebels:
			ship.flag = realm
	for person in world.people.values():
		if person.flag == rebels:
			person.flag = realm
			if person.employer == rebel.leader:
				person.employer = group.leader
	group.treasury += rebel.treasury
	rebel.treasury = 0
	rebel.alive = false
	world.refresh_all_tariffs()
	rebel.capital = 0
	if rebels_won:
		bloc.candidate = rebel.leader
		settle(world,realm,bloc)
	else:
		var ruler: Dictionary = world.people[group.leader]
		ruler.dread = mini(100,int(ruler.get("dread",0))+20)
		ruler.legitimacy = mini(5,ruler.legitimacy+1)
	world.event("%s 的内战以%s告终。" % [group.name,"反对派胜利" if rebels_won else "叛军投降"])
	return true
