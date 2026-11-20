extends RefCounted

const Art = preload("res://presentation.gd")
const Story = preload("res://frontier.gd")
const Politics = preload("res://politics.gd")
const Economy = preload("res://economy.gd")
const Hulls = preload("res://hull_catalog.gd")

var game
var mode := "welcome"
var contact_id := 0
var model_id := 0
var slot_index := 0
var black_weapons := false
var topic := ""
var station_id := 0
var stage: Control
var rendered := ""

func reset() -> void:
	mode = "welcome"
	contact_id = 0
	slot_index = 0
	black_weapons = false
	topic = ""
	station_id = 0
	rendered = ""

func section(key: String, caption: String, row: Control) -> void:
	var entry: Button = game.button(row, caption, func():
		mode = key
		topic = ""
		game.refresh(), true, true)
	entry.toggle_mode = true
	entry.button_pressed = mode == key

func sync() -> bool:
	var world = game.world
	var port_id: int = world.active().get("loc", 0)
	var visible_now: bool = port_id != 0 and not world.succession
	stage.visible = visible_now
	game.canvas.visible = not visible_now
	if not visible_now:
		reset()
		return false
	if station_id != port_id:
		reset()
		station_id = port_id
	return true

func paint(station: Dictionary) -> void:
	rendered = mode
	game.clear(stage)
	var world = game.world
	var variant := 0 if station.id == Story.origin(world) else (1 if station.module in [0, 1] else 2)
	Art.fill(Art.Pixels.backdrop_texture(variant, true), stage)
	Art.fade(stage, Color("08101c", 0.40), Color("08101c", 0.0))
	Art.fade(stage, Color("08101c", 0.0), Color("08101c", 0.97), true)
	var margins := MarginContainer.new()
	stage.add_child(margins)
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 27)
	var flow: VBoxContainer = game.vbox(margins)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	air.custom_minimum_size.y = 242
	flow.add_child(air)
	var plaque: HBoxContainer = game.hbox(flow)
	var accent := ColorRect.new()
	accent.color = game.GOLD
	accent.custom_minimum_size = Vector2(4, 55)
	plaque.add_child(accent)
	var sign = game.vbox(plaque)
	game.title(sign, "已停靠   /   %s   /   %s" % [world.systems[station.system].name, world.flag_name(station.flag)], 13, game.GOLD)
	game.title(sign, station.name, 39, Color("eef1e9"))
	if mode == "talk" and world.people.has(contact_id) and world.people[contact_id].alive and world.people[contact_id].loc == station.id:
		conversation(flow, station)
	elif mode == "yard":
		show_hull(flow, station)
	elif mode == "refit":
		show_refit(flow, station)
	else:
		var description: String = Art.PORT_TEXT[station.module]
		if station.id == Story.origin(world):
			description = "透过闸门能看见蓝弧巨行星。航务官守着泊位账本，机库工人正在校准停靠的船。"
		game.title(flow, description, 17, Color("dee5e1"), true)
	var places = game.hbox(flow)
	section("welcome", "泊位", places)
	section("market", "货栈", places)
	section("yard", "船坞", places)
	section("refit", "整备", places)
	section("people", "联络处", places)

