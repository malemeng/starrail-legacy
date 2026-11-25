extends RefCounted

const HullScale = preload("res://scripts/ui/hull_scale.gd")
const Blueprint = preload("res://scripts/ui/refit_blueprint.gd")
const RefitBench = preload("res://scripts/ui/refit_bench.tscn")
const Battle = preload("res://combat.gd")
const Art = preload("res://presentation.gd")
const Portrait = preload("res://portrait.gd")
const Story = preload("res://frontier.gd")
const Politics = preload("res://politics.gd")
const Economy = preload("res://economy.gd")
const Hulls = preload("res://hull_catalog.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")
const StationDesigner = preload("res://scripts/ui/station_designer.gd")

var game
var mode := "welcome"
var contact_id := 0
var model_id := 0
var slot_index := 0
var refit_ship_id := 0
var last_bought_ship_id := 0
var black_weapons := false
var topic := ""
var station_id := 0
var stage: Control
var rendered := ""
var backdrop := -1
var blueprint: Blueprint

func reset() -> void:
	mode = "welcome"
	contact_id = 0
	slot_index = 0
	refit_ship_id = 0
	last_bought_ship_id = 0
	black_weapons = false
	topic = ""
	station_id = 0
	rendered = ""
	backdrop = -1

func refit_candidates(world, port_id: int) -> Array:
	var list: Array = []
	var lead_id: int = world.ride().get("id", 0)
	if lead_id > 0:
		var lead: Dictionary = world.ships.get(lead_id, {})
		if not lead.is_empty() and lead.dock == port_id and world.can_operate(lead):
			list.append(lead)
	for owned in world.ships.values():
		if owned.id != lead_id and owned.dock == port_id and world.can_operate(owned):
			list.append(owned)
	return list

func resolved_refit_ship(world, port_id: int) -> Dictionary:
	var candidates := refit_candidates(world, port_id)
	if candidates.is_empty():
		refit_ship_id = 0
		return {}
	for candidate in candidates:
		if candidate.id == refit_ship_id:
			return candidate
	refit_ship_id = candidates[0].id
	return candidates[0]

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
	var visible_now: bool = port_id != 0 and not world.succession and game.watch_ship_id == 0
	stage.visible = visible_now and not game.system_chart
	game.canvas.visible = not stage.visible
	if not visible_now:
		if port_id == 0 or world.succession:
			reset()
		return false
	if station_id != port_id:
		reset()
		station_id = port_id
	return true

func paint(station: Dictionary) -> void:
	rendered = mode
	var world = game.world
	var variant := 0 if station.id == Story.origin(world) else (1 if station.module in [0, 1] else 2)
	var background: Control = stage.get_node("Background")
	if variant != backdrop:
		game.clear(background)
		Art.fill(Art.Pixels.backdrop_texture(variant, true), background)
		Art.fade(background, Color("08101c", 0.40), Color("08101c", 0.0))
		Art.fade(background, Color("08101c", 0.0), Color("08101c", 0.97), true)
		backdrop = variant
	var flow: VBoxContainer = stage.get_node("Margins/Content")
	game.clear(flow)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	air.custom_minimum_size.y = 20 if mode in ["yard", "refit"] else 242
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
		var description: String = Art.PORT_TEXT[station.module] if station.module < Art.PORT_TEXT.size() else "%s模块正在运行。" % world.MODULES[station.module]
		if station.has("planet_index"):
			var planet: Dictionary = world.systems[station.system].planets[station.planet_index]
			description = "%s · %s　%s" % [world.Celestial.PLANETS[planet.type][0],"高层大气浮港" if planet.type >= 20 else "地表泊位",
				"可在此勘测并建立行星港。" if station.get("landing_only",false) else "本站设施：" + "、".join(station.modules.map(func(i): return world.MODULES[i]))]
			if station.build == 0 and not station.get("landing_only",false):
				var harvest := PackedStringArray()
				for ware: int in station.get("surface_yields",{}):
					var units: int = world.PlanetPorts.harvest_units(station,ware)
					harvest.append("%s %d" % [world.WARES[ware],units])
				if not harvest.is_empty():
					description += "\n地表每六日可入库　" + "　".join(harvest)
		elif station.id == Story.origin(world):
			description = "透过闸门能看见蓝弧巨行星。航务官守着泊位账本，机库工人正在校准停靠的船。"
		game.title(flow, description, 17, Color("dee5e1"), true)
		if mode == "welcome" and not station.has("planet_index"):
			game.button(flow,"空间站布局",func(): StationDesigner.open(game,"layout",station))
	var places = game.hbox(flow)
	section("welcome", "泊位", places)
	if station.get("landing_only",false) or station.build > 0:
		return
	section("market", "货栈", places)
	section("yard", "船坞", places)
	section("refit", "整备", places)
	section("people", "联络处", places)

