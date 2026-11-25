extends RefCounted

const Portrait = preload("res://portrait.gd")
const Economy = preload("res://economy.gd")
const Finances = preload("res://scripts/economy/financial_report.gd")
const StockPrices = preload("res://scripts/economy/stock_prices.gd")
const Capital = preload("res://scripts/economy/capital_registry.gd")
const Dividends = preload("res://scripts/economy/station_dividends.gd")
const Treasury = preload("res://scripts/economy/station_treasury.gd")
const Equity = preload("res://scripts/economy/corporate_equity.gd")
const EquityOrders = preload("res://scripts/economy/equity_orders.gd")
const ShareExchange = preload("res://scripts/economy/share_exchange.gd")
const TradeLaw = preload("res://scripts/campaign/securities_law.gd")
const DiplomaticTrade = preload("res://scripts/economy/diplomatic_trade.gd")
const StationEquity = preload("res://scripts/economy/station_equity.gd")
const Politics = preload("res://politics.gd")
const WarPeace = preload("res://scripts/campaign/war_peace.gd")
const CompanyWars = preload("res://scripts/campaign/company_wars.gd")
const Hulls = preload("res://hull_catalog.gd")
const Frontier = preload("res://frontier.gd")
const Celestial = preload("res://celestial.gd")
const PlanetPorts = preload("res://scripts/campaign/planet_ports.gd")
const ConstructionContract = preload("res://scripts/campaign/construction_contract.gd")
const State = preload("res://scripts/models/world_state.gd")
const Person = preload("res://scripts/models/person_data.gd")
const Ship = preload("res://scripts/models/ship_data.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Operations = preload("res://scripts/campaign/operations.gd")
const Crises = preload("res://scripts/campaign/crises.gd")
const Outlaws = preload("res://scripts/campaign/outlaws.gd")
const Bounties = preload("res://scripts/campaign/bounties.gd")
const StationGeometry = preload("res://scripts/models/station_geometry.gd")
const Society = preload("res://scripts/campaign/society.gd")
const VERSION := State.VERSION
var campaign: Dictionary = {}
signal event_offered()
signal merchant_attacked(message: String)
signal watched_activity(message: String)
static var CHUNK_SIZE: float = Celestial.Scale.data.frontier_chunk_size
static var WARES: Array = Industry.WARES
static var MODULES: Array = Industry.MODULES
static var STYLES: Array = Society.rules.styles
static var REGIMES: Array = Society.rules.governments.map(func(row): return row.name)
static var ORIGINS: Array = Society.rules.origins
const TRAITS := ["谨慎", "野心勃勃", "重情", "务实"]
const NAME_POOLS := {
	"sinic": {
		"houses": ["苍岭", "望舒", "赤湾", "远岚", "北垣", "辰砂", "霜叶", "金穗", "青崖", "星河", "沈", "顾", "谢", "陆", "苏", "周", "楚", "秦", "韩", "傅", "程", "霍", "裴", "云"],
		"male": ["林遥", "景行", "知微", "闻舟", "归鸿", "明昭", "临渊", "南风", "长风", "寒江", "杜衡", "许照", "夏朔", "岑墨", "纪澜", "郁白", "予安", "观澜"],
		"female": ["叶星", "辛羽", "顾霜", "唐弦", "清晏", "辞镜", "书昀", "若水", "怀瑾", "月白", "微澜", "知秋", "凌霄", "暮雪", "千帆", "乔闻", "惊蛰", "青霓"]
	},
	"western": {
		"houses": ["瓦伦", "卡斯特", "莫罗", "霍克", "兰斯", "索恩", "阿什顿", "诺瓦克", "斯特林", "罗伊斯", "德雷克", "温特", "克劳斯", "哈珀", "科尔", "福斯特", "梅森", "格雷", "布莱克", "门罗", "维加", "桑托斯", "雷诺", "克莱尔"],
		"male": ["马库斯", "维克托", "塞巴斯蒂安", "罗兰", "加布里埃尔", "雷文", "莱昂", "亚历山大", "朱利安", "阿德里安", "卢卡斯", "菲利克斯", "康拉德", "埃里克", "诺亚", "罗伯特", "西蒙", "马丁"],
		"female": ["艾琳", "伊莱娜", "卡莲", "奥利维亚", "索菲亚", "克洛伊", "海伦娜", "塞西莉亚", "薇薇安", "伊莎贝尔", "格蕾丝", "克莱尔", "艾米莉", "爱丽丝"]
	},
	"slavic": {
		"houses": ["沃尔科夫", "索科洛夫", "莫罗佐夫", "奥尔洛夫", "科兹洛夫", "沃罗宁", "扎哈罗夫", "别洛夫", "卡林宁", "斯米尔诺夫", "瓦西里耶夫", "费奥多罗夫"],
		"male": ["尤里", "伊万", "米哈伊尔", "阿列克谢", "德米特里", "谢尔盖", "尼古拉", "帕维尔"],
		"female": ["娜塔莎", "安娜", "叶莲娜", "卡捷琳娜", "奥尔加", "塔季扬娜", "斯维特拉娜", "玛丽亚"]
	},
	"japanese": {
		"houses": ["高桥", "浅野", "黑泽", "水野", "桐生", "白石", "神崎", "藤原", "星野", "真田", "朝仓", "月城"],
		"male": ["晴明", "悠真", "隼人", "宗介", "莲", "拓海", "奏太", "健太"],
		"female": ["真希", "绫音", "千寻", "凛", "雪乃", "葵", "美咲", "沙耶", "萤"]
	},
	"levant": {
		"houses": ["阿尔法拉", "卡西姆", "曼苏尔", "纳赛尔", "萨拉赫", "拉希德", "哈达德", "塔里克", "扎伊德", "伊德里斯"],
		"male": ["阿米尔", "哈桑", "奥马尔", "卡里姆", "扎因", "拉米"],
		"female": ["莱拉", "雅丝敏", "萨米拉", "法蒂玛", "努尔", "阿丽亚"]
	}
}
const START_NAMES := ["林遥", "叶星", "辛羽", "乔闻", "纪澜", "郁白", "岑墨", "夏朔", "唐弦", "顾霜", "杜衡", "许照", "艾琳", "马库斯", "维克托", "伊莱娜", "卡莲", "罗兰", "雷文", "索菲亚", "尤里", "娜塔莎", "晴明", "真希", "阿米尔", "莱拉"]
const DYES := ["e39461", "65c4c9", "a895e2", "96bb73", "edc176", "db7f9d", "7899db", "bea798"]
var HULLS: Array = Hulls.MODELS.map(func(model): return model.name)
var HULL_HP: Array = Hulls.MODELS.map(func(model): return model.hp)
var HULL_CARGO: Array = Hulls.MODELS.map(func(model): return model.cargo)
const NEUTRAL := -1
const RAIDERS := -2
const CULT := -3
const ROGUE_MACHINES := -4
static var CANON: Array = Society.rules.faction_presets
static var deployment: Dictionary = Society.rules.deployment

func fleet_pick(pool: Array, system_id: int, duty: String) -> int:
	var roll := absi(hash([settings.seed,system_id,duty]))
	return Hulls.kind_for_reference(pool[roll % pool.size()])

func freight_hull(pool: Array, station: Dictionary, captain_id: int = 0) -> int:
	var volume := 0
	for ware in station.exports:
		volume += Industry.available(station,ware)
	for ware in station.imports:
		if ware not in station.exports:
			volume += mini(Industry.space(station,ware),maxi(0,int(Industry.stock_target(ware))-station.stock[ware]))
	var candidates := []
	var best_gap := 2147483647
	for reference in pool:
		var kind := Hulls.kind_for_reference(reference)
		if not Hulls.model_limit(station,kind):
			continue
		if captain_id != 0 and Hulls.MODELS[kind].size == Hulls.Size.CAPITAL:
			# Superfreighters need two suitable terminals serving a viable route.
			var proposal := Ship.create(0,kind,0,captain_id,station.flag,station.system,station.pos,systems[station.system].pos,station.id,quantities([]))
			proposal.job = {"kind":"贸易"}
			if Economy.trade_plan(self,proposal).is_empty():
				continue
		var gap := absi(int(Hulls.MODELS[kind].cargo)-volume)
		if gap < best_gap:
			best_gap = gap
			candidates.clear()
		if gap == best_gap:
			candidates.append(reference)
	return fleet_pick(candidates,station.system,"freighter") if not candidates.is_empty() else -1

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
var streamed_radii: Dictionary[Vector2i, int] = {}
var core_count := 0
var core_bounds := Rect2()
var intel: Dictionary = {}

func quantities(values: Array) -> Array:
	var result := values.duplicate()
	while result.size() < WARES.size():
		result.append(0)
	return result

func set_initial_stock(station: Dictionary, amounts: Array) -> void:
	for i in range(amounts.size()):
		station.stock[i] = amounts[i]

func chunk_at(position: Vector2) -> Vector2i:
	return Vector2i((position / CHUNK_SIZE).floor())

func stream_hyperspace(position: Vector2, half_extent: Vector2 = Vector2.ZERO) -> void:
	var cell := chunk_at(position)
	var radius := maxi(1, ceili(maxf(half_extent.x, half_extent.y) / CHUNK_SIZE))
	if streamed_radii.get(cell, -1) < radius:
		ensure_chunks_around(position, radius)
		streamed_radii[cell] = radius

func nearby_beacons(position: Vector2) -> Array:
	var extent := Vector2.ONE * (CHUNK_SIZE * 0.75)
	stream_hyperspace(position, extent)
	var nearby := systems_in(Rect2(position - extent, extent * 2.0))
	nearby.sort_custom(func(a: int, b: int): return position.distance_squared_to(systems[a].pos) < position.distance_squared_to(systems[b].pos))
	return nearby

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
			var random := RandomNumberGenerator.new()
			random.seed = hash("%s:%s:%s:frontier-1" % [settings.seed, cx, cy])
			var danger := clampf(Vector2(cell).length() / 22.0, 0.08, 1.0)
			var total := random.randi_range(1,4)
			var positions: Array[Vector2] = []
			for index in range(total):
				var point: Vector2
				var usable := false
				for attempt in range(24):
					var margin := float(Celestial.Scale.data.min_beacon_spacing) * 0.5
					point = box.position + Vector2(random.randf_range(margin,CHUNK_SIZE-margin),random.randf_range(margin,CHUNK_SIZE-margin))
					if positions.any(func(p: Vector2): return p.distance_to(point) < Celestial.Scale.data.min_beacon_spacing):
						continue
					usable = true
					if box.intersects(core_bounds):
						for core in range(core_count):
							if point.distance_to(systems[core].pos) < Celestial.Scale.data.min_beacon_spacing:
								usable = false
								break
					if usable:
						break
				if not usable:
					continue
				positions.append(point)
				var sites := [{"pos":Vector2(random.randf_range(480,840),random.randf_range(-410,410)),"kind":"漂流货柜","reward":random.randi_range(0,3),"seen":false,"used":false}]
				if random.randf() < 0.10 + danger * 0.64:
					sites.append({"pos":Vector2(-780,random.randf_range(-480,480)),"kind":"古代星门遗迹","reward":random.randi_range(0,3),"seen":false,"used":false})
				records.append(systems.size())
				systems.append({"name":"外域 %s.%s / %s" % [cx,cy,index+1],"pos":point,
					"ports":[],"seen":false,"wild":true,"chunk":cell,"ore_day":0,"danger":danger,
					"frontier_depot":records.size() == 1,
					"pirate":random.randf() < danger * 0.55,"spawned":false,"star":random.randf(),"sites":sites})
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
	streamed_radii.clear()
	if has_meta("trade_navigation"):
		remove_meta("trade_navigation")
	core_bounds = Rect2(systems[0].pos, Vector2.ZERO)
	for index in range(core_count):
		core_bounds = core_bounds.expand(systems[index].pos)
	core_bounds = core_bounds.grow(Celestial.Scale.data.min_beacon_spacing)

func chart(port_id: int) -> void:
	var station: Dictionary = ports[port_id]
	var quotes: Array = []
	for ware in range(WARES.size()):
		quotes.append([Economy.price(station, ware, true), Economy.price(station, ware, false)])
	intel[port_id] = {"day":day,"stock":station.stock.duplicate(),"quotes":quotes}
var projectiles: Array = []
signal ship_wrecked(id: int, record: Dictionary)
signal market_updated(port_id: int, ware: int, black: bool)
var combat_events: Array = []
var combat_serial := 0

func combat_event(kind: String, point: Vector2, system: int, direction: Vector2 = Vector2.RIGHT, strength: float = 1.0) -> void:
	combat_serial += 1
	combat_events.append({"kind":kind,"pos":point,"system":system,"direction":direction,"strength":strength,"serial":combat_serial})
	if combat_events.size() > 128:
		combat_events.pop_front()

func trade_event(black: bool, actor_id: int) -> void:
	var actor: Dictionary = people.get(actor_id, {})
	if actor.is_empty():
		return
	if black and (actor.secrets.is_empty() or actor.secrets.back().get("day", -1) != day):
		actor.secrets.append({"kind": "smuggling", "day": day})
	if actor_id == player:
		Society.offer(self, "on_trade")

func outfit(ship_id: int, input: Variant) -> bool:
	var vessel: Dictionary = ships.get(ship_id, {})
	if not can_operate(vessel) or vessel.dock == 0 or active().get("loc", 0) != vessel.dock:
		return false
	var fit: Hulls.Fitting
	if input is Hulls.Fitting:
		fit = input.copy()
	elif input is Dictionary:
		fit = Hulls.Fitting.from_dictionary(input,false,Hulls.MODELS[vessel.kind].reference_wings)
	if Hulls.fitting_cost(vessel.kind, fit) < 0:
		return false
	vessel.fit = fit
	var maximum := Hulls.capacity(vessel)
	vessel.battle.hard_flux = minf(vessel.battle.hard_flux, maximum)
	vessel.battle.soft_flux = minf(vessel.battle.soft_flux, maximum - vessel.battle.hard_flux)
	if not vessel.fit.groups.is_empty() and vessel.battle.group not in vessel.fit.groups:
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

func is_watched(person_id: int) -> bool:
	var arr: Array = campaign.get("watched_people", [])
	return person_id in arr

func toggle_watch(person_id: int) -> bool:
	if not people.has(person_id) or person_id == player:
		return false
	if not campaign.has("watched_people") or not (campaign.watched_people is Array):
		campaign["watched_people"] = []
	var arr: Array = campaign.watched_people
	if person_id in arr:
		arr.erase(person_id)
		return false
	arr.append(person_id)
	return true

func watched_list() -> Array[int]:
	var out: Array[int] = []
	for raw in campaign.get("watched_people", []):
		var pid := int(raw)
		if people.has(pid) and pid != player and not out.has(pid):
			out.append(pid)
	return out

func event(message: String) -> void:
	chronicle.push_front([day, message])
	if chronicle.size() > 180:
		chronicle.pop_back()
	var watched: Array = campaign.get("watched_people", [])
	if not watched.is_empty():
		for raw in watched:
			var pid := int(raw)
			if pid == player or not people.has(pid):
				continue
			var pname := str(people[pid].get("name", ""))
			if pname.is_empty():
				continue
			var matched := pname in message
			if not matched:
				for fid in firms:
					if int(firms[fid].get("director", 0)) == pid and str(firms[fid].get("name", "")) in message:
						matched = true
						break
			if matched:
				if not campaign.has("watched_feed") or not (campaign.watched_feed is Array):
					campaign["watched_feed"] = []
				campaign.watched_feed.push_front([day, pid, message])
				if campaign.watched_feed.size() > 40:
					campaign.watched_feed.pop_back()
				watched_activity.emit("★ [关注·%s] %s" % [pname, message])
				break

func date_label(when: int = day) -> String:
	return "%04d.%02d.%02d" % [2400 + when / 360, 1 + (when % 360) / 30, 1 + when % 30]

func name_of(person_id: int) -> String:
	return people.get(person_id, {}).get("name", "—")

func flag_name(flag: int) -> String:
	if flag == NEUTRAL:
		return "中立"
	if flag == RAIDERS:
		return Outlaws.groups[Outlaws.PIRATES].name
	if flag == CULT:
		return Outlaws.groups[Outlaws.CULT].name
	if flag == ROGUE_MACHINES:
		return "失控机群"
	return factions.get(flag, {}).get("name", "无旗")

func flag_color(flag: int) -> Color:
	if flag == NEUTRAL:
		return Color("88adbd")
	if flag == RAIDERS:
		return Color(Outlaws.groups[Outlaws.PIRATES].color)
	if flag == CULT:
		return Color(Outlaws.groups[Outlaws.CULT].color)
	if flag == ROGUE_MACHINES:
		return Color("e6b261")
	return Color(factions.get(flag, {}).get("color", "80bbbb"))

func lead_name(flag: int) -> String:
	return name_of(factions.get(flag, {}).get("leader", 0))

func person(name_text: String, house: String, birth: int, flag: int, location: int, origin: int, temperament: int, look: Dictionary, gender: int = 0) -> int:
	var person_id := uid()
	people[person_id] = Person.create(person_id, name_text, house, birth, flag, location, origin,
		temperament, look, rng.randi_range(68, 89) * 360, gender)
	Society.initialize_person(people[person_id])
	people[person_id].stats = Person.Attributes.from_dict(people[person_id].stats)
	return person_id

func random_culture_key() -> String:
	var roll := rng.randf()
	if roll < 0.34:
		return "sinic"
	if roll < 0.68:
		return "western"
	if roll < 0.80:
		return "slavic"
	if roll < 0.90:
		return "japanese"
	return "levant"

func house_culture(house: String) -> String:
	for key in NAME_POOLS:
		if house in NAME_POOLS[key].houses:
			return key
	return ""

func random_given_name(house: String = "", gender: int = -1) -> String:
	var key := house_culture(house)
	if key.is_empty():
		key = random_culture_key()
	var g := gender if gender in [0, 1] else rng.randi_range(0, 1)
	var pool: Array = NAME_POOLS[key]["female" if g == 1 else "male"]
	return pool[rng.randi_range(0, pool.size() - 1)]

func random_person(flag: int, location: int, house: String = "", gender: int = -1) -> int:
	if house.is_empty():
		var key := random_culture_key()
		var houses: Array = NAME_POOLS[key].houses
		house = houses[rng.randi_range(0, houses.size() - 1)]
	var g := gender if gender in [0, 1] else rng.randi_range(0, 1)
	return person(random_given_name(house, g), house, day - rng.randi_range(21, 46) * 360, flag, location, rng.randi_range(0, 2), rng.randi_range(0, 3), Portrait.random_look_for_gender(rng, g), g)

func ship(hull_type: int, owner: int, captain: int, flag: int, system: int, pos: Vector2, at_port: int = 0) -> int:
	return _register_ship(uid(),hull_type,owner,captain,flag,system,pos,at_port)

func _register_ship(ship_id: int, hull_type: int, owner: int, captain: int, flag: int, system: int, pos: Vector2, at_port: int) -> int:
	ships[ship_id] = Ship.create(ship_id, hull_type, owner, captain, flag, system, pos,
		systems[system].pos, at_port, quantities([]))
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
		"build": 0 if ready else int(Industry.CONSTRUCTION.foundation.days), "since": day, "hulls": Hulls.inventory(ready),
		"defense": 26 if ready else 8, "scan": system == 0, "firm": 0, "extension": -1, "expansion": 0,
	}
	ports[port_id].merge(Economy.colony_defaults(bool(systems[system].get("wild", false)), ready), false)
	Economy.initialize_station(self, ports[port_id], ready)
	Capital.register_site(ports[port_id])
	Equity.update_operator(self,ports[port_id])
	systems[system].ports.append(port_id)
	refresh_tariffs(system)
	return port_id

