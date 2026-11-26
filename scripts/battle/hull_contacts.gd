extends RefCounted

const Battle = preload("res://combat.gd")
const Hulls = preload("res://hull_catalog.gd")
const CLEARANCE := 0.02
const MAX_PASSES := 24

# Use a convex solid for the main hull and one for each surviving external module.
# The projectile solver keeps using the detailed silhouette and shield arcs.
static func parts(kind: int) -> Array:
	var geometry := Battle.Defenses.geometry(kind)
	if not geometry.has("solids"):
		var main := ConvexPolygonShape2D.new()
		main.points = Geometry2D.convex_hull(geometry.bounds)
		var solid_bounds: Rect2 = geometry.rect
		var solids := [{"shape":main,"mount":"","hp":0}]
		for module: Dictionary in Hulls.MODELS[kind].get("modules",[]):
			if module.bounds.size() < 3: continue
			var shape := ConvexPolygonShape2D.new()
			shape.points = Geometry2D.convex_hull(Transform2D(0,module.offset)*PackedVector2Array(module.bounds))
			for vertex in shape.points: solid_bounds = solid_bounds.expand(vertex)
			solids.append({"shape":shape,"mount":module.mount,"hp":module.hp})
		geometry.solids = solids
		geometry.solid_bounds = solid_bounds
	return geometry.solids

static func solid(ship: Dictionary, system: int) -> bool:
	return not ship.has("defense_port") and Battle.available(ship,system) and not Battle.phased(ship)

static func capture(world, system: int) -> Dictionary:
	var previous := {}
	for ship: Dictionary in world.ships.values():
		if solid(ship,system): previous[ship.id] = Transform2D(ship.heading,ship.pos)
	return previous

static func active_parts(ship: Dictionary) -> Array:
	var shapes := parts(ship.kind)
	var integrity: Dictionary = ship.battle.get("module_integrity",{})
	if shapes.size() == 1 or integrity.is_empty(): return shapes
	return shapes.filter(func(part): return part.mount == "" or integrity.get(part.mount,{}).get("hp",part.hp) > 0)

# Godot returns paired points on the two shapes. Their difference is the
# surface normal scaled by the distance needed to separate that contact.
static func penetration(a: Transform2D, shapes_a: Array, b: Transform2D, shapes_b: Array) -> Vector2:
	var separation := Vector2.ZERO
	for left: Dictionary in shapes_a:
		for right: Dictionary in shapes_b:
			var hits: PackedVector2Array = left.shape.collide_and_get_contacts(a,right.shape,b)
			for i in range(0,hits.size(),2):
				var push := hits[i]-hits[i+1]
				if push.length_squared() > separation.length_squared(): separation = push
	return separation

static func fits(world, system: int, kind: int, at: Transform2D) -> bool:
	var radius := float(Battle.Defenses.geometry(kind).module_radius)
	for ship: Dictionary in world.ships.values():
		if not solid(ship,system): continue
		var reach: float = radius+Battle.Defenses.geometry(ship.kind).module_radius
		if at.origin.distance_squared_to(ship.pos) >= reach*reach: continue
		if not penetration(at,parts(kind),Transform2D(ship.heading,ship.pos),active_parts(ship)).is_zero_approx():
			return false
	return true

class Body:
	var ship: Dictionary
	var shapes: Array
	var radius: float
	var local_bounds: Rect2
	var bounds: Rect2
	var sort_x: float
	var last_contact := -1
	var mass: float
	var start: Transform2D
	var end_heading: float
	var travel: Vector2
	var limit: Vector2
	var pose: Transform2D

	func _init(vessel: Dictionary, previous: Dictionary, arena: Vector2, solid_shapes: Array):
		ship = vessel
		shapes = solid_shapes
		var geometry := Battle.Defenses.geometry(ship.kind)
		radius = geometry.module_radius
		local_bounds = geometry.solid_bounds
		mass = maxf(1.0,Hulls.MODELS[ship.kind].mass)
		end_heading = ship.heading
		pose = Transform2D(end_heading,ship.pos)
		start = pose if ship.battle.erase("contact_blink") else previous.get(ship.id,pose)
		travel = pose.origin-start.origin
		limit = Vector2.INF if arena == Vector2.ZERO else (arena-Vector2.ONE*float(geometry.reach)).max(Vector2.ZERO)

	# A blocked axis cannot absorb its share of a correction. Use the free
	# component to slide along the wall before yielding the remainder to a peer.
	func push_out(direction: Vector2, depth: float) -> float:
		if not limit.is_finite():
			bounds.position += direction*depth
			pose.origin += direction*depth
			return depth
		var before := pose.origin
		var intended := before+direction*depth
		pose.origin = intended.clamp(-limit,limit)
		var remaining := depth-(pose.origin-before).dot(direction)
		if remaining > 0.001:
			var available := direction
			for axis in 2:
				if absf(pose.origin[axis]-intended[axis]) > 0.00001: available[axis] = 0
			if available.length_squared() > 0.0001:
				var shift := (available*remaining/available.length_squared()).limit_length(depth*2)
				pose.origin = (pose.origin+shift).clamp(-limit,limit)
		bounds.position += pose.origin-before
		return (pose.origin-before).dot(direction)