func show_refit(flow: Control, station: Dictionary) -> void:
	var world = game.world
	var candidates := refit_candidates(world, station.id)
	var vessel: Dictionary = resolved_refit_ship(world, station.id)
	if vessel.is_empty():
		game.title(flow, "本站当前没有停靠的自有舰船。请先停靠本站或在本站船坞购买舰船。", 16, game.DIM, true)
		return
	var lead_id: int = world.ride().get("id", 0)
	var ship_bar: HBoxContainer = game.hbox(flow)
	game.title(ship_bar, "整备舰船", 15, game.GOLD)
	var ship_labels := candidates.map(func(s):
		var tag: String = "旗舰" if s.id == lead_id else ("船长:" + world.name_of(s.captain) if s.captain != 0 else "未配船长")
		return "#%d %s · %s" % [s.id, world.HULLS[s.kind], tag])
	var selected_idx := 0
	for i in range(candidates.size()):
		if candidates[i].id == vessel.id:
			selected_idx = i
			break
	var ship_pick: OptionButton = game.choice(ship_bar, ship_labels, selected_idx)
	ship_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_pick.item_selected.connect(func(idx: int):
		refit_ship_id = candidates[idx].id
		slot_index = 0
		game.refresh())
	var spec: Dictionary = Hulls.COMBAT[vessel.kind]
	var used_op := Hulls.fitting_cost(vessel.kind, vessel.fit)
	var crew_lim := Hulls.crew_limits(vessel.kind)
	if slot_index >= spec.slots.size():
		slot_index = 0
	var bench := RefitBench.instantiate()
	flow.add_child(bench)
	var diagram: Blueprint = bench.get_node("Plan/Blueprint")
	blueprint = diagram
	diagram.configure(vessel.kind,slot_index,vessel.fit.weapons)
	diagram.selected.connect(func(index: int): slot_index = index; game.refresh())
	var families := {}
	for mount in Hulls.MODELS[vessel.kind].mounts:
		families[mount.family] = true
	for family in families:
		game.title(bench.get_node("Plan/Legend"),"● "+Blueprint.family_name(family),12,Blueprint.family_color(family))
	var summary: VBoxContainer = bench.get_node("Summary")
	var budget = game.title(summary, "%s  /  OP %d / %d" % [world.HULLS[vessel.kind], used_op, spec.op], 20, Color("eef1e9"))
	game.entity_menus.bind(budget,"ship",vessel.id)
	game.glossary.bind(budget, "op")
	var flux_readout = game.title(summary, "幅能上限 %.0f · 散热 %.1f/s · 装甲 %.0f · 系统 %s" % [Hulls.capacity(vessel), Hulls.dissipation(vessel), spec.armor, Battle.system_label(vessel)], 14, game.GOLD)
	game.glossary.bind(flux_readout,"flux")
	var system := Battle.Abilities.profile(vessel)
	if system.has("description"):
		game.title(summary, system.description, 14, game.INK, true)
	if not vessel.fit.wings.is_empty():
		game.title(summary,"机库联队　"+" · ".join(vessel.fit.wings.map(func(id): return Hulls.wing_spec(id).name)),14,game.INK,true)
	var tune_row = game.hbox(summary)
	game.title(tune_row, "电容 %d/%d" % [vessel.fit.caps,Hulls.MODELS[vessel.kind].tuning_limit], 14, game.INK)
	game.button(tune_row, "-", func(): game.hud.result(Economy.refit_tuning(world, station.id, -1, 0, vessel.id), "已卸除 1 点电容（退 ¢4）。"), vessel.fit.caps > 0)
	game.button(tune_row, "+", func(): game.hud.result(Economy.refit_tuning(world, station.id, 1, 0, vessel.id), "已加装 1 点电容（¢8）。"), used_op < spec.op and vessel.fit.caps < Hulls.MODELS[vessel.kind].tuning_limit and world.active().wallet >= 8)
	game.title(tune_row, "  散热 %d/%d" % [vessel.fit.vents,Hulls.MODELS[vessel.kind].tuning_limit], 14, game.INK)
	game.button(tune_row, "-", func(): game.hud.result(Economy.refit_tuning(world, station.id, 0, -1, vessel.id), "已卸除 1 点散热（退 ¢4）。"), vessel.fit.vents > 0)
	game.button(tune_row, "+", func(): game.hud.result(Economy.refit_tuning(world, station.id, 0, 1, vessel.id), "已加装 1 点散热（¢8）。"), used_op < spec.op and vessel.fit.vents < Hulls.MODELS[vessel.kind].tuning_limit and world.active().wallet >= 8)
	var crew_row = game.hbox(summary)
	game.title(crew_row, "船员 %d / 最低 %d · 满编 %d（效率 %d%%）" % [vessel.crew, crew_lim.x, crew_lim.y, roundi(Hulls.crew_efficiency(vessel) * 100.0)], 14, game.INK)
	if vessel.id == lead_id:
		game.button(crew_row, "招 +5", func():
			var hired := Economy.crew(world, 5)
			game.hud.result(hired > 0, "已招募 %d 名船员。" % hired, "资金、当地人口或铺位不足。"))
		game.button(crew_row, "遣 -5", func():
			var left := Economy.crew(world, -5)
			game.hud.result(left < 0, "已遣散 %d 名船员。" % absi(left), "当前无可遣散船员。"))
	var slots := []
	for i in range(spec.slots.size()):
		var slot := Hulls.slot_spec(vessel.kind, i)
		var gun: Dictionary = Hulls.WEAPONS.get(vessel.fit.weapons[i], {})
		slots.append("[%d] %s　%s" % [i+1, Blueprint.mount_label(slot), gun.get("name", "空槽位")])
	var plans := Hulls.presets(vessel.kind)
	if not plans.is_empty():
		var menu = game.hbox(flow)
		var loadouts = game.choice(menu,plans.map(func(entry): return entry.id))
		game.button(menu,"按本站价格换装",func(): game.hud.result(Economy.refit_preset(world,station.id,plans[loadouts.selected].reference_path,vessel.id),"整套预设已装舰。","本站缺货、资金不足或无整备权限。"))
	if not slots.is_empty():
		var weapons = game.hbox(flow)
		var pick = game.choice(weapons, slots, slot_index)
		pick.item_selected.connect(func(i: int): slot_index = i; game.refresh())
		var group: int = vessel.fit.groups[slot_index]
		game.button(weapons, "武器组 %d" % group, func():
			Economy.refit_group(world, station.id, slot_index, group % 3 + 1, vessel.id)
			game.refresh())

