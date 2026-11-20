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
	var faces := Pixels.blank(64 * 4, 72)
	for index in range(4):
		var look := {"face": index, "skin": index + 1, "cut": [1, 3, 4, 2][index],
			"hair": [0, 3, 4, 2][index], "eyes": index, "iris": index, "nose": index % 3,
			"mouth": index % 3, "wear": [0, 3, 1, 2][index], "mark": index}
		Pixels.stamp(faces, Pixels.portrait(look), Vector2i(index * 64, 0))
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
	Pixels.stamp(showcase, ships.get_region(Rect2i(0, 0, 192, 40)), Vector2i(575, 466), 2)
	Pixels.stamp(showcase, faces, Vector2i(22, 540))
	Pixels.stamp(showcase, stations, Vector2i(302, 543))
	Pixels.stamp(showcase, effects, Vector2i(825, 546))
	write(showcase, "pixel_preview")
	quit(1 if failed else 0)

func write(canvas: Image, name_text: String) -> void:
	var status := canvas.save_png(HERE.path_join(name_text + ".png"))
	if status != OK:
		failed = true
		printerr("Could not write ", name_text, ": ", status)
