extends RefCounted

const P = preload("res://art/pixel_art.gd")
const I = preload("res://scripts/economy/industry.gd")
const INK := Color("14202c")
const SHADOW := Color("30404c")
const METAL := Color("596a73")
const LIGHT := Color("9caab0")
const RUST := Color("a55f44")
const HAZARD := Color("e2ad58")
const GLASS := Color("a9edee")
const PANEL := Color("365577")
const ICON_SIZE := 80
const CACHE_LIMIT := 36
static var modules: Dictionary = {}
static var module_images: Dictionary = {}
static var layouts: Dictionary = {}

static func plate(im: Image, box: Rect2i, paint: Color = METAL) -> void:
	im.fill_rect(box, INK)
	im.fill_rect(box.grow(-1), paint.darkened(0.24))
	im.fill_rect(Rect2i(box.position + Vector2i(1,1), box.size - Vector2i(4,4)), paint)
	im.fill_rect(Rect2i(box.position + Vector2i(2,1),Vector2i(box.size.x-5,1)), paint.lightened(0.38))

static func pipe(im: Image, a: Vector2i, b: Vector2i, width: int = 5) -> void:
	P.line(im,a,b,INK,width)
	P.line(im,a+Vector2i.ONE,b+Vector2i.ONE,METAL,width-2)
	P.line(im,a+Vector2i.ONE,b+Vector2i.ONE,LIGHT)

static func tank(im: Image, at: Vector2, radius: int, tint: Color) -> void:
	P.ellipse(im,at,Vector2.ONE * radius,INK)
	P.ellipse(im,at-Vector2.ONE,Vector2.ONE * (radius-2),tint.darkened(0.30))
	P.ellipse(im,at-Vector2(2,3),Vector2.ONE * (radius-4),tint)
	P.ellipse(im,at-Vector2(radius*0.28,radius*0.35),Vector2(radius*0.38,radius*0.16),tint.lightened(0.45))

