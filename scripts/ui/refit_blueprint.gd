extends Control

signal selected(slot: int)
signal inspected(slot: int)

const Hulls = preload("res://hull_catalog.gd")
const Pixels = preload("res://art/pixel_art.gd")
const WeaponArt = preload("res://art/weapon_mounts.gd")
const FamilyCatalog = preload("res://data/fleet/mount_families.json")
const SIZES := ["","小 S","中 M","大 L"]

var kind := 0
var active := 0
var hovered := -1
var texture: Texture2D
var loadout: Array = []

func _ready() -> void:
	mouse_exited.connect(set_hover.bind(-1))

func configure(model: int, slot: int, weapons: Array = []) -> void:
	kind = model
	loadout = weapons
	active = slot
	set_hover(-1)
	texture = Pixels.ship_texture(kind, Color(Hulls.MODELS[kind].paint))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

static func mount_label(mount: Dictionary) -> String:
	return "%s · %s · %s" % [family_name(mount.family), SIZES[int(mount.size)], mount.type]

static func family_name(family: String) -> String:
	return FamilyCatalog.data[family].label

static func family_color(family: String) -> Color:
	return Color(FamilyCatalog.data[family].color)

func magnification() -> float:
	var pixel_scale: float = Hulls.MODELS[kind].sprite_scale
	return minf((size.x-32.0)/texture.get_width(),(size.y-32.0)/texture.get_height()) / pixel_scale

func center_point() -> Vector2:
	var model: Dictionary = Hulls.MODELS[kind]
	return size*0.5 + (Vector2(model.sprite_center)-texture.get_size()*0.5) * float(model.sprite_scale)*magnification()

func mount_point(index: int) -> Vector2:
	return center_point() + Vector2(Hulls.slot_spec(kind,index).offset)*magnification()

func hit_slot(point: Vector2) -> int:
	var nearest := -1
	var distance := 12.0
	for i in Hulls.MODELS[kind].mounts.size():
		var near := point.distance_to(mount_point(i))
		if near < distance:
			distance = near
			nearest = i
	return nearest

func set_hover(index: int) -> void:
	if hovered == index:
		return
	hovered = index
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if index >= 0 else Control.CURSOR_ARROW
	if index >= 0:
		var mount := Hulls.slot_spec(kind,index)
		tooltip_text = "[%d] %s · 射界 %.0f°" % [index+1,mount_label(mount),mount.arc]
		if index < loadout.size() and not str(loadout[index]).is_empty():
			tooltip_text += " · "+str(Hulls.WEAPONS[loadout[index]].name)
	else:
		tooltip_text = ""
	inspected.emit(index if index >= 0 else active)
	queue_redraw()

func draw_sector(index: int, tone: Color) -> void:
	var mount := Hulls.slot_spec(kind,index)
	var origin := mount_point(index)
	var angle := deg_to_rad(float(mount.facing))
	var half_arc := deg_to_rad(float(mount.arc))*0.5
	var radius := minf(size.x,size.y)*0.30
	var sector := PackedVector2Array([origin])
	for j in 49:
		sector.append(origin + Vector2.from_angle(angle-half_arc+2.0*half_arc*j/48.0)*radius)
	if half_arc >= PI-0.001:
		draw_circle(origin,radius,Color(tone,0.16))
		draw_arc(origin,radius,0,TAU,49,tone,1.5,true)
	elif half_arc > 0.001:
		draw_colored_polygon(sector,Color(tone,0.16))
		draw_arc(origin,radius,angle-half_arc,angle+half_arc,49,tone,1.5,true)
		draw_line(origin,sector[1],tone)
		draw_line(origin,sector[-1],tone)
	draw_line(origin,origin+Vector2.from_angle(angle)*radius,Color(tone,0.7))

func _draw() -> void:
	if texture == null or minf(size.x,size.y) <= 32.0:
		return
	draw_rect(Rect2(Vector2.ZERO,size),Color("#0d1d29"))
	var gap := 16.0*magnification()
	while gap < 16.0:
		gap *= 2.0
	while gap > 34.0:
		gap *= 0.5
	var origin := center_point()
	var x := fposmod(origin.x,gap)
	while x < size.x:
		draw_line(Vector2(x,0),Vector2(x,size.y),Color("#203544"))
		x += gap
	var y := fposmod(origin.y,gap)
	while y < size.y:
		draw_line(Vector2(0,y),Vector2(size.x,y),Color("#203544"))
		y += gap
	var extent := texture.get_size()*magnification()*float(Hulls.MODELS[kind].sprite_scale)
	draw_texture_rect(texture,Rect2((size-extent)*0.5,extent),false)
	var mounts: Array = Hulls.MODELS[kind].mounts
	if active in range(mounts.size()):
		draw_sector(active,Color("#f4c36e"))
	if hovered >= 0 and hovered != active:
		draw_sector(hovered,Color("#c1f3ff"))
	for i in mounts.size():
		var point := mount_point(i)
		var radius := 2.2+float(mounts[i].size)*1.4
		draw_circle(point,radius+1.6,Color("#10202c"),true,-1,true)
		if i < loadout.size() and not str(loadout[i]).is_empty():
			var weapon := WeaponArt.profile(loadout[i])
			var plan := Transform2D(0,Vector2.ONE*magnification(),0,origin)
			var pose := WeaponArt.pose(mounts[i],weapon,deg_to_rad(mounts[i].facing),0)
			WeaponArt.draw_mount(self,plan*pose,weapon.family,Color.WHITE)
		else:
			draw_arc(point,radius,0,TAU,18,family_color(mounts[i].family),1.5,true)
		if i == active or i == hovered:
			draw_arc(point,radius+3.0,0,TAU,22,Color.WHITE,1.5,true)
	draw_string(get_theme_default_font(),Vector2(7,size.y-6),"每格 %.0f 航行单位" % (gap/magnification()),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#9cb2bf"))

func _gui_input(event: InputEvent) -> void:
	if texture == null:
		return
	if event is InputEventMouseMotion:
		set_hover(hit_slot(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index := hit_slot(event.position)
		if index >= 0:
			accept_event()
			selected.emit(index)
