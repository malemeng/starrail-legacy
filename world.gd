extends RefCounted

const Portrait = preload("res://portrait.gd")
const Economy = preload("res://economy.gd")
const Politics = preload("res://politics.gd")
const Hulls = preload("res://hull_catalog.gd")
const Frontier = preload("res://frontier.gd")
const Celestial = preload("res://celestial.gd")
const VERSION := 6
const CHUNK_SIZE := 480.0
const WARES := ["矿石", "合金", "燃料", "舰船补给", "重工机械", "日用消费品", "违禁奢侈品"]
const MODULES := ["采矿", "精炼", "船厂", "防务", "居住生态"]
const STYLES := ["军武", "商业", "打捞"]
const REGIMES := ["世袭领", "议会共和国", "商团寡头", "军政府", "公司领"]
const ORIGINS := ["边境飞行员", "商团经纪", "船坞技师"]
const TRAITS := ["谨慎", "野心勃勃", "重情", "务实"]
const START_NAMES := ["林遥", "叶星", "辛羽", "乔闻", "纪澜", "郁白", "岑墨", "夏朔", "唐弦", "顾霜", "杜衡", "许照"]
const DYES := ["e39461", "65c4c9", "a895e2", "96bb73", "edc176", "db7f9d", "7899db", "bea798"]
var HULLS: Array = Hulls.MODELS.map(func(model): return model.name)
var HULL_HP: Array = Hulls.MODELS.map(func(model): return model.hp)
var HULL_CARGO: Array = Hulls.MODELS.map(func(model): return model.cargo)
const NEUTRAL := -1
const RAIDERS := -2
const CANON := [
	["赤矛边防军",3,0,"e39461"], ["曙铁共和国",1,1,"65c4c9"], ["长辉诸侯领",0,0,"a895e2"],
	["九环商会",2,1,"96bb73"], ["赫弧企业领",4,1,"edc176"], ["新岸公社",1,2,"db7f9d"],
	["白鲸舰团",3,2,"7899db"], ["灯塔守护领",0,2,"bea798"],
]

var rng := RandomNumberGenerator.new()
var settings: Dictionary
var systems: Array = []
var ports: Dictionary = {}
var people: Dictionary = {}
var factions: Dictionary = {}
var ships: Dictionary = {}
var wrecks: Dictionary = {}
var relations: Dictionary = {}
var chronicle: Array = []
var contracts: Dictionary = {}
var chunks: Dictionary = {}
var core_count := 0
var core_bounds := Rect2()
var intel: Dictionary = {}

func quantities(values: Array) -> Array:
	var result := values.duplicate()
	while result.size() < WARES.size():
		result.append(0)
	return result

func chunk_at(position: Vector2) -> Vector2i:
	return Vector2i((position / CHUNK_SIZE).floor())

func ensure_chunks_around(galpos: Vector2, radius_chunks: int = 2) -> void:
	var center := chunk_at(galpos)
	for cy in range(center.y - radius_chunks, center.y + radius_chunks + 1):
		for cx in range(center.x - radius_chunks, center.x + radius_chunks + 1):
			var cell := Vector2i(cx, cy)
			if chunks.has(cell):
				continue
			var records: Array = []
			chunks[cell] = records
			var box := Rect2(Vector2(cell) * CHUNK_SIZE, Vector2.ONE * CHUNK_SIZE)
			if box.intersects(core_bounds):
				continue
			var random := RandomNumberGenerator.new()
			random.seed = hash("%s:%s:%s:frontier-1" % [settings.seed, cx, cy])
			var danger := clampf(Vector2(cell).length() / 22.0, 0.08, 1.0)
			var total := random.randi_range(2,4)
			for index in range(total):
				var origin := box.position + Vector2(66 + (index % 2) * 235, 65 + (index / 2) * 235)
				var ore := roundi(random.randi_range(95,190) * (1.0 + danger * 0.8))
				var sites := [{"pos":Vector2(random.randf_range(480,840),random.randf_range(-410,410)),"kind":"漂流货柜","reward":random.randi_range(0,3),"seen":false,"used":false}]
				if random.randf() < 0.10 + danger * 0.64:
					sites.append({"pos":Vector2(-780,random.randf_range(-480,480)),"kind":"古代星门遗迹","reward":random.randi_range(0,3),"seen":false,"used":false})
				records.append(systems.size())
				systems.append({"name":"外域 %s.%s / %s" % [cx,cy,index+1],"pos":origin + Vector2(random.randf_range(0,95),random.randf_range(0,95)),
					"ports":[],"seen":false,"wild":true,"chunk":cell,"ore":ore,"ore_cap":ore,"ore_day":0,"danger":danger,
					"pirate":random.randf() < danger * 0.55,"spawned":false,"field":Vector2(random.randf_range(-430,-190),random.randf_range(-220,220)),"star":random.randf(),"sites":sites})
				Celestial.populate(systems.back(), str(settings.seed))