static func separate(a: Body, b: Body) -> bool:
	var reach := a.radius+b.radius
	if a.pose.origin.distance_squared_to(b.pose.origin) >= reach*reach: return false
	var push := penetration(a.pose,a.shapes,b.pose,b.shapes)
	var depth := push.length()
	if depth < 0.001: return false
	var normal := push/depth
	var share_a := b.mass/(a.mass+b.mass)
	var share_b := 1.0-share_a
	# At an exhibition wall, give the unblocked ship the remaining displacement.
	depth += CLEARANCE
	var moved_a := a.push_out(-normal,depth*share_a)
	var moved_b := b.push_out(normal,depth-moved_a)
	var remaining := depth-moved_a-moved_b
	if remaining > 0.001: a.push_out(-normal,remaining)
	var closing := (Vector2(a.ship.battle.motion)-Vector2(b.ship.battle.motion)).dot(normal)
	if closing > 0:
		a.ship.battle.motion -= normal*closing*share_a
		b.ship.battle.motion += normal*closing*share_b
	# The remaining substeps must also slide, including directly positioned
	# civilian and waypoint traffic which may have no stored combat velocity.
	var planned := (a.travel-b.travel).dot(normal)
	if planned > 0:
		a.travel -= normal*planned*share_a
		b.travel += normal*planned*share_b
	return true

static func left_edge_first(a: Body, b: Body) -> bool:
	return a.sort_x < b.sort_x

static func resolve(world, system: int, previous: Dictionary, arena := Vector2.ZERO) -> void:
	var bodies: Array[Body] = []
	var max_motion := 0.0
	var spacing := 12.0
	for ship: Dictionary in world.ships.values():
		if not solid(ship,system): continue
		var body := Body.new(ship,previous,arena,active_parts(ship))
		var bounds: Rect2 = Battle.Defenses.geometry(ship.kind).rect
		spacing = minf(spacing,maxf(1,minf(bounds.size.x,bounds.size.y)*0.35))
		var rotation := absf(angle_difference(body.start.get_rotation(),body.end_heading))
		max_motion = maxf(max_motion,body.travel.length()+rotation*body.radius)
		body.pose = body.start
		bodies.append(body)
	if bodies.size() < 2: return
	var steps := maxi(1,ceili(max_motion/spacing))
	for step in steps:
		var fraction := float(step+1)/steps
		for body: Body in bodies:
			var at := (body.pose.origin+body.travel/steps).clamp(-body.limit,body.limit)
			body.pose = Transform2D(lerp_angle(body.start.get_rotation(),body.end_heading,fraction),at)
			body.bounds = body.pose * body.local_bounds
			body.last_contact = -1
		for pass_index in MAX_PASSES:
			var touched := false
			for body: Body in bodies: body.sort_x = body.bounds.position.x
			bodies.sort_custom(left_edge_first)
			for i in bodies.size():
				var a := bodies[i]
				for j in range(i+1,bodies.size()):
					var b := bodies[j]
					if b.sort_x > a.bounds.end.x: break
					# Only a body moved by this or the previous pass can add a contact.
					if maxi(a.last_contact,b.last_contact) < pass_index-1 or not a.bounds.intersects(b.bounds): continue
					if separate(a,b):
						a.last_contact = pass_index
						b.last_contact = pass_index
						touched = true
			if not touched: break
	for body: Body in bodies:
		body.ship.pos = body.pose.origin