func pair(first: int, second: int) -> Vector2i:
	return Vector2i(mini(first, second), maxi(first, second))

func treaty(first: int, second: int) -> Dictionary:
	return relations.get(pair(first, second), {"state": 0, "since": 0})

func hostile(first: int, second: int) -> bool:
	if first == second:
		return false
	return first < NEUTRAL or second < NEUTRAL or int(treaty(first, second).state) == -1

func enemy(first: Dictionary, second: Dictionary) -> bool:
	var a: int = first.flag
	var b: int = second.flag
	if hostile(a,b) or (b >= 0 and first.get("raid",NEUTRAL) == b) or (a >= 0 and second.get("raid",NEUTRAL) == a):
		return true
	var source: Dictionary = ships.get(first.ship, first) if first.has("ship") else first
	var target: Dictionary = ships.get(second.ship, second) if second.has("ship") else second
	if source.has("engaged_by") and int(source.engaged_by.get(target.get("id",0),-1)) >= day:
		return true
	if target.has("engaged_by") and int(target.engaged_by.get(source.get("id",0),-1)) >= day:
		return true
	if (source.has("blockade_owner") or target.has("blockade_owner")) and Crises.enemies(source,target):
		return true
	return CompanyWars.ships_hostile(self, source, target)

func engage_ship(attacker: Dictionary, target: Dictionary, instigator: int) -> void:
	if attacker.is_empty() or target.is_empty() or attacker.id == target.id or enemy(attacker,target):
		return
	var engaged: Dictionary = target.get_or_add("engaged_by",{})
	for id in engaged.keys():
		if engaged[id] < day or not ships.has(id):
			engaged.erase(id)
	engaged[attacker.id] = day + 30
	if instigator != 0:
		change_faction_trust(target.flag,instigator,-25,"主动攻击 #%d %s" % [target.id,HULLS[target.kind]])
		event("%s 对 #%d %s 发起攻击。" % [name_of(instigator),target.id,HULLS[target.kind]])

