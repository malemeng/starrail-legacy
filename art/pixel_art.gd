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
	if kind >= Hulls.BASE_MODELS.size():
		return production_hull(kind,livery)
	if kind >= 3:
		return specialist(kind, livery)
	var canvas := blank(64, 40)
	var outline: Array
	match kind:
		0: outline = [[2,15],[12,13],[17,3],[28,3],[33,11],[47,12],[63,20],[47,28],[33,29],[28,37],[17,37],[12,27],[2,25]]
		1: outline = [[1,5],[17,5],[20,2],[44,2],[46,7],[58,10],[63,16],[63,24],[58,30],[46,33],[44,38],[20,38],[17,35],[1,35]]
		_: outline = [[1,6],[17,6],[23,1],[49,4],[63,7],[63,14],[53,17],[45,17],[44,23],[53,23],[63,26],[63,33],[49,36],[23,39],[17,34],[1,34]]
	polygon(canvas, outline, INK)
	polygon(canvas, [[3,16],[14,15],[19,5],[27,5],[34,13],[47,14],[59,20],[47,26],[33,27],[27,35],[19,35],[14,25],[3,24]], STEEL)
	if kind == 0:
		polygon(canvas, [[18,5],[27,5],[34,14],[22,16],[15,14]], LIGHT.darkened(0.18))
		polygon(canvas, [[15,24],[20,21],[33,26],[27,34],[19,34]], STEEL.darkened(0.17))
		polygon(canvas, [[10,16],[33,15],[47,15],[59,20],[46,23],[10,23]], LIGHT)
		rect(canvas, 18, 8, 8, 2, livery)
		rect(canvas, 18, 29, 8, 2, livery.darkened(0.30))
		polygon(canvas, [[36,17],[46,16],[51,19],[46,22],[36,22],[34,19]], INK)
		rect(canvas, 38, 17, 8, 2, TEAL.darkened(0.19))
		rect(canvas, 8, 18, 18, 1, Color("b7c0b7"))
		rect(canvas, 4, 16, 3, 3, TEAL)
		rect(canvas, 4, 21, 3, 3, TEAL.darkened(0.12))
	if kind == 1:
		polygon(canvas, [[3,7],[17,7],[21,4],[43,4],[46,9],[57,11],[61,17],[61,23],[57,28],[46,31],[43,36],[21,36],[17,33],[3,33]], STEEL)
		for py in [7, 21]:
			rect(canvas, 3, py + 1, 14, 11, Color("212c3e"))
			rect(canvas, 4, py + 3, 3, 7, TEAL)
			rect(canvas, 10, py + 2, 7, 2, LIGHT)
			for px in [19, 28, 37]:
				rect(canvas, px, py, 8, 12, INK)
				rect(canvas, px + 1, py + 1, 6, 9, livery)
				rect(canvas, px + 1, py + 1, 6, 1, livery.lightened(0.26))
				for seam in [3, 5, 7]:
					rect(canvas, px + 2, py + seam, 4, 1, livery.darkened(0.30))
		rect(canvas, 46, 11, 10, 18, LIGHT.darkened(0.15))
		rect(canvas, 51, 16, 7, 8, INK)
		rect(canvas, 54, 17, 3, 6, TEAL)
	if kind == 2:
		for side in [0, 21]:
			polygon(canvas, [[3,7+side],[17,8+side],[25,3+side],[45,5+side],[61,8+side],[61,12+side],[42,16+side],[24,16+side],[16,13+side],[3,13+side]], STEEL)
			polygon(canvas, [[22,7+side],[31,5+side],[59,8+side],[59,10+side],[43,12+side],[26,12+side]], LIGHT.darkened(0.18))
			rect(canvas, 26, 7+side, 12, 2, livery)
			rect(canvas, 5, 8+side, 3, 4, TEAL)
			rect(canvas, 41, 10+side, 17, 2, INK)
			rect(canvas, 42, 10+side, 9, 1, LIGHT)
		rect(canvas, 6, 16, 32, 8, Color("334456"))
		rect(canvas, 7, 18, 3, 4, TEAL)
		rect(canvas, 29, 17, 10, 5, INK)
		rect(canvas, 31, 17, 6, 2, TEAL.darkened(0.17))
	for spot in [Vector2i(13,19), Vector2i(25,22), Vector2i(32,16), Vector2i(45,21)]:
		if canvas.get_pixelv(spot).a > 0:
			canvas.set_pixelv(spot, LIGHT.lightened(0.19))
	return canvas