func show_refit(flow: Control, station: Dictionary) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock != station.id:
		game.title(flow, "请先在「资产」登上一艘停靠在本站的舰船，再进行可视化整备。", 16, game.DIM, true)
		return
	var spec: Dictionary = Hulls.COMBAT[vessel.kind]
	var used_op := Hulls.fitting_cost(vessel.kind, vessel.fit)
	var crew_lim := Hulls.crew_limits(vessel.kind)
	if slot_index >= spec.slots.size():
		slot_index = 0
	var header_row = game.hbox(flow)
	Art.contained(header_row, Art.ship(vessel.kind), Vector2(146, 94))
	var summary = game.vbox(header_row)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.title(summary, "%s  /  OP %d / %d" % [world.HULLS[vessel.kind], used_op, spec.op], 20, Color("eef1e9"))
	game.title(summary, "幅能上限 %.0f · 散热 %.1f/s · 装甲 %.0f · 系统 %s" % [Hulls.capacity(vessel), Hulls.dissipation(vessel), spec.armor, Hulls.SYSTEM_NAMES[spec.system]], 14, game.GOLD)
	var tune_row = game.hbox(summary)
	game.title(tune_row, "电容 %d/12" % vessel.fit.caps, 14, game.INK)
	game.button(tune_row, "-", func(): game.hud.result(Economy.refit_tuning(world, station.id, -1, 0), "已卸除 1 点电容（退 ¢4）。"), vessel.fit.caps > 0)
	game.button(tune_row, "+", func(): game.hud.result(Economy.refit_tuning(world, station.id, 1, 0), "已加装 1 点电容（¢8）。"), used_op < spec.op and vessel.fit.caps < 12 and world.active().wallet >= 8)
	game.title(tune_row, "  散热 %d/12" % vessel.fit.vents, 14, game.INK)
	game.button(tune_row, "-", func(): game.hud.result(Economy.refit_tuning(world, station.id, 0, -1), "已卸除 1 点散热（退 ¢4）。"), vessel.fit.vents > 0)
	game.button(tune_row, "+", func(): game.hud.result(Economy.refit_tuning(world, station.id, 0, 1), "已加装 1 点散热（¢8）。"), used_op < spec.op and vessel.fit.vents < 12 and world.active().wallet >= 8)
	var crew_row = game.hbox(summary)
	game.title(crew_row, "船员 %d / 最低 %d · 满编 %d（效率 %d%%）" % [vessel.crew, crew_lim.x, crew_lim.y, roundi(Hulls.crew_efficiency(vessel) * 100.0)], 14, game.INK)
	game.button(crew_row, "招 +5", func():
		var hired := Economy.crew(world, 5)
		game.hud.result(hired > 0, "已招募 %d 名船员。" % hired, "资金、当地人口或铺位不足。"))
	game.button(crew_row, "遣 -5", func():
		var left := Economy.crew(world, -5)
		game.hud.result(left < 0, "已遣散 %d 名船员。" % absi(left), "当前无可遣散船员。"))
	for idx in range(spec.slots.size()):
		var slot_key: String = spec.slots[idx]
		var slot_def: Dictionary = Hulls.SLOTS[slot_key]
		var equipped: String = vessel.fit.weapons[idx]
		var label := "空槽位"
		if not equipped.is_empty() and Hulls.WEAPONS.has(equipped):
			var w: Dictionary = Hulls.WEAPONS[equipped]
			label = "%s（%s · OP %d）" % [w.name, Hulls.DAMAGE_NAMES[w.type], w.op]
		var srow = game.hbox(flow)
		var pick: Button = game.button(srow, "[%d] %s·%d级  %s" % [idx + 1, slot_def.type, slot_def.size, label], func():
			slot_index = idx
			game.refresh(), true, true)
		pick.toggle_mode = true
		pick.button_pressed = idx == slot_index
		var group_num: int = vessel.fit.groups[idx]
		game.button(srow, "组 %d" % group_num, func():
			Economy.refit_group(world, station.id, idx, (group_num % 3) + 1)
			game.refresh())

func show_hull(flow: Control, station: Dictionary) -> void:
	var world = game.world
	var model: Dictionary = Hulls.MODELS[model_id]
	var row = game.hbox(flow)
	Art.contained(row, Art.ship(model_id), Vector2(207, 122))
	var spec = game.vbox(row)
	spec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.title(spec, model.name + "  /  " + Hulls.CLASS_NAMES[model.size], 22, Color("eef1e9"))
	game.title(spec, "%s    船体 %s    货仓 %s    ¢%s" % [model.role, model.hp, model.cargo, model.price], 15, game.GOLD)
	game.title(spec, Art.hull_description(model_id), 15, game.INK, true)
	if station.hulls[model_id] > 0 and Hulls.model_limit(station, model_id):
		game.button(spec, "购买并登记到本站", func():
			game.hud.result(Economy.buy_ship(world, station.id, model_id) != 0, "新船已入库。到「资产」可登舰或指派船长。"), world.active().wallet >= model.price)

func conversation(flow: Control, station: Dictionary) -> void:
	var world = game.world
	var contact: Dictionary = world.people[contact_id]
	var character_row = game.hbox(flow)
	Art.contained(character_row, Art.face(contact.look), Vector2(106, 117))
	var chat = game.vbox(character_row)
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var role := ("晨曦航务官" if station.id == Story.origin(world) else "炉心领班") if contact.id == station.manager and station.id in [Story.origin(world), Story.foundry(world)] else ("驻站负责人" if contact.id == station.manager else "驻站人员")
	game.title(chat, contact.name + "   /   " + role, 20, game.GOLD)
	var speech := topic
	if speech.is_empty():
		if contact.id == station.manager and station.id == Story.origin(world):
			speech = "「泊位费已经记账。你要是愿意跑一趟，炉心少一炉原矿。我按送到的货付钱，不问你是买来的还是挖来的。」"
		elif contact.id == station.manager and station.id == Story.foundry(world):
			speech = "「听，炉子的风机声都变了。希望你的货舱里不是另一张欠条。」"
		else:
			speech = "「你找我有事？我今天就在这个泊位。」"
	game.title(chat, speech, 16, Color("e0e7e3"), true)

