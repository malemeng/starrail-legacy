extends AcceptDialog

const Armament = preload("res://scripts/economy/station_armament.gd")
const Hulls = preload("res://hull_catalog.gd")
const WeaponArt = preload("res://art/weapon_mounts.gd")

var game
var site: Dictionary
var module := OptionButton.new()
var slot := OptionButton.new()
var weapon := OptionButton.new()
var summary := Label.new()
var status := Label.new()
var install := Button.new()
var preview := TextureRect.new()
var offers: Array = []
var current := ""

static func open(session, station: Dictionary) -> void:
	var dialog := new()
	dialog.game = session
	dialog.site = station
	dialog.title = station.name + " · 模块武备"
	dialog.ok_button_text = "关闭"
	dialog.get_ok_button().custom_minimum_size = Vector2(100,44)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470,275)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	scroll.add_child(body)
	for row in [["模块",dialog.module],["武器槽",dialog.slot],["舰载武器",dialog.weapon]]:
		var line := HBoxContainer.new()
		body.add_child(line)
		session.title(line,row[0],16,session.INK).custom_minimum_size.x = 88
		row[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row[1].custom_minimum_size.y = 44
		line.add_child(row[1])
	body.add_child(dialog.summary)
	dialog.preview.custom_minimum_size = Vector2(80,42)
	dialog.preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dialog.preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dialog.preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(dialog.preview)
	dialog.install.custom_minimum_size.y = 44
	body.add_child(dialog.install)
	dialog.status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(dialog.status)
	for i in station.modules.size()+1:
		dialog.module.add_item(Armament.label(session.world,station,i))
	dialog.module.item_selected.connect(func(_i): dialog.update_module())
	dialog.slot.item_selected.connect(func(_i): dialog.update_slot())
	dialog.weapon.item_selected.connect(func(_i): dialog.update_quote())
	dialog.install.pressed.connect(dialog.apply)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	session.add_child(dialog)
	dialog.update_module()
	dialog.popup_centered_clamped(Vector2i(560,350),0.95)

func update_module() -> void:
	var info := Armament.inspect(game.world,site,module.selected)
	slot.clear()
	for mount in info.mounts:
		var key: String = mount.weapon
		var spec := Hulls.slot_spec(Armament.profile(site,module.selected),int(mount.slot))
		var size_name: String = ["小型","中型","大型"][clampi(int(mount.size)-1,0,2)]
		slot.add_item("%d · %s%s · %s" % [int(mount.slot)+1,size_name,spec.type,Hulls.WEAPONS[key].name if key != "" else "空槽"])
	summary.text = "独立全向护盾 · 幅能容量 %d　装配点 %d / %d" % [info.modules[module.selected].shield, info.used_op, info.op]
	var wings: Array = info.modules[module.selected].wings
	if not wings.is_empty():
		var groups := PackedStringArray()
		for id in wings:
			var squad := Hulls.wing_spec(id)
			groups.append("%s×%d" % [squad.get("name",id),squad.count])
		summary.text += "\n驻站 %d 支联队 / %d 架\n%s" % [wings.size(),info.modules[module.selected].aircraft,"、".join(groups)]
	update_slot()

func update_slot() -> void:
	var info := Armament.inspect(game.world,site,module.selected,slot.selected)
	current = info.mounts[slot.selected].weapon
	offers = info.get("offers",[])
	if current != "" and current not in offers:
		offers.push_front(current)
	weapon.clear()
	for key in offers:
		weapon.add_item("拆下武器" if key == "" else Hulls.WEAPONS[key].name)
	if current in offers:
		weapon.select(offers.find(current))
	update_quote()

func update_quote() -> void:
	install.disabled = true
	install.text = "安装 / 拆卸"
	var shown: String = offers[weapon.selected] if weapon.selected >= 0 and weapon.selected < offers.size() else ""
	preview.texture = WeaponArt.texture(WeaponArt.profile(shown).family) if shown != "" else null
	if offers.is_empty():
		status.text = "此挂点没有可更换的武器。"
		return
	var offer := Armament.quote(game.world,site,module.selected,slot.selected,offers[weapon.selected])
	install.disabled = not offer.ok
	if offer.ok:
		install.text = "确认换装"
		status.text = ("自费 ¢%d" % offer.net if offer.net >= 0 else "回收 ¢%d" % -offer.net) + " · 换装后剩余 %d 装配点" % offer.free_op
	else:
		status.text = str(offer.reason)

func apply() -> void:
	if install.disabled or weapon.selected < 0:
		return
	var result := Armament.refit(game.world,site,module.selected,slot.selected,offers[weapon.selected],current)
	if result.ok:
		var previous := slot.selected
		update_module()
		slot.select(previous)
		update_slot()
		game.say("已更新%s武器槽 %s。" % [Armament.label(game.world,site,module.selected),slot.selected+1])
	else:
		status.text = result.reason
