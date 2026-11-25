extends Control

const Design = preload("res://scripts/models/station_design.gd")
const Geometry = preload("res://scripts/models/station_geometry.gd")
const Art = preload("res://scripts/ui/station_art.gd")

signal cell_pressed(cell: Vector2i)
var station: Dictionary
var cells: Array = []
var selected := -1
var tint := Color.WHITE

func pitch() -> float:
	return minf(size.x / (Design.GRID.size.x + 0.5),size.y / (Design.GRID.size.y + 1.5))

func core() -> Vector2:
	return size * 0.5 - Vector2(Design.GRID.get_center()) * pitch() - Vector2.DOWN * pitch() * 0.35

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := Vector2i(((event.position-core())/pitch()).round())
		if Design.GRID.has_point(cell):
			cell_pressed.emit(cell)
			accept_event()

func _draw() -> void:
	if station.is_empty() or size.x <= 0 or size.y <= 0:
		return
	var spacing := pitch()
	var origin := core()
	draw_rect(Rect2(Vector2.ZERO,size),Color("0c1924"))
	var grid_size := Vector2.ONE * spacing
	for y in range(Design.GRID.position.y,Design.GRID.end.y):
		for x in range(Design.GRID.position.x,Design.GRID.end.x):
			var rect := Rect2(origin+(Vector2(x,y)-Vector2.ONE*0.5)*spacing,grid_size)
			draw_rect(rect,Color("2b4658"),false,1.0)
	var geom := Geometry.layout(station,cells)
	var scale_factor: float = spacing / geom.step
	Art.draw_layout(self,geom,origin-Vector2(geom.core_pos)*scale_factor,0.0,scale_factor,tint)
	if selected in range(cells.size()):
		var at := origin + Vector2(cells[selected]) * spacing
		draw_rect(Rect2(at-grid_size*0.5, grid_size).grow(-2.0),Color("efbb79"),false,2.0)
	var berth := origin + Vector2.DOWN * spacing * 0.88
	draw_string(get_theme_default_font(),berth+Vector2(-75,14),"泊位进出方向 ↓",HORIZONTAL_ALIGNMENT_CENTER,150,13,Color("91d9d6"))