func systems_in(rectangle: Rect2) -> Array:
	var result: Array = []
	for index in range(core_count):
		if rectangle.has_point(systems[index].pos):
			result.append(index)
	var first := chunk_at(rectangle.position)
	var last := chunk_at(rectangle.end)
	for cy in range(first.y,last.y+1):
		for cx in range(first.x,last.x+1):
			for index in chunks.get(Vector2i(cx,cy), []):
				if rectangle.has_point(systems[index].pos):
					result.append(index)
	return result

func init_core() -> void:
	core_bounds = Rect2(systems[0].pos, Vector2.ZERO)
	for index in range(core_count):
		core_bounds = core_bounds.expand(systems[index].pos)
	core_bounds = core_bounds.grow(110)

func chart(port_id: int) -> void:
	var station: Dictionary = ports[port_id]
	var quotes: Array = []
	for ware in range(6):
		quotes.append([Economy.price(station, ware, true), Economy.price(station, ware, false)])
	intel[port_id] = {"day":day,"stock":station.stock.duplicate(),"quotes":quotes}
var projectiles: Array = []
var combat_events: Array = []
var combat_serial := 0

func combat_event(kind: String, point: Vector2, system: int, direction: Vector2 = Vector2.RIGHT, strength: float = 1.0) -> void:
	combat_serial += 1
	combat_events.append({"kind":kind,"pos":point,"system":system,"direction":direction,"strength":strength,"serial":combat_serial})
	if combat_events.size() > 128:
		combat_events.pop_front()

func outfit(ship_id: int, fit: Dictionary) -> bool:
	var vessel: Dictionary = ships.get(ship_id, {})
	if vessel.is_empty() or not oversees(vessel.owner) or vessel.dock == 0 or active().get("loc", 0) != vessel.dock:
		return false
	if Hulls.fitting_cost(vessel.kind, fit) < 0:
		return false
	vessel.fit = fit.duplicate(true)
	var maximum := Hulls.capacity(vessel)
	vessel.battle.hard_flux = minf(vessel.battle.hard_flux, maximum)
	vessel.battle.soft_flux = minf(vessel.battle.soft_flux, maximum - vessel.battle.hard_flux)
	if vessel.battle.group not in vessel.fit.groups:
		vessel.battle.group = vessel.fit.groups[0]
	return true
var firms: Dictionary = {}
var day := 0
var player := 0
var next_id := 1
var succession := false
var regency := 0
var regent := 0
var last_player := 0
var attention := false
var before_death: Callable

func uid() -> int:
	var result := next_id
	next_id += 1
	return result

func event(message: String) -> void:
	chronicle.push_front([day, message])
	if chronicle.size() > 180:
		chronicle.pop_back()

func date_label(when: int = day) -> String:
	return "%04d.%02d.%02d" % [2400 + when / 360, 1 + (when % 360) / 30, 1 + when % 30]

func name_of(person_id: int) -> String:
	return people.get(person_id, {}).get("name", "—")

func flag_name(flag: int) -> String:
	if flag == NEUTRAL:
		return "中立"
	if flag == RAIDERS:
		return "裂缝掠夺者"
	return factions.get(flag, {}).get("name", "无旗")

func flag_color(flag: int) -> Color:
	if flag == NEUTRAL:
		return Color("88adbd")
	if flag == RAIDERS:
		return Color("e57873")
	return Color(factions.get(flag, {}).get("color", "80bbbb"))

func lead_name(flag: int) -> String:
	return name_of(factions.get(flag, {}).get("leader", 0))