static func sprite(kind: int, tint: Color) -> Image:
	var im := P.blank(ICON_SIZE,ICON_SIZE)
	var stripe := tint.lightened(0.12)
	match kind:
		-1:
			# Four pressure-lock arms and a southern approach collar.
			plate(im,Rect2i(5,30,70,18))
			plate(im,Rect2i(31,4,18,72))
			P.polygon(im,[[17,27],[27,15],[52,15],[64,28],[64,49],[52,61],[28,61],[17,49]],INK)
			P.polygon(im,[[20,28],[29,18],[51,18],[60,28],[60,48],[50,57],[30,57],[20,47]],METAL)
			tank(im,Vector2(40,36),15,stripe.darkened(0.18))
			plate(im,Rect2i(28,60,24,10),stripe)
			for x in [30,36,42,48]:
				P.rect(im,x,65,2,2,GLASS)
		I.Module.MINE:
			# An open, triangulated derrick with three exposed drill heads.
			for x in [7,36,65]:
				pipe(im,Vector2i(37,19),Vector2i(x,52))
				pipe(im,Vector2i(x,47),Vector2i(37,35),3)
				plate(im,Rect2i(x-3,47,12,15),RUST)
				P.polygon(im,[[x-2,62],[x+8,62],[x+3,74]],LIGHT)
			plate(im,Rect2i(26,8,28,27))
			for x in range(30,48,5):
				P.rect(im,x,13,2,12,HAZARD)
		I.Module.REFINERY:
			plate(im,Rect2i(6,43,67,23))
			for column in [[10,16],[27,7],[46,14],[60,25]]:
				var x: int = column[0]
				var y: int = column[1]
				plate(im,Rect2i(x,y,10,49-y),RUST)
				plate(im,Rect2i(x-2,y,14,7),LIGHT)
				P.rect(im,x+1,y+13,8,3,HAZARD)
			for x in [14,33,52]:
				plate(im,Rect2i(x,52,13,9),SHADOW)
		I.Module.YARD:
			plate(im,Rect2i(6,49,68,21))
			for x in [6,60]:
				plate(im,Rect2i(x,8,14,55))
				for y in range(14,46,9):
					plate(im,Rect2i(x-3,y,20,7),RUST)
					P.rect(im,x+2,y+1,6,2,HAZARD)
				plate(im,Rect2i(x-2,4,18,8),LIGHT)
			plate(im,Rect2i(29,56,22,16),stripe)
		I.Module.DEFENSE:
			pipe(im,Vector2i(12,12),Vector2i(64,64),6)
			pipe(im,Vector2i(12,64),Vector2i(64,12),6)
			for p: Vector2i in [Vector2i(17,17),Vector2i(63,17),Vector2i(17,63),Vector2i(63,63)]:
				tank(im,p,9,METAL)
				var ray := Vector2(40,40).direction_to(p)
				P.line(im,p,p+Vector2i(ray*16),LIGHT,3)
			P.polygon(im,[[21,30],[31,20],[49,20],[60,31],[60,49],[50,60],[30,60],[21,49]],SHADOW)
			tank(im,Vector2(40,40),14,stripe)
		I.Module.HABITAT:
			P.ellipse(im,Vector2(40,40),Vector2(36,34),INK)
			P.ellipse(im,Vector2(40,39),Vector2(33,31),METAL)
			P.ellipse(im,Vector2(40,39),Vector2(26,24),stripe.darkened(0.24))
			P.ellipse(im,Vector2(40,40),Vector2(22,20),Color.TRANSPARENT)
			for spoke in 3:
				var v := Vector2.from_angle(spoke*TAU/3.0-PI/2)
				pipe(im,Vector2i(39,39),Vector2i(Vector2(39,39)+v*25),4)
			for lamp in 20:
				var p := Vector2(40,39)+Vector2.from_angle(lamp*TAU/20)*Vector2(30,28)
				P.rect(im,roundi(p.x),roundi(p.y),2,2,GLASS)
			tank(im,Vector2(40,40),8,LIGHT)
		I.Module.SOLAR:
			pipe(im,Vector2i(5,38),Vector2i(72,38),5)
			for x in [3,48]:
				plate(im,Rect2i(x,11,29,58),PANEL)
				for col in range(x+4,x+26,8):
					for row in range(15,64,9):
						im.fill_rect(Rect2i(col,row,6,7),Color("587f9f"))
						P.rect(im,col,row,6,1,Color("93b5bb"))
			plate(im,Rect2i(35,28,10,25),stripe)
		I.Module.CHEMICAL:
			pipe(im,Vector2i(15,24),Vector2i(36,60),6)
			pipe(im,Vector2i(38,58),Vector2i(61,24),6)
			pipe(im,Vector2i(15,24),Vector2i(61,24),6)
			tank(im,Vector2(21,26),17,Color("809594"))
			tank(im,Vector2(60,26),17,Color("809594"))
			tank(im,Vector2(41,56),19,stripe.darkened(0.16))
		I.Module.ELECTRONICS:
			plate(im,Rect2i(18,23,46,41),SHADOW)
			for x in range(10,72,8):
				var top: int = 5 if x % 3 == 0 else 12
				plate(im,Rect2i(x,top,5,63-top),LIGHT)
				P.rect(im,x+1,top,3,4,GLASS)
			plate(im,Rect2i(19,34,44,21),PANEL)
			for x in range(23,58,8):
				plate(im,Rect2i(x,39,6,10),stripe)
		I.Module.COMPONENTS:
			plate(im,Rect2i(8,25,64,34),METAL)
			for pos: Vector2i in [Vector2i(23,31),Vector2i(54,48)]:
				for tooth in 8:
					var pin := Vector2i(Vector2(pos)+Vector2.from_angle(tooth*TAU/8.0)*16.0)
					plate(im,Rect2i(pin-Vector2i(3,3),Vector2i(7,7)),LIGHT)
				tank(im,pos,15,METAL)
				tank(im,pos,7,RUST)
			plate(im,Rect2i(35,28,12,25),stripe)
		I.Module.RECYCLER:
			plate(im,Rect2i(25,32,30,42),METAL)
			P.polygon(im,[[6,9],[20,11],[32,30],[24,37],[11,29]],SHADOW)
			P.polygon(im,[[74,9],[60,11],[48,30],[56,37],[69,29]],SHADOW)
			for x in [13,59]:
				plate(im,Rect2i(x,19,7,13),RUST)
			plate(im,Rect2i(18,32,46,17),RUST)
			for x in range(22,58,7):
				P.line(im,Vector2(x,36),Vector2(x+3,43),HAZARD,2)
			for y in range(53,69,5):
				P.rect(im,29,y,21,2,LIGHT)
	return im