func sidebar(body: Node, station: Dictionary) -> void:
	var world = game.world
	var actor: Dictionary = world.active()
	var vessel: Dictionary = world.ride()
	game.hud.heading(body, {"welcome":"站务简报", "market":"货栈  /  即时报价", "yard":"船坞图鉴", "refit":"武器市场  /  槽位整备", "people":"驻站人员", "talk":"交谈"}.get(mode, "站务简报"))
	if station.build > 0:
		game.hud.hint(body, "工地合金 %s / 20  ·  尚需 %s 日" % [station.stock[1], station.build])
		game.button(body, "卸下建站材料", func(): game.hud.result(Economy.donate(world, station.id) > 0, "建材已卸到工地。"))
		return
	match mode:
		"market":
			game.hud.market(body, station)
		"refit":
			refit_sidebar(body, station)
		"yard":
			var classes = game.choice(body, Hulls.CLASS_NAMES, Hulls.MODELS[model_id].size)
			classes.item_selected.connect(func(choice: int):
				for index in range(Hulls.MODELS.size()):
					if Hulls.MODELS[index].size == choice:
						model_id = index
						break
				game.refresh())
			game.hud.hint(body, "泊位上限：" + Hulls.CLASS_NAMES[Hulls.station_limit(station)])
			for index in range(Hulls.MODELS.size()):
				var model: Dictionary = Hulls.MODELS[index]
				if model.size != Hulls.MODELS[model_id].size:
					continue
				var listing := "现货 %s" % station.hulls[index] if Hulls.model_limit(station, index) else "本站泊位不足"
				game.button(body, "%s  ·  %s" % [model.name, listing], func(): model_id = index; game.refresh())
			if not vessel.is_empty():
				game.button(body, "机务保养", func(): game.hud.result(Economy.supply(world, true), "维修完成。"))
		"people":
			for resident in world.people.values():
				if resident.id == actor.id or not resident.alive or resident.loc != actor.loc or Politics.age(world, resident) < 18:
					continue
				var role := "负责人" if resident.id == station.manager else ("贵族" if resident.noble else "船员 / 旅客")
				game.button(body, "%s  ·  %s" % [resident.name, role], func(): talk(resident.id))
		"talk":
			var contact: Dictionary = world.people.get(contact_id, {})
			if not contact.get("alive", false) or contact.loc != actor.loc:
				game.hud.hint(body, "这个人已经不在站内。")
				return
			dialogue_options(body, station, contact)
		_:
			game.hud.hint(body, "进入货栈交易、进船坞看船，或到联络处见当地人。")
			var manager: Dictionary = world.people.get(station.manager, {})
			if manager.get("alive", false) and manager.loc == station.id and manager.id != actor.id:
				var row = game.hbox(body)
				Art.contained(row, Art.face(manager.look), Vector2(56, 63))
				var info = game.vbox(row)
				game.title(info, manager.name, 18)
				game.button(info, "和负责人谈谈", func(): talk(manager.id))
			var objective := Story.objective(world)
			if not objective.is_empty():
				game.title(body, objective, 15, game.GOLD, true)
			if vessel.is_empty():
				game.hud.hint(body, "你目前没有登舰。打开「资产」选择本站的自有船。")
			else:
				game.button(body, "解除系泊  /  返回太空", game.flight.dock)

func talk(person_id: int) -> void:
	contact_id = person_id
	mode = "talk"
	topic = ""
	game.refresh()

