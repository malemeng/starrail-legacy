extends RefCounted

enum Size { FRIGATE, DESTROYER, CRUISER, CAPITAL }
const CLASS_NAMES := ["护卫舰级", "驱逐舰级", "巡洋舰级", "主力舰级"]
const CLASS_SPRITE := [0.83, 1.00, 1.26, 1.55]
const CLASS_RADIUS := [15, 20, 26, 33]
const DAMAGE_NAMES := ["动能", "高爆", "能量", "破片"]
const SHIELD_MULT := [2.0, 0.5, 1.0, 0.25]
const ARMOR_MULT := [0.5, 2.0, 1.0, 0.25]
const SYSTEM_NAMES := {"boost":"高能加速", "phase":"相位闪现", "burst":"火控超频", "repair":"维修无人机"}
const BASE_WEAPONS := {
	"pulse": {"name":"脉冲激光","type":2,"damage":16.0,"op":4,"flux":8.0,"cool":0.26,"speed":510.0,"range":350.0,"mount":1},
	"rail": {"name":"轨道炮","type":0,"damage":22.0,"op":6,"flux":12.0,"cool":0.60,"speed":570.0,"range":420.0,"mount":2},
	"howitzer": {"name":"裂甲炮","type":1,"damage":30.0,"op":7,"flux":14.0,"cool":0.86,"speed":380.0,"range":345.0,"mount":2},
	"missile": {"name":"追踪导弹","type":1,"damage":38.0,"op":8,"flux":7.0,"cool":2.30,"speed":250.0,"range":490.0,"mount":2,"missile":true},
	"pd": {"name":"守门点防炮","type":3,"damage":8.0,"op":3,"flux":3.0,"cool":0.34,"speed":620.0,"range":118.0,"mount":1,"pd":true},
	"lance": {"name":"长弧主炮","type":2,"damage":58.0,"op":12,"flux":27.0,"cool":1.08,"speed":665.0,"range":520.0,"mount":3},
}
const SLOTS := {
	"nose": {"offset":Vector2(23,0),"facing":0.0,"arc":20.0,"type":"固定","size":2},
	"light": {"offset":Vector2(21,0),"facing":0.0,"arc":27.0,"type":"固定","size":1},
	"spinal": {"offset":Vector2(25,0),"facing":0.0,"arc":16.0,"type":"固定","size":3},
	"port": {"offset":Vector2(6,-11),"facing":-22.0,"arc":106.0,"type":"炮塔","size":2},
	"starboard": {"offset":Vector2(6,11),"facing":22.0,"arc":106.0,"type":"炮塔","size":2},
	"dorsal": {"offset":Vector2(-9,-4),"facing":0.0,"arc":360.0,"type":"炮塔","size":2},
	"aft": {"offset":Vector2(-18,0),"facing":180.0,"arc":360.0,"type":"炮塔","size":1},
}
const BASE_COMBAT := [
	{"op":20,"capacity":100.0,"dissipation":24.0,"armor":32.0,"system":"boost","slots":["light","port","aft"],"stock":["pulse","missile","pd"],"groups":[1,2,3]},
	{"op":18,"capacity":92.0,"dissipation":21.0,"armor":41.0,"system":"boost","slots":["light","aft"],"stock":["pulse","pd"],"groups":[1,3]},
	{"op":24,"capacity":118.0,"dissipation":28.0,"armor":63.0,"system":"burst","slots":["nose","port","aft"],"stock":["rail","howitzer","pd"],"groups":[1,2,3]},
	{"op":16,"capacity":86.0,"dissipation":20.0,"armor":46.0,"system":"repair","slots":["light","aft"],"stock":["pulse","pd"],"groups":[1,3]},
	{"op":24,"capacity":119.0,"dissipation":25.0,"armor":56.0,"system":"phase","slots":["nose","starboard","aft"],"stock":["pulse","howitzer","pd"],"groups":[1,2,3]},
	{"op":38,"capacity":190.0,"dissipation":39.0,"armor":138.0,"system":"burst","slots":["spinal","port","starboard","aft"],"stock":["lance","rail","missile","pd"],"groups":[1,2,2,3]},
	{"op":29,"capacity":149.0,"dissipation":30.0,"armor":102.0,"system":"repair","slots":["nose","port","aft"],"stock":["rail","pulse","pd"],"groups":[1,2,3]},
	{"op":58,"capacity":300.0,"dissipation":51.0,"armor":240.0,"system":"burst","slots":["spinal","port","starboard","dorsal","aft"],"stock":["lance","rail","howitzer","missile","pd"],"groups":[1,1,2,2,3]},
	{"op":35,"capacity":195.0,"dissipation":38.0,"armor":165.0,"system":"repair","slots":["nose","port","starboard","aft"],"stock":["rail","pulse","pulse","pd"],"groups":[1,2,2,3]},
]

