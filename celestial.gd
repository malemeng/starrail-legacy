extends RefCounted

const JUMP_RANGE := 72.0
const BEACON_RANGE := 30.0
const Fields = preload("res://data/campaign/starfields.json")
const Scale = preload("res://data/campaign/stellar_scale.json")
const Orbits = preload("res://scripts/campaign/orbital_dynamics.gd")
const Industry = preload("res://scripts/economy/industry.gd")
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

# Net marketable water and staple food per 1,000 residents in a six-day harvest.
const SURFACE_YIELDS := {
	2: Vector2i(72,0),     # Ice
	3: Vector2i(100,150),  # Temperate
	4: Vector2i(150,90),   # Oceans and fisheries
	5: Vector2i(70,45),    # Tundra
	16: Vector2i(115,135), # Tropical
	17: Vector2i(65,155),  # Grassland
	19: Vector2i(48,0),    # Dark ice
}

static func core_chart(seed_text: String, count: int) -> Array[Vector2]:
	var random := RandomNumberGenerator.new()
	random.seed = hash(seed_text + ":chart")
	var points: Array[Vector2] = [Vector2.ZERO]
	while points.size() < count:
		var parent := points[random.randi_range(0, points.size()-1)]
		var spacing: Array = Scale.data.core_beacon_spacing
		var trial := parent + Vector2.from_angle(random.randf_range(0, TAU)) * random.randf_range(spacing[0],spacing[1])
		if points.all(func(other: Vector2): return other.distance_to(trial) >= Scale.data.min_beacon_spacing):
			points.append(trial)
	return points

static func anchor(region: Dictionary, point: Vector2) -> Vector2:
	return (point * Vector2(region.get("handedness", 1), 1)).rotated(region.get("layout_angle", 0.0)) * region.get("layout_scale", 1.0)

static func profile(region: Dictionary) -> Dictionary:
	return Fields.data[int(region.get("starfield", 0))]

static func port_anchor(region: Dictionary) -> Vector2:
	return anchor(region, Vector2(110,60))

static func refinery_anchor(region: Dictionary) -> Vector2:
	var offset: Array = Scale.data.refinery_offset
	return anchor(region, Vector2(offset[0],offset[1]))

static func survey_point(body: Dictionary, from: Vector2) -> Vector2:
	return body.pos + Vector2(body.pos).direction_to(from) * (body.radius + 25.0)

static func system_bounds(region: Dictionary) -> Rect2:
	var area := Rect2(Vector2.ZERO,Vector2.ZERO)
	var bodies: Array = [region.sun] + region.planets
	if region.has("companion"):
		bodies.append(region.companion)
	for body: Dictionary in bodies:
		var extent := Vector2.ONE * float(body.radius) * (1.65 if body.get("rings",false) else 1.12)
		area = area.expand(body.pos-extent).expand(body.pos+extent)
	return area

static func populate(region: Dictionary, seed: String) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = hash("%s:%s:celestial-2" % [seed,region.name])
	region.sky_seed = random.randi()
	region.starfield = random.randi_range(0, Fields.data.size()-1)
	region.layout_angle = random.randf_range(0, TAU)
	region.handedness = -1 if random.randf() < 0.5 else 1
	region.layout_scale = random.randf_range(0.88,1.18)
	var spec := profile(region)
	var star_class: int = spec.stars[random.randi_range(0, spec.stars.size()-1)]
	var sun_radius := roundi(STARS[star_class][2] * Scale.data.star_radius_factor * random.randf_range(0.9,1.1))
	var solar_axis := anchor(region,Vector2(random.randf_range(350,445),random.randf_range(-505,-430))).normalized()
	var altitude := random.randf_range(2100,2700)
	region.sun = {"type":star_class,"name":region.name+" 主星","radius":sun_radius,"jump_altitude":altitude,
		"pos":solar_axis * (sun_radius + altitude + random.randf_range(310,480))}
	if random.randf() < 0.29:
		var companion_type := random.randi_range(0,STARS.size()-1)
		var second_radius := roundi(STARS[companion_type][2] * Scale.data.star_radius_factor * random.randf_range(0.7,1.0))
		region.companion = {"type":companion_type,"pos":Vector2(region.sun.pos) + solar_axis.rotated(random.randf_range(-1.2,1.2)) * (sun_radius + second_radius + random.randf_range(6000,14000)), "radius":second_radius}
	region.field = anchor(region,Vector2(random.randf_range(-340,-240),random.randf_range(-185,-110)))
	var reserve := random.randi_range(int(spec.ore[0]), int(spec.ore[1]))
	region.ore = reserve
	if region.get("wild",false):
		region.ore_cap = reserve
	region.belt_angle = random.randf_range(0,TAU)
	region.rock_count = random.randi_range(int(spec.rocks[0]), int(spec.rocks[1]))
	region.belt_width = random.randf_range(0.18,0.85)
	region.planets = []
	var planet_count := random.randi_range(1,7)
	var outer_orbit := float(sun_radius)
	var clearance := float(Scale.data.surface_clearance)
	var exclusions := [port_anchor(region),refinery_anchor(region),gravity_point(region),region.field]
	for index in range(planet_count):
		var kind: int = spec.planets[random.randi_range(0,spec.planets.size()-1)] if random.randf() < 0.78 else random.randi_range(0,PLANETS.size()-1)
		var radius_range: Array = Scale.data.giant_radius if kind >= 20 else Scale.data.rock_radius
		var radius := random.randi_range(radius_range[0],radius_range[1])
		var rings := kind == 20 or (kind >= 21 and random.randf() < 0.44)
		var extent := radius * (1.6 if rings else 1.0)
		var orbit := outer_orbit + extent + random.randf_range(clearance,clearance*2.8)
		var heading := -solar_axis.rotated(random.randf_range(-0.45,0.45)) if index == 0 else Vector2.from_angle(random.randf_range(0,TAU))
		var point: Vector2 = region.sun.pos + heading * orbit
		while exclusions.any(func(p: Vector2): return p.distance_to(point) < extent + clearance) or (region.has("companion") and point.distance_to(region.companion.pos) < extent + region.companion.radius + clearance):
			heading = heading.rotated(0.63)
			orbit += 180
			point = region.sun.pos + heading * orbit
		outer_orbit = orbit + extent
		region.planets.append({"type":kind,"name":"%s %s" % [region.name,["Ⅰ","Ⅱ","Ⅲ","Ⅳ","Ⅴ","Ⅵ","Ⅶ"][index]], "pos":point,
			"radius":radius,"surface_seed":random.randi(),"rings":rings,"surveyed":false})
	Orbits.initialize(region,0)
	region.chart_bounds = system_bounds(region)