func person(name_text: String, house: String, birth: int, flag: int, location: int, origin: int, temperament: int, look: Dictionary) -> int:
	var person_id := uid()
	people[person_id] = {
		"id": person_id, "name": name_text, "house": house, "birth": birth, "flag": flag, "noble": false,
		"loc": location, "ship": 0, "alive": true, "wallet": 0, "origin": origin, "trait": temperament, "shares": {},
		"look": look.duplicate(true), "parents": [], "spouse": 0, "children": [], "law": 0,
		"endorsement": 0, "employer": 0, "opinions": {}, "last_child": -4000,
		"lifespan": rng.randi_range(68, 89) * 360, "loyalty": 55 + (20 if temperament == 2 else 0),
	}
	return person_id

func random_person(flag: int, location: int, house: String = "") -> int:
	if house.is_empty():
		house = ["苍岭", "望舒", "赤湾", "远岚", "北垣", "辰砂", "霜叶", "金穗"][rng.randi_range(0, 7)]
	return person(START_NAMES[rng.randi_range(0, START_NAMES.size() - 1)], house, day - rng.randi_range(21, 46) * 360, flag, location, rng.randi_range(0, 2), rng.randi_range(0, 3), Portrait.random_look(rng))

func ship(hull_type: int, owner: int, captain: int, flag: int, system: int, pos: Vector2, at_port: int = 0) -> int:
	var ship_id := uid()
	ships[ship_id] = {
		"id": ship_id, "kind": hull_type, "owner": owner, "captain": captain, "flag": flag,
		"system": system, "pos": pos, "dock": at_port, "heading": -PI / 2, "hp": float(HULL_HP[hull_type]),
		"cargo": quantities([]), "fuel": 70.0, "job": {}, "travel": {}, "locked": false, "cool": 0.0,
		"galpos": systems[system].pos, "layer": false, "raid": NEUTRAL,
		"fit": Hulls.stock_fit(hull_type), "battle": Hulls.battle_state(hull_type),
		"crew": Hulls.crew_limits(hull_type).x, "transponder":true, "ping":0.0,
	}
	if captain != 0:
		people[captain].ship = ship_id
		people[captain].loc = at_port
	return ship_id

func port(system: int, label: String, pos: Vector2, flag: int, owner: int, kind: int, ready: bool = true) -> int:
	var port_id := uid()
	var stock := [45, 35, 85]
	if kind == 0:
		stock = [125, 18, 85]
	elif kind == 2:
		stock = [22, 72, 85]
	ports[port_id] = {
		"id": port_id, "system": system, "name": label, "pos": pos, "flag": flag, "owner": owner,
		"manager": 0, "module": kind, "stock": quantities(stock + [120,35,120] if ready else []),
		"build": 0 if ready else 30, "since": day, "hulls": Hulls.inventory(ready),
		"defense": 26 if ready else 8, "scan": system == 0, "firm": 0, "extension": -1, "expansion": 0,
	}
	ports[port_id].merge(Economy.colony_defaults(bool(systems[system].get("wild", false))), false)
	systems[system].ports.append(port_id)
	return port_id

func pair(first: int, second: int) -> Vector2i:
	return Vector2i(mini(first, second), maxi(first, second))

func treaty(first: int, second: int) -> Dictionary:
	return relations.get(pair(first, second), {"state": 0, "since": 0})

func hostile(first: int, second: int) -> bool:
	if first == second:
		return false
	return first == RAIDERS or second == RAIDERS or int(treaty(first, second).state) == -1

func enemy(first: Dictionary, second: Dictionary) -> bool:
	return hostile(first.flag, second.flag) or (second.flag >= 0 and first.get("raid", NEUTRAL) == second.flag) or (first.flag >= 0 and second.get("raid", NEUTRAL) == first.flag)

func set_treaty(first: int, second: int, state: int) -> void:
	if first == second or first == NEUTRAL or second == NEUTRAL:
		return
	relations[pair(first, second)] = {"state": state, "since": day}

func systems_owned(flag: int) -> Array:
	var owned: Array = []
	for port_id in ports:
		if ports[port_id].flag == flag and ports[port_id].build == 0:
			owned.append(port_id)
	return owned

func local_flag(system: int) -> int:
	return NEUTRAL if systems[system].ports.is_empty() else ports[systems[system].ports[0]].flag

