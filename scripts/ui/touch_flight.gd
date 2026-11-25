extends Control

const PAD_RADIUS := 44.0
const BUTTON_HEIGHT := 40.0
const LABELS := {"course":"航点","attack":"开火","inspect":"查看","shield":"护盾","boost":"助推","system":"舰载系统","vent":"排散","group":"武器组","zoom_in":"放大","zoom_out":"缩小","systems":"航行设备"}

var game
var mode := "course"
var fingers := {}
var movement := Vector2.ZERO
var aim_at := Vector2.ZERO
var has_aim := false
var firing := false
var shield := false
var boost := false

func _ready() -> void:
	custom_minimum_size = Vector2(590, 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_visibility_changed)

func reset_input() -> void:
	fingers.clear()
	movement = Vector2.ZERO
	firing = false
	shield = false
	boost = false
	has_aim = false
	queue_redraw()

func _visibility_changed() -> void:
	if not is_visible_in_tree():
		reset_input()

func pad_center() -> Vector2:
	return Vector2(66, size.y * 0.5)

func buttons() -> Dictionary:
	var rects := {}
	var gap := 7.0
	var width := minf(100.0,(size.x-154.0-4.0*gap)/6.0)
	var groups := [["course","attack","inspect","zoom_out","zoom_in","systems"],["shield","boost","system","vent","group"]]
	var starts := [126.0,size.x-12.0-3.0*width-2.0*gap]
	for g in groups.size():
		for i in groups[g].size():
			if game.galaxy and groups[g][i] in ["attack","shield","system","vent","group"]:
				continue
			var corner := Vector2(starts[g]+(i%3)*(width+gap),5.0+floori(i/3.0)*47.0)
			rects[groups[g][i]] = Rect2(corner,Vector2(width,BUTTON_HEIGHT))
	return rects

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("0d1c2a"))
	var center := pad_center()
	draw_circle(center,PAD_RADIUS,Color("1d3847"))
	draw_arc(center,PAD_RADIUS,0,TAU,48,Color("64999d"),2,true)
	draw_circle(center+movement*24.0,16.0,Color("85cfc4"))
	var layout := buttons()
	for id in layout:
		var rect: Rect2 = layout[id]
		var active: bool = id == mode or (id == "boost" and boost) or (id == "shield" and shield)
		draw_rect(rect,Color("24594f") if active else Color("193044"))
		draw_rect(rect,Color("76ccba") if active else Color("416078"),false,1.5)
		var label: String = LABELS[id]
		if id == "group" and is_instance_valid(game) and not game.world.ride().is_empty():
			var group: int = game.world.ride().battle.group
			label = "齐射" if group == 0 else "武器组 %d" % group
		draw_string(get_theme_default_font(),rect.position+Vector2(0,27),label,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,17,Color("e6efef"))

func handle(event: InputEvent) -> bool:
	if not is_visible_in_tree() or not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return false
	var point: Vector2 = event.position
	var index: int = event.index
	if event is InputEventScreenDrag:
		if not fingers.has(index):
			return false
		update_finger(fingers[index],point)
		return true
	if not event.pressed or event.canceled:
		if not fingers.has(index):
			return false
		var role: String = fingers[index]
		fingers.erase(index)
		if role == "pad":
			movement = Vector2.ZERO
		if role == "fire":
			firing = false
		shield = "shield" in fingers.values()
		boost = "boost" in fingers.values()
		queue_redraw()
		return true
	var local := get_global_transform_with_canvas().affine_inverse()*point
	if Rect2(Vector2.ZERO,size).has_point(local):
		var role := "strip"
		if local.distance_to(pad_center()) <= PAD_RADIUS+12 and "pad" not in fingers.values():
			role = "pad"
		else:
			var layout := buttons()
			for id in layout:
				if layout[id].has_point(local):
					role = id
					break
		fingers[index] = role
		press_button(role)
		update_finger(role,point)
		return true
	if not game.canvas.get_global_rect().has_point(point):
		return false
	var target_point := world_point(point)
	if mode == "attack" and not game.galaxy:
		if "fire" in fingers.values():
			fingers[index] = "tap"
			return true
		fingers[index] = "fire"
		var id: int = game.flight.target_at(game.world.ride(),target_point,52.0,true)
		game.selected_target = id
		firing = true
		game.fire_requested = game.speed > 0
		update_finger("fire",point)
	elif mode == "inspect":
		fingers[index] = "tap"
		var click := InputEventMouseButton.new()
		click.position = point
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = true
		game.entity_menus.origin = game.get_window()
		game.entity_menus.anchor = point
		game.InputController.handle(game,click)
	else:
		fingers[index] = "tap"
		game.set_waypoint(target_point)
	return true

func world_point(viewport_point: Vector2) -> Vector2:
	return game.canvas.location(game.canvas.get_global_transform_with_canvas().affine_inverse()*viewport_point)

func update_finger(role: String, point: Vector2) -> void:
	if role == "pad":
		var delta := get_global_transform_with_canvas().affine_inverse()*point-pad_center()
		movement = (delta/PAD_RADIUS).limit_length()
		if movement.length() < 0.12:
			movement = Vector2.ZERO
		queue_redraw()
	elif role == "fire":
		aim_at = point
		has_aim = true

func press_button(role: String) -> void:
	var ship: Dictionary = game.world.ride()
	match role:
		"course","inspect","attack":
			mode = role
		"shield": shield = true
		"boost": boost = true
		"zoom_in","zoom_out":
			var zoom := clampf(game.canvas.zoom*(1.2 if role=="zoom_in" else 1.0/1.2),0.18,1.35 if game.galaxy else 1.65)
			if game.galaxy: game.galaxy_zoom = zoom
			else: game.flight_zoom = zoom
			game.canvas.zoom = zoom
			game.canvas.queue_redraw()
		"group":
			for offset in range(1,5):
				if game.flight.select_group(ship,(int(ship.battle.group)+offset)%4,false):
					break
		"systems":
			open_equipment(ship)
		"vent":
			if game.speed == 1 and not game.galaxy and game.Battle.vent(ship):
				game.world.combat_event("vent",ship.pos,ship.system)
		"system":
			if game.speed == 1 and not game.galaxy:
				var aim := world_point(aim_at) if has_aim else Vector2.INF
				if game.Battle.system(game.world,ship,movement,aim,game.selected_target):
					game.say(game.Battle.system_label(ship))
	queue_redraw()

func open_equipment(ship: Dictionary) -> void:
	var menu := PopupMenu.new()
	add_child(menu)
	menu.add_item("主动传感器扫描",KEY_R)
	menu.add_item("恢复标准航行" if ship.battle.get("silent_running",false) else "转入静默航行",KEY_H)
	menu.add_item("关闭应答器" if ship.transponder else "开启应答器",KEY_T)
	if not game.galaxy:
		menu.add_item("切换当前武器组自动索敌",KEY_Q)
	menu.id_pressed.connect(func(key: int):
		if key == KEY_Q:
			game.flight.select_group(ship,ship.battle.group,true)
			game.say("已切换自动索敌。")
		else:
			var press := InputEventKey.new()
			press.keycode = key
			press.pressed = true
			game.InputController.handle(game,press))
	menu.popup_hide.connect(menu.queue_free,CONNECT_ONE_SHOT)
	var anchor: Rect2 = buttons().systems
	menu.popup_on_parent(Rect2i(Vector2i(get_global_transform_with_canvas()*anchor.position),menu.get_contents_minimum_size()))