func dialogue_options(body: Node, station: Dictionary, contact: Dictionary) -> void:
	var world = game.world
	var actor: Dictionary = world.active()
	game.hud.hint(body, "%s · %s · 对你的评价 %s" % ["贵族" if contact.noble else "平民", world.TRAITS[contact.trait], Politics.opinion(world, contact.id, actor.id)])
	if contact.id == station.manager and station.id == Story.origin(world) and world.people.get(world.ports[Story.foundry(world)].manager, {}).get("alive", false):
		game.button(body, "「第一趟去哪儿？」", func():
			topic = "「先在航务面板追踪恒星旁的引力点，飞进标记圈再按 M 跃入超空间。铁尘矿带在第 02 号信标，靠近再按 M。给炉心送 8 单位矿石就成。」"
			game.refresh())
		if not actor.get("first_berth", false):
			var empty: bool = not world.contracts.has(actor.id)
			game.button(body, "「我跑这一趟。」 · 接下熄火之前", func():
				if Story.accept(world):
					topic = "「我把目的地写进航务记录了。老规矩：货到付款。路上别追着掠夺者跑。」"
					game.refresh(), empty)
		elif not actor.get("first_berth_return", false):
			game.button(body, "「货到了，回来报个平安。」", func():
				if Story.return_to_port(world):
					topic = "「罗启山发过电报。返程津贴给你记上了。下次有货想找人担保，可以报我的名字。」"
					game.refresh())
	if contact.id == station.manager and station.id == Story.foundry(world):
		var can_deliver := not Story.active(world).is_empty()
		game.button(body, "「送来 8 单位矿石。」", func():
			topic = "「熔炉不用停了。¢210，全数转给你。下回还有这种矿，直接来找我。」" if Story.deliver(world) else "「至少要八个单位。先把货凑齐，我们才能点火。」"
			game.refresh(), can_deliver)
	game.button(body, "「送你一点心意。」 · ¢35", func():
		if Politics.influence(world, contact.id):
			topic = "「心意我收下了。下次靠港，记得来打声招呼。」"
		game.refresh(), actor.wallet >= 35)
	if actor.noble and contact.noble and actor.spouse == 0 and contact.spouse == 0:
		game.button(body, "「说说我们两家的事。」 · 提议联姻", func():
			topic = "「我们可以商议盟约了。」" if Politics.marry(world, actor.id, contact.id) else "「现在还不是时候。」"
			game.refresh())
	game.button(body, "「回头见。」", func(): mode = "people"; game.refresh())

func refit_sidebar(body: Node, station: Dictionary) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	if vessel.is_empty() or vessel.dock != station.id:
		game.hud.hint(body, "当前未登舰，无法整备。")
		return
	var spec: Dictionary = Hulls.COMBAT[vessel.kind]
	if slot_index >= spec.slots.size():
		slot_index = 0
	var slot_def: Dictionary = Hulls.SLOTS[spec.slots[slot_index]]
	var current_key: String = vessel.fit.weapons[slot_index]
	var used_op := Hulls.fitting_cost(vessel.kind, vessel.fit)
	var current_op := int(Hulls.WEAPONS[current_key].op) if Hulls.WEAPONS.has(current_key) else 0
	var free_op := int(spec.op) - used_op + current_op
	if world.is_regular(station):
		var channel = game.hbox(body)
		var pub_btn: Button = game.button(channel, "公开武器库", func(): black_weapons = false; game.refresh(), true, true)
		pub_btn.toggle_mode = true
		pub_btn.button_pressed = not black_weapons
		var blk_btn: Button = game.button(channel, "黑市军火", func(): black_weapons = true; game.refresh(), true, true)
		blk_btn.toggle_mode = true
		blk_btn.button_pressed = black_weapons
	else:
		black_weapons = false
	game.hud.hint(body, "槽位 [%d]：%s · 尺寸上限 %d · 可用 OP %d" % [slot_index + 1, slot_def.type, slot_def.size, free_op])
	if not current_key.is_empty():
		var refund := Economy.weapon_price(current_key, false, false)
		game.button(body, "卸下当前武器（退 ¢%d）" % refund, func():
			game.hud.result(Economy.refit_slot(world, station.id, slot_index, "", black_weapons), "已卸下槽位武器并结算折价。"))
	var list := Economy.station_weapons(world, station, black_weapons)
	var wallet: int = world.active().wallet
	var old_refund := Economy.weapon_price(current_key, false, false)
	for item in list:
		var key: String = str(item)
		var w: Dictionary = Hulls.WEAPONS[key]
		if int(w.mount) > int(slot_def.size):
			continue
		var net := Economy.weapon_price(key, true, black_weapons) - old_refund
		var price_label := "¢%d" % net if net >= 0 else "退¢%d" % absi(net)
		var can_fit: bool = int(w.op) <= free_op and (net <= 0 or wallet >= net) and key != current_key
		var caption := "%s  [%s · %d级 · OP%d]  %s" % [w.name, Hulls.DAMAGE_NAMES[w.type], w.mount, w.op, "已装" if key == current_key else price_label]
		var entry: Button = game.button(body, caption, func():
			game.hud.result(Economy.refit_slot(world, station.id, slot_index, key, black_weapons), "已换装 " + w.name + "。", "OP、信用点或权限不足。"), can_fit)
		entry.tooltip_text = "伤害 %.1f · 射程 %.0f · 冷却 %.2fs · 幅能 %.0f" % [w.damage, w.range, w.cool, w.flux]
