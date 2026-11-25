extends RefCounted

const Hulls = preload("res://hull_catalog.gd")

const INK := Color("090f1c")
const STEEL := Color("394f66")
const LIGHT := Color("8095a2")
const TEAL := Color("63d5cd")
const AMBER := Color("ebae67")
const RUST := Color("9d5b4b")
const PALETTES := [
	["142437", "223e58", "3d657c", "5e8a9f", "94c6c9"],
	["241a26", "49313a", "79504b", "aa7259", "e8b681"],
	["101f2e", "1c3a48", "31636a", "4e8d8c", "8bc9b3"],
]
const FACE_SKINS := ["e8b39a", "c88e70", "aa795e", "865b4b", "674742"]
const FACE_HAIR := ["242736", "573535", "934e3e", "9aa8b8", "a68056", "38556a"]
const FACE_EYES := ["80bce2", "966757", "65b49b", "e4b674", "576d88"]
static var cache: Dictionary = {}
static var portrait_cache: Dictionary = {}

static func portrait_texture(look: Dictionary) -> Texture2D:
	var owner: int = look.get("actor_id",-1)
	var fingerprint := hash(look)
	var saved: Dictionary = portrait_cache.get(owner,{})
	if saved.get("fingerprint") == fingerprint:
		return saved.texture
	if not portrait_cache.has(owner) and portrait_cache.size() >= 160:
		portrait_cache.erase(portrait_cache.keys().front())
	var baked := ImageTexture.create_from_image(portrait(look))
	portrait_cache[owner] = {"fingerprint":fingerprint,"texture":baked}
	return baked

static func blank(width: int, height: int) -> Image:
	return Image.create_empty(width, height, false, Image.FORMAT_RGBA8)

static func rect(canvas: Image, x: int, y: int, width: int, height: int, paint: Color) -> void:
	var area := Rect2i(x, y, width, height).intersection(Rect2i(Vector2i.ZERO, canvas.get_size()))
	if area.has_area():
		canvas.fill_rect(area, paint)

static func dot(canvas: Image, x: int, y: int, paint: Color) -> void:
	if x >= 0 and y >= 0 and x < canvas.get_width() and y < canvas.get_height():
		canvas.set_pixel(x, y, paint)

static func polygon(canvas: Image, points: Array, paint: Color) -> void:
	var vectors := PackedVector2Array()
	for point in points:
		vectors.append(Vector2(point[0], point[1]))
	var bounds := Rect2(vectors[0], Vector2.ZERO)
	for vertex in vectors:
		bounds = bounds.expand(vertex)
	for py in range(maxi(0, floori(bounds.position.y)), mini(canvas.get_height(), ceili(bounds.end.y))):
		for px in range(maxi(0, floori(bounds.position.x)), mini(canvas.get_width(), ceili(bounds.end.x))):
			if Geometry2D.is_point_in_polygon(Vector2(px + 0.5, py + 0.5), vectors):
				canvas.set_pixel(px, py, paint)

static func line(canvas: Image, start: Vector2, stop: Vector2, paint: Color, thick: int = 1) -> void:
	var steps := maxi(1, ceili(start.distance_to(stop)))
	for index in range(steps + 1):
		var point := start.lerp(stop, float(index) / steps).round()
		rect(canvas, int(point.x), int(point.y), thick, thick, paint)

static func ellipse(canvas: Image, center: Vector2, radius: Vector2, paint: Color) -> void:
	for py in range(maxi(0, floori(center.y - radius.y)), mini(canvas.get_height(), ceili(center.y + radius.y))):
		for px in range(maxi(0, floori(center.x - radius.x)), mini(canvas.get_width(), ceili(center.x + radius.x))):
			var uv := (Vector2(px + 0.5, py + 0.5) - center) / radius
			if uv.length_squared() <= 1.0:
				canvas.set_pixel(px, py, paint)

static func stamp(canvas: Image, source: Image, pos: Vector2i, factor: int = 1) -> void:
	if factor <= 1:
		canvas.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), pos)
		return
	var enlarged := source.duplicate()
	enlarged.resize(source.get_width() * factor, source.get_height() * factor, Image.INTERPOLATE_NEAREST)
	canvas.blend_rect(enlarged, Rect2i(Vector2i.ZERO, enlarged.get_size()), pos)

