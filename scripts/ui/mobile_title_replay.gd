extends TextureRect

const SHEET := preload("res://art/mobile_title_replay.webp")
const GRID := Vector2i(4,8)
const FRAME := Vector2i(448,252)

var frame := 0
var tile := AtlasTexture.new()
var timer := Timer.new()
var previous_low_processor_usage: bool

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tile.atlas = SHEET
	tile.filter_clip = true
	tile.region = Rect2i(Vector2i.ZERO,FRAME)
	texture = tile
	previous_low_processor_usage = OS.low_processor_usage_mode
	OS.low_processor_usage_mode = true
	timer.wait_time = 1.0/6.0
	timer.timeout.connect(next_frame)
	add_child(timer)
	timer.start()

func next_frame() -> void:
	frame = (frame+1) % (GRID.x*GRID.y)
	var cell := Vector2i(frame%GRID.x,floori(float(frame)/GRID.x))
	tile.region = Rect2i(cell*FRAME,FRAME)

func _exit_tree() -> void:
	OS.low_processor_usage_mode = previous_low_processor_usage
