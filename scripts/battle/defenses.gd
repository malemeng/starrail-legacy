extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const GRID := Vector2i(7, 5)
const RESIDUAL := 0.05
const MAX_REDUCTION := 0.85
const EDGE_CELL := 14.0
static var shapes: Dictionary = {}

static func geometry(kind: int) -> Dictionary:
	if shapes.has(kind):
		return shapes[kind]
	var model: Dictionary = Hulls.MODELS[kind]
	var points: PackedVector2Array = model.get("bounds", PackedVector2Array())
	if points.size() < 3:
		var r: float = Hulls.CLASS_RADIUS[model.size]
		points = PackedVector2Array([Vector2(r, 0), Vector2(-r, -r * 0.55), Vector2(-0.7 * r, 0), Vector2(-r, r * 0.55)])
	var envelope := Rect2(points[0], Vector2.ZERO)
	var radius := 0.0
	var center: Vector2 = model.get("shield_center", Vector2.ZERO)
	var shield_radius := 0.0
	for point in points:
		envelope = envelope.expand(point)
		radius = maxf(radius, point.length())
		shield_radius = maxf(shield_radius, center.distance_to(point))
	var module_envelope := radius
	for module in model.get("modules",[]):
		if module.get("offset") is Vector2:
			module_envelope = maxf(module_envelope,Vector2(module.offset).length() + float(module.radius))
	var edges := {}
	var interior := {}
	for i in points.size():
		var a := points[i-1]
		var b := points[i]
		var start := Vector2i((a.min(b) / EDGE_CELL).floor())
		var end := Vector2i((a.max(b) / EDGE_CELL).floor())
		for x in range(start.x, end.x + 1):
			for y in range(start.y, end.y + 1):
				var bin := Vector2i(x,y)
				if not edges.has(bin):
					edges[bin] = []
				edges[bin].append(i)
	var min_cell := Vector2i((envelope.position / EDGE_CELL).floor())
	var max_cell := Vector2i((envelope.end / EDGE_CELL).floor())
	for x in range(min_cell.x, max_cell.x+1):
		for y in range(min_cell.y, max_cell.y+1):
			var bin := Vector2i(x,y)
			if not edges.has(bin) and Geometry2D.is_point_in_polygon((Vector2(bin)+Vector2(0.5,0.5))*EDGE_CELL,points):
				interior[bin] = true
	shield_radius = model.get("shield_radius",shield_radius+4.0)
	shapes[kind] = {"bounds":points, "rect":envelope, "radius":radius, "module_radius":module_envelope,"shield_center":center,
		"shield_radius":shield_radius,"reach":maxf(module_envelope,shield_radius+center.length()),"edges":edges,"inside":interior}
	return shapes[kind]

static func grid_for(vessel: Dictionary) -> PackedFloat32Array:
	var state: Dictionary = vessel.battle
	var grid: PackedFloat32Array = state.get("armor_grid", PackedFloat32Array())
	if grid.size() != GRID.x * GRID.y or not is_equal_approx(state.get("armor_report", state.armor), state.armor):
		grid.resize(GRID.x * GRID.y)
		grid.fill(clampf(state.armor, 0.0, Hulls.COMBAT[vessel.kind].armor) * 4.0 / grid.size())
		state.armor_grid = grid
		state.armor = grid[0] * grid.size() * .25
		state.armor_report = state.armor
	return grid

static func cell_at(vessel: Dictionary, point: Vector2) -> Vector2i:
	var rect: Rect2 = geometry(vessel.kind).rect
	var local := (point - Vector2(vessel.pos)).rotated(-float(vessel.heading))
	var uv := ((local - rect.position) / rect.size).clamp(Vector2.ZERO, Vector2(0.9999, 0.9999))
	return Vector2i(uv * Vector2(GRID))

static func sync_armor(state: Dictionary, grid: PackedFloat32Array) -> void:
	var total := 0.0
	for cell in grid:
		total += cell
	state.armor_grid = grid
	state.armor = total * 0.25
	state.armor_report = state.armor

static func damage_armor(vessel: Dictionary, point: Vector2, damage: float) -> float:
	var grid := grid_for(vessel)
	var cell := cell_at(vessel, point)
	var index := cell.y * GRID.x + cell.x
	var rating: float = Hulls.COMBAT[vessel.kind].armor
	var maximum := rating * 4.0 / grid.size()
	var thickness := rating * maxf(RESIDUAL, grid[index] / maxf(maximum, 0.0001))
	var breach := damage * maxf(1.0 - MAX_REDUCTION, damage / maxf(0.0001, damage + thickness))
	var removed := 0.0
	for y in range(maxi(0, cell.y - 1), mini(GRID.y, cell.y + 2)):
		for x in range(maxi(0, cell.x - 1), mini(GRID.x, cell.x + 2)):
			var at := y * GRID.x + x
			var weight := 1.0 if at == index else (0.35 if x == cell.x or y == cell.y else 0.35 / sqrt(2.0))
			var previous := grid[at]
			grid[at] = maxf(0.0, previous - breach * weight)
			removed += previous - grid[at]
	var state: Dictionary = vessel.battle
	state.armor_grid = grid
	state.armor = maxf(0.0, state.armor - removed*.25)
	state.armor_report = state.armor
	return breach

