extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
enum { RAIL, HOWITZER, PULSE, LANCE, MISSILE, DEFENSE }
const SIZE := Vector2(24,15)
const PIVOT := Vector2(7.5,7.5)
const DISABLED := Color("987569")
const CASINGS := ["60828c","866d5c","4a8788","716c92","697853","827457"]
const ACCENTS := ["80d4df","e6aa69","63e8e1","baa1ff","fa8767","ffd06c"]
# Viewed from above, every mount points right. The bearing is shared across
# sprites so training a weapon and previewing it on the refit bench agree.
const PATTERNS := [
	[
		".....xxxxx",
		"...xxhhhmmxx",
		"..xhhmmssmhx..xx....xx",
		".xlhmssDDsmhxxhhxxxxhhxx",
		".xhmAAmsDmmhhhlhhmmhhlhx",
		".xmAAAmssDsAAAAhmmmAAmsx",
		".xsDDmshmmsxxxxxxxxxxxxx",
		".xshhmshmmx",
		".xsDDmsmmmsxxxxxxxxxxxxx",
		".xsAAAmssDsmmAAmsssAAmsx",
		"..xsAAmDDmmmmmhhmmmhmmhx",
		"...xssmssmsxxshhxxxxhhxx",
		"....xxsssxx...xx....xx",
		"......xxx",
	],
	[
		".....xxxxxx",
		"...xxhhhhhhx",
		"..xlhmmmsmmhx....xxxxx",
		".xhmmAAAmssmhxx.xhlllhx",
		".xhmAmmAsDDmhhlxhmmmmmsx",
		".xhmAAAmshmhAAhmmDDsAAhx",
		".xhhmhsDshmhhhhmmDDmmmsx",
		".xmsshsDshmssssmmDDmDDsx",
		".xmssmmssmmssssmmDDmDDsx",
		".xsAhmhhmssmAAhmmDDmAmsx",
		"..xsmAAAmsmssxhxsmmmmmsx",
		"..xssmmmsmmsxx..xssmssx",
		"...xxssssssx.....xxxxx",
		".....xxxxxx",
	],
	[
		".....xxxxx...xxxx",
		"...xxhhhmmx.xhAAhx",
		"..xhhmmmsmhxhAAAlhx",
		".xhmmAAmmsshhAlhhx",
		".xhmAmmAmsmhhsDxx...x",
		".xhmAmmAmmhAmmhx...xAx",
		".xhhhmmhshAAAAlhhxxAlAx",
		".xsDDmmsmhAllllllllAllx",
		".xsDDmmsmhAAAAlhhxxAlAx",
		".xsmmmmsssAmmmhx...xAx",
		"..xsmAAmsmsshsDxx...x",
		"..xssmmssmsxsAmmhx",
		"...xxsssxxx.xmAAmsx",
		".....xxx.....xxxx",
	],
	[
		".....xxxxx",
		"...xxhAAmhxx",
		"..xhhAmmmsmmxx",
		"..xmmshhmmmhhmxx",
		"...xDmmsDshmmmhhxx",
		"...xsmAmsmsxxmmhhhxx",
		"..xxhmmmhAmmDxxmhhhhxx",
		".xlhAAAlAAAAAlllAAlllllx",
		".xmhAAAmAAAAmAAAhhAmmxx",
		"..xxshmssmsDDxxxxxxxx",
		"...xsmAmsssxxssmmxx",
		"...xDmmssmmmssxxx",
		"..xmmsmmssmmxx",
		"..xssAmmssxx",
		"....xxxxx",
	],
	[
		"..xxxxxxxxxxxxx",
		".xhhhhhhhhhhhmxx",
		".xhmmshmmshmmshhx",
		".xhDDshDDshDDsmhAx",
		".xhAlshAlshAlsmhAx",
		".xhAmshAmshAmsmhx",
		".xhxxshxxshxxsmhx",
		".xmmAAmmmmmmmAAmsx",
		".xhhhhhhhhhhhmshx",
		".xhDDshDDshDDsmhAx",
		".xhAlshAlshAlsmhAx",
		".xhAmshAmshAmsmhx",
		".xsxxssxxssxxssmx",
		"..xsssssssssssxx",
		"...xxxxxxxxxxx",
	],
	[
		"....xxxxx",
		"..xxhhhmmxxx",
		".xhAAhmhhmhhxx",
		".xhAAmmsDmhmmhhx",
		".xhmDDmmmsssxxxx",
		".xhAAhmmsDmmhmmmmx",
		".xsAAmmhmmDDxxxxxx",
		".xsmmmhhmmmhhhmmhhhhhx",
		".xshDshsmsmmssmmsssmmx",
		".xsAAmmhsDmmxxxxxxxxxx",
		".xsAAmmmssmmhmmmx",
		"..xsshhmmmssxxxxx",
		"...xssssssx",
		"....xxxxxx",
	]
]
static var textures: Array[Texture2D] = []
static var profiles := {}

static func profile(id: String) -> Dictionary:
	if profiles.has(id): return profiles[id]
	var spec: Dictionary = Hulls.WEAPONS[id]
	var family := RAIL
	if spec.get("pd",false): family = DEFENSE
	elif spec.get("missile",false): family = MISSILE
	elif id.get_slice("_",0) == "lance" or spec.get("beam",false): family = LANCE
	elif spec.get("family","") == "energy": family = PULSE
	elif spec.type == 1: family = HOWITZER
	var unit: float = [0.48,0.66,0.86][clampi(int(spec.mount)-1,0,2)]
	profiles[id] = {"family":family,"unit":unit}
	return profiles[id]

static func texture(family: int) -> Texture2D:
	if textures.is_empty(): textures.resize(PATTERNS.size())
	if textures[family] == null:
		var palette := {"x":Color("121e28"),"s":Color("374955"),"m":Color(CASINGS[family]),"h":Color("a6b9ba"),"l":Color("e6f0e4"),"D":Color("20313d"),"A":Color(ACCENTS[family])}
		var bitmap := Image.create_empty(int(SIZE.x),int(SIZE.y),false,Image.FORMAT_RGBA8)
		for y in PATTERNS[family].size():
			var line: String = PATTERNS[family][y]
			for x in line.length():
				if line[x] != ".": bitmap.set_pixel(x,y,palette[line[x]])
		textures[family] = ImageTexture.create_from_image(bitmap)
	return textures[family]

static func pose(mount: Dictionary, weapon: Dictionary, angle: float, recoil: float) -> Transform2D:
	var unit: float = weapon.unit
	var transform := Transform2D(angle,Vector2.ONE*unit,0,mount.offset)
	# Center the sprite quad on its bearing; visible recoil moves along the bore.
	transform.origin = transform*(SIZE*0.5-PIVOT-Vector2.RIGHT*recoil*2.5)
	return transform

static func tint(disabled: bool, recoil: float) -> Color:
	if disabled: return DISABLED
	return Color.WHITE*(1.0+0.25*recoil) if recoil > 0.0 else Color.WHITE

static func draw_mount(canvas: CanvasItem, transform: Transform2D, family: int, color: Color) -> void:
	canvas.draw_set_transform_matrix(transform)
	canvas.draw_texture_rect(texture(family),Rect2(-SIZE*0.5,SIZE),false,color)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
