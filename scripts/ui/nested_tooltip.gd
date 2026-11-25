extends CanvasLayer

const Topics = preload("res://data/campaign/glossary.json")
var panel := PanelContainer.new()
var column := VBoxContainer.new()
var history: Array[String] = []
var pinned := false
var close_at := 0

func _ready() -> void:
	layer = 8
	add_child(panel)
	panel.add_child(column)
	panel.custom_minimum_size.x = 296
	panel.theme = preload("res://scripts/ui/bridge_theme.tres")
	panel.hide()
	panel.mouse_entered.connect(func(): close_at = 0)
	panel.mouse_exited.connect(schedule_close)
	set_process(false)

func bind(control: Control, topic: String) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.mouse_entered.connect(func():
		if pinned:
			return
		close_at = 0
		history.clear()
		open(topic,control.get_global_rect().end))
	control.mouse_exited.connect(schedule_close)

func schedule_close() -> void:
	if not pinned:
		close_at = Time.get_ticks_msec() + 350
		set_process(true)

func _process(_delta: float) -> void:
	if close_at and Time.get_ticks_msec() >= close_at:
		hide_card()
	elif not close_at:
		set_process(false)

func hide_card() -> void:
	panel.hide()
	history.clear()
	close_at = 0
	pinned = false
	set_process(false)

func handle(event: InputEvent) -> bool:
	if not panel.visible:
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
		pinned = not pinned
		close_at = 0
		rebuild()
		return true
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		hide_card()
		return true
	return false

func open(id: String, origin: Vector2) -> void:
	if not Topics.data.has(id):
		return
	history.append(id)
	close_at = 0
	rebuild()
	panel.show()
	panel.reset_size()
	var viewport_size := get_viewport().get_visible_rect().size
	panel.position = origin.clamp(Vector2.ZERO, (viewport_size-panel.size).max(Vector2.ZERO))

func rebuild() -> void:
	for item in column.get_children():
		column.remove_child(item)
		item.queue_free()
	var entry: Dictionary = Topics.data[history.back()]
	var heading := Label.new()
	heading.text = entry.title + ("　已锁定" if pinned else "　中键锁定")
	column.add_child(heading)
	var copy := Label.new()
	copy.custom_minimum_size.x = 270
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.text = entry.body
	column.add_child(copy)
	for next in entry.links:
		var link := Button.new()
		link.text = Topics.data[next].title
		link.pressed.connect(func(): pinned = true; open(next,panel.position))
		column.add_child(link)
	if history.size() > 1:
		var back := Button.new()
		back.text = "返回上一条"
		back.pressed.connect(func(): history.pop_back(); rebuild())
		column.add_child(back)