static func survey(world, vessel: Dictionary) -> bool:
	var region: Dictionary = world.systems[vessel.system]
	for planet in region.planets:
		if planet.surveyed or vessel.pos.distance_to(planet.pos) > planet.radius + 52.0:
			continue
		planet.surveyed = true
		var spec: Array = PLANETS[planet.type]
		world.credit(world.player,18 + roundi(spec[2] * 28) + int(spec[3]),vessel,"勘测酬金")
		world.event("完成勘测：%s · %s，适居度 %d%%，矿藏评级 %d。" % [planet.name,spec[0],roundi(spec[2]*100),spec[3]])
		return true
	return false

## A Hill estimate in game units. The near-surface floor accounts for compressed planet/stellar distances.
static func gravity_radius(region: Dictionary, planet: Dictionary) -> float:
	var radius := float(planet.radius)
	var density: float = Orbits.Rules.data.giant_mu_density if planet.get("type",0) >= 20 else Orbits.Rules.data.rock_mu_density
	var mu := float(planet.get("mu",density*radius*radius*radius))
	var solar_mu := float(region.get("gravity_mu",Orbits.star_mu(region.sun)))
	var distance: float = Vector2(planet.pos).distance_to(region.sun.pos)
	var hill := distance * pow(mu / (3.0*solar_mu),1.0/3.0)
	return clampf(hill,radius*Industry.CONSTRUCTION.minimum_gravity_radii,radius*Industry.CONSTRUCTION.maximum_gravity_radii)

static func construction_point(region: Dictionary, planet: Dictionary, from: Vector2) -> Vector2:
	var direction := Vector2(planet.pos).direction_to(from)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var lower: float = planet.radius + Industry.CONSTRUCTION.minimum_altitude
	var outer := gravity_radius(region,planet)
	var core_clearance := Orbits.Geometry.berth_for_core({"module":Industry.Module.YARD,"capital_yard":true},Vector2.ZERO,0.0).length()
	var safe_distance := maxf(lower,minf(lerpf(lower,outer,0.5),outer-core_clearance-1.0))
	return planet.pos + direction * safe_distance

static func build_orbit_point(region: Dictionary, planet_index: int, from: Vector2) -> Vector2:
	return construction_point(region,region.planets[planet_index],from)

static func orbit_at(region: Dictionary, point: Vector2) -> int:
	var closest := -1
	var proximity := INF
	for i in region.planets.size():
		var planet: Dictionary = region.planets[i]
		var gap := point.distance_to(planet.pos)
		if gap < planet.radius + Industry.CONSTRUCTION.minimum_altitude:
			return -1
		var fraction := gap / gravity_radius(region,planet)
		if fraction <= 1.0 and fraction < proximity:
			closest = i
			proximity = fraction
	return closest

static func gravity_point(region: Dictionary) -> Vector2:
	var star: Dictionary = region.sun
	var direction := -Vector2(star.pos).normalized()
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	return Vector2(star.pos) + direction * (star.radius + star.get("jump_altitude",128.0))

static func at_gravity_point(region: Dictionary, position: Vector2) -> bool:
	return position.distance_squared_to(gravity_point(region)) <= JUMP_RANGE * JUMP_RANGE

static func gravity_approach(region: Dictionary, ship_id: int) -> Vector2:
	var angle := float(ship_id) * 2.3999632
	return gravity_point(region) + Vector2.from_angle(angle) * (JUMP_RANGE * 0.62)

static func gravity_arrival(world, system_id: int, ship_id: int) -> Vector2:
	var center := gravity_point(world.systems[system_id])
	var best := center
	var best_clearance := -1.0
	var base_angle := float(ship_id) * 2.3999632
	for step in range(24):
		var radius := 46.0 + float(step) * 5.0
		var candidate := center + Vector2.from_angle(base_angle + float(step) * 2.3999632) * radius
		var min_dist := INF
		for other in world.ships.values():
			if other.id == ship_id or other.system != system_id or other.dock != 0 or other.layer or other.hp <= 0.0:
				continue
			min_dist = minf(min_dist, candidate.distance_to(other.pos))
		if min_dist >= 44.0:
			return candidate
		if min_dist > best_clearance:
			best_clearance = min_dist
			best = candidate
	return best
