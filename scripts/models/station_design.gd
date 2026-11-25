extends RefCounted

const CORE := Vector2i.ZERO
const AUTO := Vector2i(999,999)
const GRID := Rect2i(-2,-2,5,3)
const NEIGHBORS := [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]
const DEFAULT_CELLS := [
	Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i(-1,-1),Vector2i(1,-1),
	Vector2i(0,-2),Vector2i(-2,0),Vector2i(2,0),Vector2i(-2,-1),Vector2i(2,-1),
	Vector2i(-1,-2),Vector2i(1,-2),Vector2i(-2,-2),Vector2i(2,-2)
]

## One module per economic slot. A paid construction site reserves its space immediately.
static func kinds(station: Dictionary) -> Array:
	var result: Array = station.get("modules",[station.module]).duplicate()
	if station.get("build",0) > 0 and result.is_empty():
		result.append(station.module)
	if station.get("expansion",0) > 0:
		result.append(station.extension)
	return result

static func cells(station: Dictionary) -> Array:
	var count := kinds(station).size()
	if station.has("design_cells"):
		return station.design_cells.duplicate()
	return DEFAULT_CELLS.slice(0,count)

## The forward row is kept open for the berth. Only orthogonal neighbors share a passage.
static func issue(layout: Array) -> String:
	if layout.is_empty():
		return "至少需要一个产业模块。"
	var occupied := {CORE:true}
	for cell: Variant in layout:
		if not cell is Vector2i or not GRID.has_point(cell):
			return "模块须安装在船坞网格内，泊位前方须留空。"
		if occupied.has(cell):
			return "核心或其他模块已经占用该格。"
		occupied[cell] = true
	var connected := {CORE:true}
	var queue: Array[Vector2i] = [CORE]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset: Vector2i in NEIGHBORS:
			var neighbor := cell + offset
			if occupied.has(neighbor) and not connected.has(neighbor):
				connected[neighbor] = true
				queue.append(neighbor)
	if occupied.size() != connected.size():
		return "每个模块都需要通过相邻边连接到核心。"
	return ""