static func module_texture(kind: int, tint: Color) -> Texture2D:
	var key := "%d:%s" % [kind,tint.to_html()]
	if not modules.has(key):
		modules[key] = ImageTexture.create_from_image(module_image(kind,tint))
	return modules[key]

static func module_image(kind: int, tint: Color) -> Image:
	var key := "%d:%s" % [kind,tint.to_html()]
	if not module_images.has(key):
		module_images[key] = sprite(kind,tint)
	return module_images[key]

static func bake(geom: Dictionary, tint: Color) -> Texture2D:
	# Bake the whole layout once so even a dense fleet pays one station draw call.
	var size: Vector2 = geom.size
	var density := minf(0.60, 800.0/maxf(size.x,size.y))
	var px := Vector2i((size*density).ceil()).maxi(1)
	var im := P.blank(px.x,px.y)
	var density_xy := Vector2(px)/size
	var half_size := size * 0.5
	var width := maxi(3,roundi(geom.link_width*density))
	for points: PackedVector2Array in geom.links:
		var a := (points[0]+half_size)*density_xy
		var b := (points[1]+half_size)*density_xy
		var offset := Vector2.ONE * floorf(width*0.5)
		P.line(im,a-offset,b-offset,INK,width)
		P.line(im,a-offset+Vector2.ONE,b-offset+Vector2.ONE,LIGHT,width-2)
		P.line(im,a-Vector2.ONE,b-Vector2.ONE,SHADOW,maxi(1,width/3))
	for part: Dictionary in geom.parts:
		var imprint := module_image(part.kind,tint).duplicate() as Image
		if part.get("pending",false):
			imprint.adjust_bcs(0.82,0.85,0.4)
			for x in range(6,70,8):
				P.line(imprint,Vector2(x,69),Vector2(x+4,74),HAZARD,2)
		var target := Vector2i((Vector2(part.size)*density_xy).round()).maxi(1)
		imprint.resize(target.x,target.y,Image.INTERPOLATE_NEAREST)
		im.blend_rect(imprint,Rect2i(Vector2i.ZERO,target),Vector2i(((Vector2(part.center)+half_size)*density_xy-Vector2(target)*0.5).round()))
	return ImageTexture.create_from_image(im)

static func draw_layout(target: CanvasItem, geom: Dictionary, origin: Vector2, angle: float, scale_factor: float, tint: Color, modulation: Color = Color.WHITE) -> void:
	var signature: int = geom.signature if geom.has("signature") else hash(geom.parts)
	var key: Array = [signature,tint]
	if not layouts.has(key):
		if layouts.size() >= CACHE_LIMIT:
			layouts.erase(layouts.keys().front())
		layouts[key] = bake(geom,tint)
	target.draw_set_transform(origin,angle,Vector2.ONE*scale_factor)
	target.draw_texture_rect(layouts[key],Rect2(-Vector2(geom.size)*0.5,geom.size),false,modulation)
	target.draw_set_transform(Vector2.ZERO)
