extends RefCounted

const Rules = preload("res://data/campaign/orbits.json")
const Geometry = preload("res://scripts/models/station_geometry.gd")

static func star_mu(star: Dictionary) -> float:
	return Rules.data.stellar_mu * pow(float(star.radius) / Rules.data.reference_star_radius, 1.15)

static func initialize(region: Dictionary, day: int) -> void:
	var sun: Dictionary = region.sun
	var mu := star_mu(sun)
	var bodies: Array = region.planets.duplicate()
	var origin: Vector2 = sun.pos
	var direction := float(region.get("handedness",1))
	if region.has("companion"):
		var companion: Dictionary = region.companion
		var outer := float(sun.radius)
		for planet: Dictionary in bodies:
			outer = maxf(outer,origin.distance_to(planet.pos)+planet.radius)
		var offset := Vector2(companion.pos) - origin
		companion.pos = origin + offset.normalized() * maxf(offset.length(),outer * Rules.data.binary_outer_orbit_ratio)
		companion.mu = mu * clampf(pow(float(companion.radius) / sun.radius,1.15),0.12,1.0)
		bodies.append(companion)
	for i in bodies.size():
		var body: Dictionary = bodies[i]
		var radius := float(body.radius)
		var seed_value: int = int(body.get("surface_seed",hash([region.name,i])))
		var roll := float(absi(seed_value) % 1009) / 1008.0
		if not body.has("mu"):
			var density: float = Rules.data.giant_mu_density if body.get("type",0) >= 20 else Rules.data.rock_mu_density
			body.mu = density * radius * radius * radius
		var radius_vector := Vector2(body.pos) - origin
		body.orbital_velocity = Vector2(-radius_vector.y,radius_vector.x).normalized() * direction * sqrt((mu + body.mu)/maxf(radius_vector.length(),1.0))
		body.spin_rate = lerpf(Rules.data.surface_spin_speed[0],Rules.data.surface_spin_speed[1],roll) / radius * (-1.0 if seed_value % 5 == 0 else 1.0)
		body.spin = 0.0
	region.orbit_day = day
	region.gravity_mu = mu
	calculate_acceleration(bodies,origin,mu)

## Heliocentric coordinates. Subtract the acceleration of the primary to keep its origin fixed.
static func calculate_acceleration(bodies: Array, origin: Vector2, primary_mu: float) -> void:
	var acc := PackedVector2Array()
	acc.resize(bodies.size())
	var reflex := Vector2.ZERO
	var soft_sq := float(Rules.data.softening) ** 2
	for i in bodies.size():
		var body: Dictionary = bodies[i]
		var offset := Vector2(body.pos) - origin
		var r2 := offset.length_squared() + soft_sq
		var force := offset / (r2 * sqrt(r2))
		acc[i] -= force * primary_mu
		reflex += force * float(body.mu)
		for j in i:
			var neighbor: Dictionary = bodies[j]
			var pair := Vector2(neighbor.pos) - Vector2(body.pos)
			var gap := pair.length_squared() + soft_sq
			var attraction := pair / (gap * sqrt(gap))
			acc[i] += attraction * float(neighbor.mu)
			acc[j] -= attraction * float(body.mu)
	for i in bodies.size():
		bodies[i].orbital_acceleration = acc[i] - reflex

## The same one-day velocity Verlet steps are used by normal play and fast-forward.
static func advance_bodies(region: Dictionary, day: int) -> void:
	if not region.has("orbit_day"):
		initialize(region,day-1)
	var bodies: Array = region.planets.duplicate()
	if region.has("companion"):
		bodies.append(region.companion)
	for elapsed in range(region.orbit_day,day):
		for body: Dictionary in bodies:
			body.orbital_velocity += Vector2(body.orbital_acceleration) * 0.5
			body.pos += Vector2(body.orbital_velocity)
			body.spin = fposmod(body.spin + body.spin_rate,TAU)
		calculate_acceleration(bodies,region.sun.pos,region.gravity_mu)
		for body: Dictionary in bodies:
			body.orbital_velocity += Vector2(body.orbital_acceleration) * 0.5
	region.orbit_day = day

static func advance_station(station: Dictionary, region: Dictionary, day: int) -> void:
	var parent_index := int(station.get("orbit",-1))
	var parent: Dictionary = region.planets[parent_index] if parent_index in range(region.planets.size()) else region.sun
	var orbit: Dictionary = station.get("orbital_motion",{})
	if orbit.is_empty() or orbit.parent != parent_index:
		var geom := Geometry.outpost(station) if station.has("group") else Geometry.layout(station)
		var center: Vector2 = geom.get("design_origin",geom.center)
		var axis := center - Vector2(parent.pos)
		var radius := maxf(1.0,axis.length())
		var rate := float(region.handedness) * sqrt(float(parent.get("mu",region.gravity_mu)) / (radius*radius*radius))
		var periods: Array = Rules.data.station_spin_days
		var spin := TAU / lerpf(periods[0],periods[1],float(absi(hash(station.get("id",station.get("group","")))) % 100)/99.0)
		# Low orbital berths continuously face their parent, keeping their approach corridor outside the surface.
		if parent_index >= 0:
			spin = rate
		orbit = {"parent":parent_index,"epoch":day-1,"axis":axis,"rate":rate,"heading":Vector2(geom.outward).angle(),"spin":spin,"berth_offset":center.distance_to(geom.berth)}
		station.orbital_motion = orbit
	var duration: int = day - orbit.epoch
	var core := Vector2(parent.pos) + Vector2(orbit.axis).rotated(duration*float(orbit.rate))
	station.berth_heading = wrapf(orbit.heading + duration * orbit.spin,-PI,PI)
	station.pos = core + Vector2.from_angle(station.berth_heading)*float(orbit.berth_offset)

static func advance(world) -> void:
	for region: Dictionary in world.systems:
		if region.get("wild",false) and not region.seen:
			continue
		advance_bodies(region,world.day)
		if region.has("outlaw_base"):
			var base: Dictionary = region.outlaw_base
			advance_station(base,region,world.day)
			for ship_id in base.members:
				if world.ships.has(ship_id):
					world.ships[ship_id].job.anchor = base.pos
		for id in region.ports:
			var port: Dictionary = world.ports[id]
			if port.has("planet_index"):
				var planet: Dictionary = region.planets[port.planet_index]
				port.pos = world.PlanetPorts.point(planet)
				port.berth_heading = world.PlanetPorts.outward(planet).angle()
			else:
				advance_station(port,region,world.day)
	for vessel: Dictionary in world.ships.values():
		if vessel.dock != 0 and world.ports.has(vessel.dock):
			vessel.pos = world.ports[vessel.dock].pos