func show_hull(flow: Control, station: Dictionary) -> void:
	var world = game.world
	var model: Dictionary = Hulls.MODELS[model_id]
	var combat: Dictionary = Hulls.COMBAT[model_id]
	var invoice := Economy.ship_quote(station, model_id)
	var chart := HullScale.new()
	chart.configure(model_id)
	chart.class_selected.connect(func(kind: int):
		model_id = kind
		game.refresh())
	flow.add_child(chart)

	var row: HBoxContainer = game.hbox(flow)
	row.add_theme_constant_override("separation", 10)

	# Left: Tactical Blueprint & Mount Legend
	var preview_card := UIKit.card(row, UIKit.CYAN)
	var preview_panel := preview_card.get_parent() as PanelContainer
	preview_panel.size_flags_horizontal = Control.SIZE_FILL
	preview_panel.custom_minimum_size.x = 264
	game.title(preview_card, "战术蓝图与出厂武备", 13, UIKit.CYAN)
	var diagram := Blueprint.new()
	diagram.custom_minimum_size = Vector2(240, 184)
	diagram.configure(model_id, -1, Hulls.stock_fit(model_id).weapons)
	preview_card.add_child(diagram)
	var legend: HBoxContainer = game.hbox(preview_card)
	var families := {}
	for mount in model.mounts:
		families[mount.family] = true
	if families.is_empty():
		game.title(legend, "无武器挂点", 12, game.DIM)
	else:
		for family in families:
			game.title(legend, "● " + Blueprint.family_name(family), 12, Blueprint.family_color(family))
	var mount_summary := "武器位 %d  ·  机库 %d  ·  部署点 %d" % [model.mounts.size(), model.fighter_bays, model.dp]
	game.title(preview_card, mount_summary, 12, game.DIM)

	# Right: Ship Dossier & Procurement
	var spec := UIKit.card(row, UIKit.GOLD)
	var hdr: HBoxContainer = game.hbox(spec)
	var title_lbl: Label = game.title(hdr, model.name, 20, Color("eef1e9"))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.badge(hdr, Hulls.CLASS_NAMES[model.size], "gold")
	UIKit.badge(hdr, model.role, "info")
	UIKit.badge(hdr, "¢%s" % invoice.price, "ok")

	game.title(spec, Art.hull_description(model_id), 14, game.INK, true)

	var bars: VBoxContainer = game.vbox(spec)
	bars.add_theme_constant_override("separation", 3)
	UIKit.meter(bars, "船体", float(model.hp), 1600.0, "ok", "%d" % int(model.hp))
	UIKit.meter(bars, "装甲", float(combat.armor), 320.0, "gold", "%.0f" % float(combat.armor))
	UIKit.meter(bars, "幅能", float(combat.capacity), 1200.0, "info", "%.0f · 散热 %.0f/s" % [float(combat.capacity), float(combat.dissipation)])
	UIKit.meter(bars, "装配", float(combat.op), 160.0, "info", "%d OP · 货仓 %d" % [int(combat.op), int(model.cargo)])

	var sys_name: String = Hulls.SYSTEM_NAMES.get(combat.system, combat.system)
	var crew_lim := Hulls.crew_limits(model_id)
	UIKit.kv_grid(spec, [
		["战术系统", sys_name, "gold"],
		["船员编制", "%d / %d" % [crew_lim.x, crew_lim.y]],
		["原型编号", Hulls.hull_id(model_id), "dim"],
		["在本港库存", "%s 艘" % station.hulls[model_id] if Hulls.model_limit(station, model_id) else "泊位不足", "ok" if station.hulls[model_id] > 0 and Hulls.model_limit(station, model_id) else "warn"],
	], 2)

	var quote_box := UIKit.card(spec, Color.TRANSPARENT, true)
	var breakdown := PackedStringArray()
	for item in invoice.materials:
		breakdown.append("%s×%d ¢%d" % [world.WARES[item.ware], item.units, item.cost])
	var production := {"universal":"通用工业链", "direct":"短链制造", "recycling":"回收制造"}
	game.title(quote_box, "%s · 补料 ¢%d　%s" % [production[invoice.method], invoice.material_cost, "、".join(breakdown)], 13, game.INK, true)
	game.title(quote_box, "船厂人工 %d 工时 × ¢%.2f = ¢%d　设施费 ¢%d　港税 ¢%d" % [invoice.labor_hours, invoice.hourly_wage, invoice.labor_cost, invoice.yard_fee, invoice.tax], 12, game.DIM, true)

	var work: Dictionary = station.get("yard_work", {})
	if not work.is_empty():
		game.title(spec, "在建　%s　%d / %d 工时" % [world.HULLS[work.kind], work.hours, work.required], 14, game.GOLD)
	for vessel in world.ships.values():
		if vessel.get("charter", {}).get("operator", 0) == world.player and vessel.charter.port == station.id:
			var quote := Economy.charter_quote(world, vessel.id)
			var detail: String = "买断后可委派船长，船体可由后人继承。" if quote.ok else quote.reason
			game.title(spec, "航务局工船 #%d · %s　新造 ¢%d，折旧减 ¢%d。%s" % [vessel.id, world.HULLS[vessel.kind], quote.replacement_price, quote.depreciation, detail], 13, game.DIM, true)
			game.button(spec, "买断在用工船　¢%d" % quote.price, func():
				game.hud.result(Economy.buyout_charter(world, vessel.id, quote.price), "工船已登记到你名下。", "买断条件或报价已变化，请核对新报价。"), quote.ok)
	if game.world.oversees(station.owner) and 2 in station.modules and Hulls.model_limit(station, model_id):
		game.button(spec, "委托船厂建造", func(): game.hud.result(Economy.order_hull(game.world, station.id, model_id), "建造订单已登记。"))
	if station.hulls[model_id] > 0 and Hulls.model_limit(station, model_id):
		game.button(spec, "购买并登记到本站", func():
			var bought := Economy.buy_ship(world, station.id, model_id, invoice.price)
			if bought != 0:
				last_bought_ship_id = bought
				refit_ship_id = bought
			game.hud.result(bought != 0, "新船 #%d 已停靠在本站，可直接整备或到「资产」编队。" % bought, "库存、资金或报价已变化，请核对本站报价。"), world.active().wallet >= invoice.price)
		if world.oversees(station.owner) or world.oversees(station.get("manager", 0)):
			var assign_row: HBoxContainer = game.hbox(spec)
			for duty in [["贸易", "站属贸易"], ["采矿", "站属采矿"], ["巡逻", "巡逻"]]:
				var d_label: String = duty[0]
				var d_kind: String = duty[1]
				game.button(assign_row, "购舰直派:" + d_label, func():
					var bought := Economy.buy_and_assign_to_station(world, station.id, model_id, d_kind, invoice.price)
					if bought != 0:
						last_bought_ship_id = bought
						refit_ship_id = bought
					game.hud.result(bought != 0, "已购入 #%d 并配船长直派执行「%s」（含 ¢55 雇佣费）。" % [bought, d_kind], "资金（需舰价+¢55）、库存或权限不足。"), world.active().wallet >= invoice.price + 55)
	var bought_ship: Dictionary = world.ships.get(last_bought_ship_id, {})
	if not bought_ship.is_empty() and bought_ship.dock == station.id and world.oversees(bought_ship.owner):
		var quick: HBoxContainer = game.hbox(spec)
		game.button(quick, "整备 #%d %s" % [bought_ship.id, world.HULLS[bought_ship.kind]], func():
			refit_ship_id = bought_ship.id
			slot_index = 0
			mode = "refit"
			game.refresh())
		game.button(quick, "在「资产」查看 / 指挥", func():
			game.hud.selected_ship_id = bought_ship.id
			game.tab = "资产"
			game.refresh())

