extends BaseButton

signal class_selected(kind: int)

const Hulls = preload("res://hull_catalog.gd")
const Pixels = preload("res://art/pixel_art.gd")
const GRID := 25.0

var selected_kind := -1
var touch_selection := false
var hovered_col := -1
var vessels := []
var textures := []
var outlines: Array[Rect2] = []
var col_rects: Array[Rect2] = []

static func dimensions(kind: int) -> Rect2:
	var points: PackedVector2Array = Hulls.MODELS[kind].bounds
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect

func configure(kind: int) -> void:
	selected_kind = kind
	hovered_col = -1
	vessels.clear()
	textures.clear()
	outlines.clear()
	col_rects.clear()
	for tier in range(Hulls.CLASSES.size()):
		var index := kind if kind >= 0 and Hulls.MODELS[kind].size == tier else Hulls.kind_for_reference(Hulls.CLASSES[tier].representative)
		vessels.append(index)
		textures.append(Pixels.ship_texture(index, Color(Hulls.MODELS[index].paint)))
		outlines.append(dimensions(index))
	custom_minimum_size = Vector2(400, 176)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	queue_redraw()

func _on_mouse_exited() -> void:
	if hovered_col != -1:
		hovered_col = -1
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		tooltip_text = ""
		queue_redraw()

func _col_at(pos: Vector2) -> int:
	for i in range(col_rects.size()):
		if col_rects[i].has_point(pos):
			return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if vessels.is_empty():
		return
	if event is InputEventMouseMotion and not touch_selection:
		var idx := _col_at(event.position)
		if idx != hovered_col:
			hovered_col = idx
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if idx >= 0 else Control.CURSOR_ARROW
			if idx >= 0:
				var m: Dictionary = Hulls.MODELS[vessels[idx]]
				tooltip_text = "点击切换至 %s（%s · DP %d）" % [m.name, Hulls.CLASS_NAMES[idx], int(m.dp)]
			else:
				tooltip_text = ""
			queue_redraw()
	elif not touch_selection and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _col_at(event.position)
		if idx >= 0 and idx < vessels.size():
			accept_event()
			class_selected.emit(vessels[idx])

func _pressed() -> void:
	if touch_selection:
		var idx := _col_at(get_local_mouse_position())
		if idx >= 0:
			class_selected.emit(vessels[idx])

func _draw_brackets(rect: Rect2, color: Color, arm: float = 7.0) -> void:
	var p0 := rect.position
	var p1 := rect.position + Vector2(rect.size.x, 0)
	var p2 := rect.position + rect.size
	var p3 := rect.position + Vector2(0, rect.size.y)
	draw_line(p0, p0 + Vector2(arm, 0), color, 1.5)
	draw_line(p0, p0 + Vector2(0, arm), color, 1.5)
	draw_line(p1, p1 + Vector2(-arm, 0), color, 1.5)
	draw_line(p1, p1 + Vector2(0, arm), color, 1.5)
	draw_line(p2, p2 + Vector2(-arm, 0), color, 1.5)
	draw_line(p2, p2 + Vector2(0, -arm), color, 1.5)
	draw_line(p3, p3 + Vector2(arm, 0), color, 1.5)
	draw_line(p3, p3 + Vector2(0, -arm), color, 1.5)

