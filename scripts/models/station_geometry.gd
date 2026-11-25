extends RefCounted

const Profiles = preload("res://data/economy/station_layouts.json")
const Defenses = preload("res://scripts/battle/defenses.gd")
const Design = preload("res://scripts/models/station_design.gd")
const MAX_REACH := 1900.0
const BERTH_RANGE := 75.0
static var layout_cache: Dictionary = {}

static func make(berth: Vector2, heading: float, span: float, skin: int) -> Dictionary:
	var size := Vector2(span, span * 0.9)
	var outward := Vector2.from_angle(heading)
	var angle := heading - PI * 0.5
	var center := berth - outward * (size.y * 0.5 + 24.0)
	var bounds := Transform2D(angle, center) * Rect2(-size * 0.5, size)
	return {"center": center, "berth": berth, "angle": angle, "outward": outward, "span": span,
		"size": size, "bounds": bounds, "skin": skin,"solids":[Rect2(-size*0.5,size)]}

static func layout(station: Dictionary, cells_override: Array = []) -> Dictionary:
	var heading := float(station.get("berth_heading", float(absi(hash([station.system, station.id])) % 360) * PI / 180.0))
	var outward := Vector2.from_angle(heading)
	var angle := heading - PI * 0.5
	var geometry := local_geometry(station,cells_override).duplicate()
	var origin: Vector2 = station.pos - outward * geometry.berth_offset
	var transform := Transform2D(angle,origin)
	geometry.angle = angle
	geometry.outward = outward
	geometry.berth = station.pos
	geometry.design_origin = origin
	geometry.center = transform * -Vector2(geometry.core_pos)
	geometry.bounds = transform * Rect2(-Vector2(geometry.core_pos) - Vector2(geometry.size)*0.5,geometry.size)
	return geometry

static func grid_step(station: Dictionary) -> float:
	var span: float = Profiles.data.capital_yard if station.get("capital_yard",false) else Profiles.data.modules[station.module].span
	return span / float(Profiles.data.span_per_step)

static func berth_for_core(station: Dictionary, core_position: Vector2, heading: float) -> Vector2:
	var offset := float(Profiles.data.core_size[1]) * grid_step(station) * 0.5 + 24.0
	return core_position + Vector2.from_angle(heading) * offset

static func local_geometry(station: Dictionary, cells_override: Array) -> Dictionary:
	var spec: Dictionary = Profiles.data.modules[station.module]
	var step := grid_step(station)
	var cells := Design.cells(station) if cells_override.is_empty() else cells_override
	var kinds := Design.kinds(station)
	var shape := [station.module,step,cells,kinds,station.get("build",0)>0,station.get("expansion",0)>0]
	if layout_cache.has(shape):
		return layout_cache[shape]
	var core_size: Array = Profiles.data.core_size
	var core := Vector2(core_size[0],core_size[1]) * step
	var parts := [{"kind":-1,"cell":Design.CORE,"center":Vector2.ZERO,"size":core,"pending":false}]
	var occupied := {Design.CORE:true}
	var box := Rect2(-core*0.5,core)
	for i in mini(cells.size(),kinds.size()):
		var cell: Vector2i = cells[i]
		var footprint: Array = Profiles.data.modules[kinds[i]].footprint
		var dimensions := Vector2(footprint[0],footprint[1]) * step
		var at := Vector2(cell) * step
		var pending: bool = station.get("build",0) > 0 or (station.get("expansion",0) > 0 and i == kinds.size()-1)
		parts.append({"kind":kinds[i],"cell":cell,"center":at,"size":dimensions,"pending":pending})
		occupied[cell] = true
		box = box.merge(Rect2(at-dimensions*0.5,dimensions))
	var midpoint := box.get_center()
	var sections := []
	for part: Dictionary in parts:
		part.center -= midpoint
		sections.append(Rect2(part.center-part.size*0.5,part.size))
	var links := []
	var width := float(Profiles.data.link_width) * step
	for cell: Vector2i in occupied:
		for offset: Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
			if occupied.has(cell + offset):
				var a := Vector2(cell) * step - midpoint
				var b := Vector2(cell + offset) * step - midpoint
				links.append(PackedVector2Array([a,b]))
				var section := Rect2(a,b-a).grow(width*0.5)
				sections.append(section)
	var result := {"step":step,"signature":hash(shape),"span":maxf(box.size.x,box.size.y),"size":box.size,"skin":int(spec.skin),
		"core_pos":-midpoint,"berth_offset":core.y*0.5+24.0,"parts":parts,"links":links,"link_width":width,"solids":sections}
	if layout_cache.size() >= 512:
		layout_cache.clear()
	layout_cache[shape.duplicate(true)] = result
	return result

static func outpost(base: Dictionary) -> Dictionary:
	var spec: Dictionary = Profiles.data.outposts[base.group]
	var heading := float(base.get("berth_heading",float(absi(hash([base.group, base.pos])) % 360)*PI/180.0))
	return make(base.pos, heading, float(spec.span), int(spec.skin))

static func docking_range(kind: int) -> float:
	return BERTH_RANGE + float(Defenses.geometry(kind).radius)

static func intersects_body(geom: Dictionary, body: Dictionary) -> bool:
	var local := (Vector2(body.pos) - Vector2(geom.center)).rotated(-geom.angle)
	var radius_sq := float(body.radius) * float(body.radius)
	for section: Rect2 in geom.solids:
		if local.distance_squared_to(local.clamp(section.position,section.end)) <= radius_sq:
			return true
	return false

static func protected_sections(geom: Dictionary, pose: Transform2D) -> Array:
	var result: Array = geom.solids.duplicate()
	var berth: Vector2 = pose.affine_inverse() * geom.berth
	result.append(Rect2(berth - Vector2(75,0),Vector2(150,150)))
	return result

static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	if not Rect2(a.bounds).grow(180.0).intersects(Rect2(b.bounds).grow(180.0),true):
		return false
	var a_pose := Transform2D(a.angle,a.center)
	var b_pose := Transform2D(b.angle,b.center)
	var a_sections := protected_sections(a,a_pose)
	var b_sections := protected_sections(b,b_pose)
	var relative := a_pose.affine_inverse() * b_pose
	var ax := relative.x.abs()
	var ay := relative.y.abs()
	for first: Rect2 in a_sections:
		var half := first.size * 0.5
		for second: Rect2 in b_sections:
			var other_half := second.size * 0.5
			var delta := relative * second.get_center() - first.get_center()
			# Separating-axis test in both stations' local frames.
			var extent := half + ax * other_half.x + ay * other_half.y
			var other_extent := other_half + Vector2(ax.dot(half),ay.dot(half))
			var other_delta := Vector2(delta.dot(relative.x),delta.dot(relative.y))
			if absf(delta.x) <= extent.x and absf(delta.y) <= extent.y and absf(other_delta.x) <= other_extent.x and absf(other_delta.y) <= other_extent.y:
				return true
	return false

static func departure(station: Dictionary, kind: int, wing: int = -1) -> Vector2:
	var radius := float(Defenses.geometry(kind).radius)
	var heading := float(station.get("berth_heading", float(absi(hash([station.system, station.id])) % 360) * PI / 180.0))
	var outward := Vector2.from_angle(heading)
	if wing < 0:
		return station.pos + outward * (radius + 35.0)
	var rank := floori(wing / 2.0) + 1
	var side := -1.0 if wing % 2 == 0 else 1.0
	return station.pos + outward * (radius + 70.0 + rank * 35.0) + outward.orthogonal() * side * (rank * 98.0 + radius)