func conversation(flow: Control, station: Dictionary) -> void:
	var world = game.world
	var contact: Dictionary = world.people[contact_id]
	var character_row = game.hbox(flow)
	Art.contained(character_row, Art.face(Portrait.for_actor(world,contact)), Vector2(106, 117))
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
	if station.get("landing_only",false):
		var planet: Dictionary = world.systems[station.system].planets[station.planet_index]
		game.button(body,"勘测着陆区",func(): game.hud.result(world.Celestial.survey(world,vessel),"已完成行星勘测。"),not planet.surveyed)
		var primary = game.choice(body,world.MODULES)
		var foundation: Dictionary = Economy.Industry.CONSTRUCTION.foundation
		game.button(body,"建立行星港　¢%d" % foundation.credits,func(): game.hud.result(world.PlanetPorts.found(world,primary.selected),"已设立行星港工地。"),planet.surveyed and actor.wallet >= foundation.credits)
		game.button(body,"起飞",game.flight.dock)
		return
	if station.build > 0 or station.expansion > 0:
		var requirements := Economy.build_requirements(station)
		var need: Array = []
		for ware in requirements:
			need.append("%s %d/%d" % [world.WARES[ware],station.build_storage[ware],requirements[ware]])
		game.hud.hint(body, "施工仓　" + " · ".join(need))
		game.button(body, "卸下建站材料", func(): game.hud.result(Economy.donate(world, station.id) > 0, "建材已卸到工地。"))
		if station.build > 0:
			game.button(body,"离开工地",game.flight.dock)
			return
	if mode == "welcome":
		var q: Dictionary = Economy.supply_fleet_quote(world, station.id)
		var qcard := UIKit.card(body, UIKit.CYAN)
		var qtitle := "一键全队补给整备（%d 艘 · 约 ¢%d）" % [int(q.ships), int(q.cost)] if bool(q.needs_service) else "一键全队补给整备（全队满状态）"
		UIKit.action_button(qcard, qtitle, func():
			var n := Economy.supply_fleet(world, station.id)
			game.hud.result(n > 0, "已为 %d 艘停泊舰船完成维修与加注燃料。" % n, "全队已满血满油，或资金/站点库存不足。"),
			"primary", bool(q.needs_service), "所有停泊舰船均已满船体与满燃料", true)
		var nav_row: HBoxContainer = game.hbox(qcard)
		UIKit.action_button(nav_row, "货栈", func(): mode = "market"; game.refresh(), "ghost", true, "", true)
		UIKit.action_button(nav_row, "船坞", func(): mode = "yard"; game.refresh(), "ghost", true, "", true)
		UIKit.action_button(nav_row, "改装", func(): mode = "refit"; game.refresh(), "ghost", true, "", true)
		UIKit.action_button(nav_row, "离港 E", game.flight.dock, "default", not vessel.is_empty(), "未登舰", true)
	match mode:
		"market":
			game.hud.market(body, station)
		"refit":
			refit_sidebar(body, station)
		"yard":
			if Economy.Industry.Module.YARD in station.modules:
				var contractor: Dictionary = world.ConstructionContract.active_ship(world)
				if contractor.is_empty():
					var offer: Dictionary = world.ConstructionContract.offer(world,station.id)
					var hire = game.button(body,"雇工程舰建站　¢%d" % offer.fee,func():
						game.hud.result(world.ConstructionContract.hire(world,station.id) != 0,"工程船长已签约，离港后随旗舰前往工地。"),offer.ok)
					hire.tooltip_text = "一次建站服务，工地另付建材和开工费。" if offer.ok else offer.reason
				elif contractor.construction_contract.status == "working":
					var site: Dictionary = world.ports[contractor.construction_contract.site]
					game.hud.hint(body,"工程舰 #%d 正在「%s」施工，剩余 %d 日。完工后返厂。" % [contractor.id,site.name,site.build])
				else:
					game.hud.hint(body,"已雇用工程舰 #%d · 随旗舰前往工地" % contractor.id)
					game.button(body,"解除建站委托",func(): game.hud.result(world.ConstructionContract.cancel(world),"委托已解除，工程舰返厂。"))
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
			game.button(body, "全队补给修理", func():
				var count := Economy.supply_fleet(world, station.id)
				game.hud.result(count > 0, "已为 %d 艘同港自有船补给修理。" % count, "同港自有船均已满状态，或资金/库存不足。"))
		"people":
			for resident in world.people.values():
				if resident.id == actor.id or not resident.alive or resident.loc != actor.loc or Politics.age(world, resident) < 18:
					continue
				var role := "负责人" if resident.id == station.manager else ("贵族" if resident.noble else "船员 / 旅客")
				var prow: HBoxContainer = game.hbox(body)
				var talk_btn: Button = game.button(prow, "%s  ·  %s" % [resident.name, role], func(): talk(resident.id))
				talk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				game.hud.bind_character_menu(talk_btn, resident.id)
				var dbtn: Button = game.button(prow, "档案", func(): game.hud.dossier.open(game, resident.id))
				game.hud.bind_character_menu(dbtn, resident.id)
		"talk":
			var contact: Dictionary = world.people.get(contact_id, {})
			if not contact.get("alive", false) or contact.loc != actor.loc:
				game.hud.hint(body, "这个人已经不在站内。")
				return
			dialogue_options(body, station, contact)
		_:
			var manager: Dictionary = world.people.get(station.manager, {})
			if manager.get("alive", false) and manager.loc == station.id and manager.id != actor.id:
				var row = game.hbox(body)
				Art.contained(row, Art.face(Portrait.for_actor(world,manager)), Vector2(56, 63))
				var info = game.vbox(row)
				game.title(info, manager.name, 18)
				game.button(info, "和负责人谈谈", func(): talk(manager.id))
			if int(station.manager) == actor.id:
				game.hud.hint(body, "你是本站站长（每 6 日领取俸禄，可统筹本站运营与开发）。")
			elif int(station.flag) >= 0:
				var is_ruler := false
				for fid in world.factions:
					if world.factions[fid].alive and int(world.factions[fid].leader) == actor.id:
						is_ruler = true
						break
				if int(actor.flag) != int(station.flag) and not is_ruler and not world.hostile(int(actor.flag), int(station.flag)):
					var join_btn: Button = game.button(body, "加入 %s 阵营" % world.flag_name(int(station.flag)), func():
						game.hud.result(Politics.join_faction(world, actor.id, int(station.flag)), "已加入 %s。" % world.flag_name(int(station.flag)), "当前无法加入该阵营。"))
					join_btn.tooltip_text = "收益：信任 +15、领袖好感 +10、每 6 日领阵营俸禄、可受雇任站长。\n风险：敌对势力信任 -20，脱离原阵营信任 -15，战时将被敌方拦截。"
				elif int(actor.flag) == int(station.flag) and int(world.factions[station.flag].leader) != actor.id and int(station.manager) != int(world.factions[station.flag].leader):
					game.button(body, "受雇成为本站站长（不驾船）", func():
						game.hud.result(Politics.employ_as_manager(world, actor.id, station.id), "已出任 %s 站长。" % station.name, "无法受雇出任本站站长。"))
			if vessel.is_empty():
				game.hud.hint(body, "你目前不驾驶飞船（可在「资产」查看名下舰队或登舰）。")
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
	game.button(body,"人物档案",func(): game.hud.dossier.open(game,contact.id))
	game.button(body,"和此人交易",func(): game.open_trade_table("person",contact.id))
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
	var gift = game.button(body, "「送你一点心意。」 · ¢%d" % int(world.Society.rules.personal_gift.cost), func():
		if Politics.influence(world, contact.id):
			topic = "「心意我收下了。下次靠港，记得来打声招呼。」"
		game.refresh(), Politics.can_gift(world,contact.id))
	if Politics.gift_wait(world,contact.id) > 0:
		gift.tooltip_text = "%d 日后可再次赠礼。" % Politics.gift_wait(world,contact.id)
	if actor.noble and contact.noble and actor.spouse == 0 and contact.spouse == 0:
		game.button(body, "「说说我们两家的事。」 · 提议联姻", func():
			topic = "「我们可以商议盟约了。」" if Politics.marry(world, actor.id, contact.id) else "「现在还不是时候。」"
			game.refresh())
	game.button(body, "「回头见。」", func(): mode = "people"; game.refresh())