static func hull(kind: int, livery: Color) -> Image:
	var model := Hulls.hull_spec(kind)
	var dimensions: Vector2i = model.sprite_size
	var center: Vector2 = model.sprite_center
	var scale_factor: float = model.sprite_scale
	var canvas := blank(dimensions.x, dimensions.y)
	var mask := blank(dimensions.x, dimensions.y)
	var outline: Array = []
	for point: Vector2 in model.bounds:
		outline.append(center + point / scale_factor)
	polygon(mask, outline, Color.WHITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(model.id)
	var base := Color("526570").lerp(Color(model.paint), 0.36)
	var upper := base.lightened(0.19)
	var lower := base.darkened(0.36)
	canvas.fill(base)
	# Plate seams retain the same pixel width across hull sizes. Deck hardware
	# consequently reads smaller against the silhouette of a capital hull.
	var plate_width := rng.randi_range(7, 13)
	var plate_height := rng.randi_range(5, 9)
	for row in range(0, dimensions.y + plate_height, plate_height):
		var shift: int = rng.randi_range(0,plate_width)
		for col in range(-plate_width + shift, dimensions.x + 1, plate_width):
			var light: float = rng.randf_range(0.02,0.14)
			var face := base.lightened(light) if row < center.y else base.darkened(light)
			rect(canvas,col,row,plate_width-1,plate_height-1,face)
			line(canvas,Vector2(col,row),Vector2(col+plate_width-3,row),face.lightened(0.12))
			rect(canvas,col+1,row+plate_height-2,plate_width-3,1,lower)
			if rng.randf() < 0.35:
				dot(canvas,col+2,row+2,upper)
	var x := dimensions.x
	var y := dimensions.y
	var mid := int(center.y)
	var bridge_x := roundi(x*0.48)
	var bridge_y := mid
	var frame: String = model.frame
	# The pressure keel and its side armour run above the shipyard plating.
	# Recessed apertures stay dark enough for muzzle flashes to remain legible.
	for flank in [-1,1]:
		var steps: int = 3 + model.size
		for index in range(steps):
			var deck_x := roundi(x*.15 + index*x*.63/steps)
			var plate_length := roundi(x*.48/steps)
			var lift := roundi(y * (.05 + .038 * sin(PI * index / steps)))
			var outer := Vector2(deck_x,mid+int(flank)*lift*2.2)
			var inner := Vector2(deck_x+plate_length,mid+int(flank)*lift)
			var plating := base.lightened(.22) if flank < 0 else base.darkened(.06)
			polygon(canvas,[outer,outer+Vector2(plate_length*.47,-int(flank)*2),inner,
				inner-Vector2(4,int(flank)*3),outer+Vector2(1,-int(flank)*4)],plating)
			line(canvas,outer,outer+Vector2(plate_length*.47,-int(flank)*2),upper)
	match frame:
		"train", "box", "barge", "truss":
			# Twin external racks leave a service alley and a side-set bridge.
			var cargo_width := rng.randi_range(9,14)
			var cargo_height := maxi(6,roundi(y*.18))
			for row in [-1,1]:
				var deck_y: int = mid + int(row) * roundi(y*.16) - cargo_height/2
				for col in range(roundi(x*.18),roundi(x*.73),cargo_width+2):
					if frame == "barge":
						ellipse(canvas,Vector2(col+cargo_width/2,deck_y+cargo_height/2),Vector2(cargo_width*.55,cargo_height*.53),INK)
						ellipse(canvas,Vector2(col+cargo_width/2,deck_y+cargo_height/2-1),Vector2(cargo_width*.48,cargo_height*.43),livery.darkened(.16))
					else:
						hull_plate(canvas, col, deck_y, cargo_width, cargo_height, livery.darkened(.18))
					for seam in range(3,cargo_width-1,4):
						rect(canvas,col+seam,deck_y+2,1,cargo_height-5,lower)
			bridge_x = roundi(x*.70)
			bridge_y = mid - roundi(y*.12)
		"fork", "crane":
			for side in [-1,1]:
				var arm_start := Vector2(x*.46,mid+side*y*.14)
				var arm_end := Vector2(x*.90,mid+side*y*.20)
				line(canvas,arm_start,arm_end,INK,5)
				line(canvas,arm_start,arm_end,AMBER.darkened(.26),3)
				for index in range(2,9):
					var p := arm_start.lerp(arm_end,index*.1)
					line(canvas,p,p+Vector2(2,2),lower,1)
			hull_plate(canvas,roundi(x*.17),mid-4,roundi(x*.21),8,upper)
			bridge_x = roundi(x*.36)
		"bulwark", "breaker", "lancet":
			for side in [-1,1]:
				var p := Vector2(x*.24,mid+side*y*.19)
				var q := Vector2(x*.82,mid+side*y*.10)
				line(canvas,p,q,lower,5)
				line(canvas,p+Vector2(1,-2),q+Vector2(1,-2),livery.darkened(.12),3)
			hull_plate(canvas,roundi(x*.23),mid-5,roundi(x*.32),10,upper)
			bridge_x = roundi(x*.33)
		"hangar":
			for side in [-1,1]:
				var deck_y: int = mid+int(side)*roundi(y*.17)-4
				hull_plate(canvas,roundi(x*.19),deck_y,roundi(x*.56),9,lower)
				for col in range(roundi(x*.23),roundi(x*.70),7):
					rect(canvas,col,deck_y+3,3,1,AMBER)
				rect(canvas,roundi(x*.2),deck_y+6,roundi(x*.48),1,livery)
			bridge_y = mid - roundi(y*.08)
		"wing", "arc":
			for side in [-1,1]:
				var root := Vector2(x*.28,mid+side*y*.11)
				var tip := Vector2(x*.61,mid+side*y*.24)
				line(canvas,root,tip,INK,4)
				line(canvas,root+Vector2(0,1),tip+Vector2(0,1),livery.darkened(.08),2)
			bridge_x = roundi(x*.52)
		_:
			hull_plate(canvas,roundi(x*.20),mid-3,roundi(x*.54),7,livery.darkened(.14))
			line(canvas,Vector2(x*.33,mid-y*.14),Vector2(x*.67,mid-y*.065),upper,2)
	hull_plate(canvas,bridge_x-4,bridge_y-3,9+int(model.size),6,INK)
	rect(canvas,bridge_x,bridge_y-2,4+int(model.size),2,Color("83b5be"))
	for p: Vector2 in model.engine_slots:
		var nozzle := Vector2i((center+p/scale_factor).round())
		var size := maxi(2, roundi(y*.035))
		hull_plate(canvas,nozzle.x,nozzle.y-size,size*4+2,size*2+1,lower)
		rect(canvas,nozzle.x+1,nozzle.y-size+1,2,size*2-1,TEAL.darkened(.2))
		for tube in range(size):
			rect(canvas,nozzle.x+4+tube*2,nozzle.y-size+1,1,size*2-1,upper)
	for mount in model.mounts:
		var seat: Vector2 = center+Vector2(mount.offset)/scale_factor
		var radius := 1.5 + float(mount.size)*.85
		ellipse(canvas,seat,Vector2(radius+1,radius),lower.lightened(.12))
		ellipse(canvas,seat+Vector2(.5,.4),Vector2(radius*.75,radius*.68),INK)
		dot(canvas,roundi(seat.x),roundi(seat.y),base.darkened(.22))
	# Clip deck machinery to the gameplay outline and bevel its upper edge.
	# Alpha edges and collision vertices therefore agree in the refit and battle views.
	for py in range(y):
		for px in range(x):
			if mask.get_pixel(px,py).a == 0:
				canvas.set_pixel(px,py,Color.TRANSPARENT)
			elif px == 0 or py == 0 or px == x-1 or py == y-1:
				canvas.set_pixel(px,py,INK)
			elif mask.get_pixel(px,py-1).a == 0:
				canvas.set_pixel(px,py,upper.lightened(.13))
			elif mask.get_pixel(px-1,py).a == 0 or mask.get_pixel(px+1,py).a == 0 or mask.get_pixel(px,py+1).a == 0:
				canvas.set_pixel(px,py,INK)
	return canvas

static func hull_plate(canvas: Image, x: int, y: int, w: int, h: int, face: Color) -> void:
	polygon(canvas,[[x+2,y],[x+w-3,y],[x+w,y+2],[x+w-1,y+h-2],[x+w-3,y+h],
		[x+1,y+h-1],[x,y+h-3],[x,y+2]],face)
	line(canvas,Vector2(x+2,y),Vector2(x+w-3,y),face.lightened(.32))
	rect(canvas,x+2,y+h-2,w-4,1,face.darkened(.45))

static func atlas_hulls() -> Image:
	var cell := Vector2i(178, 116)
	var columns := 10
	var canvas := blank(cell.x * columns, cell.y * ceili(float(Hulls.MODELS.size()) / columns))
	for kind in range(Hulls.MODELS.size()):
		var sprite := hull(kind, Color(Hulls.MODELS[kind].paint))
		var model: Dictionary = Hulls.MODELS[kind]
		var fit := Hulls.stock_fit(kind)
		for i in range(fit.weapons.size()):
			if fit.weapons[i].is_empty():
				continue
			var mount: Dictionary = model.mounts[i]
			var p: Vector2 = model.sprite_center + Vector2(mount.offset)/float(model.sprite_scale)
			var tip: Vector2 = p+Vector2.from_angle(deg_to_rad(mount.facing))*(2.5+mount.size*1.4)
			line(sprite,p,tip,Color("b0b7aa"),1+int(mount.size)/2)
		# One battle-world scale for the entire sheet; large hulls visibly
		# occupy more deck area than a frigate in a neighboring berth.
		var factor := float(Hulls.MODELS[kind].sprite_scale) * 0.65
		sprite.resize(roundi(sprite.get_width()*factor),roundi(sprite.get_height()*factor),Image.INTERPOLATE_NEAREST)
		var pos := Vector2i(kind % columns, kind / columns) * cell + (cell-sprite.get_size())/2
		stamp(canvas,sprite,pos)
	return canvas

static func station_part(kind: int, tint: Color) -> Image:
	var canvas := blank(32, 32)
	var metal := Color("53677a")
	match kind:
		0:
			polygon(canvas, [[7,0],[25,0],[32,7],[32,25],[25,32],[7,32],[0,25],[0,7]], INK)
			polygon(canvas, [[8,2],[24,2],[30,8],[30,24],[24,30],[8,30],[2,24],[2,8]], metal)
			polygon(canvas, [[11,6],[21,6],[26,11],[26,21],[21,26],[11,26],[6,21],[6,11]], INK)
			ellipse(canvas, Vector2(16,16), Vector2(8,8), STEEL)
			rect(canvas, 12, 12, 8, 8, metal.lightened(0.13))
			rect(canvas, 14, 14, 4, 4, tint)
			for pin in [8, 12, 16, 20]:
				rect(canvas, pin, 3, 2, 1, AMBER)
				rect(canvas, pin, 27, 2, 1, TEAL.darkened(0.32))
		1:
			polygon(canvas, [[1,8],[7,4],[30,4],[32,8],[32,24],[30,28],[7,28],[1,24]], INK)
			rect(canvas, 4, 6, 26, 20, STEEL)
			rect(canvas, 8, 9, 21, 14, Color("131f2f"))
			rect(canvas, 10, 10, 19, 1, LIGHT)
			rect(canvas, 9, 22, 20, 1, LIGHT.darkened(0.39))
			for stripe in range(3):
				rect(canvas, 9 + stripe * 6, 13, 2, 6, tint)
			rect(canvas, 29, 12, 2, 7, TEAL)
		2:
			rect(canvas, 1, 8, 31, 16, INK)
			rect(canvas, 4, 10, 28, 12, STEEL)
			for tank in [4, 13, 22]:
				rect(canvas, tank, 5, 7, 22, INK)
				rect(canvas, tank + 1, 6, 5, 19, tint.darkened(0.30))
				rect(canvas, tank + 1, 7, 2, 14, tint)
				rect(canvas, tank, 12, 7, 2, LIGHT.darkened(0.31))
		3:
			rect(canvas, 2, 9, 18, 16, INK)
			rect(canvas, 4, 11, 13, 12, STEEL)
			rect(canvas, 14, 13, 17, 3, LIGHT)
			rect(canvas, 15, 19, 16, 2, STEEL)
			rect(canvas, 23, 12, 3, 10, LIGHT.darkened(0.25))
			rect(canvas, 30, 13, 2, 8, tint)
	return canvas

static func station(kind: int, tint: Color) -> Image:
	var canvas := blank(80, 72)
	rect(canvas, 32, 7, 16, 58, INK)
	rect(canvas, 36, 9, 8, 54, LIGHT.darkened(0.37))
	for x in [10, 52]:
		rect(canvas, x, 32, 19, 8, STEEL)
		rect(canvas, x, 33, 19, 2, LIGHT)
	var module := station_part([2,2,1,3][kind], tint)
	var opposite := module.duplicate()
	opposite.flip_x()
	stamp(canvas, module, Vector2i(48, 20))
	stamp(canvas, opposite, Vector2i(0, 20))
	var annex := station_part(2 if kind != 1 else 1, STEEL.lightened(0.25))
	annex.rotate_90(CLOCKWISE)
	stamp(canvas, annex, Vector2i(24, 0))
	stamp(canvas, station_part(0, tint), Vector2i(24, 20))
	rect(canvas, 39, 57, 2, 9, LIGHT)
	rect(canvas, 39, 65, 2, 2, AMBER)
	return canvas

static func props(kind: int, tint: Color) -> Image:
	var canvas := blank(32, 24)
	match kind:
		0:
			polygon(canvas, [[4,6],[26,6],[32,11],[32,22],[4,22],[0,17],[0,10]], INK)
			rect(canvas, 3, 10, 24, 11, tint.darkened(0.32))
			polygon(canvas, [[3,10],[7,7],[26,7],[30,10]], tint.lightened(0.32))
			for stripe in range(5):
				rect(canvas, 5 + stripe * 4, 12, 2, 6, tint)
			rect(canvas, 4, 20, 24, 2, STEEL)
		1:
			rect(canvas, 4, 2, 23, 19, INK)
			rect(canvas, 6, 3, 18, 13, STEEL)
			rect(canvas, 8, 5, 13, 7, Color("183642"))
			line(canvas, Vector2(9,10), Vector2(19,7), TEAL)
			rect(canvas, 6, 14, 23, 4, LIGHT.darkened(0.32))
			rect(canvas, 13, 18, 6, 5, STEEL)
			rect(canvas, 26, 15, 2, 1, tint)
		2:
			rect(canvas, 8, 3, 15, 21, INK)
			rect(canvas, 10, 2, 10, 20, STEEL)
			rect(canvas, 12, 4, 3, 14, LIGHT)
			rect(canvas, 9, 7, 12, 3, tint)
			rect(canvas, 9, 16, 12, 2, tint.darkened(0.33))
		_:
			rect(canvas, 10, 6, 12, 17, INK)
			rect(canvas, 12, 8, 8, 14, STEEL)
			rect(canvas, 11, 3, 10, 6, tint)
			rect(canvas, 13, 4, 6, 3, tint.lightened(0.44))
			rect(canvas, 10, 21, 12, 2, LIGHT.darkened(0.44))
	return canvas

# The farther eye and cheek are compressed towards screen left. Each face plane is a
# native-resolution polygon so the small previews keep their silhouette under nearest filtering.
static func portrait(look: Dictionary) -> Image:
	var canvas := blank(128, 144)
	canvas.fill(Color("101b2c"))
	polygon(canvas, [[0,0],[80,0],[30,76],[0,85]], Color("1d3144"))
	polygon(canvas, [[0,0],[12,0],[0,18]], Color("435164"))
	polygon(canvas, [[108,0],[116,0],[128,20],[128,29]], Color("394354"))
	for x in range(6,127,12):
		line(canvas, Vector2(x,6), Vector2(x,100), Color("203345"))
	for y in [14,38,62,86]:
		line(canvas, Vector2(2,y), Vector2(124,y), Color("233646"))
	rect(canvas, 7,17,12,2,Color("39656e"))
	rect(canvas, 110,35,11,2,Color("594849"))
	var skin := Color(FACE_SKINS[clampi(int(look.get("skin",1)),0,4)])
	var hair := Color(FACE_HAIR[clampi(int(look.get("hair",0)),0,5)])
	var age := int(look.get("age_band",0))
	if age >= 1:
		hair = hair.lerp(Color("aeb7bd"),0.48 if age == 1 else 0.82)
	var light := skin.lerp(Color("c6deed"),0.35)
	var mid := skin.lerp(Color("ead2bc"),0.1)
	var shade := skin.lerp(Color("393447"),0.44)
	var deep := skin.lerp(Color("252031"),0.65)
	var rim := skin.lerp(Color("ffa568"),0.66)
	var haircut := clampi(int(look.get("cut",0)),0,5)
	var profile := clampi(int(look.get("face",0)),0,3)
	var left: int = [39,38,42,37][profile]
	var cheek: int = [86,89,84,90][profile]
	var jaw: int = [72,80,69,76][profile]
	var chin: int = [97,94,101,92][profile]
	if haircut in [2,4]:
		polygon(canvas, [[42,25],[64,14],[85,20],[96,41],[100,102],[84,116],[72,79],[36,100],[33,58]],hair.darkened(0.34))
	polygon(canvas, [[47,78],[80,70],[86,106],[72,119],[46,111],[53,92]],deep)
	polygon(canvas, [[66,87],[80,77],[83,98],[75,106],[63,109]],shade)
	portrait_uniform(canvas,look)
	polygon(canvas, [[left+3,31],[53,20],[72,18],[85,25],[93,43],[92,68],[cheek,79],[jaw,chin-4],[56,chin],[47,chin-5],[left+3,78],[left-2,62],[left-1,45]],deep)
	polygon(canvas, [[left+3,30],[54,19],[71,19],[84,28],[88,45],[85,66],[cheek-4,78],[jaw,chin-7],[56,chin-2],[48,chin-8],[left+4,75],[left,60],[left,43]],shade)
	polygon(canvas, [[left+2,35],[54,22],[70,20],[78,29],[77,47],[72,59],[78,66],[67,73],[61,85],[57,chin-3],[49,chin-9],[left+4,77],[left,60],[left,44]],mid)
	polygon(canvas, [[left+2,37],[55,24],[68,23],[61,32],[58,46],[46,46],[left,51]],light)
	polygon(canvas, [[50,61],[58,57],[68,57],[73,60],[63,65],[51,69]],light)
	polygon(canvas, [[66,65],[76,60],[85,57],[82,67],[68,75],[60,80]],shade)
	polygon(canvas, [[51,chin-10],[59,chin-9],[66,chin-12],[62,chin-5],[57,chin-3],[51,chin-5]],mid.lightened(0.1))
	polygon(canvas, [[84,48],[92,45],[96,50],[94,62],[87,69],[82,66]],shade)
	polygon(canvas, [[87,51],[92,49],[94,51],[91,60],[88,62],[91,54],[87,55]],rim)
	line(canvas,Vector2(86,76),Vector2(jaw+1,chin-6),rim,1)
	line(canvas,Vector2(jaw,chin-5),Vector2(64,chin-2),rim.darkened(0.2))
	if haircut != 5:
		portrait_hair(canvas,hair,haircut,age)
	elif age > 0:
		polygon(canvas, [[80,32],[86,35],[88,46],[83,48]],hair)
	var eyes := clampi(int(look.get("eyes",0)),0,3)
	var iris := Color(FACE_EYES[clampi(int(look.get("iris",0)),0,4)])
	var brow := hair.darkened(0.32)
	var stressed := int(look.get("stress_tier",0)) >= 2
	var tired: bool = stressed or look.get("low_health",false)
	for side in range(2):
		var ex := 40 if side == 0 else 58
		var ey := 51 if side == 0 else 53
		var width: int = (8 if side == 0 else 14) - (2 if eyes == 1 else 0)
		var rise := 2 if eyes == 3 else 0
		var height := 4 if eyes == 2 else 3
		polygon(canvas, [[ex,ey-4],[ex+3,ey-7],[ex+width,ey-6-rise],[ex+width,ey-4-rise],[ex+3,ey-5]],brow)
		polygon(canvas, [[ex,ey],[ex+3,ey-2],[ex+width-3,ey-2-rise],[ex+width,ey-rise],[ex+width-4,ey+height-1],[ex+2,ey+height-1]],deep)
		polygon(canvas, [[ex+1,ey+1],[ex+4,ey-1],[ex+width-2,ey-rise],[ex+width-5,ey+height-2],[ex+2,ey+height-2]],Color("d9d0bf"))
		rect(canvas,ex+width/2-2,ey-1,3,height,iris)
		dot(canvas,ex+width/2-1,ey,INK)
		dot(canvas,ex+width/2-2,ey-1,Color("dee7de"))
		if tired:
			line(canvas,Vector2(ex+1,ey+height+1),Vector2(ex+width-2,ey+height+2-rise),shade.darkened(0.17),2)
			line(canvas,Vector2(ex,ey-2),Vector2(ex+width-3,ey-3-rise),deep)
	var nose := clampi(int(look.get("nose",0)),0,2)
	var tip_y: int = [68,72,69][nose]
	var tip_x := 44 if nose == 2 else 47
	polygon(canvas, [[53,48],[56,49],[54,61],[53,tip_y-2],[tip_x,tip_y+1],[tip_x-2,tip_y-1],[49,61]],light)
	polygon(canvas, [[55,52],[58,56],[55,65],[58,tip_y],[54,tip_y+2],[tip_x,tip_y+1],[53,tip_y-2]],shade)
	line(canvas,Vector2(52,tip_y+1),Vector2(56,tip_y),deep)
	var mouth := clampi(int(look.get("mouth",0)),0,2)
	var lip_y := mini(chin-11,80)
	polygon(canvas, [[44,lip_y],[50,lip_y-2],[53,lip_y-1],[57,lip_y-2],[63+mouth,lip_y],[55,lip_y+1],[49,lip_y+1]],deep)
	polygon(canvas, [[46,lip_y+2],[54,lip_y+2],[62,lip_y+1],[57,lip_y+3+mouth],[51,lip_y+3+mouth]],mid.lerp(Color("c88582"),0.28))
	if age >= 1:
		line(canvas,Vector2(48,39),Vector2(57,37),shade)
		line(canvas,Vector2(61,36),Vector2(72,37),shade)
		line(canvas,Vector2(72,54),Vector2(78,51),shade)
		line(canvas,Vector2(74,56),Vector2(79,56),shade)
		line(canvas,Vector2(59,71),Vector2(65,79),shade)
	if age >= 2:
		line(canvas,Vector2(47,36),Vector2(56,34),shade)
		line(canvas,Vector2(64,82),Vector2(62,87),deep)
	if tired and haircut != 5:
		line(canvas,Vector2(61,32),Vector2(56,45),hair.darkened(0.12),2)
	match int(look.get("mark",0)):
		1: line(canvas,Vector2(68,41),Vector2(62,52),rim,2)
		2:
			polygon(canvas, [[73,61],[82,58],[83,66],[73,72],[68,68]],Color("445969"))
			line(canvas,Vector2(73,67),Vector2(79,63),TEAL,2)
		3:
			for point in [[43,62],[45,65],[49,63],[61,63],[64,64],[68,62],[70,64]]:
				dot(canvas,point[0],point[1],shade)
	if look.get("wounded",false):
		polygon(canvas, [[63,68],[78,62],[81,67],[66,75]],Color("a8a799"))
		line(canvas,Vector2(66,69),Vector2(77,65),Color("d9d5b7"),2)
		line(canvas,Vector2(70,67),Vector2(72,71),Color("838679"))
	return canvas

static func portrait_hair(canvas: Image, hair: Color, cut: int, age: int) -> void:
	var crown: int = [14,11,10,20,12][cut]
	var fringe: Array = [
		[[89,53],[82,47],[77,33],[64,34],[51,40],[40,38],[37,46]],
		[[89,55],[81,49],[78,31],[70,28],[50,41],[38,43],[35,48]],
		[[91,76],[85,66],[78,35],[65,39],[54,35],[43,45],[38,69],[34,53]],
		[[88,48],[81,42],[78,31],[64,28],[49,31],[40,39]],
		[[90,54],[83,45],[78,32],[60,31],[46,36],[36,47]]
	][cut]
	polygon(canvas, [[36,36],[42,crown+9],[56,crown],[70,crown-1],[84,crown+5],[92,33],[94,45]] + fringe, hair.darkened(0.15))
	polygon(canvas, [[38,36],[44,crown+10],[57,crown+2],[70,crown+1],[79,crown+6],[60,crown+5],[51,crown+11]],hair.lerp(Color("94a7ba"),0.36))
	line(canvas,Vector2(75,crown+4),Vector2(85,crown+10),hair.lerp(Color("e5a078"),0.57),2)
	if cut == 1:
		line(canvas,Vector2(45,35),Vector2(66,19),hair.lightened(0.30),2)
	if cut == 4:
		for braid in range(6):
			var y := 55+braid*8
			var x := 89+braid%2*3
			polygon(canvas, [[x,y],[x+7,y-2],[x+10,y+6],[x+4,y+11],[x-1,y+6]],hair)
			line(canvas,Vector2(x+3,y+2),Vector2(x+6,y+4),hair.lightened(0.3),2)
		rect(canvas,94,103,7,4,AMBER)
	if age >= 1:
		line(canvas,Vector2(82,38),Vector2(86,47),Color("acb7be"),2)
		line(canvas,Vector2(84,36),Vector2(88,45),Color("89959d"))

const COAT_FABRIC := ["49515a","245b62","463c67","59604a","42495e","613c4b","384c70","554c4a"]
const COAT_TRIM := ["db9868","70d7d2","c2a8ec","bbce8c","e8c881","ec99ad","a3bce7","cfac8a"]

static func portrait_uniform(canvas: Image, look: Dictionary) -> void:
	var uniform := int(look.get("uniform",-1))
	var index := clampi(uniform,0,7)
	var wear := clampi(int(look.get("wear",0)),0,3)
	var coat := Color(COAT_FABRIC[index]) if uniform >= 0 else Color(["546b7b","526951","614b63","795a49"][wear])
	var accent := Color(str(look.get("uniform_color",COAT_TRIM[index]))) if uniform >= 0 else coat.lightened(0.32)
	var bright := coat.lerp(Color("b4d2e4"),0.30)
	var dark := coat.lerp(INK,0.48)
	polygon(canvas, [[0,144],[5,126],[15,114],[41,104],[49,99],[62,109],[82,99],[111,110],[123,120],[128,140],[128,144]],dark)
	polygon(canvas, [[1,144],[8,125],[18,115],[44,106],[50,103],[58,112],[52,144]],bright)
	polygon(canvas, [[12,144],[16,123],[39,113],[52,105],[62,113],[80,103],[101,109],[111,144]],coat)
	polygon(canvas, [[80,105],[101,109],[117,118],[126,139],[109,144],[89,120]],dark)
	line(canvas,Vector2(64,114),Vector2(58,143),dark,3)
	var seam := uniform if uniform >= 0 else [1,3,2,5][wear] as int
	match seam:
		0: # Guard epaulettes and placket.
			polygon(canvas, [[8,122],[20,113],[43,106],[44,112],[24,121],[10,126]],accent)
			polygon(canvas, [[81,103],[106,110],[114,117],[91,112]],accent.darkened(0.22))
			rect(canvas,65,119,4,22,dark)
			for y in [121,129,137]: rect(canvas,65,y,3,2,accent)
		1: # Two broad lapels on a double-breasted jacket.
			polygon(canvas, [[38,107],[47,95],[57,106],[61,114],[51,125]],dark)
			polygon(canvas, [[64,112],[80,96],[86,104],[70,122],[59,131]],bright)
			line(canvas,Vector2(84,104),Vector2(61,128),accent,2)
			for y in [124,132,140]: rect(canvas,71,y,3,2,accent)
		2: # High brocade collar and a gold, off-centre sash.
			polygon(canvas, [[38,106],[41,91],[51,96],[61,113],[45,111]],dark)
			polygon(canvas, [[63,114],[79,91],[87,94],[84,109],[69,120]],bright)
			polygon(canvas, [[17,115],[27,110],[80,144],[60,144]],accent.darkened(0.18))
			line(canvas,Vector2(25,113),Vector2(73,143),accent)
		3: # Freight harness with brass clasp.
			polygon(canvas, [[22,110],[32,106],[76,144],[60,144]],dark)
			polygon(canvas, [[82,104],[91,106],[62,144],[52,144]],bright)
			polygon(canvas, [[50,127],[58,123],[66,131],[57,137]],accent)
			rect(canvas,80,124,16,8,dark)
			for x in [82,85,89,91]: rect(canvas,x,125,1,5,accent)
		4: # Asymmetric corporate suit.
			polygon(canvas, [[43,103],[50,99],[62,110],[85,101],[61,141],[54,143],[55,118]],dark)
			polygon(canvas, [[80,101],[91,106],[81,116],[77,116],[63,137]],bright)
			line(canvas,Vector2(44,105),Vector2(55,119),accent,2)
			rect(canvas,81,124,15,2,accent)
		5: # Reinforced work suit with bib and shoulder panel.
			polygon(canvas, [[26,114],[34,110],[42,125],[38,143],[27,144]],dark)
			polygon(canvas, [[40,119],[68,122],[81,144],[38,144]],bright)
			polygon(canvas, [[84,105],[103,108],[116,118],[105,124],[91,115]],accent.darkened(0.17))
			rect(canvas,45,129,18,7,dark)
			rect(canvas,45,129,18,2,accent)
		6: # Fleece-lined storm collar.
			polygon(canvas, [[29,108],[41,94],[49,95],[56,110],[60,119],[49,116]],bright)
			polygon(canvas, [[63,118],[76,96],[91,98],[96,106],[82,108],[70,119]],bright)
			line(canvas,Vector2(31,109),Vector2(43,96),accent,3)
			line(canvas,Vector2(79,98),Vector2(92,100),accent,3)
			rect(canvas,39,128,11,6,dark)
		7: # Layered gorget and keeper's central lamp.
			polygon(canvas, [[37,103],[48,99],[61,111],[83,99],[91,106],[79,118],[62,126],[46,117]],accent.darkened(0.27))
			polygon(canvas, [[38,105],[50,111],[61,117],[84,106],[78,115],[61,124],[44,114]],dark)
			polygon(canvas, [[61,116],[67,122],[61,132],[55,123]],accent)
			rect(canvas,60,122,3,5,Color("efdeab"))
	# Culture determines the pin geometry. The flag style determines the stripe on the other shoulder.
	var emblem := int(look.get("crest",-1))
	if emblem >= 0:
		rect(canvas,84,130,13,8,dark)
		for bit in range(6):
			if (emblem & (1 << bit)) != 0:
				var x := 85+(bit%3)*2
				var y := 131+(bit/3)*3
				rect(canvas,x,y,2,2,accent)
				rect(canvas,96-(x-84),y,2,2,accent)
	var style := int(look.get("uniform_style",-1))
	if style >= 0:
		for stripe in range(clampi(style+1,1,3)):
			line(canvas,Vector2(8+stripe*3,134),Vector2(15+stripe*3,127),accent.darkened(0.24),2)
	if look.get("regalia",false):
		polygon(canvas, [[37,107],[37,92],[45,95],[55,112]],dark)
		line(canvas,Vector2(37,93),Vector2(46,97),accent,2)
		polygon(canvas, [[71,111],[79,93],[88,91],[87,104]],dark)
		line(canvas,Vector2(80,96),Vector2(88,93),accent,2)
		polygon(canvas, [[12,117],[27,110],[35,109],[32,114],[14,122]],Color("d6ad75"))
		line(canvas,Vector2(20,119),Vector2(40,132),AMBER,2)
		line(canvas,Vector2(40,132),Vector2(48,128),AMBER,2)
		rect(canvas,79,102,4,3,accent.lightened(0.4))

static func effect(kind: int, phase: int, tint: Color) -> Image:
	var canvas := blank(24, 24)
	match kind:
		0:
			polygon(canvas, [[22,8],[22,16],[13,16],[2+phase*2,12],[13,8]], tint.darkened(0.39))
			polygon(canvas, [[22,10],[22,14],[12,14],[8+phase,12],[13,10]], tint)
			rect(canvas, 17, 11, 6, 2, Color("d8fbef"))
		1:
			var radius := 2 + phase * 2
			for ray in range(8):
				var angle := ray * TAU / 8.0
				var direction := Vector2.from_angle(angle)
				line(canvas, Vector2(12,12) + direction * (radius / 2.0), Vector2(12,12) + direction * radius,
					Color(tint, 1.0 - phase * 0.15))
			ellipse(canvas, Vector2(12,12), Vector2.ONE * maxi(1, 3-phase), Color("ffe1a7", 1.0 - phase * 0.20))
		_:
			var radius := 8 + phase
			for step in range(12):
				var point := Vector2(12, 12) + Vector2.from_angle(step * TAU / 12.0) * radius
				rect(canvas, int(point.x), int(point.y), 2, 2, Color(tint, 0.85 - phase * 0.17))
	return canvas

static func orbit(variant: int) -> Image:
	var canvas := blank(320, 180)
	var colors: Array = PALETTES[variant]
	var random := RandomNumberGenerator.new()
	random.seed = 8340 + variant * 93
	for py in range(180):
		for px in range(320):
			var swirl := sin(px * 0.016 + py * 0.044) * 0.52 + sin(px * 0.039 - py * 0.031) * 0.24
			var current := (swirl + 0.8) / 1.65 * (0.7 + float(py) / 460)
			if (px + py) % 2 == 0:
				current += 0.04
			canvas.set_pixel(px, py, Color("080f1d").lerp(Color(colors[1]), floorf(maxf(0.0, current) * 9) / 12.0))
	for index in range(360):
		var px := random.randi_range(0, 319)
		var py := random.randi_range(0, 179)
		var tone := Color(colors[4]).lerp(Color("141c2b"), random.randf_range(0.25, 0.81))
		dot(canvas, px, py, tone)
		if index % 26 == 0:
			dot(canvas, px + 1, py, tone.darkened(0.33))
			dot(canvas, px, py + 1, tone.darkened(0.33))
	var center: Vector2 = [Vector2(243,80), Vector2(251,93), Vector2(254,67)][variant]
	var radius: float = [68.0, 57.0, 39.0][variant]
	for py in range(5, 165):
		for px in range(135, 319):
			var coord := (Vector2(px, py) - center) / radius
			var dist := coord.length_squared()
			if dist > 1.0:
				continue
			var daylight := maxf(0, Vector3(coord.x, coord.y, sqrt(1 - dist)).dot(Vector3(0.68, -0.56, 0.49)))
			var band := sin(coord.y * (16 if variant == 0 else 44) + sin(coord.x * 9 + coord.y * 4) * 2)
			var luminance := daylight * 3.4 + band * 0.55
			if (px + py) % 2 == 1:
				luminance -= 0.34
			var color_index := clampi(floori(luminance), 0, 3)
			if dist > 0.95 and daylight > 0.35:
				color_index = 4 if (px + py) % 3 else 3
			dot(canvas, px, py, Color(colors[color_index]))
	if variant == 0:
		for lane in [0, 2, 5]:
			for px in range(146, 319):
				var py: int = 118 - (px - 146) / 3 + lane
				if px < 190 or py >= center.y - 4:
					dot(canvas, px, py, Color(colors[3]).darkened(lane * 0.09))
	elif variant == 1:
		for index in range(112):
			var px := random.randi_range(0, 319)
			var py := 121 - px / 5 + random.randi_range(-18, 23)
			dot(canvas, px, py, Color(colors[2 + index % 3]).darkened(0.19))
	return canvas

static func bay(variant: int) -> Image:
	var canvas := blank(320, 180)
	var accents: Color = [AMBER, RUST, TEAL][variant]
	var space := orbit(variant)
	canvas.fill(Color("141e2a"))
	stamp(canvas, space, Vector2i.ZERO)
	polygon(canvas, [[0,0],[130,0],[101,37],[100,111],[0,139]], Color("182430"))
	polygon(canvas, [[0,0],[320,0],[320,14],[143,21],[102,45],[0,29]], Color("202e3c"))
	polygon(canvas, [[0,127],[110,101],[229,96],[320,111],[320,180],[0,180]], Color("283440"))
	polygon(canvas, [[0,136],[120,108],[235,104],[320,120],[320,138],[225,117],[111,122],[0,151]], Color("37454b"))
	polygon(canvas, [[0,151],[113,124],[239,119],[320,141],[320,180],[0,180]], Color("1b2835"))
	polygon(canvas, [[0,171],[117,142],[233,137],[320,158],[320,180],[0,180]], Color("263747"))
	for beam in [[Vector2(49,0),Vector2(51,119)], [Vector2(103,12),Vector2(105,107)], [Vector2(294,0),Vector2(288,108)]]:
		line(canvas, beam[0], beam[1], INK, 7)
		line(canvas, beam[0] + Vector2(2,0), beam[1] + Vector2(2,0), STEEL, 2)
	for offset in [0, 18, 36]:
		line(canvas, Vector2(0, 153+offset), Vector2(151, 119+offset), Color("41515a"))
		line(canvas, Vector2(170, 124+offset), Vector2(319, 131+offset), Color("334651"))
	for px in [117, 143, 169, 195, 221, 247, 273]:
		rect(canvas, px, 19 - px / 28, 5, 2, accents)
		rect(canvas, px, 19 - px / 28, 3, 1, accents.lightened(0.38))
	for px in [106, 131, 178, 226, 265, 298]:
		rect(canvas, px, 131 + (px-181)*(px-181)/800, 4, 2, accents)
	if variant == 1:
		for px in [199, 228, 257, 285]:
			stamp(canvas, props(2, RUST), Vector2i(px, 67), 2)
			rect(canvas, px + 19, 82, 6, 2, AMBER)
		line(canvas, Vector2(177,101), Vector2(313,101), STEEL, 3)
	else:
		var parked := hull(0 if variant == 0 else 2, accents)
		var berth_shadow := blank(96, 20)
		ellipse(berth_shadow, Vector2(48,10), Vector2(47,7), Color("0d1423", 0.65))
		stamp(canvas, berth_shadow, Vector2i(177, 115))
		stamp(canvas, parked, Vector2i(190, 79))
		rect(canvas, 208, 112, 3, 13, STEEL)
		rect(canvas, 243, 107, 3, 14, STEEL)
	stamp(canvas, props(0, accents.darkened(0.17)), Vector2i(121, 102))
	stamp(canvas, props(0, accents.darkened(0.35)), Vector2i(281, 129))
	stamp(canvas, props(1, accents), Vector2i(87, 111))
	stamp(canvas, props(3, accents), Vector2i(154, 133))
	polygon(canvas, [[0,149],[100,130],[104,134],[0,160]], INK)
	line(canvas, Vector2(0,151), Vector2(103,131), LIGHT.darkened(0.19))
	return canvas

static func texture(key: String, source: Callable) -> Texture2D:
	if not cache.has(key):
		cache[key] = ImageTexture.create_from_image(source.call())
	return cache[key]

static func ship_texture(kind: int, tint: Color = AMBER) -> Texture2D:
	return texture("ship:%s:%s:%s:hull" % [Hulls.hull_id(kind), Hulls.hull_spec(kind).style_id, tint.to_html()], func(): return hull(kind, tint))

static func station_texture(kind: int, tint: Color) -> Texture2D:
	return texture("station:%s:%s" % [kind, tint.to_html()], func(): return station(kind, tint))

static func station_hull_texture(kind: int, tint: Color) -> Texture2D:
	return texture("station_hull:%d:%s" % [kind,tint.to_html()], func():
		var hull := station(kind,tint)
		hull.resize(320,288,Image.INTERPOLATE_NEAREST)
		# Panel joints and paired windows follow opaque plating on the existing silhouette.
		for y in range(4,hull.get_height()-5,7):
			for x in range(4 + (y % 3) * 2,hull.get_width()-7,10):
				var plate := hull.get_pixel(x,y)
				if plate.a < 0.99 or plate.get_luminance() < 0.10 or hull.get_pixel(x+6,y+3) != plate:
					continue
				var joint := plate.darkened(0.26)
				hull.fill_rect(Rect2i(x,y,6,1),joint)
				hull.set_pixel(x,y+1,joint)
				if (x / 10 + y / 7 * 3) % 6 == 0:
					hull.set_pixel(x+2,y+2,tint.lightened(0.25))
					hull.set_pixel(x+4,y+2,tint)
		return hull)

static func backdrop_texture(variant: int, inside: bool = false) -> Texture2D:
	return texture("backdrop:%s:%s" % [variant, inside], func(): return bay(variant) if inside else orbit(variant))

static func effect_texture(kind: int, phase: int, tint: Color) -> Texture2D:
	return texture("effect:%s:%s:%s" % [kind, phase, tint.to_html()], func(): return effect(kind, phase, tint))