func _draw() -> void:
	if vessels.is_empty():
		return
	var font := get_theme_default_font()
	var ink := Color("dfebea")
	var muted := Color("8ca7b3")
	var highlight := Color("ecc78a")
	var cyan := Color("63d2e4")
	var header_h := 28.0
	var footer_h := 40.0

	# Panel backdrop & header bar
	draw_rect(Rect2(Vector2.ZERO, size), Color("091620"))
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, header_h)), Color("0e2230"))
	draw_line(Vector2(0, header_h), Vector2(size.x, header_h), Color("1e394a"), 1.0)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("264557"), false, 1.0)
	draw_string(font, Vector2(12, 19), "舰体比例尺 · 全舰级同比例对照", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)

	var world_width := 0.0
	var world_height := 0.0
	for bounds in outlines:
		world_width += bounds.size.x
		world_height = maxf(world_height, bounds.size.y)

	# All four silhouettes and the ruler share one world-to-panel transform.
	var body_h := maxf(24.0, size.y - header_h - footer_h)
	var magnification := minf((size.x - 104.0) / maxf(1.0, world_width), (body_h - 14.0) / maxf(1.0, world_height))
	var spacing := (size.x - world_width * magnification) / 4.0
	var center_y := header_h + body_h * 0.5

	# Blueprint grid
	var grid := maxf(8.0, GRID * magnification)
	for x in range(ceili(size.x / grid)):
		var gx := x * grid
		var major := x % 2 == 0
		draw_line(Vector2(gx, header_h), Vector2(gx, size.y - footer_h), Color("152c38" if major else "10212b"))
	draw_line(Vector2(0, center_y), Vector2(size.x, center_y), Color("244352"))
	draw_line(Vector2(0, size.y - footer_h), Vector2(size.x, size.y - footer_h), Color("1a3240"))

	# Scale ruler in header
	var rx1 := size.x - 14.0
	var rx0 := rx1 - grid
	draw_line(Vector2(rx0, 14.0), Vector2(rx1, 14.0), highlight, 2.0)
	draw_line(Vector2(rx0, 10.0), Vector2(rx0, 18.0), highlight, 1.5)
	draw_line(Vector2(rx1, 10.0), Vector2(rx1, 18.0), highlight, 1.5)
	draw_string(font, Vector2(rx0 - 134.0, 19.0), "25 航行单位", HORIZONTAL_ALIGNMENT_RIGHT, 126.0, 12, muted)

	col_rects.clear()
	var cursor := 0.0
	for i in range(vessels.size()):
		var kind: int = vessels[i]
		var model: Dictionary = Hulls.MODELS[kind]
		var bounds := outlines[i]
		var column_width := bounds.size.x * magnification + spacing
		var col_rect := Rect2(cursor, header_h, column_width, size.y - header_h)
		col_rects.append(col_rect)
		var is_selected := kind == selected_kind
		var is_hovered := i == hovered_col

		if is_selected:
			draw_rect(Rect2(cursor + 2.0, header_h + 1.0, column_width - 4.0, size.y - header_h - 3.0), Color(0.11, 0.22, 0.30, 0.52))
			draw_line(Vector2(cursor + 4.0, size.y - 2.0), Vector2(cursor + column_width - 4.0, size.y - 2.0), highlight, 2.5)
		elif is_hovered:
			draw_rect(Rect2(cursor + 2.0, header_h + 1.0, column_width - 4.0, size.y - header_h - 3.0), Color(0.09, 0.19, 0.26, 0.35))
			draw_line(Vector2(cursor + 4.0, size.y - 2.0), Vector2(cursor + column_width - 4.0, size.y - 2.0), Color(cyan, 0.7), 1.5)

		if i > 0:
			draw_line(Vector2(cursor, header_h + 6.0), Vector2(cursor, size.y - 6.0), Color("162c38"), 1.0)

		var center := Vector2(cursor + column_width / 2.0, center_y)
		var origin := center - bounds.get_center() * magnification
		var pixels: Texture2D = textures[i]
		var factor := float(model.sprite_scale) * magnification
		var tex_rect := Rect2(origin - model.sprite_center * factor, pixels.get_size() * factor)
		draw_texture_rect(pixels, tex_rect, false)

		if is_selected:
			var pad := Vector2(6.0, 6.0)
			var frame := Rect2(origin + bounds.position * magnification - pad, bounds.size * magnification + pad * 2.0)
			_draw_brackets(frame, Color(highlight, 0.85), 6.0)

		var name_color := highlight if is_selected else (ink if is_hovered else muted)
		draw_string(font, Vector2(cursor, size.y - 22.0), model.name, HORIZONTAL_ALIGNMENT_CENTER, column_width, 13, name_color)
		draw_string(font, Vector2(cursor, size.y - 6.0), "%s · %.0fm · DP%d" % [Hulls.CLASS_NAMES[i].trim_suffix("舰"), bounds.size.x, int(model.dp)], HORIZONTAL_ALIGNMENT_CENTER, column_width, 11, cyan if is_selected else muted)
		cursor += column_width
