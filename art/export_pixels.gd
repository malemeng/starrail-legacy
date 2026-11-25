extends SceneTree

const Pixels = preload("res://art/pixel_art.gd")
const HERE := "res://art"
var failed := false

func _initialize() -> void:
	var ships := Pixels.atlas_hulls()
	var parts := Pixels.blank(32 * 4, 32 * 3)
	var props := Pixels.blank(32 * 4, 24 * 3)
	var colors := [Pixels.AMBER, Pixels.TEAL, Pixels.RUST]
	for palette in range(colors.size()):
		for module in range(4):
			Pixels.stamp(parts, Pixels.station_part(module, colors[palette]), Vector2i(module * 32, palette * 32))
			Pixels.stamp(props, Pixels.props(module, colors[palette]), Vector2i(module * 32, palette * 24))
	write(ships, "hulls")
	write(parts, "station_parts")
	write(props, "dock_props")
	var stations := Pixels.blank(80 * 4, 72)
	for module in range(4):
		Pixels.stamp(stations, Pixels.station(module, colors[module % 3]), Vector2i(80 * module, 0))
	write(stations, "station_examples")
	var faces := Pixels.blank(128 * 4, 144 * 2)
	for index in range(8):
		var look := {"face": index%4, "skin": [1,3,2,4,0,2,4,3][index],
			"cut":[0,1,4,3,2,5,0,1][index], "hair":[0,1,3,2,0,5,2,4][index],
			"eyes":index%4,"iris":index%5,"nose":index%3,"mouth":index%3,"mark":index%4,
			"uniform":index,"uniform_style":[0,1,0,1,1,2,2,2][index],"crest":(index+1)*5,
			"age_band":[0,0,2,0,0,1,0,1][index],"regalia":index in [2,7],
			"stress_tier":2 if index == 5 else 0,"wounded":index == 6}
		Pixels.stamp(faces, Pixels.portrait(look), Vector2i(index%4*128,index/4*144))
	write(faces, "portrait_examples")
	var effects := Pixels.blank(24 * 4, 24 * 3)
	for kind in range(3):
		for phase in range(4):
			Pixels.stamp(effects, Pixels.effect(kind, phase, Pixels.AMBER if kind == 1 else Pixels.TEAL), Vector2i(phase * 24, kind * 24))
	write(effects, "effects")
	for variant in range(3):
		write(Pixels.orbit(variant), "orbit_%s" % variant)
		write(Pixels.bay(variant), "bay_%s" % variant)
	var showcase := Pixels.blank(960, 626)
	showcase.fill(Color("101b2a"))
	Pixels.stamp(showcase, Pixels.bay(0), Vector2i.ZERO, 3)
	var berth_x := 599
	for kind in [0,1,7]:
		var model: Dictionary = Pixels.Hulls.MODELS[kind]
		var example := Pixels.hull(kind,Color(model.paint))
		var scale_factor := float(model.sprite_scale) * 0.68
		example.resize(roundi(example.get_width()*scale_factor),roundi(example.get_height()*scale_factor),Image.INTERPOLATE_NEAREST)
		Pixels.stamp(showcase,example,Vector2i(berth_x,481-example.get_height()/2))
		berth_x += example.get_width()+13
	var face_strip := faces.get_region(Rect2i(0,0,512,144))
	face_strip.resize(256,72,Image.INTERPOLATE_NEAREST)
	Pixels.stamp(showcase, face_strip, Vector2i(22, 540))
	Pixels.stamp(showcase, stations, Vector2i(302, 543))
	Pixels.stamp(showcase, effects, Vector2i(825, 546))
	write(showcase, "pixel_preview")
	quit(1 if failed else 0)

func write(canvas: Image, name_text: String) -> void:
	var status := canvas.save_png(HERE.path_join(name_text + ".png"))
	if status != OK:
		failed = true
		printerr("Could not write ", name_text, ": ", status)