func active() -> Dictionary:
	return people.get(player, {})

func ride() -> Dictionary:
	return ships.get(active().get("ship", 0), {})

func can_dock(vessel: Dictionary, station: Dictionary) -> bool:
	if vessel.has("kind") and not Hulls.model_limit(station, vessel.kind):
		return false
	return station.build > 0 or not enemy(vessel, station)

func distance(first: int, second: int) -> float:
	return systems[first].pos.distance_to(systems[second].pos)

func new_game(options: Dictionary) -> bool:
	var count := int(options.get("systems", 24))
	var groups := int(options.get("factions", 5))
	if count < 12 or count > 48 or groups < 3 or groups > 8 or count < groups * 3:
		return false
	day = 0
	next_id = 1
	succession = false
	regency = 0
	regent = 0
	last_player = 0
	attention = false
	settings = options.duplicate(true)
	systems.clear()
	ports.clear()
	people.clear()
	factions.clear()
	ships.clear()
	wrecks.clear()
	relations.clear()
	chronicle.clear()
	contracts.clear()
	chunks.clear()
	intel.clear()
	projectiles.clear()
	combat_events.clear()
	combat_serial = 0
	firms.clear()
	rng.seed = hash(str(options.seed))
	var columns := ceili(sqrt(count * 1.35))
	var rows := ceili(float(count) / columns)
	var letters := ["奎宿", "风暴", "长夜", "乌木", "青铜", "白鲸", "断矛", "灰潮", "海镜", "残阳", "远岸", "黎明"]
	for index in range(count):
		var map_pos := (Vector2(index % columns, index / columns) - Vector2(columns - 1, rows - 1) / 2.0) * 152
		map_pos += Vector2(rng.randf_range(-34, 34), rng.randf_range(-34, 34))
		var label := "%s-%02d" % [letters[rng.randi_range(0, letters.size() - 1)], index + 1]
		if index == 0:
			label = "曙光锚地"
		systems.append({"name": label, "pos": map_pos, "ports": [], "seen": index == 0,
			"field": Vector2(-265, -155) + Vector2(rng.randf_range(-35, 35), rng.randf_range(-60, 45)),
			"ore": 180, "star": rng.randf()})
		Celestial.populate(systems.back(),str(options.seed))
	var overrides: Array = options.get("overrides", [])
	var names := {}
	for flag in range(groups):
		var preset: Dictionary = overrides[flag] if flag < overrides.size() else {}
		var style: int = CANON[flag][2]
		var color: String = CANON[flag][3]
		if int(preset.get("style", -1)) in [0, 1, 2]:
			style = int(preset.style)
		if int(preset.get("color", -1)) in range(DYES.size()):
			color = DYES[preset.color]
		var label := str(preset.get("name", "")).strip_edges().left(16)
		if label.is_empty():
			label = CANON[flag][0]
		if names.has(label):
			label += " %02d" % (flag + 1)
		names[label] = true
		var regime: int = CANON[flag][1]
		if int(preset.get("regime", -1)) in range(REGIMES.size()):
			regime = int(preset.regime)
		factions[flag] = {"name": label, "style": style, "regime": regime, "color": color, "leader": 0, "npc": true,
			"alive": true, "treasury": 1800, "last_war": -360, "capital": 0}
	var vacant: Array = range(2, count)
	for index in range(vacant.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var original: int = vacant[index]
		vacant[index] = vacant[swap]
		vacant[swap] = original
	var owned := [NEUTRAL, NEUTRAL]
	owned.resize(count)
	for index in range(vacant.size()):
		owned[vacant[index]] = index % groups
	var home := 0
	for index in range(count):
		var flag: int = owned[index]
		var module := 2 if index == 0 else (0 if index == 1 else rng.randi_range(0, 2))
		if flag >= 0 and factions[flag].capital == 0:
			module = 2
		elif index == count - 1:
			module = 1
		var port_id := port(index, "晨曦自由港" if index == 0 else systems[index].name + "站", Vector2(110, 60), flag, 0, module)
		if index == 0:
			home = port_id
			ports[port_id].stock = quantities([15,145,125,150,45,150])
		if flag >= 0 and factions[flag].capital == 0:
			factions[flag].capital = port_id
			if flag % 2 == 0:
				ports[port_id].capital_yard = true
				ports[port_id].hulls[7 + flag / 2 % 2] = 1
			var leader := random_person(flag, port_id)
			factions[flag].leader = leader
			people[leader].noble = factions[flag].regime == 0 or rng.randf() < 0.3
			if factions[flag].regime == 0:
				ports[port_id].owner = leader
			people[leader].wallet = 700
			if people[leader].noble:
				var spouse := random_person(flag, port_id)
				people[spouse].noble = true
				Politics.marry(self, leader, spouse)
				people[spouse].last_child = -1200
		var manager := random_person(flag, port_id)
		ports[port_id].manager = manager
		people[manager].wallet = 150
		if flag >= 0:
			people[manager].employer = factions[flag].leader
			var guard := random_person(flag, port_id)
			var guard_ship := ship(2 if factions[flag].style == 0 else 0, 0, guard, flag, index, Vector2(228, -75))
			ships[guard_ship].job = {"kind": "护航", "system": index}
			if module != 2 or index % 2 == 0:
				var trader := random_person(flag, port_id)
				var trader_ship := ship(1, 0, trader, flag, index, ports[port_id].pos, port_id)
				ships[trader_ship].job = {"kind": "贸易"}
		if index == 0 or index % 3 == 1:
			wreck(index, Vector2(240, -175), 12 + (index % 7), 4)
		if index == 1 or index % 4 == 2:
			var pirate := random_person(RAIDERS, port_id)
			var pirate_ship := ship(0, 0, pirate, RAIDERS, index, Vector2(-332, 170))
			ships[pirate_ship].job = {"kind": "护航", "system": index}
	var free_refinery := port(1, "炉心转运站", Vector2(198, -175), NEUTRAL, 0, 1)
	ports[free_refinery].stock = quantities([8,20,50,100,35,110])
	var firm_site := free_refinery
	var possible_branches: Array = []
	for station in ports.values():
		if station.flag < 0:
			continue
		if station.module == 1 and firm_site == free_refinery:
			firm_site = station.id
		if station.module in [0, 1]:
			possible_branches.append(station.id)
	if firm_site == free_refinery:
		firm_site = systems[2].ports[0]
	var director := random_person(ports[firm_site].flag, firm_site)
	var firm_id := incorporate(["赫弧工业", "铂穹冶金", "星砧联合"][rng.randi_range(0, 2)], director, firm_site)
	ports[free_refinery].firm = firm_id
	var expanded := false
	for station_id in possible_branches:
		if not expanded and ports[station_id].flag != ports[firm_site].flag:
			ports[station_id].firm = firm_id
			expanded = true
	for flag in factions:
		if factions[flag].regime == 4:
			var headquarters: int = factions[flag].capital
			if ports[headquarters].firm == 0:
				incorporate(factions[flag].name + "控股", factions[flag].leader, headquarters)
			else:
				people[factions[flag].leader].shares[ports[headquarters].firm] = 25
	for first in factions:
		for second in factions:
			if first < second:
				set_treaty(first, second, 1 if rng.randf() < 0.12 else 0)
	var avatar: Dictionary = options.get("avatar", {})
	var noble := bool(avatar.get("noble", false))
	player = person(str(avatar.get("name", "林遥")), str(avatar.get("house", "远岚")),
		-clampi(int(avatar.get("age", 26)), 18, 65) * 360, NEUTRAL, home, int(avatar.get("origin", 0)),
		int(avatar.get("trait", 0)), avatar.get("look", Portrait.random_look(rng)))
	people[player].wallet = 460
	people[player].noble = noble
	for index in range(2):
		var minor_noble := random_person(NEUTRAL, home)
		people[minor_noble].noble = true
	ship(0, player, player, NEUTRAL, 0, ports[home].pos, home)
	for index in range(5):
		var recruit := random_person(NEUTRAL, home)
		people[recruit].wallet = 140
	ports[home].hulls[3] = 1
	Frontier.setup(self)
	core_count = systems.size()
	init_core()
	chart(home)
	event("「%s」在晨曦自由港登记。隔壁星系的采矿站长期出售低价矿石。" % name_of(player))
	return true

func incorporate(label: String, founder: int, site: int) -> int:
	var firm_id := uid()
	firms[firm_id] = {"name": label.strip_edges().left(20), "director": founder, "hq": site, "embargo": NEUTRAL, "revenue": 0}
	people[founder].shares[firm_id] = 100
	ports[site].firm = firm_id
	return firm_id

func wreck(system: int, pos: Vector2, alloy: int, fuel: int) -> void:
	var wreck_id := uid()
	wrecks[wreck_id] = {"system": system, "pos": pos, "stock": [0, alloy, fuel], "at": day}

func mark_seen(system: int) -> void:
	if not systems[system].seen:
		systems[system].seen = true
		event("首次抵达 " + systems[system].name)
	for port_id in systems[system].ports:
		ports[port_id].scan = true
	var region: Dictionary = systems[system]
	if region.get("wild",false):
		region.ore = mini(region.ore_cap, region.ore + floori((day - region.ore_day) / 30.0) * 14)
		region.ore_day = day
		if region.pirate and not region.spawned:
			region.spawned = true
			ship(0 if region.danger < 0.52 else 2, 0, 0, RAIDERS, system, Vector2(-640, 260))

func oversees(owner: int) -> bool:
	return owner != 0 and (owner == player or (regency == owner and player == regent))

func cargo_free(vessel: Dictionary) -> int:
	var free: int = HULL_CARGO[vessel.kind]
	for amount in vessel.cargo:
		free -= amount
	return maxi(0, free)

func pilot(new_ship_id: int) -> bool:
	var character := active()
	var vessel: Dictionary = ships.get(new_ship_id, {})
	var old := ride()
	var location: int = old.get("dock", character.get("loc", 0))
	if vessel.is_empty() or location == 0 or vessel.dock != location or not oversees(vessel.owner):
		return false
	if vessel.captain not in [0, player]:
		var other: Dictionary = people[vessel.captain]
		other.ship = 0
		other.loc = location
	if not old.is_empty() and old.captain == player:
		old.captain = 0
	vessel.captain = player
	vessel.job = {}
	character.ship = new_ship_id
	character.loc = location
	return true

func berth(vessel: Dictionary, port_id: int) -> bool:
	var station: Dictionary = ports[port_id]
	if vessel.captain == player and not vessel.transponder and is_regular(station):
		return false
	if not can_dock(vessel, station):
		return false
	vessel.system = station.system
	vessel.pos = station.pos
	vessel.dock = port_id
	vessel.locked = false
	vessel.battle.shield = false
	vessel.battle.vent = false
	vessel.battle.motion = Vector2.ZERO
	if vessel.captain != 0:
		people[vessel.captain].loc = port_id
	if vessel.captain == player:
		chart(port_id)
	return true

func is_regular(station: Dictionary) -> bool:
	return station.build == 0 and (not systems[station.system].get("wild", false) or station.pop >= 120)

func depart(vessel: Dictionary) -> void:
	vessel.dock = 0
	if vessel.captain != 0:
		people[vessel.captain].loc = 0

func credit(person_id: int, amount: int) -> void:
	if person_id != 0 and people.has(person_id):
		people[person_id].wallet += amount

func tick(days: int = 1) -> void:
	for step in range(days):
		if succession or attention:
			break
		day += 1
		Economy.population_day(self)
		if day % 6 == 0:
			Economy.advance(self)
		if day % 30 == 0:
			Politics.advance(self)
		if day % 90 == 0:
			for wreck_id in wrecks.keys():
				if day - wrecks[wreck_id].at > 360:
					wrecks.erase(wreck_id)

func destruction(ship_id: int, killer: int = 0) -> void:
	if not ships.has(ship_id):
		return
	var vessel: Dictionary = ships[ship_id]
	var killed: int = vessel.captain
	if killed != 0 and killed == player and before_death.is_valid():
		before_death.call()
	combat_event("rupture", vessel.pos, vessel.system, Vector2.from_angle(vessel.heading), Hulls.CLASS_SPRITE[Hulls.MODELS[vessel.kind].size])
	wreck(vessel.system, vessel.pos, 6 + vessel.kind * 3 + vessel.cargo[1], 4 + vessel.cargo[2])
	ships.erase(ship_id)
	if killed != 0:
		people[killed].ship = 0
		Politics.die(self, killed, false)
	if killer != 0 and people.has(killer) and people[killer].alive and vessel.flag == RAIDERS:
		credit(killer, 95)
		if contracts.get(killer, {}).get("type", -1) == 1:
			credit(killer, 180)
			contracts.erase(killer)
			if killer == player:
				event("赏金委托完成：收到 180 信用点。")

func snapshot() -> Dictionary:
	return {"save_version": VERSION, "version": VERSION, "settings": settings, "systems": systems, "ports": ports,
		"chunks":chunks,"core_count":core_count,"intel":intel,
		"people": people, "factions": factions, "ships": ships, "wrecks": wrecks, "relations": relations,
		"chronicle": chronicle, "contracts": contracts, "firms": firms, "day": day, "player": player,
		"next_id": next_id, "rng_seed": rng.seed, "rng_state": rng.state, "succession": succession,
		"last_player": last_player, "regency": regency, "regent": regent}

func migrate(data: Dictionary) -> Dictionary:
	var version: Variant = data.get("save_version", data.get("version", 3))
	if not version is int or version < 3 or version > VERSION:
		return {}
	var copy := data.duplicate(true)
	copy.merge({"chunks":{},"core_count":copy.systems.size(),"intel":{}},false)
	for region in copy.systems:
		if not region.has("planets") or not region.has("sun"):
			Celestial.populate(region,str(copy.settings.get("seed","")))
	for station in copy.ports.values():
		station.stock = quantities(station.get("stock", []))
		station.merge(Economy.colony_defaults(bool(copy.systems[station.system].get("wild", false))),false)
		var inventory := Hulls.inventory(false)
		var old_inventory: Variant = station.get("hulls", [])
		if old_inventory is Array:
			for model in range(mini(old_inventory.size(), inventory.size())):
				inventory[model] = old_inventory[model]
		station.hulls = inventory
	if version == 3:
		for flag in copy.factions:
			var capital: int = copy.factions[flag].capital
			if flag >= 0 and flag % 2 == 0 and copy.ports.has(capital) and copy.ports[capital].module == 2:
				copy.ports[capital].capital_yard = true
	for vessel in copy.ships.values():
		if vessel.get("kind", -1) not in range(Hulls.MODELS.size()):
			return {}
		if not vessel.get("fit") is Dictionary or Hulls.fitting_cost(vessel.kind, vessel.fit) < 0:
			vessel.fit = Hulls.stock_fit(vessel.kind)
		var battle := Hulls.battle_state(vessel.kind)
		if vessel.get("battle") is Dictionary:
			for key in battle:
				if vessel.battle.has(key) and typeof(vessel.battle[key]) == typeof(battle[key]):
					battle[key] = vessel.battle[key]
		if battle.cooldowns.size() != Hulls.COMBAT[vessel.kind].slots.size():
			battle.cooldowns = Hulls.battle_state(vessel.kind).cooldowns
		vessel.battle = battle
		vessel.cargo = quantities(vessel.get("cargo", []))
		vessel.merge({"crew":Hulls.crew_limits(vessel.kind).x,"transponder":true,"ping":0.0},false)
	copy.save_version = VERSION
	copy.version = VERSION
	return copy

func load_state(data: Dictionary) -> bool:
	for key in ["settings", "ports", "people", "factions", "ships", "wrecks", "relations", "contracts", "firms"]:
		if not data.get(key) is Dictionary:
			return false
	for key in ["systems", "chronicle"]:
		if not data.get(key) is Array:
			return false
	for key in ["day", "player", "next_id", "rng_seed", "rng_state", "last_player", "regency", "regent"]:
		if not data.get(key) is int:
			return false
	if data.people.is_empty() or data.systems.is_empty() or (not data.succession and not data.people.has(data.player)):
		return false
	var copy := migrate(data)
	if copy.is_empty():
		return false
	for key in ["settings", "systems", "ports", "people", "factions", "ships", "wrecks", "relations", "chronicle", "contracts", "firms", "chunks", "core_count", "intel",
		"day", "player", "next_id", "succession", "last_player", "regency", "regent"]:
		set(key, copy[key])
	rng.seed = copy.rng_seed
	rng.state = copy.rng_state
	init_core()
	projectiles.clear()
	combat_events.clear()
	combat_serial = 0
	attention = false
	return true