static func production_hull(kind: int, livery: Color) -> Image:
	var spec: Dictionary = Hulls.MODELS[kind]
	var line_id: int = spec.silhouette
	var role: int = spec.role_id
	var variants := [0,1,3,7]
	var base: Image = hull(variants[role],livery)
	var panel_start := 12 + (line_id % 4)*5
	var span := 12 + (line_id / 4)*7
	var wing_y := 7 + (line_id % 3)
	if line_id % 2 == 0:
		for side in [1,-1]:
			var py: int = 20 + side*11
			polygon(base,[[panel_start,py],[panel_start+6,py-side*wing_y],[panel_start+span,py-side*3],[panel_start+span+2,py]],STEEL)
			rect(base,panel_start+3,py-side*2,span-3,2,livery.lightened(0.22))
	else:
		for py in [6,28]:
			rect(base,panel_start,py,span,5,INK)
			rect(base,panel_start+2,py+1,span-4,3,livery)
			for point in range(panel_start+3,panel_start+span-2,4):
				dot(base,point,py+1,LIGHT)
	var vent_start := 7 + line_id * 3
	rect(base,vent_start,18,7+role,4,INK)
	for pin in range(3):
		rect(base,vent_start+1+pin*2,19,1,2,livery.lightened(0.33))
	return base

static func specialist(kind: int, livery: Color) -> Image:
	var canvas := blank(64, 40)
	var side: Array
	match kind:
		3: side = [[3,11],[27,10],[35,4],[47,6],[49,12],[61,5],[64,8],[55,16],[46,19],[3,20]]
		4: side = [[2,13],[13,11],[14,3],[29,3],[35,8],[52,8],[60,11],[63,16],[51,16],[46,12],[36,15],[34,20],[2,20]]
		5: side = [[1,7],[14,7],[21,2],[39,4],[47,8],[58,10],[64,20],[1,20]]
		6: side = [[1,5],[12,5],[13,2],[38,2],[41,5],[49,5],[58,10],[60,15],[52,19],[1,20]]
		7: side = [[0,3],[16,3],[23,0],[41,1],[53,7],[62,15],[64,20],[0,20]]
		_: side = [[0,9],[9,7],[11,1],[46,1],[49,6],[57,8],[63,15],[64,20],[0,20]]
	polygon(canvas, side, INK)
	var lower := []
	for vertex in side:
		lower.append([vertex[0], 40-vertex[1]])
	polygon(canvas, lower, INK)
	for mirror in [false, true]:
		var armor: Array = []
		for vertex in side:
			var px: float = lerpf(vertex[0], 30.0, 0.065)
			var py: float = lerpf(vertex[1], 20.0, 0.13)
			armor.append([px, 40-py if mirror else py])
		polygon(canvas, armor, STEEL.darkened(0.20) if mirror else STEEL)
	match kind:
		3:
			for py in [7, 25]:
				polygon(canvas, [[39,py+6],[55,py+1],[60,py],[59,py+3],[48,py+8],[40,py+9]], livery)
				rect(canvas, 22, py + 4, 9, 4, LIGHT)
			rect(canvas, 10, 15, 14, 10, livery.darkened(0.35))
		4:
			for py in [6, 26]:
				rect(canvas, 16, py, 11, 7, livery)
				rect(canvas, 32, py + 3, 17, 3, LIGHT.darkened(0.25))
				rect(canvas, 46, py + 4, 12, 3, livery)
				rect(canvas, 9, py + 7, 8, 4, LIGHT)
			rect(canvas, 20, 15, 14, 10, LIGHT.darkened(0.27))
		5:
			for py in [7, 28]:
				polygon(canvas, [[23,py-2],[35,py-2],[57,py+3],[53,py+6],[25,py+6]], livery.darkened(0.24))
				rect(canvas, 34, py, 14, 3, INK)
				rect(canvas, 38, py, 12, 1, LIGHT)
			rect(canvas, 11, 14, 19, 12, STEEL.lightened(0.26))
		6, 8:
			for py in [5, 22]:
				for px in range(14, 45, 10):
					rect(canvas, px, py, 9, 13, INK)
					rect(canvas, px + 1, py + 1, 7, 10, livery.darkened(0.16))
					rect(canvas, px + 2, py + 1, 6, 2, livery.lightened(0.29))
					rect(canvas, px + 2, py + 8, 5, 1, LIGHT)
				rect(canvas, 10, py + 6, 4, 8, LIGHT.darkened(0.22))
			rect(canvas, 44, 15, 11, 10, STEEL.lightened(0.25))
			if kind == 6:
				for py in [10, 28]:
					rect(canvas, 47, py, 8, 2, livery.lightened(0.35))
		7:
			for py in [5, 27]:
				polygon(canvas, [[18,py],[36,py],[49,py+4],[53,py+6],[33,py+8],[20,py+8]], livery.darkened(0.34))
				for px in [23, 37]:
					rect(canvas, px, py + 3, 8, 5, STEEL.darkened(0.4))
					rect(canvas, px + 4, py + 4, 10, 2, LIGHT)
			rect(canvas, 13, 15, 35, 10, STEEL.lightened(0.27))
			rect(canvas, 17, 17, 21, 2, LIGHT)
	for py in [15, 22]:
		rect(canvas, 3, py, 4, 3, TEAL)
		rect(canvas, 5, py, 2, 1, Color("b4ebde"))
	rect(canvas, 38 if kind in [3, 4] else 47, 18, 8, 4, INK)
	rect(canvas, 40 if kind in [3, 4] else 49, 18, 4, 1, TEAL)
	return canvas