func faction_trust(flag: int, person: int) -> int:
	return people.get(person,{}).get("faction_trust",{}).get(flag,{}).get("score",0)

func change_faction_trust(flag: int, person: int, change: int, reason: String) -> void:
	if not factions.has(flag) or not people.has(person) or change == 0:
		return
	var scores: Dictionary = people[person].get_or_add("faction_trust",{})
	var before := faction_trust(flag,person)
	var after := clampi(before + change,-100,100)
	if before != after:
		scores[flag] = {"score":after,"day":day,"change":after-before,"reason":reason}

func set_treaty(first: int, second: int, state: int) -> void:
	if first == second or first == NEUTRAL or second == NEUTRAL:
		return
	relations[pair(first, second)] = {"state": state, "since": day}
	ShareExchange.audit(self)
	if not campaign.get("equity_orders",{}).get("orders",{}).is_empty():
		EquityOrders.audit(self)
	if not campaign.get("diplomatic_deal",{}).is_empty():
		DiplomaticTrade.daily(self)

func systems_owned(flag: int) -> Array:
	var owned: Array = []
	for port_id in ports:
		if ports[port_id].flag == flag and ports[port_id].build == 0:
			owned.append(port_id)
	return owned

func local_flag(system: int) -> int:
	return NEUTRAL if systems[system].ports.is_empty() else ports[systems[system].ports[0]].flag

