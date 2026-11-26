extends VBoxContainer

const Hulls = preload("res://hull_catalog.gd")
const Pixels = preload("res://art/pixel_art.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const ArenaBattle = preload("res://scripts/ui/skirmish_battle.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const CLASS_NAMES := ["护卫舰","驱逐舰","巡洋舰","主力舰"]
const STATIONS := [[],[Industry.Module.MINE,Industry.Module.SOLAR],[Industry.Module.YARD,Industry.Module.REFINERY],[Industry.Module.DEFENSE,Industry.Module.SOLAR]]
const PAGE_SIZE := 6

var game
var rosters: Array = [[],[]]
var station_types := [0,0]
var controls: Array = [{},{}]
var sides: Array[Label] = []
var start_button: Button
var pause_button: Button
var outcome: Label
var timer: Label
var battle: ArenaBattle
var query := ""
var class_filter := 0
var page := 0
var selected_kind := -1
var matches: Array[int] = []
var search: LineEdit
var grid: GridContainer
var previous_page: Button
var next_page: Button
var page_label: Label
var selected_details: Label
var wings: OptionButton
var qty: SpinBox
var add_buttons: Array[Button] = []
var portraits := {}
var camera_picker: OptionButton
var camera_ids: Array = []
var zoom_label: Label

func open(host) -> void:
	game = host
	name = "Skirmish"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	rosters[0] = [entry("condor",1),entry("wolf",2)]
	rosters[1] = [entry("enforcer",1),entry("sunder",1)]
	setup()

func entry(reference: String, count: int) -> Dictionary:
	return {"hull":Hulls.hull_id(Hulls.kind_for_reference(reference)),"wing":"","count":count}

func reset_view() -> void:
	battle = null
	sides.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()

func button(parent: Node, caption: String, callback: Callable, variant := "default") -> Button:
	var b := UI.action_button(parent,caption,callback,variant)
	b.custom_minimum_size.y = 42
	return b

func setup() -> void:
	reset_view()
	var header = game.hbox(self)
	game.title(header,"战斗沙盘",32,UI.GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(header,"返回主菜单",game.show_title)
	var columns = game.hbox(self)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation",14)
	var catalog := UI.card(columns,UI.GOLD)
	catalog.get_parent().size_flags_stretch_ratio = 1.35
	catalog.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var fleets = game.vbox(columns)
	fleets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fleets.add_theme_constant_override("separation",10)
	for side in 2:
		build_roster(fleets,side)
	build_catalog(catalog)
	var footer = game.hbox(self)
	game.title(footer,"双方由 AI 指挥。每方同时部署最多 %d 艘，余舰按编成顺序增援。" % ArenaBattle.ACTIVE_PER_SIDE,15,game.DIM,true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button = button(footer,"开始交战",begin,"primary")
	start_button.custom_minimum_size.x = 168
	refresh_start()

func build_roster(parent: Node, side: int) -> void:
	var tint := ArenaBattle.BLUE if side==0 else ArenaBattle.AMBER
	var card := UI.card(parent,tint)
	card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header=game.hbox(card)
	var heading: Label=game.title(header,"",22,tint)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(header,"清空",func():
		rosters[side].clear()
		station_types[side]=0
		controls[side].station.select(0)
		refresh_roster(side),"ghost")
	var station: OptionButton=game.choice(card,["无空间站","采矿站 · 采矿与太阳能","轨道船厂 · 造船与精炼","防务站 · 防务与太阳能"],station_types[side])
	station.custom_minimum_size.y=40
	station.item_selected.connect(func(idx): station_types[side]=idx; refresh_start())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var rows=game.vbox(scroll)
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls[side]={"rows":rows,"station":station,"heading":heading}
	refresh_roster(side)

func build_catalog(card: Node) -> void:
	var header=game.hbox(card)
	game.title(header,"舰船图鉴",22,UI.GOLD).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	search=LineEdit.new()
	search.placeholder_text="舰名 / 型号"
	search.custom_minimum_size=Vector2(180,40)
	header.add_child(search)
	search.text=query
	search.text_changed.connect(func(txt): query=txt; page=0; filter_hulls())
	var filters=HFlowContainer.new()
	card.add_child(filters)
	var group:=ButtonGroup.new()
	var labels:=["全部"]+CLASS_NAMES+["航母"]
	for i in labels.size():
		var chip:=button(filters,labels[i],func(): class_filter=i; page=0; filter_hulls(),"ghost")
		chip.toggle_mode=true
		chip.button_group=group
		chip.button_pressed=(i==class_filter)
	var scroll:=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	grid=GridContainer.new()
	grid.columns=3
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",7)
	scroll.add_child(grid)
	var nav=game.hbox(card)
	previous_page=button(nav,"上一页",func(): page-=1; filter_hulls(),"ghost")
	page_label=game.title(nav,"",15,game.DIM)
	page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	page_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	next_page=button(nav,"下一页",func(): page+=1; filter_hulls(),"ghost")
	selected_details=game.title(card,"",16,game.INK,true)
	wings=OptionButton.new()
	wings.fit_to_longest_item=false
	wings.custom_minimum_size.y=40
	card.add_child(wings)
	wings.add_item("使用原厂联队")
	for id in Hulls.wing_ids():
		var squad:=Hulls.wing_spec(id)
		wings.add_item("可换机库：%s · 每队 %d 架" % [squad.name,squad.count])
		wings.set_item_metadata(wings.item_count-1,id)
	var actions=game.hbox(card)
	game.title(actions,"数量",15,game.DIM)
	qty=SpinBox.new()
	qty.min_value=1
	qty.max_value=99
	qty.value=1
	qty.custom_minimum_size=Vector2(90,42)
	actions.add_child(qty)
	add_buttons.clear()
	for side in 2:
		var add:=button(actions,"加入蓝方" if side==0 else "加入红方",add_selected.bind(side),"primary")
		add.add_theme_color_override("font_color",ArenaBattle.BLUE if side==0 else ArenaBattle.AMBER)
		add.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		add_buttons.append(add)
	filter_hulls()

func filter_hulls() -> void:
	matches.clear()
	var needle:=query.strip_edges().to_lower()
	for kind in Hulls.MODELS.size():
		var hull: Dictionary=Hulls.MODELS[kind]
		if class_filter in [1,2,3,4] and int(hull.size)!=class_filter-1: continue
		if class_filter==5 and int(hull.fighter_bays)==0: continue
		if not needle.is_empty() and needle not in (str(hull.name)+" "+str(hull.id)+" "+str(hull.reference)).to_lower(): continue
		matches.append(kind)
	var pages:=maxi(1,ceili(matches.size()/float(PAGE_SIZE)))
	page=clampi(page,0,pages-1)
	page_label.text="%d 艘  ·  %d / %d 页" % [matches.size(),page+1,pages]
	previous_page.disabled=page==0
	next_page.disabled=page==pages-1
	game.clear(grid)
	var visible_hulls:=matches.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE)
	var selection:=ButtonGroup.new()
	if selected_kind not in visible_hulls:
		selected_kind=-1 if visible_hulls.is_empty() else int(visible_hulls[0])
	for kind in visible_hulls:
		var b:=ship_card(kind,selection)
		b.set_pressed_no_signal(kind==selected_kind)
	show_selection()

func ship_card(kind: int, group: ButtonGroup) -> Button:
	var hull: Dictionary=Hulls.MODELS[kind]
	var tile:=Button.new()
	tile.name="Hull_%d" % kind
	tile.toggle_mode=true
	tile.button_group=group
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size=Vector2(100,180)
	tile.tooltip_text="%s · %s" % [hull.name,hull.role]
	var picked:=StyleBoxFlat.new()
	picked.bg_color=Color("173342")
	picked.border_color=UI.GOLD
	picked.set_border_width_all(2)
	picked.set_corner_radius_all(4)
	tile.add_theme_stylebox_override("pressed",picked)
	tile.add_theme_stylebox_override("hover_pressed",picked)
	grid.add_child(tile)
	var box:=VBoxContainer.new()
	box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left=7
	box.offset_right=-7
	box.offset_top=5
	box.offset_bottom=-4
	var icon:=ship_image(box,kind,Color(hull.paint),Vector2(100,101))
	icon.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var name_label:Label=game.title(box,hull.name,15,game.INK)
	name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	name_label.clip_text=true
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var note:String=CLASS_NAMES[hull.size]+(" · %d 机库" % hull.fighter_bays if hull.fighter_bays else " · %d 武器槽" % hull.mounts.size())
	var stats:Label=game.title(box,note,13,game.DIM)
	stats.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stats.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	tile.pressed.connect(func(): selected_kind=kind; show_selection())
	return tile

func ship_image(parent: Node, kind: int, color: Color, minimum: Vector2) -> TextureRect:
	var image:=TextureRect.new()
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	image.custom_minimum_size=minimum
	var key:="%d:%s" % [kind,color.to_html()]
	if not portraits.has(key):
		var pixels:=Pixels.hull(kind,color)
		var occupied:=pixels.get_used_rect().grow(2).intersection(Rect2i(Vector2i.ZERO,pixels.get_size()))
		portraits[key]=ImageTexture.create_from_image(pixels.get_region(occupied))
	image.texture=portraits[key]
	parent.add_child(image)
	return image

func show_selection() -> void:
	for add in add_buttons: add.disabled=selected_kind<0
	wings.hide()
	wings.select(0)
	if selected_kind<0:
		selected_details.text="没有匹配的舰船"
		return
	var hull: Dictionary=Hulls.MODELS[selected_kind]
	selected_details.text="%s　·　%s　·　船体 %d　·　武器槽 %d　·　机库 %d" % [hull.name,CLASS_NAMES[hull.size],hull.hp,hull.mounts.size(),hull.fighter_bays]
	wings.visible=hull.fighter_bays>0
	wings.disabled=hull.builtin_wings.size()>=int(hull.fighter_bays)

func add_selected(side: int) -> void:
	if selected_kind<0: return
	var wing:=str(wings.get_item_metadata(wings.selected)) if wings.visible and wings.selected>0 else ""
	var hull:=Hulls.hull_id(selected_kind)
	for group in rosters[side]:
		if group.hull==hull and group.wing==wing:
			group.count+=int(qty.value)
			refresh_roster(side)
			return
	rosters[side].append({"hull":hull,"wing":wing,"count":int(qty.value)})
	refresh_roster(side)

func refresh_roster(side: int) -> void:
	var rows:VBoxContainer=controls[side].rows
	game.clear(rows)
	var total:=0
	var tint:=ArenaBattle.BLUE if side==0 else ArenaBattle.AMBER
	for group:Dictionary in rosters[side]:
		total+=int(group.count)
		var kind:=Hulls.kind_for_id(group.hull)
		var hull:Dictionary=Hulls.MODELS[kind]
		var row=game.hbox(rows)
		ship_image(row,kind,tint,Vector2(66,44))
		var title:String=hull.name if group.wing=="" else "%s · %s" % [hull.name,Hulls.wing_spec(group.wing).name]
		game.title(row,title,15,game.INK,true).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button(row,"−",func():
			group.count-=1
			if group.count<=0: rosters[side].erase(group)
			refresh_roster(side))
		game.title(row,str(group.count),17,game.GOLD)
		button(row,"+",func(): group.count+=1; refresh_roster(side))
		button(row,"移除",func(): rosters[side].erase(group); refresh_roster(side),"ghost")
	controls[side].heading.text=("%s舰队 · %d 艘" % ["蓝方" if side==0 else "红方",total])
	refresh_start()

func refresh_start() -> void:
	if is_instance_valid(start_button) and start_button.is_inside_tree():
		start_button.disabled = (rosters[0].is_empty() and station_types[0]==0) or (rosters[1].is_empty() and station_types[1]==0)

func begin() -> void:
	if (rosters[0].is_empty() and station_types[0]==0) or (rosters[1].is_empty() and station_types[1]==0): return
	reset_view()
	var header=game.hbox(self)
	game.title(header,"战斗沙盘",24,UI.GOLD)
	outcome=game.title(header,"交战中",20,UI.GOLD)
	outcome.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	timer=game.title(header,"00:00",16,game.DIM)
	button(header,"同阵容重赛",begin)
	button(header,"调整阵容",setup)
	button(header,"返回主菜单",game.show_title)
	var tools=game.hbox(self)
	pause_button=button(tools,"暂停",func(): battle.paused=not battle.paused; pause_button.text="继续" if battle.paused else "暂停")
	var pace: OptionButton=game.choice(tools,["1×","2×","4×"])
	pace.item_selected.connect(func(i): battle.time_scale=[1,2,4][i])
	game.title(tools,"视角",15,game.DIM)
	camera_picker=OptionButton.new()
	camera_picker.fit_to_longest_item=false
	camera_picker.custom_minimum_size=Vector2(210,42)
	tools.add_child(camera_picker)
	camera_ids.clear()
	camera_picker.item_selected.connect(func(i):
		var view: Dictionary=camera_picker.get_item_metadata(i)
		battle.set_view(view.mode,view.ship))
	button(tools,"缩小",func(): battle.change_zoom(1.0/1.3)).custom_minimum_size.x=54
	zoom_label=game.title(tools,"",15,game.INK)
	zoom_label.custom_minimum_size.x=48
	zoom_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	button(tools,"放大",func(): battle.change_zoom(1.3)).custom_minimum_size.x=54
	button(tools,"全景",func(): battle.set_view(ArenaBattle.View.ALL))
	game.title(tools,"轻点舰船锁定 · 双指缩放" if game.mobile_play else "点击舰船锁定 · 滚轮缩放",14,game.DIM)
	var bar=game.hbox(self)
	for side in 2:
		var label: Label=game.title(bar,"",16,ArenaBattle.BLUE if side==0 else ArenaBattle.AMBER)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		sides.append(label)
	battle=ArenaBattle.new()
	battle.orders=rosters.duplicate(true)
	battle.stations=[STATIONS[station_types[0]].duplicate(),STATIONS[station_types[1]].duplicate()]
	battle.size_flags_vertical=Control.SIZE_EXPAND_FILL
	battle.standings_changed.connect(update_scores)
	battle.finished.connect(func(winner):
		outcome.text="平局" if winner<0 else ("蓝方胜利" if winner==0 else "红方胜利"))
	add_child(battle)
	battle.camera_changed.connect(sync_camera)
	rebuild_camera_list()
	update_scores(battle.tally(0),battle.tally(1))

func rebuild_camera_list() -> void:
	if camera_picker.get_popup().visible: return
	var ids:=battle.world.ships.keys()
	ids.sort()
	if ids==camera_ids and camera_picker.item_count>0: return
	camera_ids=ids
	camera_picker.clear()
	var labels:=["全景","跟随蓝方","跟随红方","跟拍战机","自由视角"]
	for mode in labels.size():
		camera_picker.add_item(labels[mode])
		camera_picker.set_item_metadata(mode,{"mode":mode,"ship":0})
	for team in 2:
		for id in ids:
			var ship: Dictionary=battle.world.ships[id]
			if ship.flag!=battle.flag_for(team): continue
			var name_:String=ship.job.label if ship.has("defense_port") else Hulls.MODELS[ship.kind].name
			camera_picker.add_item("%s #%d · %s" % ["蓝方" if team==0 else "红方",id,name_])
			camera_picker.set_item_metadata(camera_picker.item_count-1,{"mode":ArenaBattle.View.SHIP,"ship":id})
	sync_camera(battle.camera_mode,battle.tracked_id,battle.space.scale.x)

func sync_camera(mode: int, id: int, scale_value: float) -> void:
	zoom_label.text="%.0f%%" % (scale_value*100.0)
	for i in camera_picker.item_count:
		var option:Dictionary=camera_picker.get_item_metadata(i)
		if option.mode==mode and option.ship==id:
			camera_picker.select(i)
			return

func update_scores(blue: Dictionary, red: Dictionary) -> void:
	rebuild_camera_list()
	zoom_label.text="%.0f%%" % (battle.space.scale.x*100.0)
	timer.text="%02d:%02d" % [int(battle.elapsed)/60,int(battle.elapsed)%60]
	for side in 2:
		var row := blue if side==0 else red
		sides[side].text = "%s　舰船 %d　预备 %d　站防模块 %d　出击战机 %d" % ["蓝方" if side==0 else "红方",row.ships,row.reserve,row.modules,row.aircraft]
