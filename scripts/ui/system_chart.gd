extends RefCounted

const Celestial = preload("res://celestial.gd")
const TEXT := Color("c9d9e3")
const TEAL := Color("72dfdf")
const GOLD := Color("f0bc74")
const LAND := Color("a8c7a0")
const SKY := Color("83afd5")
const DARK := Color("091721")

static func bounds(world, region: Dictionary, ship_pos: Vector2) -> Rect2:
	var frame := Celestial.system_bounds(region).expand(ship_pos).expand(region.field).expand(Celestial.gravity_point(region))
	for id: int in region.ports:
		frame = frame.expand(world.ports[id].pos)
	if region.has("outlaw_base"):
		frame = frame.expand(region.outlaw_base.pos)
	return frame

static func entry(kind: String, id: int, point: Vector2, name: String, label: String, color: Color) -> Dictionary:
	return {"kind":kind,"id":id,"pos":point,"name":name,"label":label,"color":color}

static func markers(view, world, region: Dictionary, vessel: Dictionary) -> Array:
	var list: Array = []
	if not vessel.is_empty():
		list.append(entry("ship",vessel.id,vessel.pos,world.HULLS[vessel.kind],"当前舰船",TEAL))
	for id: int in region.ports:
		var port: Dictionary = world.ports[id]
		if not port.has("planet_index"):
			list.append(entry("port",id,port.pos,port.name,port.name,GOLD))
	var sun: Dictionary = region.sun
	var primary := entry("star",0,sun.pos,sun.name,"主星 · "+Celestial.STARS[sun.type][0],Color(Celestial.STARS[sun.type][1]))
	primary.disk_radius = sun.radius*view.zoom
	list.append(primary)
	if region.has("companion"):
		var companion: Dictionary = region.companion
		var secondary := entry("companion",0,companion.pos,"伴星","伴星 · "+Celestial.STARS[companion.type][0],Color(Celestial.STARS[companion.type][1]))
		secondary.disk_radius = companion.radius*view.zoom
		list.append(secondary)
	for i in region.planets.size():
		var planet: Dictionary = region.planets[i]
		var label: String = planet.name.rsplit(" ",true,1)[-1]+" · "+Celestial.PLANETS[planet.type][0]
		var body := entry("planet",i,planet.pos,planet.name,label,SKY)
		body.disk_radius = planet.radius*view.zoom
		list.append(body)
	list.append(entry("gravity",0,Celestial.gravity_point(region),"恒星引力点","跃迁点",TEAL))
	list.append(entry("field",0,region.field,"小行星矿带","矿带",GOLD))
	if region.has("outlaw_base"):
		var base: Dictionary = region.outlaw_base
		var org: Dictionary = world.Outlaws.groups[base.group]
		list.append(entry("outlaw",0,base.pos,org.base_name,org.base_name,Color(org.color)))
	for id: int in region.ports:
		var port: Dictionary = world.ports[id]
		if port.has("planet_index"):
			var inhabited: bool = not port.get("landing_only",false)
			var site := entry("port",id,port.pos,port.name,"地表港" if inhabited else "",LAND)
			site.surface = true
			site.inhabited = inhabited
			list.append(site)
	var occupied: Array[Rect2] = []
	var visible := Rect2(Vector2(6,36),Vector2(view.size)-Vector2(12,61))
	for marker: Dictionary in list:
		var original: Vector2 = view.screen(marker.pos)
		marker.anchor = original
		marker.at = original
		if not visible.has_point(original):
			continue
		var offset := Vector2.ZERO
		for i in 49:
			if i > 0:
				var ring := ceili(float(i)/8.0)
				offset = Vector2.from_angle(-PI/2.0+(i-1)%8*PI/4.0)*(ring*15.0)
			var candidate := Rect2(original+offset-Vector2.ONE*7.0,Vector2.ONE*14)
			if visible.encloses(candidate) and not overlaps(candidate,occupied):
				marker.at = candidate.get_center()
				occupied.append(candidate)
				break
	var font: Font = view.get_theme_default_font()
	for marker: Dictionary in list:
		var active: bool = selected(marker,view.chart_selected)
		var caption: String = marker.name if active else marker.label
		marker.label_box = Rect2()
		if caption.is_empty() or not visible.has_point(marker.at):
			continue
		var dims := Vector2(ceilf(font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x)+8,19)
		var at: Vector2 = marker.at
		for shift in [Vector2(10,-9),Vector2(10,-27),Vector2(10,9),Vector2(-10-dims.x,-9),Vector2(-10-dims.x,-29),
				Vector2(-10-dims.x,10),Vector2(-dims.x/2,-34),Vector2(-dims.x/2,19),Vector2(20,31),Vector2(-dims.x-15,36),Vector2(18,-47)]:
			var box := Rect2(at+Vector2(shift),dims)
			if visible.encloses(box) and not overlaps(box,occupied):
				marker.label_box = box
				marker.caption = caption
				occupied.append(box.grow(1.5))
				break
	return list