static func stock_fit(kind: int) -> Dictionary:
	var spec: Dictionary = COMBAT[kind]
	return {"weapons":spec.stock.duplicate(), "groups":spec.groups.duplicate(), "auto":[false,false,false], "caps":0, "vents":0}

static func fitting_cost(kind: int, fit: Dictionary) -> int:
	var spec: Dictionary = COMBAT[kind]
	var list: Variant = fit.get("weapons")
	var groups: Variant = fit.get("groups")
	var automatic: Variant = fit.get("auto")
	if not list is Array or not groups is Array or not automatic is Array or list.size() != spec.slots.size() or groups.size() != list.size() or automatic.size() != 3:
		return -1
	for enabled in automatic:
		if not enabled is bool:
			return -1
	var caps: Variant = fit.get("caps", 0)
	var vents: Variant = fit.get("vents", 0)
	if not caps is int or not vents is int or caps not in range(13) or vents not in range(13):
		return -1
	var cost: int = caps + vents
	for index in range(list.size()):
		if not groups[index] is int or groups[index] not in [1,2,3] or not list[index] is String:
			return -1
		var key: String = list[index]
		if key.is_empty():
			continue
		if not WEAPONS.has(key) or WEAPONS[key].mount > SLOTS[spec.slots[index]].size:
			return -1
		cost += WEAPONS[key].op
	return cost if cost <= spec.op else -1

static func battle_state(kind: int) -> Dictionary:
	var cool: Array = []
	cool.resize(COMBAT[kind].slots.size())
	cool.fill(0.0)
	return {"soft_flux":0.0,"hard_flux":0.0,"armor":COMBAT[kind].armor,"shield":false,"vent":false,"overload":0.0,
		"group":1,"cooldowns":cool,"system_cd":0.0,"system_time":0.0,"order":0,"focus":0,"retired":false,"ai":"巡航","motion":Vector2.ZERO}

static func capacity(vessel: Dictionary) -> float:
	return COMBAT[vessel.kind].capacity + vessel.fit.caps * 5.0

static func dissipation(vessel: Dictionary) -> float:
	return COMBAT[vessel.kind].dissipation + vessel.fit.vents * 1.35