static func atlas_hulls() -> Image:
	var canvas := blank(64 * 6, 40 * ceili(Hulls.MODELS.size() / 6.0))
	for model in range(Hulls.MODELS.size()):
		stamp(canvas, hull(model, Color(Hulls.MODELS[model].paint)), Vector2i((model % 6) * 64, (model / 6) * 40))
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

static func portrait(look: Dictionary) -> Image:
	var canvas := blank(64, 72)
	canvas.fill(Color("152331"))
	for px in range(2, 62, 4):
		rect(canvas, px, 2, 1, 68, Color("192a3b"))
	var skin := Color(FACE_SKINS[clampi(int(look.get("skin", 1)), 0, 4)])
	var hair := Color(FACE_HAIR[clampi(int(look.get("hair", 0)), 0, 5)])
	var iris := Color(FACE_EYES[clampi(int(look.get("iris", 0)), 0, 4)])
	var coat := Color(["536b81", "496b62", "6d506b", "8b6048"][clampi(int(look.get("wear", 0)), 0, 3)])
	var haircut := int(look.get("cut", 0))
	var profile := int(look.get("face", 0))
	var jaw: int = [10, 13, 8, 11][clampi(profile, 0, 3)]
	var brow: int = [13, 14, 11, 14][clampi(profile, 0, 3)]
	var bottom: int = [52, 51, 55, 48][clampi(profile, 0, 3)]
	if haircut in [2, 4]:
		polygon(canvas, [[15,20],[23,11],[39,10],[48,21],[50,61],[14,62]], hair.darkened(0.31))
	polygon(canvas, [[2,72],[6,64],[22,58],[42,58],[58,64],[63,72]], coat)
	polygon(canvas, [[4,71],[12,65],[25,62],[30,71]], coat.lightened(0.18))
	polygon(canvas, [[44,59],[59,65],[63,72],[48,72]], coat.darkened(0.24))
	rect(canvas, 25, 44, 14, 18, skin.darkened(0.35))
	polygon(canvas, [[32-brow,22],[24,16],[40,16],[32+brow,22],[32+brow,39],[32+jaw,bottom-5],[32,bottom],[32-jaw,bottom-5],[32-brow,39]], skin)
	polygon(canvas, [[37,19],[32+brow,22],[32+brow,39],[32+jaw,bottom-5],[32,bottom],[36,45],[38,33]], skin.darkened(0.28))
	polygon(canvas, [[21,25],[26,20],[34,20],[33,27],[25,32],[21,39]], skin.lightened(0.18))
	rect(canvas, 32-brow-2, 33, 4, 8, skin.darkened(0.24))
	rect(canvas, 32+brow-1, 33, 4, 8, skin.darkened(0.40))
	if haircut != 5:
		var crown: int = [10, 10, 10, 15, 8, 0][haircut]
		var fringe: Array = [[44,32],[40,23],[27,25],[19,29]]
		if haircut == 1:
			fringe = [[46,28],[39,22],[30,20],[18,33]]
		elif haircut == 2:
			fringe = [[48,35],[39,22],[34,26],[24,24],[16,37]]
		elif haircut == 3:
			fringe = [[44,24],[40,21],[24,21],[20,26]]
		polygon(canvas, [[17,22],[21,crown+5],[29,crown],[41,crown+3],[46,20]] + fringe, hair)
		line(canvas, Vector2(21,20), Vector2(31,crown+4), hair.lightened(0.25))
		line(canvas, Vector2(30,crown+2), Vector2(41,crown+6), hair.lightened(0.15))
		if haircut == 4:
			for braid in range(4):
				rect(canvas, 46 + braid % 2, 32 + braid * 6, 4, 7, hair.lightened(0.14))
	for px in [22, 35]:
		var eye := int(look.get("eyes", 0))
		rect(canvas, px, 30 if eye != 3 else 29, 7, 1, hair.darkened(0.21))
		var height := 3 if eye == 2 else 2
		rect(canvas, px, 34, 7 if eye == 1 else 6, height, INK)
		rect(canvas, px + 1, 34, 3, height - 1, Color("dbc8a6"))
		rect(canvas, px + 3, 34, 2, height, iris)
		rect(canvas, px + 4, 34, 1, 1, INK)
	var nose := int(look.get("nose", 0))
	var end_nose := 41 if nose == 1 else 39
	line(canvas, Vector2(33,35), Vector2(30,end_nose), skin.lightened(0.12))
	rect(canvas, 30 if nose != 2 else 29, end_nose, 5 if nose != 2 else 7, 1, skin.darkened(0.28))
	var mouth := int(look.get("mouth", 0))
	rect(canvas, 28 - mouth, mini(bottom-3, 45), 8 + mouth * 2, 1 + mouth / 2, skin.darkened(0.48))
	match int(look.get("mark", 0)):
		1: line(canvas, Vector2(39,26), Vector2(42,33), skin.lightened(0.32))
		2:
			rect(canvas, 39, 38, 6, 4, STEEL)
			rect(canvas, 42, 39, 2, 1, TEAL)
		3:
			for freckle in [Vector2i(24,38), Vector2i(27,39), Vector2i(37,39), Vector2i(40,38)]:
				canvas.set_pixelv(freckle, skin.darkened(0.38))
	line(canvas, Vector2(24,57), Vector2(30,68), coat.darkened(0.40), 2)
	line(canvas, Vector2(40,57), Vector2(34,68), coat.lightened(0.24), 2)
	rect(canvas, 45, 65, 5, 2, AMBER)
	return canvas

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
	return texture("ship:%s:%s" % [kind, tint.to_html()], func(): return hull(kind, tint))

static func station_texture(kind: int, tint: Color) -> Texture2D:
	return texture("station:%s:%s" % [kind, tint.to_html()], func(): return station(kind, tint))

static func backdrop_texture(variant: int, inside: bool = false) -> Texture2D:
	return texture("backdrop:%s:%s" % [variant, inside], func(): return bay(variant) if inside else orbit(variant))

static func effect_texture(kind: int, phase: int, tint: Color) -> Texture2D:
	return texture("effect:%s:%s:%s" % [kind, phase, tint.to_html()], func(): return effect(kind, phase, tint))
