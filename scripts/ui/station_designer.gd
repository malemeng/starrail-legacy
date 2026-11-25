extends Window

const Grid = preload("res://scripts/ui/station_design_grid.gd")
const Design = preload("res://scripts/models/station_design.gd")
const Economy = preload("res://economy.gd")
const Celestial = preload("res://celestial.gd")
const Art = preload("res://scripts/ui/station_art.gd")

var game
var station: Dictionary
var draft: Dictionary
var design_mode: String
var cells: Array
var selected := 0
var current_kind := 0
var old_speed := 0
var grid: Grid
var installed: ItemList
var status: Label
var commit: Button
var tint: Color
var site_index := -1
var site_navigation: Button

static func open(game_screen, entry: String, live_station: Dictionary = {}, kind: int = 0) -> Window:
	var editor := new()
	editor.game = game_screen
	editor.design_mode = entry
	editor.current_kind = kind
	editor.station = live_station
	editor.old_speed = game_screen.speed
	if live_station.has("planet_index"):
		editor.free()
		return null
	if entry == "foundation":
		var vessel: Dictionary = game_screen.world.ride()
		var system_id: int = game_screen.current_system()
		var point: Vector2 = vessel.get("pos",Vector2.ZERO)
		var region: Dictionary = game_screen.world.systems[system_id]
		var orbit := Celestial.orbit_at(region,point)
		var heading := point.angle_to_point(region.planets[orbit].pos) if orbit >= 0 else 0.0
		editor.station = {"pos":point,"berth_heading":heading,"module":kind,"build":1,"modules":[],
			"system":system_id,"id":game_screen.world.next_id,"name":"新轨道工地","flag":game_screen.world.active().flag}
	elif live_station.is_empty():
		editor.free()
		return null
	elif not game_screen.world.oversees(live_station.owner) or game_screen.world.ride().get("dock",0) != live_station.id:
		editor.design_mode = "view"
	game_screen.set_speed(0)
	editor.transient = true
	editor.exclusive = true
	editor.visible = false
	editor.min_size = Vector2i(580,370)
	editor.title = "空间站设计"
	game_screen.add_child(editor)
	editor.make_ui()
	editor.popup_centered_clamped(Vector2i(920,570),0.92)
	return editor

func make_ui() -> void:
	var panel := PanelContainer.new()
	panel.theme = game.theme
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,14)
	panel.add_child(margin)
	var body = game.vbox(margin)
	game.title(body,station.name,22,game.GOLD)
	var split = game.hbox(body)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation",16)
	grid = Grid.new()
	grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(grid)
	grid.cell_pressed.connect(click_cell)
	var controls = game.vbox(split)
	controls.custom_minimum_size.x = 205
	if design_mode == "foundation":
		game.title(controls,"轨道选址",17)
		var planets: Array = game.world.systems[station.system].planets
		var sites: Array = ["当前舰位"]
		for planet: Dictionary in planets:
			sites.append(planet.name)
		var site: OptionButton = game.choice(controls,sites)
		site.item_selected.connect(select_site)
		site_navigation = game.button(controls,"导航至选址",navigate_to_site)
		site_navigation.disabled = true
	game.title(controls,"产业布局",17)
	if design_mode in ["foundation","expansion"]:
		var picker: OptionButton = game.choice(controls,game.world.MODULES,current_kind)
		picker.item_selected.connect(change_kind)
		var terms: Dictionary = Economy.Industry.CONSTRUCTION.foundation if design_mode == "foundation" else Economy.Industry.CONSTRUCTION.expansion
		var bill := PackedStringArray()
		for ware in terms.bill:
			bill.append("%s × %s" % [game.world.WARES[Economy.Industry.WARE_ID[ware]],terms.bill[ware]])
		game.title(controls,"工程款 ¢%d · 工期 %d 天" % [terms.credits,terms.days],14,game.GOLD,true)
		game.title(controls,"交付材料  "+ "、".join(bill),13,game.DIM,true)
	installed = ItemList.new()
	installed.icon_mode = ItemList.ICON_MODE_LEFT
	installed.fixed_icon_size = Vector2i(27,27)
	installed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(installed)
	installed.item_selected.connect(func(index: int): select(index))
	status = game.title(body,"",14,game.DIM,true)
	var row = game.hbox(body)
	game.button(row,"关闭" if design_mode == "view" else "取消",close_editor)
	if design_mode != "view":
		commit = game.button(row,{"foundation":"支付并设立工地","expansion":"支付并开始扩建","layout":"保存布局"}[design_mode],apply)
	close_requested.connect(close_editor)
	window_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			set_input_as_handled()
			close_editor())
	tint = game.world.flag_color(station.flag)
	reset_preview()