const BASE_MODELS := [
	{"name":"信标级轻艇","size":Size.FRIGATE,"role":"侦察 / 通勤","hp":100,"cargo":36,"price":240,"recipe":18,"speed":1.00,"fuel":0.78,"power":17,"reload":0.19,"mine":12,"salvage":0,"paint":"91b7c7"},
	{"name":"渡鸦级货船","size":Size.DESTROYER,"role":"物流 / 跑商","hp":145,"cargo":105,"price":510,"recipe":28,"speed":0.82,"fuel":0.95,"power":12,"reload":0.27,"mine":12,"salvage":0,"paint":"cc9a62"},
	{"name":"锋针级护卫舰","size":Size.FRIGATE,"role":"近距护航","hp":185,"cargo":52,"price":760,"recipe":42,"speed":0.93,"fuel":1.10,"power":25,"reload":0.17,"mine":12,"salvage":0,"paint":"ad7565"},
	{"name":"石吻级采矿船","size":Size.FRIGATE,"role":"浅层采掘","hp":112,"cargo":62,"price":590,"recipe":32,"speed":0.79,"fuel":0.88,"power":11,"reload":0.27,"mine":24,"salvage":0,"paint":"d8ad66"},
	{"name":"钩灯级回收船","size":Size.DESTROYER,"role":"残骸回收","hp":160,"cargo":92,"price":820,"recipe":46,"speed":0.85,"fuel":1.11,"power":15,"reload":0.24,"mine":13,"salvage":6,"paint":"72b8ab"},
	{"name":"戍星级巡洋舰","size":Size.CRUISER,"role":"装甲压制","hp":410,"cargo":82,"price":2450,"recipe":78,"speed":0.71,"fuel":1.48,"power":49,"reload":0.32,"mine":12,"salvage":0,"paint":"bc7271"},
	{"name":"井脊级采冶船","size":Size.CRUISER,"role":"深层采掘 / 大宗货运","hp":265,"cargo":164,"price":1890,"recipe":65,"speed":0.64,"fuel":1.35,"power":19,"reload":0.32,"mine":38,"salvage":0,"paint":"bda075"},
	{"name":"长夜级战列舰","size":Size.CAPITAL,"role":"重装火力","hp":720,"cargo":128,"price":5200,"recipe":128,"speed":0.54,"fuel":2.24,"power":86,"reload":0.45,"mine":12,"salvage":0,"paint":"a98fb6"},
	{"name":"远岸级超货船","size":Size.CAPITAL,"role":"远洋大宗物流","hp":480,"cargo":340,"price":4080,"recipe":104,"speed":0.60,"fuel":1.67,"power":25,"reload":0.37,"mine":16,"salvage":0,"paint":"7cacb8"},
]
const DESIGN_LINES := ["白帆","赤枝","潮痕","石弧","青栈","银梭","铁鹞","玄塔","新炬","裂湾","环砧"]
const DESIGN_ROLES := ["快反护航","边境物流","远征采冶","重型火力"]
const WEAPON_SERIES := ["斥候","边防","伏击","近卫","远射","快装","重型","增压","低耗","破阵","余烬","穿云","舰队"]
static var WEAPONS: Dictionary = weapon_catalog()
static var MODELS: Array = hull_catalog()
static var COMBAT: Array = combat_catalog()

static func weapon_catalog() -> Dictionary:
	var result := BASE_WEAPONS.duplicate(true)
	var types := ["pulse","rail","howitzer","missile","pd","lance"]
	for family in range(types.size()):
		var base_key: String = types[family]
		var base: Dictionary = BASE_WEAPONS[base_key]
		for variant in range(WEAPON_SERIES.size()):
			var data := base.duplicate(true)
			var tuning: float = [0.66,0.80,1.20,0.78,1.05,0.73,1.62,1.42,0.85,1.30,1.12,1.18,1.48][variant]
			data.name = WEAPON_SERIES[variant] + "·" + base.name
			data.damage = snappedf(base.damage*tuning + family*0.3,0.1)
			data.range = roundf(base.range * [0.96,1.05,0.82,0.88,1.43,0.92,0.88,1.09,0.98,1.19,1.12,1.33,1.25][variant])
			data.cool = base.cool * [0.68,0.89,1.15,0.67,1.25,0.63,1.54,0.91,1.14,1.32,0.94,1.19,1.28][variant]
			data.flux = roundf(base.flux * [0.63,0.77,1.08,0.93,1.21,0.84,1.53,1.6,0.57,1.14,1.07,1.3,1.42][variant])
			data.speed = roundf(base.speed * (0.84 + (variant % 5) * 0.085))
			data.op = maxi(1,base.op + [-2,-1,0,0,2,1,3,3,2,2,1,2,4][variant])
			data.burst = 3 if variant == 7 else (2 if variant in [2,5,10] else 1)
			data.spread = 0.10 if data.burst > 1 else 0.0
			result["%s_%02d" % [base_key,variant]] = data
	return result