func wing_workshop(body: Node, station: Dictionary, vessel: Dictionary) -> void:
	var installed: Array = vessel.fit.wings
	if installed.is_empty():
		return
	var fixed: Array = Hulls.MODELS[vessel.kind].builtin_wings
	game.title(body,"舰载联队",18,game.INK)
	var bays := []
	for i in installed.size():
		bays.append("%d 号机库 · %s%s" % [i+1,Hulls.wing_spec(installed[i]).name,"（内置）" if i < fixed.size() else ""])
	var bay = game.choice(body,bays,mini(fixed.size(),installed.size()-1))
	if fixed.size() == installed.size():
		game.hud.hint(body,"本舰使用专用机库，固定搭载出厂联队。")
		return
	var ids := Hulls.wing_ids()
	var choice = game.choice(body,ids.map(func(id): return Hulls.wing_spec(id).name))
	var details = game.title(body,"",14,game.DIM,true)
	var install: Button = game.button(body,"制造并装入机库",func():
		game.hud.result(Economy.refit_wing(game.world,station.id,bay.selected,ids[choice.selected],vessel.id),"联队已装舰。","机库、库存、资金或整备权限不满足。"))
	var preview := func():
		var spec := Hulls.wing_spec(ids[choice.selected])
		var offer := Economy.wing_exchange([installed[bay.selected]],[spec.id])
		var parts := PackedStringArray()
		var stocked := true
		for ware in offer.materials:
			var available := Economy.Industry.available(station,ware)
			parts.append("%s %d/%d" % [game.world.WARES[ware],available,offer.materials[ware]])
			stocked = stocked and available >= int(offer.materials[ware])
		var origin := " · 转接规格" if not spec.native_trade else ""
		details.text = "%s · %d 架 · 补充 %.1f 秒%s\n%s" % [spec.specialty,spec.count,spec.refit,origin,"　".join(parts)]
		install.text = "已装舰" if installed[bay.selected] == spec.id else "制造并换装（结算 ¢%d）" % offer.net
		install.disabled = installed[bay.selected] == spec.id or bay.selected < fixed.size() or not stocked or offer.net > game.world.active().wallet
	var select_bay := func(index: int):
		choice.select(ids.find(installed[index]))
		preview.call()
	bay.item_selected.connect(select_bay)
	choice.item_selected.connect(func(_idx): preview.call())
	select_bay.call(bay.selected)

func refit_sidebar(body: Node, station: Dictionary) -> void:
	var world = game.world
	var vessel: Dictionary = resolved_refit_ship(world, station.id)
	if vessel.is_empty():
		game.hud.hint(body, "本站当前没有可整备的自有舰船。")
		return
	var spec: Dictionary = Hulls.COMBAT[vessel.kind]
	if slot_index >= spec.slots.size():
		slot_index = 0
	if spec.slots.is_empty():
		game.hud.hint(body, "这型舰船没有武器挂点。")
		wing_workshop(body,station,vessel)
		return
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
	var market := preload("res://scripts/ui/refit_market.gd").new()
	body.add_child(market)
	market.configure(game,station,black_weapons,slot_index,vessel.id)
	if is_instance_valid(blueprint) and blueprint.is_inside_tree():
		blueprint.inspected.connect(market.show_mount)
	wing_workshop(body,station,vessel)