static func overlaps(rect: Rect2, occupied: Array[Rect2]) -> bool:
	for other in occupied:
		if rect.intersects(other):
			return true
	return false

static func selected(marker: Dictionary, active: Dictionary) -> bool:
	return marker.kind == active.get("kind","") and marker.id == active.get("id",-1)

static func pick(markers_at: Array, cursor: Vector2) -> Dictionary:
	var nearest := {}
	var range_sq := 10.0*10.0
	for marker: Dictionary in markers_at:
		var distance := cursor.distance_squared_to(marker.at)
		if distance <= range_sq:
			nearest = marker
			range_sq = distance
	if not nearest.is_empty():
		return nearest
	for marker: Dictionary in markers_at:
		if Rect2(marker.label_box).has_point(cursor):
			return marker
	for marker: Dictionary in markers_at:
		if marker.has("disk_radius") and cursor.distance_to(marker.anchor) <= marker.disk_radius:
			return marker
	return {}

static func draw(view, region: Dictionary, vessel: Dictionary, listed: Array) -> void:
	var sun: Vector2 = view.screen(region.sun.pos)
	var bounds_px := Rect2(Vector2.ZERO,view.size)
	for planet: Dictionary in region.planets:
		var at: Vector2 = view.screen(planet.pos)
		var orbit := at.distance_to(sun)
		if orbit >= 5.0 and orbit <= view.size.length()*2.0:
			view.draw_arc(sun,orbit,0,TAU,144,Color("536884",0.42),1,true)
		var influence: float = Celestial.gravity_radius(region,planet)*view.zoom
		if bounds_px.grow(influence).has_point(at) and influence > 2.0:
			view.draw_arc(at,influence,0,TAU,48,Color(TEAL,0.36),1,true)
	if not vessel.is_empty() and view.game.waypoint_live:
		view.draw_dashed_line(view.screen(vessel.pos),view.screen(view.game.waypoint),GOLD,1.5,5,true)
	for marker: Dictionary in listed:
		var at: Vector2 = marker.at
		if not bounds_px.grow(8).has_point(at):
			continue
		var color: Color = marker.color
		if at.distance_squared_to(marker.anchor) > 4:
			view.draw_line(marker.anchor,at,Color(color,0.70),1.0,true)
		match marker.kind:
			"ship":
				view.draw_colored_polygon(PackedVector2Array([at+Vector2(0,-7),at+Vector2(6,5),at,at+Vector2(-6,5)]),color)
			"port":
				if marker.has("surface"):
					var diamond := PackedVector2Array([at+Vector2(0,-4),at+Vector2(4,0),at+Vector2(0,4),at+Vector2(-4,0),at+Vector2(0,-4)])
					if marker.inhabited:
						diamond.resize(4)
						view.draw_colored_polygon(diamond,color)
					else:
						view.draw_polyline(diamond,color,1.0,true)
				else:
					view.draw_rect(Rect2(at-Vector2(4,4),Vector2(8,8)),DARK)
					view.draw_rect(Rect2(at-Vector2(4,4),Vector2(8,8)),color,false,1.6)
			"gravity":
				view.draw_arc(at,5,0,TAU,16,color,1.5,true)
				view.draw_line(at-Vector2(8,0),at+Vector2(8,0),color)
			"field":
				for dot: Vector2 in [Vector2(-3,1),Vector2(2,-3),Vector2(4,3)]:
					view.draw_circle(at+dot,1.7,color)
			"outlaw":
				view.draw_arc(at,5,0,TAU,6,color,2,true)
			_:
				view.draw_arc(at,3.5,0,TAU,16,Color(color,0.86),1.2,true)
		if selected(marker,view.chart_selected):
			view.draw_arc(at,9,0,TAU,20,Color.WHITE,1.6,true)
		var box: Rect2 = marker.label_box
		if box.has_area():
			view.draw_rect(box,Color(DARK,0.82))
			view.ink(box.position+Vector2(4,14),marker.caption,color,12)