static func hull_catalog() -> Array:
	var result := BASE_MODELS.duplicate(true)
	for line in range(DESIGN_LINES.size()):
		for role in range(DESIGN_ROLES.size()):
			var size := (line + role) % 4
			var train: float = [0.83,1.15,1.64,2.62][size]
			var data := {"name":DESIGN_LINES[line]+"级"+DESIGN_ROLES[role]+"舰","size":size,"role":DESIGN_ROLES[role],
				"hp":roundi((92 + line * 6 + role * 28)*train),"cargo":roundi((30 + line*2 + [7,66,51,0][role])*train),
				"price":roundi((355 + line*42 + role * 84)*train),"recipe":roundi((25 + line*2 + role*6)*train),
				"speed":maxf(0.48,1.14 - size*0.13 - role*0.04 - line*0.008),"fuel":0.76+size*0.31+role*0.04+line*0.02,
				"power":roundi((15 + role*6+line*0.8)*train),"reload":0.22 + size*0.04,"mine":14+size*5+([0,0,15,0][role]),
				"salvage":([0,3,6,0][role]),"paint":["8bbbc0","c58b63","a6a476","ab8299"][role],
				"silhouette":line,"role_id":role}
			result.append(data)
	return result

static func combat_catalog() -> Array:
	var result := BASE_COMBAT.duplicate(true)
	for index in range(BASE_MODELS.size(), MODELS.size()):
		var model: Dictionary = MODELS[index]
		var role: int = model.role_id
		var size: int = model.size
		var slots := ["light" if size == 0 and role != 3 else ("spinal" if size >= 2 and role == 3 else "nose"), "aft"]
		var shot: String = ["pulse","pulse","pulse","rail"][role]
		if slots[0] == "spinal":
			shot = "lance"
		var stock := [shot,"pd"]
		var groups := [1,3]
		if size >= 1 or role in [0,3]:
			slots.append("port")
			stock.append("howitzer" if role == 3 else "missile")
			groups.append(2)
		if size >= 2:
			slots.append("starboard")
			stock.append("rail" if role != 1 else "pulse")
			groups.append(1)
		if size == 3:
			slots.append("dorsal")
			stock.append("missile" if role == 3 else "pd")
			groups.append(2 if role == 3 else 3)
		result.append({"op":23+size*13+role*2,"capacity":88.0+size*62.0+model.silhouette*3.0,"dissipation":19.0+size*9.0+role*2.0,
			"armor":float(roundi(model.hp*(0.29+role*0.035))),"system":["boost","phase","repair","burst"][role],"slots":slots,"stock":stock,"groups":groups})
	return result

static func crew_limits(kind: int) -> Vector2i:
	var model: Dictionary = MODELS[kind]
	var minimum: int = [3,7,15,30][model.size] + int(model.get("role_id",0))
	return Vector2i(minimum, minimum*2+2)

static func crew_efficiency(vessel: Dictionary) -> float:
	return clampf(float(vessel.get("crew",crew_limits(vessel.kind).x)) / crew_limits(vessel.kind).x,0.25,1.0)

static func station_limit(station: Dictionary) -> int:
	if station.get("capital_yard", false):
		return Size.CAPITAL
	if station.module == 2 or (station.get("extension", -1) == 2 and station.get("expansion", 0) == 0):
		return Size.CRUISER
	return Size.DESTROYER

static func model_limit(station: Dictionary, model: int) -> bool:
	return int(MODELS[model].size) <= station_limit(station)

static func inventory(available: bool) -> Array:
	var stock: Array = []
	stock.resize(MODELS.size())
	stock.fill(0)
	if available:
		stock[0] = 1
		stock[1] = 1
	return stock
