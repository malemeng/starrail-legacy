extends RefCounted

const JUMP_RANGE := 72.0
const BEACON_RANGE := 30.0
const STARS := [
	["红矮星","d88768",105],["橙矮星","edab6e",127],["黄矮星","f4d08c",145],
	["蓝白主序星","8db9ed",181],["红巨星","dc7158",209],["白矮星","c6d9ed",72],
]
const PLANETS := [
	["荒漠行星","b17d58",0.15,22],["熔岩行星","b85047",0.03,36],["冰封行星","8db2cc",0.08,15],["温带行星","6b9473",0.91,11],
	["海洋行星","469aba",0.78,8],["苔原行星","758e91",0.46,16],["沙丘行星","cc9d64",0.28,19],["岩质行星","8e8583",0.12,27],
	["金属行星","a7a9b5",0.02,38],["碳质行星","5a5968",0.07,29],["高压毒云行星","a3a660",0.03,24],["硫雾行星","d5ad68",0.02,28],
	["盐壳行星","a8c0c5",0.23,16],["晶簇行星","a190d1",0.09,33],["裂谷行星","8d6b76",0.12,31],["潮锁行星","aa847d",0.31,20],
	["热带行星","77a77d",0.88,12],["草原行星","a5aa68",0.86,13],["辐照废土","c5715f",0.04,30],["暗冰行星","5c7293",0.04,24],
	["环带气态巨行星","738fb9",0.0,0],["风暴气态巨行星","b2816d",0.0,0],["蓝色冰巨星","5396bc",0.0,0],["氨云气态巨行星","a79eac",0.0,0],
]

static func populate(region: Dictionary, seed: String) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = hash("%s:%s:celestial-1" % [seed,region.name])
	var star_class := random.randi_range(0,STARS.size()-1)
	region.sun = {"type":star_class,"name":region.name+" 主星","pos":Vector2(405,-477),"radius":STARS[star_class][2]}
	region.planets = []
	var planet_count := random.randi_range(2,5)
	for index in range(planet_count):
		var kind := random.randi_range(0,PLANETS.size()-1)
		if region.name == "曙光锚地" and index == 0:
			kind = 20
		var angle := 0.48 + index * TAU / planet_count + random.randf_range(-0.15,0.15)
		var distance := random.randf_range(480,760)
		var point := Vector2(cos(angle)*distance, sin(angle)*distance*0.83)
		region.planets.append({"type":kind,"name":"蓝弧" if region.name == "曙光锚地" and index == 0 else "%s %s" % [region.name,["Ⅰ","Ⅱ","Ⅲ","Ⅳ","Ⅴ"][index]],
			"pos":point,"radius":random.randi_range(38,63) + (30 if kind >= 20 else 0),"surveyed":false})

static func survey(world, vessel: Dictionary) -> bool:
	var region: Dictionary = world.systems[vessel.system]
	for planet in region.planets:
		if planet.surveyed or vessel.pos.distance_to(planet.pos) > planet.radius + 52.0:
			continue
		planet.surveyed = true
		var spec: Array = PLANETS[planet.type]
		world.credit(world.player, 18 + roundi(spec[2] * 28) + int(spec[3]))
		world.event("完成勘测：%s · %s，适居度 %d%%，矿藏评级 %d。" % [planet.name,spec[0],roundi(spec[2]*100),spec[3]])
		return true
	return false

static func orbit_at(region: Dictionary, point: Vector2) -> int:
	var index := 0
	for planet in region.planets:
		var gap: float = point.distance_to(planet.pos)
		if gap >= planet.radius + 58.0 and gap <= planet.radius + 152.0:
			return index
		index += 1
	return -1

static func gravity_point(region: Dictionary) -> Vector2:
	var star: Dictionary = region.sun
	var direction := -Vector2(star.pos).normalized()
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	return Vector2(star.pos) + direction * (star.radius + 128.0)

static func at_gravity_point(region: Dictionary, position: Vector2) -> bool:
	return position.distance_squared_to(gravity_point(region)) <= JUMP_RANGE * JUMP_RANGE