## The first port is the political seat of the system; individual facilities retain their own owners and flags.
func sovereign(system: int) -> int:
	if system<0 or system>=systems.size():
		return NEUTRAL
	var flag := local_flag(system)
	return flag if flag>=0 and factions.get(flag,{}).get("alive",false) else NEUTRAL

func refresh_tariffs(system: int) -> void:
	var flag := sovereign(system)
	var sites: Array = systems[system].ports
	var former: int = ports[sites.front()].get("tariff_flag",flag) if not sites.is_empty() else flag
	var rate := float(ports[sites.front()].tax_rate) if flag>=0 else 0.0
	for id: int in sites:
		ports[id].tariff_flag = flag
		ports[id].tariff_rate = rate
	if former != flag:
		ShareExchange.audit(self)
		if not campaign.get("equity_orders",{}).get("orders",{}).is_empty():
			EquityOrders.audit(self)
		DiplomaticTrade.daily(self)
		Capital.audit(self)

func refresh_all_tariffs() -> void:
	for system in systems.size():
		refresh_tariffs(system)

func active() -> Dictionary:
	return people.get(player, {})

func ride() -> Dictionary:
	return ships.get(active().get("ship", 0), {})

func can_dock(vessel: Dictionary, station: Dictionary) -> bool:
	if not Hulls.berth_fits(vessel,station):
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
	if has_meta("battle_screens"): remove_meta("battle_screens")
	combat_events.clear()
	combat_serial = 0
	firms.clear()
	campaign = Society.initial_state()
	rng.seed = hash(str(options.seed))
	var chart_points := Celestial.core_chart(str(options.seed), count)
	var letters: Array = Society.rules.systems
	for index in range(count):
		var label := "%s-%02d" % [letters[rng.randi_range(0, letters.size() - 1)], index + 1]
		if index == 0:
			label = "曙光锚地"
		systems.append({"name": label, "pos": chart_points[index], "ports": [], "seen": index == 0,"star":rng.randf()})
		Celestial.populate(systems.back(),str(options.seed))
	Treasury.establish(self)
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
			"alive": true, "treasury": 12000, "last_war": -360, "capital": 0}
	var vacant: Array = range(2, count)
	for index in range(vacant.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var original: int = vacant[index]
		vacant[index] = vacant[swap]
		vacant[swap] = original
	var owned := [NEUTRAL, NEUTRAL]
	var opening_traders := {}
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
		var port_id := port(index, "晨曦自由港" if index == 0 else systems[index].name + "站", Celestial.port_anchor(systems[index]), flag, 0, module)
		if index == 0:
			home = port_id
			set_initial_stock(ports[port_id], [15,145,125,150,45,150])
		elif index > 1:
			Industry.seed_industry_stock(ports[port_id],str(options.seed))
		if flag >= 0 and factions[flag].capital == 0:
			factions[flag].capital = port_id
			if flag % 2 == 0:
				ports[port_id].capital_yard = true
				ports[port_id].hulls[fleet_pick(deployment.capital_stock,index,"reserve")] = 1
			var leader := random_person(flag, port_id)
			factions[flag].leader = leader
			people[leader].noble = factions[flag].regime == 0 or rng.randf() < 0.3
			if factions[flag].regime == 0:
				ports[port_id].owner = leader
			people[leader].wallet = 3500
			if people[leader].noble:
				var spouse := random_person(flag, port_id, "", 1 - int(people[leader].get("gender", 0)))
				people[spouse].noble = true
				Politics.marry(self, leader, spouse)
				people[spouse].last_child = -1200
		var manager := random_person(flag, port_id)
		ports[port_id].manager = manager
		people[manager].wallet = 800
		if flag >= 0:
			people[manager].employer = factions[flag].leader
			var guard := random_person(flag, port_id)
			var guard_ship := ship(fleet_pick(deployment.guards[factions[flag].style],index,"patrol"), 0, guard, flag, index, Celestial.anchor(systems[index],Vector2(228,-75)))
			ships[guard_ship].job = {"kind": "护航", "system": index}
			if module != 2 or index % 2 == 0:
				var trader := random_person(flag,port_id)
				opening_traders[uid()] = {"captain":trader,"port":port_id}
		if index == 0 or index % 3 == 1:
			wreck(index, Celestial.anchor(systems[index],Vector2(240,-175)), 12 + (index % 7), 4)
		if index == 1 or index % 4 == 2:
			var pirate := random_person(RAIDERS, port_id)
			var kind := Hulls.kind_for_reference(deployment.tutorial_raider) if index == 1 else fleet_pick(deployment.raiders,index,"raider")
			var pirate_ship := ship(kind, 0, pirate, RAIDERS, index, Celestial.anchor(systems[index],Vector2(-332,170)))
			Outlaws.assign(ships[pirate_ship], Outlaws.PIRATES, ships[pirate_ship].pos)
			if index == 1:
				ships[pirate_ship].job.ambush_only = true
	var free_refinery := port(1, "炉心转运站", Celestial.refinery_anchor(systems[1]), NEUTRAL, 0, 1)
	set_initial_stock(ports[free_refinery], [8,20,50,100,35,110])
	var firm_site := free_refinery
	var possible_branches: Array = []
	for station in ports.values():
		if station.flag < 0 or (Equity.corporate(factions[station.flag].regime) and factions[station.flag].capital == station.id):
			continue
		if station.module == 1 and station.owner==0 and firm_site == free_refinery:
			firm_site = station.id
		if station.module in [0, 1]:
			possible_branches.append(station.id)
	var director := random_person(ports[firm_site].flag, firm_site)
	var firm_id := incorporate(["赫弧工业", "铂穹冶金", "星砧联合"][rng.randi_range(0, 2)], director, firm_site)
	StationEquity.set_operator(self,ports[free_refinery],firm_id)
	var expanded := false
	for station_id in possible_branches:
		if not expanded and ports[station_id].flag != ports[firm_site].flag:
			StationEquity.set_operator(self,ports[station_id],firm_id)
			expanded = true
	for flag in factions:
		Equity.establish(self,flag)
	for first in factions:
		var capital: Dictionary = ports[factions[first].capital]
		var frigate: int = Economy.ship_quote(capital,Hulls.kind_for_reference(deployment.starter)).price
		factions[first].treasury += frigate * int(Industry.RULES.ship_market.initial_frigate_reserve_per_faction)
		for second in factions:
			if first < second:
				set_treaty(first, second, 1 if rng.randf() < 0.12 else 0)
	var avatar: Dictionary = options.get("avatar", {})
	var noble := bool(avatar.get("noble", false))
	var player_gender := clampi(int(avatar.get("gender", 0)), 0, 1)
	var role_raw: Variant = avatar.get("station_master", 0)
	var role_mode := (1 if role_raw else 0) if role_raw is bool else clampi(int(role_raw), 0, 2)
	player = person(str(avatar.get("name", "林遥")), str(avatar.get("house", "远岚")),
		-clampi(int(avatar.get("age", 26)), 18, 65) * 360, NEUTRAL, home, int(avatar.get("origin", 0)),
		int(avatar.get("trait", 0)), avatar.get("look", Portrait.random_look_for_gender(rng, player_gender)), player_gender)
	people[player].wallet = int(Industry.RULES.ship_market.starting_working_capital)
	people[player].noble = noble
	for index in range(2):
		var minor_noble := random_person(NEUTRAL, home)
		people[minor_noble].noble = true
	if role_mode == 0:
		var starter := ship(Hulls.kind_for_reference(deployment.starter), player if noble else 0, player, NEUTRAL, 0, ports[home].pos, home)
		if not noble:
			ships[starter].charter = {"operator":player,"port":home}
	for index in range(5):
		var recruit := random_person(NEUTRAL, home)
		people[recruit].wallet = 500
	ports[home].hulls[Hulls.kind_for_reference(deployment.home_miner)] = 1
	ports[home].hulls[Hulls.kind_for_reference(deployment.home_carrier)] = 1
	Frontier.setup(self)
	core_count = systems.size()
	init_core()
	Outlaws.establish(self)
	Bounties.advance(self)
	PlanetPorts.prepare(self,0)
	for vessel_id: int in opening_traders:
		var order: Dictionary = opening_traders[vessel_id]
		var terminal: Dictionary = ports[order.port]
		var pool: Array = deployment.traders[factions[terminal.flag].style]
		var freighter := freight_hull(pool,terminal,order.captain)
		if freighter >= 0:
			_register_ship(vessel_id,freighter,0,order.captain,terminal.flag,terminal.system,terminal.pos,terminal.id)
			ships[vessel_id].job = {"kind":"贸易"}
	chart(home)
	PlanetPorts.prepare_producers(self)
	if role_mode == 1:
		var old_mgr: int = ports[home].manager
		if old_mgr != 0 and people.has(old_mgr):
			people[old_mgr].employer = 0
		ports[home].owner = player
		ports[home].manager = player
		StationEquity.set_operator(self, ports[home], 0)
		people[player].wallet = maxi(int(people[player].wallet), 2500)
		var trader_cap := random_person(NEUTRAL, home)
		people[trader_cap].employer = player
		var freighter_kind := freight_hull(deployment.traders[0], ports[home], trader_cap)
		if freighter_kind < 0 and not deployment.traders[0].is_empty():
			freighter_kind = Hulls.kind_for_reference(deployment.traders[0][0])
		if freighter_kind >= 0:
			var fid := ship(freighter_kind, player, trader_cap, NEUTRAL, 0, ports[home].pos, home)
			ships[fid].station_owner = home
			ships[fid].job = {"kind": "站属贸易", "home_port": home}
		event("「%s」出任 %s 独立站长（不驾驶飞船），统筹贸易与空间站经营。" % [name_of(player), ports[home].name])
	elif role_mode == 2:
		var target_flag := 0
		for f_id in factions:
			if factions[f_id].alive and systems_owned(f_id).size() >= 1:
				target_flag = int(f_id)
				break
		var owned_ports := systems_owned(target_flag)
		var assigned_port: int = home
		for pid in owned_ports:
			if int(pid) != int(factions[target_flag].capital):
				assigned_port = int(pid)
				break
		if assigned_port == home and not owned_ports.is_empty():
			assigned_port = int(owned_ports[0])
		Politics.join_faction(self, player, target_flag)
		Politics.employ_as_manager(self, player, assigned_port)
		people[player].wallet = maxi(int(people[player].wallet), 1200)
		var has_station_ship := false
		for sh in ships.values():
			if int(sh.get("station_owner", 0)) == assigned_port:
				has_station_ship = true
				break
		if not has_station_ship:
			var sm_cap := random_person(target_flag, assigned_port)
			people[sm_cap].employer = factions[target_flag].leader
			var sm_kind := freight_hull(deployment.traders[factions[target_flag].style], ports[assigned_port], sm_cap)
			if sm_kind < 0 and not deployment.traders[factions[target_flag].style].is_empty():
				sm_kind = Hulls.kind_for_reference(deployment.traders[factions[target_flag].style][0])
			if sm_kind >= 0:
				var sm_sid := ship(sm_kind, factions[target_flag].leader, sm_cap, target_flag, ports[assigned_port].system, ports[assigned_port].pos, assigned_port)
				ships[sm_sid].station_owner = assigned_port
				ships[sm_sid].job = {"kind": "站属贸易", "home_port": assigned_port, "automatic": true, "phase": 0}
		event("「%s」加入 %s 并受雇出任 %s 站长（不驾驶飞船）。" % [name_of(player), flag_name(target_flag), ports[assigned_port].name])
	else:
		event("「%s」在晨曦自由港登记。铁尘矿带出产矿石，炉心转运站收购冶炼原料。" % name_of(player))
	if not noble:
		event("航务局交你一艘通勤工船经营。货物与配装归你，船体可在晨曦自由港船坞买断。")
	return true

func incorporate(label: String, founder: int, site: int, assign_site: bool = true, reserve_cash: int = 0, vessel: Dictionary = {}) -> int:
	if not people.has(founder) or not ports.has(site):
		return 0
	var port_record: Dictionary = ports[site]
	var current: Dictionary = StationEquity.cap_table(self,port_record)
	var group: Dictionary = factions.get(port_record.flag,{})
	var public_charter: bool = group.get("leader",0)==founder and group.get("capital",0)==site and Equity.corporate(group.get("regime",-1))
	var contributed := 0
	if not vessel.is_empty():
		if assign_site or vessel.owner != founder or not Economy.contributable(vessel):
			return 0
		contributed = Hulls.MODELS[vessel.kind].price
	elif assign_site or public_charter:
		if current.total==0:
			contributed = StationEquity.net_assets(port_record)
		elif current.company_units==0 and current.people.get(founder,0)>0:
			contributed = StationEquity.net_assets(port_record)*int(current.people[founder])/maxi(1,int(current.total)-int(current.treasury_units))
	var par := int(Industry.RULES.equity.par_value)
	var paid := 0 if contributed>=par and vessel.is_empty() else mini(maxi(0,int(people[founder].wallet)-reserve_cash),int(Industry.RULES.equity.founder_cash_limit))
	var units := (contributed+paid)/par
	if units<1:
		return 0
	var firm_id := uid()
	firms[firm_id] = {"name":label.strip_edges().left(20),"director":founder,"hq":site,"flag":NEUTRAL,"embargo":NEUTRAL,"revenue":0,
		"issued":units,"treasury_shares":0,"par_value":par,"paid_in_capital":contributed+paid,"ballots":{},"treasury":paid,"operating_profit":0}
	credit(founder,-paid)
	people[founder].shares[firm_id] = units
	if not vessel.is_empty():
		if vessel.captain != founder and people.has(vessel.captain) and people[vessel.captain].employer == founder:
			people[vessel.captain].employer = 0
		vessel.firm = firm_id
		vessel.owner = 0
	if assign_site:
		StationEquity.set_operator(self,ports[site],firm_id)
		if contributed>0 and port_record.has("equity") and port_record.equity.people.has(founder) and int(port_record.equity.company_units)==0:
			port_record.equity.company_units = port_record.equity.people[founder]
			port_record.equity.people.erase(founder)
			port_record.equity.company = firm_id
	return firm_id

func wreck(system: int, pos: Vector2, alloy: int, fuel: int) -> int:
	var wreck_id := uid()
	wrecks[wreck_id] = {"system": system, "pos": pos, "stock": quantities([0, alloy, fuel]), "at": day}
	return wreck_id

func leave_ship_wreck(vessel: Dictionary, tint: Color) -> int:
	var id := wreck(vessel.system,vessel.pos,0,0)
	var record: Dictionary = wrecks[id]
	record.merge({"source_id":vessel.id,"hull_id":Hulls.hull_id(vessel.kind),"heading":vessel.heading,"tint":tint})
	combat_event("ship_breakup",vessel.pos,vessel.system,Vector2.from_angle(vessel.heading),Hulls.CLASSES[Hulls.MODELS[vessel.kind].size].rupture_strength)
	ship_wrecked.emit(id,record)
	return id

func mark_seen(system: int) -> void:
	var region: Dictionary = systems[system]
	Celestial.Orbits.advance_bodies(region,day)
	if not region.seen:
		if region.get("frontier_depot", false):
			var depot := port(system, region.name + " 补给站", Celestial.port_anchor(region), NEUTRAL, 0, Industry.Module.CHEMICAL)
			ports[depot].hulls.fill(0)
			region.depot_port = depot
		region.seen = true
		event("首次抵达 " + region.name)
	PlanetPorts.prepare(self,system)
	for port_id in region.ports:
		ports[port_id].scan = true
	if region.get("wild",false):
		region.ore = mini(region.ore_cap, region.ore + floori((day - region.ore_day) / 30.0) * 14)
		region.ore_day = day
		if region.pirate and not region.spawned:
			region.spawned = true
			var anchor: Vector2 = region.field + Vector2(-320, 210)
			var id := ship(fleet_pick(deployment.raiders,system,"frontier"), 0, 0, RAIDERS, system, anchor)
			region.pirate_patrol = id
			Outlaws.assign(ships[id], Outlaws.PIRATES, anchor)

func oversees(owner: int) -> bool:
	return owner != 0 and (owner == player or (regency == owner and player == regent))

func ship_principal(vessel: Dictionary) -> int:
	return firms.get(vessel.get("firm",0),{}).get("director",vessel.get("owner",0))

func reports_to(person: Dictionary) -> int:
	var vessel: Dictionary = ships.get(person.get("ship",0),{})
	if vessel.has("firm") and vessel.captain == person.id:
		var director := ship_principal(vessel)
		if director != person.id:
			return director
	return person.get("employer",0)

func can_operate(vessel: Dictionary) -> bool:
	return not vessel.is_empty() and (oversees(ship_principal(vessel)) or (player != 0 and (int(vessel.get("captain",0)) == player or vessel.get("charter",{}).get("operator",0) == player)))

func cargo_free(vessel: Dictionary) -> int:
	var free: int = HULL_CARGO[vessel.kind]-int(vessel.get("deal_space",0))
	for amount in vessel.cargo:
		free -= amount
	return maxi(0, free)

func pilot(new_ship_id: int) -> bool:
	var character := active()
	var vessel: Dictionary = ships.get(new_ship_id, {})
	var old := ride()
	var location: int = old.get("dock", character.get("loc", 0))
	if vessel.is_empty() or location == 0 or vessel.dock != location or not can_operate(vessel):
		return false
	if vessel.captain not in [0, player]:
		var other: Dictionary = people[vessel.captain]
		other.ship = 0
		other.loc = location
	if not old.is_empty() and old.captain == player:
		old.captain = 0
	Economy.clear_assignments(self,vessel)
	vessel.captain = player
	character.ship = new_ship_id
	character.loc = location
	return true

func disembark(person_id: int = 0) -> bool:
	var pid := player if person_id == 0 else person_id
	var character: Dictionary = people.get(pid, {})
	if character.is_empty() or character.ship == 0:
		return false
	var vessel: Dictionary = ships.get(character.ship, {})
	if not vessel.is_empty():
		if vessel.dock == 0:
			return false
		if int(vessel.captain) == pid:
			vessel.captain = 0
		character.loc = vessel.dock
	character.ship = 0
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
	vessel.battle.erase("system_charges")
	vessel.battle.system_cd=0.0
	vessel.battle.system_time=0.0
	vessel.battle.shield = false
	vessel.battle.vent = false
	vessel.battle.motion = Vector2.ZERO
	if vessel.captain != 0:
		people[vessel.captain].loc = port_id
	if vessel.captain == player:
		if station.has("planet_index"):
			Celestial.survey(self,vessel)
		chart(port_id)
		if not station.get("landing_only",false):
			Society.offer(self, "on_dock_regular_port" if is_regular(station) else "on_dock_wild_port",
				{"port": port_id, "port_name": station.name, "manager": station.manager, "manager_name": name_of(station.manager)})
	return true

func is_regular(station: Dictionary) -> bool:
	return not station.get("landing_only",false) and station.build == 0 and (not systems[station.system].get("wild", false) or station.pop >= 120)

func depart(vessel: Dictionary) -> void:
	var prev_dock: int = vessel.dock
	vessel.dock = 0
	var origin: Dictionary = ports.get(prev_dock, {})
	if not origin.is_empty():
		vessel.pos = StationGeometry.departure(origin, vessel.kind)
		vessel.heading = Vector2(origin.pos).angle_to_point(vessel.pos)
	if vessel.captain != 0:
		people[vessel.captain].loc = 0
		if vessel.captain == player:
			Society.prune_pending(self)
			if prev_dock != 0:
				var wing := 0
				for other in ships.values():
					if other.id != vessel.id and other.dock == prev_dock and oversees(other.owner) and other.captain not in [0, player]:
						if other.job.get("kind", "") == "护航" or other.get("fleet_role", "") in ["ATTACK", "INTERCEPT", "BOMBARD", "DEFEND"]:
							if other.get("commander_id", vessel.id) == vessel.id:
								other.dock = 0
								people[other.captain].loc = 0
								other.system = vessel.system
								other.pos = StationGeometry.departure(origin, other.kind, wing)
								other.heading = vessel.heading
								wing += 1

func credit(person_id: int, amount: int, asset: Dictionary = {}, category: String = "") -> void:
	if person_id != 0 and people.has(person_id):
		people[person_id].wallet += amount
		if not asset.is_empty():
			Finances.record(self,person_id,asset,category,amount)

func tick(days: int = 1, first_day_motion: Dictionary = {}) -> void:
	for step in range(days):
		if succession or attention:
			break
		day += 1
		Finances.expire(self)
		DiplomaticTrade.daily(self)
		EquityOrders.daily(self)
		ShareExchange.daily(self)
		Capital.audit(self)
		Capital.daily(self)
		Celestial.Orbits.advance(self)
		Operations.daily(self)
		Crises.daily(self,first_day_motion if step == 0 else {})
		Economy.population_day(self,first_day_motion if step == 0 else {})
		Politics.npc_autonomous_step(self)
		if day % 6 == 0:
			Outlaws.advance(self)
			Bounties.advance(self)
			Economy.advance(self)
			Politics.military(self)
			var current_port: int = active().get("loc",0)
			if current_port != 0:
				market_updated.emit(current_port, -1, false)
		if day % 30 == 0:
			Politics.advance(self)
			Society.advance(self)
		Dividends.monthly(self)
		if day % 90 == 0:
			for wreck_id in wrecks.keys():
				if day - wrecks[wreck_id].at > 360:
					wrecks.erase(wreck_id)

func destruction(ship_id: int, killer: int = 0) -> void:
	if not ships.has(ship_id):
		return
	DiplomaticTrade.release_for(self,0,ship_id)
	var vessel: Dictionary = ships[ship_id]
	Economy.release_reservation(self, vessel)
	var killed: int = vessel.captain
	var killer_flag: int = people.get(killer, {}).get("flag", -1) if killer != 0 else -1
	if killer_flag >= 0:
		WarPeace.record_kill(self, vessel, killer_flag)
	if killed != 0 and killed == player and before_death.is_valid():
		before_death.call()
	var model: Dictionary = Hulls.MODELS[vessel.kind]
	var wreck_id := leave_ship_wreck(vessel,Color("8dd5de") if vessel.captain == player else flag_color(vessel.flag))
	var salvage: Array = vessel.cargo.duplicate()
	salvage[Industry.SCRAP] += maxi(4, roundi(float(model.recipe) * 0.45))
	salvage[Industry.Ware.ALLOY] += maxi(1, roundi(float(model.recipe) * 0.18))
	salvage[Industry.Ware.HULL_PARTS] += maxi(1, int(model.size) + roundi(float(model.recipe) * 0.08))
	salvage[Industry.Ware.FUEL] += maxi(2, mini(roundi(float(vessel.get("fuel", 0.0)) * 0.5), 4 + int(model.size) * 4))
	if int(model.size) > 0:
		salvage[Industry.Ware.ORDNANCE] += int(model.size)
	wrecks[wreck_id].stock = salvage
	if killer == player and killed != player:
		Society.offer(self, "on_battle_victory", {"system": vessel.system})
	ships.erase(ship_id)
	if killed != 0:
		people[killed].ship = 0
		Politics.die(self, killed, false)
	if killer != 0 and people.has(killer) and people[killer].alive and vessel.flag == RAIDERS:
		var victor: Dictionary = ships.get(people[killer].ship,{})
		var bounty := maxi(95, roundi(60.0 + float(model.power) * 18.0))
		credit(killer,bounty,victor,"战斗赏金")
		if contracts.get(killer, {}).get("type", -1) == 1:
			credit(killer,180,victor,"作战委托")
			contracts.erase(killer)
			if killer == player:
				event("赏金委托完成：收到 180 信用点。")
	Bounties.on_kill(self, vessel, killer)

func snapshot() -> Dictionary:
	return State.capture(self)

func load_state(data: Dictionary) -> bool:
	var decoded := State.decode(data, WARES.size())
	if decoded.is_empty() or not Society.valid_state(decoded.campaign) or not Equity.valid(decoded) or not EquityOrders.valid(decoded) or not Capital.valid(decoded) or not TradeLaw.valid(decoded) or not ShareExchange.valid(decoded) or not StockPrices.valid(decoded):
		return false
	Society.restore_events(decoded.campaign)
	for key in State.TABLES + State.LISTS + State.NUMBERS + ["succession"]:
		set(key, decoded[key])
	rng.seed = decoded.rng_seed
	rng.state = decoded.rng_state
	for station in ports.values():
		if station.has("planet_index"):
			PlanetPorts.configure_harvest(station,systems[station.system].planets[station.planet_index])
	PlanetPorts.prepare_producers(self)
	refresh_all_tariffs()
	init_core()
	projectiles.clear()
	if has_meta("battle_screens"): remove_meta("battle_screens")
	combat_events.clear()
	combat_serial = 0
	attention = false
	Society.prune_pending(self)
	Outlaws.establish(self)
	Bounties.advance(self)
	return true