func reset_preview() -> void:
	draft = station.duplicate()
	cells = Design.cells(station)
	if design_mode == "foundation":
		draft.module = current_kind
	elif design_mode == "expansion":
		draft.extension = current_kind
		draft.expansion = int(Economy.Industry.CONSTRUCTION.expansion.days)
		var at := Economy.expansion_cell(game.world,station,current_kind,cells)
		if at == Design.AUTO:
			for trial: Vector2i in Design.DEFAULT_CELLS:
				if trial not in cells:
					at = trial
					break
		cells.append(at)
		selected = cells.size()-1
	installed.clear()
	var kinds := Design.kinds(draft)
	for i in kinds.size():
		var label: String = game.world.MODULES[kinds[i]]
		if (design_mode == "expansion" and i == kinds.size()-1) or draft.get("build",0) > 0:
			label += " · 在建" if design_mode not in ["foundation","expansion"] else " · 拟建"
		installed.add_item(label,Art.module_texture(kinds[i],tint))
	grid.station = draft
	grid.tint = tint
	select(selected)

func change_kind(kind: int) -> void:
	if kind == current_kind:
		return
	var kept := cells.duplicate()
	current_kind = kind
	reset_preview()
	if kept.size() == cells.size():
		cells = kept
		refresh_grid()

func select_site(index: int) -> void:
	site_index = index-1
	var vessel: Dictionary = game.world.ride()
	var from: Vector2 = vessel.get("pos",Vector2.ZERO)
	var region: Dictionary = game.world.systems[station.system]
	var point := from
	if site_index >= 0:
		point = Celestial.construction_point(region,region.planets[site_index],from)
	var orbit := Celestial.orbit_at(region,point)
	station.pos = point
	station.berth_heading = point.angle_to_point(region.planets[orbit].pos) if orbit >= 0 else 0.0
	draft.pos = station.pos
	draft.berth_heading = station.berth_heading
	site_navigation.text = "离港并导航至选址" if vessel.get("dock",0) != 0 else "导航至选址"
	site_navigation.disabled = site_index < 0 or game.galaxy or vessel.is_empty() or vessel.get("locked",false)
	refresh_grid()

func navigate_to_site() -> void:
	var vessel: Dictionary = game.world.ride()
	if vessel.get("dock",0) != 0:
		game.flight.dock()
	if not vessel.is_empty() and vessel.dock == 0 and not game.galaxy:
		var region: Dictionary = game.world.systems[station.system]
		var planet: Dictionary = region.planets[site_index]
		var approach: Vector2 = Vector2(station.pos)-Vector2(planet.pos)
		game.set_waypoint(station.pos,planet.name+" · 建设轨道",func(): return Vector2(planet.pos)+approach)
		old_speed = maxi(old_speed,1)
		close_editor()

func select(index: int) -> void:
	selected = clampi(index,0,maxi(0,cells.size()-1))
	if installed.item_count > 0:
		installed.select(selected)
	refresh_grid()

func click_cell(cell: Vector2i) -> void:
	if cell in cells:
		select(cells.find(cell))
	elif design_mode != "view" and cell != Design.CORE and selected < cells.size():
		cells[selected] = cell
		refresh_grid()

func refresh_grid() -> void:
	grid.cells = cells
	grid.selected = selected
	grid.queue_redraw()
	if design_mode == "view":
		status.text = "只读图纸。选择模块可查看其在站体上的位置。"
		return
	var issue := Economy.construction_issue(game.world,current_kind,draft.pos,cells) if design_mode == "foundation" else Economy.design_issue(game.world,draft,cells)
	if design_mode == "expansion" and game.world.active().wallet < Economy.Industry.CONSTRUCTION.expansion.credits:
		issue = "工程款不足。"
	status.text = issue if not issue.is_empty() else "选择模块，再点击空格移动。每个模块都须与核心连通。"
	commit.disabled = not issue.is_empty()

func apply() -> void:
	var world = game.world
	var ok := false
	match design_mode:
		"foundation":
			ok = Economy.deploy(world,current_kind,station.pos,cells) != 0
		"expansion":
			ok = Economy.expand(world,station.id,current_kind,cells.back(),cells.slice(0,cells.size()-1))
		"layout":
			ok = Economy.redesign(world,station.id,cells)
	if not ok:
		status.text = "未能保存，请检查所在轨道、港口权限、资金和施工状态。"
		return
	game.say("已登记轨道工地。" if design_mode == "foundation" else ("扩建已开工。" if design_mode == "expansion" else "空间站布局已保存。"))
	close_editor()

func close_editor() -> void:
	hide()
	game.refresh()
	game.set_speed(old_speed)
	queue_free()
