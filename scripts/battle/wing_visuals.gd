extends Node2D

const Wings = preload("res://scripts/battle/wings.gd")

# Forward is right. A formation contains exactly the surviving craft in its squadron.
const PATTERNS := {
	"interceptor": [".......oo.........","......olm.........","....oolmm.........","..oommmmlooo......","..xshmmlmllhhooo..","efshmAAAccccchhhoo","..xshmmlmllhhooo..","..oommmmlooo......","....oolmm.........","......olm.........",".......oo........."],
	"fighter": ["...oo.............","...olloo..........","....ommloo........","..oommmmlhooo.....","efsmmshhmlhhlloo..","efsmmAAAAcccclllho","efsmmshhmlhhlloo..","..oommmmlhooo.....","....ommloo........","...olloo..........","...oo............."],
	"bomber": ["......oooo........","...oohmllhoo......","..ohmmmssmmlloo...","efshmmmAAmmlhhhoo.","..ohssmllmssmllho.","efshmmAAAAccccllho","..ohssmllmssmllho.","efshmmmAAmmlhhhoo.","..ohmmmssmmlloo...","...oohmllhoo......","......oooo........"],
	"support": ["....ooooo.........","..oohmmmhooo......","..ommmsmmmlloo....","efshhsslhhmmlloo..","..ossmAAmmccchho..","efshhsslhhmmlloo..","..ommmsmmmlloo....","..oohmmmhooo......","....ooooo........."]
}
const PALETTE := {"o":Color("21313a"),"x":Color("512f29"),"s":Color("53656c"),"m":Color("91a5ac"),"l":Color("c1d4d4"),
	"h":Color("dbe5dd"),"A":Color("d69950"),"c":Color("72d5e9"),"f":Color("ffbd64"),"e":Color("eb783c")}
var batches := {}
var visible_craft := 0
static var textures := {}

static func sprite_for(role: String) -> Texture2D:
	if not textures.has(role):
		var sprite := Image.create_empty(18,11,false,Image.FORMAT_RGBA8)
		var rows: Array = PATTERNS.get(role,PATTERNS.fighter)
		for y in rows.size():
			for x in rows[y].length():
				var pixel: String = rows[y][x]
				if pixel != ".":
					sprite.set_pixel(x,y,PALETTE[pixel])
		textures[role] = ImageTexture.create_from_image(sprite)
	return textures[role]

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for role in PATTERNS:
		var node := MultiMeshInstance2D.new()
		node.texture = sprite_for(role)
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		node.multimesh.use_colors = true
		var mesh := QuadMesh.new()
		mesh.size = Vector2(18,11)
		node.multimesh.mesh = mesh
		add_child(node)
		batches[role] = node.multimesh

func sync(flights: Array) -> void:
	var poses := {}
	var colors := {}
	visible_craft = 0
	for flight in flights:
		var wing: Dictionary = flight[0]
		var role := str(wing.role) if batches.has(wing.role) else "fighter"
		var heading := float(wing.get("heading",flight[1]))
		var transforms: Array = poses.get_or_add(role,[])
		var tones: Array = colors.get_or_add(role,[])
		var color := Color.WHITE.lerp(flight[2],0.25)
		if wing.has("craft"):
			for unit: Dictionary in wing.craft:
				if unit.sortie and unit.hp>0:
					transforms.append(Transform2D(unit.heading,unit.pos)*Transform2D.FLIP_Y)
					tones.append(color)
					visible_craft += 1
			continue
		for i in int(wing.get("count_live",wing.count)):
			transforms.append(Transform2D(heading,Wings.craft_position(wing,heading,i))*Transform2D.FLIP_Y)
			tones.append(color)
			visible_craft += 1
	for role in batches:
		var mesh: MultiMesh = batches[role]
		var transforms: Array = poses.get(role,[])
		if mesh.instance_count < transforms.size():
			mesh.instance_count = nearest_po2(maxi(transforms.size(),8))
		for i in transforms.size():
			mesh.set_instance_transform_2d(i,transforms[i])
			mesh.set_instance_color(i,colors[role][i])
		mesh.visible_instance_count = transforms.size()