static func repair_armor(vessel: Dictionary, amount: float) -> void:
	var grid := grid_for(vessel)
	var maximum := float(Hulls.COMBAT[vessel.kind].armor) * 4.0 / grid.size()
	var missing := maxf(0.0, float(Hulls.COMBAT[vessel.kind].armor) - float(vessel.battle.armor))
	if missing <= 0.0001:
		return
	var fraction := minf(1.0, amount / missing)
	for i in grid.size():
		grid[i] = lerpf(grid[i], maximum, fraction)
	sync_armor(vessel.battle, grid)

static func shield_world_center(vessel: Dictionary) -> Vector2:
	return Vector2(vessel.pos) + Vector2(geometry(vessel.kind).shield_center).rotated(vessel.heading)

static func covered(vessel: Dictionary, point: Vector2) -> bool:
	if not vessel.battle.shield or float(vessel.battle.get("shield_arc_live", 0.0)) <= 0:
		return false
	var facing: float = vessel.heading + vessel.battle.get("shield_offset", 0.0)
	var incoming := point - shield_world_center(vessel)
	return absf(angle_difference(facing, incoming.angle())) <= float(vessel.battle.shield_arc_live) * 0.5 + 0.00001

static func shield_contact(vessel: Dictionary, start: Vector2, finish: Vector2) -> Vector2:
	if not vessel.battle.shield:
		return Vector2.INF
	var center := shield_world_center(vessel)
	var ray := finish - start
	var radius: float = geometry(vessel.kind).shield_radius
	var relative := start - center
	var a := ray.length_squared()
	var b := relative.dot(ray)
	var c := relative.length_squared() - radius * radius
	var disc := b * b - a * c
	if a <= 0.000001 or disc < 0.0:
		return Vector2.INF
	var t := (-b - sqrt(disc)) / a
	if t < 0.0 or t > 1.0:
		return Vector2.INF
	var point := start + ray * t
	return point if covered(vessel, point) else Vector2.INF

static func hull_contact(vessel: Dictionary, start: Vector2, finish: Vector2) -> Vector2:
	var shape := geometry(vessel.kind)
	var center: Vector2 = vessel.pos
	var radius: float = shape.radius
	if start.is_equal_approx(finish) or Geometry2D.get_closest_point_to_segment(center, start, finish).distance_squared_to(center) > radius * radius:
		return Vector2.INF
	var points: PackedVector2Array = shape.bounds
	var local_start := (start - center).rotated(-float(vessel.heading))
	var local_finish := (finish - center).rotated(-float(vessel.heading))
	var cell := Vector2i((local_start / EDGE_CELL).floor())
	var dest := Vector2i((local_finish / EDGE_CELL).floor())
	if shape.inside.has(cell) or (shape.edges.has(cell) and Geometry2D.is_point_in_polygon(local_start, points)):
		return start
	var best := INF
	var nearest := Vector2.INF
	var indices: Array
	if cell == dest:
		indices = shape.edges.get(cell, [])
	elif local_start.distance_squared_to(local_finish) > EDGE_CELL * EDGE_CELL * 16:
		indices = range(points.size())
	else:
		var first := cell.min(dest)
		var last := cell.max(dest)
		for x in range(first.x,last.x+1):
			for y in range(first.y,last.y+1):
				indices.append_array(shape.edges.get(Vector2i(x,y), []))
	for i: int in indices:
		var candidate: Variant = Geometry2D.segment_intersects_segment(local_start, local_finish, points[i-1], points[i])
		if candidate != null:
			var distance := local_start.distance_squared_to(candidate)
			if distance < best:
				best = distance
				nearest = candidate
	if not nearest.is_finite():
		return Vector2.INF
	return center + nearest.rotated(vessel.heading)

static func module_contact(vessel: Dictionary, start: Vector2, finish: Vector2) -> Dictionary:
	var modules: Array = Hulls.MODELS[vessel.kind].get("modules",[])
	if modules.is_empty():
		return {}
	var a := (start - Vector2(vessel.pos)).rotated(-float(vessel.heading))
	var b := (finish - Vector2(vessel.pos)).rotated(-float(vessel.heading))
	var best := INF
	var selected := {}
	for part in modules:
		if not part.get("offset") is Vector2 or vessel.battle.get("module_integrity",{}).get(part.mount,{}).get("hp",part.hp) <= 0.0:
			continue
		var offset: Vector2 = part.offset
		if Geometry2D.get_closest_point_to_segment(offset,a,b).distance_squared_to(offset) > float(part.radius)*float(part.radius):
			continue
		var polygon: PackedVector2Array = part.bounds
		var local := a-offset
		var point := Vector2.INF
		if Geometry2D.is_point_in_polygon(local,polygon):
			point = a
		else:
			var near := INF
			for i in polygon.size():
				var hit: Variant = Geometry2D.segment_intersects_segment(local,b-offset,polygon[i-1],polygon[i])
				if hit != null and local.distance_squared_to(hit) < near:
					near = local.distance_squared_to(hit)
					point = Vector2(hit)+offset
		if point.is_finite() and a.distance_squared_to(point) < best:
			best = a.distance_squared_to(point)
			selected = {"module":part,"point":start if point == a else Vector2(vessel.pos)+point.rotated(vessel.heading)}
	return selected
