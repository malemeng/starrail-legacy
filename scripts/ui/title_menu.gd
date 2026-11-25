extends Control

const GOLD := Color("ecc797")
const PAPER := Color("e7edf0")
const MUTED := Color("98aebd")
var game
var battle: Control
var replay: TextureRect
var column := VBoxContainer.new()
var saves := VBoxContainer.new()
var choices := VBoxContainer.new()
var feed := Label.new()
var message := Label.new()
var showing_saves := false

func open(host) -> void:
	game = host
	name = "TitleMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if game.mobile_play:
		replay = load("res://scripts/ui/mobile_title_replay.gd").new()
		add_child(replay)
		replay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		set_process(false)
	else:
		battle = load("res://scripts/ui/title_battle.gd").new()
		battle.remember_lineup = not game.test_profile
		add_child(battle)
		battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shadow := TextureRect.new()
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0,0.27,0.52,0.80,1.0])
	ramp.colors = PackedColorArray([Color("070e18fc"),Color("0a1320ef"),Color("0a13209a"),Color("0a111d18"),Color("0a111d00")])
	var tex := GradientTexture2D.new()
	tex.gradient = ramp
	shadow.texture = tex
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation",12)
	add_child(column)
	var accent := ColorRect.new()
	accent.color = GOLD
	accent.custom_minimum_size = Vector2(54,3)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(accent)
	game.title(column,"S T A R R A I L    L E G A C Y",16,GOLD)
	var title: Label = game.title(column,"星轨遗产",80,PAPER)
	var display := SystemFont.new()
	display.font_names = PackedStringArray(["SimSun","Songti SC","Microsoft YaHei"])
	display.font_weight = 700
	title.add_theme_font_override("font",display)
	var rule := HSeparator.new()
	column.add_child(rule)
	column.add_child(choices)
	column.add_child(saves)
	choices.add_theme_constant_override("separation",8)
	saves.add_theme_constant_override("separation",8)
	saves.hide()
	var slots := [[game.SAVE,"手动存档"],[game.AUTO,"抵港自动存档"],[game.BEFORE,"接班前存档"]]
	var latest := ""
	var newest := -1
	for slot in slots:
		if FileAccess.file_exists(slot[0]):
			var stamp := FileAccess.get_modified_time(slot[0])
			if stamp > newest:
				newest = stamp
				latest = slot[0]
			menu_button(saves,slot[1],resume.bind(slot[0]))
	if not latest.is_empty():
		menu_button(choices,"继续航程",resume.bind(latest),true)
	menu_button(choices,"新航程",game.show_creator,latest.is_empty())
	if not latest.is_empty(): menu_button(choices,"读取存档",switch_page.bind(true))
	menu_button(choices,"退出游戏",func(): get_tree().quit())
	menu_button(saves,"返回主菜单",switch_page.bind(false))
	column.add_child(message)
	message.add_theme_color_override("font_color",GOLD)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.hide()
	var broadcast := HBoxContainer.new()
	add_child(broadcast)
	broadcast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	broadcast.offset_left = -370
	broadcast.offset_top = -69
	broadcast.offset_right = -44
	broadcast.offset_bottom = -29
	broadcast.alignment = BoxContainer.ALIGNMENT_END
	broadcast.add_theme_constant_override("separation",20)
	broadcast.add_child(feed)
	feed.add_theme_font_size_override("font_size",16)
	feed.add_theme_color_override("font_color",Color("c1dfdf"))
	feed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shuffle := Button.new()
	shuffle.flat = true
	if game.mobile_play:
		feed.text = "开场战斗回放"
		shuffle.text = "暂停回放"
		shuffle.pressed.connect(func():
			replay.timer.paused = not replay.timer.paused
			shuffle.text = "继续回放" if replay.timer.paused else "暂停回放")
		var report := Button.new()
		report.text = "退出诊断"
		report.flat = true
		report.pressed.connect(show_exit_report,CONNECT_DEFERRED)
		broadcast.add_child(report)
	else:
		shuffle.text = "换一场"
		shuffle.tooltip_text = "重新抽选交战舰队"
		shuffle.pressed.connect(battle.start_round)
	broadcast.add_child(shuffle)
	resized.connect(arrange)
	column.minimum_size_changed.connect(arrange.call_deferred)
	arrange()
	choices.get_child(0).grab_focus()

func show_exit_report() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "安卓退出诊断"
	dialog.dialog_text = preload("res://scripts/services/android_exit_report.gd").describe()
	dialog.add_button("复制",true,"copy")
	dialog.custom_action.connect(func(action):
		if action == "copy":
			DisplayServer.clipboard_set(dialog.dialog_text))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func menu_button(parent: VBoxContainer, caption: String, action: Callable, primary: bool = false) -> void:
	var button := Button.new()
	button.text = caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size",19)
	for state in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = (GOLD if primary else Color("102232df")) if state == "normal" else (Color("f5d9ae") if primary else Color("244154"))
		style.border_color = GOLD if primary or state == "focus" else Color("426072")
		style.border_width_left = 3
		if state == "focus":
			style.draw_center = false
			style.set_border_width_all(1)
		style.content_margin_left = 22
		style.content_margin_right = 16
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:
		button.add_theme_color_override(state,Color("16222e") if primary else PAPER)
	button.pressed.connect(action, CONNECT_DEFERRED if game.mobile_play else 0)
	parent.add_child(button)

func arrange() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	column.size = Vector2(minf(398,maxf(245,size.x*0.34)),column.get_combined_minimum_size().y)
	column.position = Vector2(size.x*0.075,maxf(20,(size.y-column.size.y)*0.52))

func switch_page(show_slots: bool) -> void:
	showing_saves = show_slots
	choices.visible = not show_slots
	saves.visible = show_slots
	message.hide()
	var visible_choices := saves if show_slots else choices
	visible_choices.get_child(0).grab_focus()
	arrange()

func resume(path: String) -> void:
	if not game.load_game(path):
		message.text = game.notice_text
		message.show()

func _process(_delta: float) -> void:
	if battle:
		feed.text = "●  实时交战     /     %d 艘在场" % battle.world.ships.size()

func _unhandled_key_input(event: InputEvent) -> void:
	if showing_saves and event.is_action_pressed("ui_cancel"):
		switch_page(false)
		get_viewport().set_input_as_handled()
