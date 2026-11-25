extends RefCounted

const Portrait = preload("res://portrait.gd")
const Economy = preload("res://economy.gd")
const Politics = preload("res://politics.gd")
const Art = preload("res://presentation.gd")
const Hulls = preload("res://hull_catalog.gd")
const Celestial = preload("res://celestial.gd")
const StationDesigner = preload("res://scripts/ui/station_designer.gd")
const CargoIcons = preload("res://scripts/ui/cargo_icons.gd")
const FreightNotice = preload("res://scripts/economy/freight_notice.gd")
const MARKET_FIELDS := ["PortStock","ShipCargo","Ask","Bid"]
const MARKET_WIDTHS := [42,42,48,48]

var game
var black_market := false
var market_rows: Dictionary = {}
var market_context := Vector2i(-1,-1)
var market_population: Label
var market_tax: Label
var selected_ship_id := 0
var asset_filter := "all"
var report_open := false
var diagnostics_open := false
var diagnostic_ship := 0
var report_days := 30
var report_asset := 0
var equity = preload("res://scripts/ui/equity_panel.gd").new()
var dossier = preload("res://scripts/ui/person_dossier.gd").new()
const UIKit = preload("res://scripts/ui/ui_kit.gd")
var roster_query := ""
var roster_role := "全部"
var history_filter := "全部"

func heading(body: Node, text: String) -> Label:
	return game.title(body, text, 20, game.GOLD)

func hint(body: Node, text: String) -> Label:
	return game.title(body, text, 14, game.DIM, true)

func result(success: bool, yes: String, no: String = "条件未满足。") -> void:
	game.say(yes if success else no)
	game.refresh()

func bind_character_menu(control: Control, target_id: int) -> void:
	if target_id > 0:
		game.entity_menus.bind(control,"person",target_id)

func bind_location_menu(control: Control, port_id: int, system_id: int = -1) -> void:
	if port_id > 0:
		game.entity_menus.bind(control,"port",port_id)
	elif system_id >= 0:
		game.entity_menus.bind(control,"system",system_id)

func open_location_menu(port_id: int, system_id: int = -1, planet_id: int = -1) -> void:
	var world = game.world
	var port: Dictionary = world.ports.get(port_id,{})
	if not port.is_empty():
		system_id = port.system
	if system_id not in range(world.systems.size()):
		return
	var region: Dictionary = world.systems[system_id]
	var planet: Dictionary = region.planets[planet_id] if planet_id in range(region.planets.size()) else {}
	var menu := PopupMenu.new()
	var label: String = planet.name if not planet.is_empty() else str(port.get("name",region.name))
	menu.add_separator(label)
	var vessel: Dictionary = world.ride()
	var local: bool = not vessel.is_empty() and not vessel.layer and vessel.system == system_id
	var destination := port_id
	if not planet.is_empty():
		destination = planet.get("port_id",0)
	elif port.is_empty():
		for id in region.ports:
			if world.ports[id].build == 0 and not world.ports[id].get("landing_only",false):
				destination = id
				break
	if world.ports.has(destination) and world.ports[destination].build == 0:
		menu.add_item("直达导航　%s" % world.ports[destination].name,1)
		menu.set_item_disabled(menu.get_item_index(1),vessel.is_empty())
	if local and not planet.is_empty() and not vessel.dock:
		menu.add_item("追踪行星着陆点",2)
	if not port.is_empty() and can_target_station(vessel,port,world.active().flag):
		menu.add_item("攻击本站防务" if port.owner == world.player else "进攻此港",8)
	if not vessel.is_empty() and vessel.layer and port.is_empty() and planet.is_empty():
		menu.add_item("追踪星系信标",3)
	if port_id != 0 or planet_id >= 0:
		menu.add_item("所属星系　" + region.name,4)
	elif local:
		menu.add_item("打开本星系星图",5)
	var flag: int = port.get("flag",world.local_flag(system_id))
	if flag >= 0:
		menu.add_item("查看所属势力　" + world.flag_name(flag),6)
	var station_manager: int = port.get("manager",0)
	if world.people.get(station_manager,{}).get("alive",false):
		menu.add_item("联络站长　"+world.name_of(station_manager),9)
	if world.factions.has(flag) and world.factions[flag].alive:
		menu.add_item("联络阵营领袖　"+world.lead_name(flag),10)
	if menu.item_count == 1:
		menu.add_item("星图坐标　%s" % str(region.pos),7)
		menu.set_item_disabled(menu.get_item_index(7),true)
	var select_location := func(id):
		match id:
			1: game.navigate_to_station(destination)
			2:
				var flagship: Dictionary = world.ride()
				if not flagship.is_empty() and not flagship.layer and not flagship.dock and flagship.system == system_id:
					game.track_planet(planet_id)
			3:
				if world.ride().get("layer",false): game.set_waypoint(region.pos,region.name)
			4: open_location_menu(0,system_id)
			5:
				game.entity_menus.reveal_panel()
				if not game.system_chart: game.toggle_system_chart()
			6:
				game.entity_menus.reveal_panel()
				game.tab = "疆域"
				game.refresh()
			8: attack(port_id,false,port.owner == world.player)
			9: open_character_menu(port.get("manager",0))
			10: open_character_menu(world.factions[flag].leader)
	menu.id_pressed.connect(select_location)
	game.entity_menus.present(menu)

func open_space_object_menu(kind: String, object_id: int, system_id: int) -> void:
	var world = game.world
	if system_id not in range(world.systems.size()):
		return
	var region: Dictionary = world.systems[system_id]
	var vessel: Dictionary = world.ride()
	var menu := PopupMenu.new()
	match kind:
		"wreck":
			var wreck: Dictionary = world.wrecks.get(object_id, {})
			if wreck.is_empty():
				return
			menu.add_separator("残骸 #%d" % object_id)
			var loot := PackedStringArray()
			for wi in range(mini(world.WARES.size(), wreck.stock.size())):
				if int(wreck.stock[wi]) > 0:
					loot.append("%s×%d" % [world.WARES[wi], int(wreck.stock[wi])])
			if not loot.is_empty():
				menu.add_item("物资：" + "、".join(loot), 99)
				menu.set_item_disabled(menu.get_item_index(99), true)
			if not vessel.is_empty() and not vessel.layer and vessel.system == system_id and vessel.dock == 0:
				menu.add_item("前往打捞", 1)
				menu.add_item("设为航点", 2)
			menu.id_pressed.connect(func(act: int):
				if act == 1:
					game.set_waypoint(Vector2(wreck.pos), "残骸 #%d" % object_id, Callable(), func(gap: float):
						if gap < 80.0:
							game.flight.salvage()
							return true
						return false)
				elif act == 2:
					game.set_waypoint(Vector2(wreck.pos), "残骸 #%d" % object_id))
		"field":
			menu.add_separator("%s · 矿带（余量 %d）" % [region.name, int(region.get("ore", 0))])
			if not vessel.is_empty() and not vessel.layer and vessel.system == system_id and vessel.dock == 0:
				menu.add_item("前往采掘", 1)
				menu.add_item("设为航点", 2)
			menu.id_pressed.connect(func(act: int):
				if act == 1:
					game.set_waypoint(Vector2(region.field), "矿带", Callable(), func(gap: float):
						if gap < 85.0:
							game.flight.salvage()
							return true
						return false)
				elif act == 2:
					game.set_waypoint(Vector2(region.field), "矿带"))
		"gravity":
			var gp := Celestial.gravity_point(region)
			menu.add_separator("%s · 恒星引力点" % region.name)
			if not vessel.is_empty() and not vessel.layer and vessel.system == system_id and vessel.dock == 0:
				if Celestial.at_gravity_point(region, vessel.pos):
					menu.add_item("立即跃入超空间 (M)", 3)
				else:
					menu.add_item("前往引力点并跃迁", 1)
					menu.add_item("设为航点", 2)
			menu.id_pressed.connect(func(act: int):
				if act == 3:
					game.flight.change_layer()
				elif act == 1:
					game.set_waypoint(gp, "恒星引力点", Callable(), func(gap: float):
						if gap <= Celestial.JUMP_RANGE * 0.8:
							game.flight.change_layer()
							return true
						return false)
				elif act == 2:
					game.set_waypoint(gp, "恒星引力点"))
	if menu.item_count <= 1:
		menu.add_item("当前不在本地航行中", 98)
		menu.set_item_disabled(menu.get_item_index(98), true)
	game.entity_menus.present(menu)

func open_ship_menu(id: int) -> void:
	var world = game.world
	var ship: Dictionary = world.ships.get(id,{})
	if ship.is_empty():
		return
	var menu := PopupMenu.new()
	menu.add_separator("#%d %s" % [id,world.HULLS[ship.kind]])
	if world.people.has(ship.captain):
		menu.add_item("船长档案　" + world.name_of(ship.captain),1)
		if ship.captain != world.player and world.people[ship.captain].alive:
			menu.add_item("呼叫船长",7)
	menu.add_item("所在位置　" + ship_location_text(world,ship),2)
	menu.set_item_disabled(menu.get_item_index(2),ship.layer)
	if Economy.Diagnostics.accessible(world,ship):
		menu.add_item("查看舰船运行诊断",3)
	var lead: Dictionary = world.ride()
	var contact: bool = game.watch_ship_id == 0 and not lead.is_empty() and lead.id != id and game.Battle.available(lead,lead.system) and game.Battle.available(ship,lead.system) and game.flight.visible_contact(lead,ship)
	if contact:
		menu.add_item("选为目标",4)
		menu.add_item("旗舰自动攻击",5)
		menu.add_item("设置跟随航点",8)
		if game.canvas.tactical_open():
			menu.add_item("命令僚舰集火",6)
	var select_ship := func(action):
		var current: Dictionary = world.ships.get(id,{})
		if current.is_empty():
			game.say("舰船已离场。")
			return
		match action:
			1:
				if world.people.has(current.captain):
					game.entity_menus.reveal_panel()
					dossier.open(game,current.captain)
			2:
				if not current.layer: open_location_menu(current.dock,current.system)
			3:
				if Economy.Diagnostics.accessible(world,current):
					game.entity_menus.reveal_panel()
					open_diagnostics(id)
			4:
				var flagship: Dictionary = world.ride()
				if not flagship.is_empty() and game.Battle.available(flagship,flagship.system) and game.Battle.available(current,flagship.system) and game.flight.visible_contact(flagship,current):
					game.selected_target = id
			5: game.flight.attack_target(id)
			6:
				var sent: int = game.flight.issue(2,id,game.canvas.fleet_selection)
				game.say("已下令 %d 艘僚舰集火。" % sent if sent > 0 else "没有可接令的僚舰。")
			7: open_character_menu(current.captain)
			8:
				var flagship: Dictionary = world.ride()
				if not flagship.is_empty() and game.Battle.available(flagship,flagship.system) and game.Battle.available(current,flagship.system) and game.flight.visible_contact(flagship,current):
					game.select_chart_target({"kind":"ship","name":"#%d %s" % [id,world.HULLS[current.kind]],"id":id,"pos":current.pos})
					game.navigate_chart_target()
	menu.id_pressed.connect(select_ship)
	game.entity_menus.present(menu)

func open_character_menu(target_id: int) -> void:
	var world = game.world
	var actor: Dictionary = world.active()
	var target: Dictionary = world.people.get(target_id, {})
	if target.is_empty():
		return
	var menu := PopupMenu.new()
	var handlers: Dictionary = {}
	var next_id := 1
	menu.add_item("查看角色档案 (%s)" % target.name, next_id)
	handlers[next_id] = func():
		game.entity_menus.reveal_panel()
		dossier.open(game,target_id)
	next_id += 1
	if target_id != world.player:
		var watched: bool = world.is_watched(target_id)
		menu.add_item(("☆ 取消特别关注 (%s)" if watched else "★ 特别关注 (%s)") % target.name, next_id)
		handlers[next_id] = func():
			var on: bool = world.toggle_watch(target_id)
			result(true, ("已特别关注 %s，后续动态将实时播报。" % target.name) if on else ("已取消关注 %s。" % target.name))
		next_id += 1
	var target_port := 0
	if int(target.get("loc", 0)) > 0 and world.ports.has(int(target.loc)):
		target_port = int(target.loc)
	elif int(target.get("ship", 0)) > 0 and world.ships.has(int(target.ship)):
		var tsh: Dictionary = world.ships[int(target.ship)]
		if int(tsh.get("dock", 0)) > 0 and world.ports.has(int(tsh.dock)):
			target_port = int(tsh.dock)
		elif not tsh.get("layer", false) and not world.systems[int(tsh.system)].ports.is_empty():
			target_port = int(world.systems[int(tsh.system)].ports[0])
	if target_port > 0 and world.ports.has(target_port) and int(world.ports[target_port].get("build", 0)) == 0:
		var dest_st: Dictionary = world.ports[target_port]
		menu.add_item("直达导航：前往 %s (%s)" % [dest_st.name, world.systems[int(dest_st.system)].name], next_id)
		handlers[next_id] = func(): game.navigate_to_station(target_port)
		next_id += 1
	if bool(world.campaign.get("cheat_mode", false)) and target_id != world.player and target.alive and int(target.get("flag", world.NEUTRAL)) != world.RAIDERS:
		menu.add_item("[作弊] 切换为此角色 (%s)" % target.name, next_id)
		handlers[next_id] = func():
			if Politics.switch_character(world, target_id):
				dossier.person_id = 0
				game.watch_ship_id = 0
				result(true, "已切换为 %s。" % target.name)
				game.run_bridge()
		next_id += 1
	if target_id != world.player and target.alive:
		var same_port: bool = actor.loc > 0 and target.loc == actor.loc
		menu.add_separator("外交与社交" if same_port else "远程外交")
		if actor.flag >= 0 and target.flag >= 0 and world.factions[target.flag].leader == target_id and world.hostile(actor.flag,target.flag) and world.Society.player_governs(world,actor.flag):
			menu.add_item("商谈两国停战条款",next_id)
			handlers[next_id] = func(): game.open_strategic_map("peace",target.flag)
			next_id += 1
		var gift_idx := next_id
		var wait_days: int = Politics.gift_wait(world, target_id)
		var gift_label := ("当面赠礼 ¢%d" if same_port else "汇赠信用点 ¢%d") % int(world.Society.rules.personal_gift.cost)
		if wait_days > 0:
			gift_label += "（%d日后）" % wait_days
		menu.add_item(gift_label, gift_idx)
		menu.set_item_disabled(menu.get_item_index(gift_idx), not Politics.can_gift(world,target_id,true))
		handlers[gift_idx] = func(): result(Politics.influence(world,target_id,true), "赠礼已送达。")
		next_id += 1
		if actor.spouse == 0 and target.spouse == 0:
			var terms: Dictionary = Politics.marriage_terms(world,world.player,target_id,true)
			var m_idx := next_id
			menu.add_item("提议联姻" if terms.dynastic else "向%s求婚" % target.name, m_idx)
			menu.set_item_disabled(menu.get_item_index(m_idx), not terms.eligible)
			handlers[m_idx] = func():
				var cur: Dictionary = Politics.marriage_terms(world,world.player,target_id,true)
				result(Politics.marry(world,world.player,target_id,true), "你与%s结为配偶。" % target.name, cur.reason)
			next_id += 1
		menu.add_separator("密谋与把柄")
		var active_scheme: Dictionary = world.campaign.schemes.get(world.player, {})
		if active_scheme.is_empty():
			var sway_idx := next_id
			menu.add_item("展开拉拢计谋" if same_port else "通过通信拉拢",sway_idx)
			handlers[sway_idx] = func(): result(world.Society.scheme(world, target_id, "sway"), "已对 %s 展开拉拢。" % target.name)
			next_id += 1
			var spy_idx := next_id
			menu.add_item("刺探秘密（获取把柄）" + ("" if same_port else "（需同港）"), spy_idx)
			menu.set_item_disabled(menu.get_item_index(spy_idx), not same_port)
			handlers[spy_idx] = func(): result(world.Society.scheme(world, target_id, "find_secrets"), "已开始刺探 %s 的秘密。" % target.name)
			next_id += 1
		elif active_scheme.target == target_id:
			var fund_idx := next_id
			menu.add_item("资助特工 ¢25（阶段 %d/3）" % active_scheme.stage, fund_idx)
			menu.set_item_disabled(menu.get_item_index(fund_idx), active_scheme.funded >= 3 or actor.wallet < 25)
			handlers[fund_idx] = func(): result(world.Society.fund_scheme(world), "已资助计谋。")
			next_id += 1
			var res_idx := next_id
			menu.add_item("收网结算计谋", res_idx)
			menu.set_item_disabled(menu.get_item_index(res_idx), active_scheme.stage < 3)
			handlers[res_idx] = func(): result(world.Society.resolve_scheme(world), "计谋已结算。")
			next_id += 1
		if world.Equity.at_market(world):
			menu.add_separator("商业与股权")
			var tr_idx := next_id
			menu.add_item("与 %s 大宗交易" % target.name, tr_idx)
			handlers[tr_idx] = func(): game.open_trade_table("person", target_id)
			next_id += 1
	menu.id_pressed.connect(func(id: int):
		if handlers.has(id):
			handlers[id].call()
		menu.queue_free())
	game.entity_menus.present(menu)

func delivery(world, station: Dictionary) -> void:
	var paid := FreightNotice.deliver(world,station)
	result(paid > 0,"交货到账 ¢%d（含运费）。" % paid,"交货未完成，请检查货量、收货港仓容、资金和准入。")

func port(body: Node) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	var actor: Dictionary = world.active()
	var port_id: int = actor.loc
	var system_index: int = game.current_system()
	if port_id == 0:
		var region: Dictionary = world.systems[system_index]
		heading(body, "星区导航" if game.galaxy else Celestial.profile(region).name)
		if not game.galaxy:
			hint(body, "%s · %s · %d 颗行星" % [region.name,"双星" if region.has("companion") else Celestial.STARS[region.sun.type][0],region.planets.size()])
		hint(body, "靠近星系信标后按 M 跃入该星系。" if game.galaxy else "到恒星旁的引力点按 M 跃入超空间。接近航站后可按 E 停靠。")
		if game.galaxy:
			var pos: Vector2 = vessel.galpos
			var nearby: Array = world.nearby_beacons(pos)
			var shown := 0
			for index in nearby:
				if shown >= 12:
					break
				var destination: Dictionary = world.systems[index]
				var broadcast: String = "燃料补给站" if destination.get("frontier_depot",false) else (world.flag_name(world.local_flag(index)) if destination.seen else "未勘测")
				var label := "%s  ·  %s  ·  %d" % [destination.name, broadcast, pos.distance_to(destination.pos)]
				var beacon = game.button(body, label, func(): game.set_waypoint(destination.pos, destination.name))
				beacon.tooltip_text = "预计耗油 %.1f" % game.flight.Hyperspace.fuel_for_distance(Hulls.MODELS[vessel.kind],pos.distance_to(destination.pos))
				shown += 1
		elif not vessel.is_empty():
			var point := Celestial.gravity_point(world.systems[system_index])
			game.button(body, "追踪恒星引力点  →", func(): game.set_waypoint(point, "恒星引力点"))
			for station_id in world.systems[system_index].ports:
				var station: Dictionary = world.ports[station_id]
				if station.get("landing_only",false):
					continue
				var caption: String = "%s  ·  %s" % [station.name, world.flag_name(station.flag)]
				game.button(body, caption + "  →", func(): game.track_port(station))
				if can_target_station(vessel,station,actor.flag):
					var actions = game.hbox(body)
					var own_defense: bool = station.owner == world.player
					game.button(actions,"攻击本站防务" if own_defense else "宣战 / 强占",func(): attack(station_id,false,own_defense))
					if actor.flag == world.NEUTRAL:
						game.button(actions, "替雇主夺站", func(): attack(station_id, true))
			var planets := MenuButton.new()
			planets.text = "行星航点（%d）" % region.planets.size()
			planets.flat = false
			body.add_child(planets)
			var menu := planets.get_popup()
			menu.about_to_popup.connect(func():
				menu.clear()
				for index in region.planets.size():
					var planet: Dictionary = region.planets[index]
					var distance: float = vessel.pos.distance_to(world.PlanetPorts.point(planet))
					menu.add_item("%s · %s · %d" % [world.PlanetPorts.caption(world,system_index,index),Celestial.PLANETS[planet.type][0],distance],index*2)
					menu.add_item("%s · 建站轨道" % planet.name,index*2+1))
			menu.id_pressed.connect(func(id: int):
				if id % 2 == 0:
					game.track_planet(id / 2)
				else:
					game.track_construction_orbit(id / 2))
		return
func chart(body: Node) -> void:
	var world = game.world
	var region: Dictionary = world.systems[game.current_system()]
	var ship: Dictionary = world.ride()
	heading(body,region.name)
	hint(body,"左键选地标，滚轮缩放。停港时可以先规划航线。")
	var controls = game.hbox(body)
	game.button(controls,"全图居中",func(): game.chart_scale = 1.0; game.chart_pan = Vector2.ZERO; game.update_bridge(0))
	game.button(controls,"关闭星图  C",game.toggle_system_chart)
	var items: Array = game.canvas.SystemChart.markers(game.canvas,world,region,game.viewed_ship())
	var selector = game.choice(body,["选择星系地标"] + items.map(func(item): return item.name))
	selector.item_selected.connect(func(index):
		if index > 0:
			game.select_chart_target(items[index-1]))
	var target: Dictionary = game.chart_target
	if target.is_empty():
		return
	game.title(body,target.name,18,game.GOLD,true)
	match target.kind:
		"port":
			var site: Dictionary = world.ports[target.id]
			hint(body,"%s · %s" % [world.flag_name(site.flag),"、".join(site.modules.map(func(m): return world.MODULES[m]))])
		"planet":
			var planet: Dictionary = region.planets[target.id]
			hint(body,"%s　半径 %d　引力圈半径 %d" % [Celestial.PLANETS[planet.type][0],roundi(planet.radius),roundi(Celestial.gravity_radius(region,planet))])
			var yields: Vector2i = Celestial.SURFACE_YIELDS.get(planet.type,Vector2i.ZERO)
			if yields.x > 0:
				hint(body,"地表可供应净水和口粮。" if yields.y > 0 else "地表冰层可供应净水。")
		"star": hint(body,"航线将前往恒星的跃迁引力点。")
	if not ship.is_empty() and ship.system == game.current_system() and not (target.kind == "ship" and target.id == ship.id):
		var here: bool = target.kind == "port" and target.id == ship.dock
		game.button(body,"已停靠此港" if here else ("离港并导航" if ship.dock != 0 else "导航至此"),game.navigate_chart_target,not here)

func market_conditions(station: Dictionary) -> String:
	var text := "市场 %s · 人口 %d/%d · 稳定度 %d%% · 居民税 %d%%" % [Economy.market_size_label(station),station.pop,station.pop_cap,roundi(station.stability),roundi(station.tax_rate*100.0)]
	var suspicion: int = game.world.active().get("suspicion",0)
	return text+" · 嫌疑 %d%%"%suspicion if suspicion>0 else text

func market_customs(station: Dictionary, black: bool) -> String:
	var world = game.world
	var flag: int = world.sovereign(station.system)
	if flag<0:
		return "商品税 0% · 无主星系"
	var group: Dictionary = world.factions[flag]
	var rate := roundi(Economy.Industry.tariff_rate(station)*100.0)
	var policy := "黑市免商品税（公开税率 %d%%）"%rate if black else "商品税 %d%%"%rate
	return "%s · %s国库 · 统治者 %s"%[policy,group.name,world.name_of(group.leader)]

func market_figures(row: HBoxContainer, captions: Array, headings: bool) -> void:
	for i in MARKET_FIELDS.size():
		var cell: Label = game.title(row,captions[i],13 if headings else 14,game.DIM if headings else game.INK)
		cell.name = MARKET_FIELDS[i]
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.custom_minimum_size.x = MARKET_WIDTHS[i]

func update_market_row(ware: int, station: Dictionary, vessel: Dictionary, black: bool) -> void:
	var row: Node = market_rows[ware].get_parent()
	var buy := Economy.price(station,ware,true,game.world.active().origin,black)
	var sell := Economy.price(station,ware,false,game.world.active().origin,black)
	var trend := "↑" if buy>Economy.BASE[ware]*1.15 else ("↓" if buy<Economy.BASE[ware]*0.9 else "")
	row.get_node("PortStock").text = str((station.black if black else station.stock)[ware])
	row.get_node("ShipCargo").text = str(vessel.cargo[ware])
	row.get_node("Ask").text = "%d%s"%[buy,trend]
	row.get_node("Bid").text = str(sell)

func market(body: Node, station: Dictionary) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	var actor: Dictionary = world.active()
	var port_id: int = station.id
	var regular: bool = world.is_regular(station)
	if not regular:
		black_market = false
	market_context = Vector2i(port_id,int(black_market))
	market_rows.clear()
	if station.firm != 0:
		hint(body, "经营商：" + world.firms[station.firm].name)
	if station.extension >= 0:
		hint(body, "扩建模块：%s%s" % [world.MODULES[station.extension], "（施工 %s 日）" % station.expansion if station.expansion > 0 else ""])
	if station.build > 0:
		var materials := PackedStringArray()
		var requirements := Economy.build_requirements(station)
		for ware in requirements:
			materials.append("%s %d/%d" % [world.WARES[ware],station.build_storage[ware],requirements[ware]])
		hint(body, "施工仓　%s · 剩余 %d 日" % [" · ".join(materials),station.build])
		game.button(body, "交付建材", func(): result(Economy.donate(world, port_id) > 0, "建材已卸到工地。"))
		return
	if not (Economy.market_open(world,actor,station) if vessel.is_empty() else Economy.allowed(world,vessel,station)):
		hint(body, "战争或企业禁运导致公开市场关闭。")
		if not world.is_regular(station):
			return
	market_population = game.title(body,market_conditions(station),14,game.DIM,true)
	market_tax = game.title(body,market_customs(station,black_market),14,game.GOLD,true)
	game.button(body,"打开交易窗口",func(): game.open_trade_table("station",port_id,black_market))
	if not vessel.is_empty():
		var supplies = game.hbox(body)
		game.button(supplies, "补充燃料", func(): result(Economy.supply(world, false), "补给完成。"), true, true)
		game.button(supplies, "修理船体", func(): result(Economy.supply(world, true), "维修完成。"), true, true)
		var crew_lim := Hulls.crew_limits(vessel.kind)
		var crew_row = game.hbox(body)
		var crew_lbl = game.title(crew_row, "船员 %d/%d（最低 %d）" % [vessel.crew, crew_lim.y, crew_lim.x], 14, game.INK)
		crew_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.button(crew_row, "招 +5", func():
			var n := Economy.crew(world, 5)
			result(n > 0, "招募 %d 名船员。" % n, "资金、当地人口或铺位不足。"))
		game.button(crew_row, "遣 -5", func():
			var n := Economy.crew(world, -5)
			result(n < 0, "遣散 %d 名船员。" % absi(n), "当前无可遣散船员。"))
		if regular:
			var mode_row = game.hbox(body)
			var pub_btn: Button = game.button(mode_row, "公开市场", func(): black_market = false; game.refresh(), true, true)
			pub_btn.toggle_mode = true
			pub_btn.button_pressed = not black_market
			var blk_btn: Button = game.button(mode_row, "黑市（免税）", func(): black_market = true; game.refresh(), true, true)
			blk_btn.toggle_mode = true
			blk_btn.button_pressed = black_market
		heading(body, "黑 市 交 易" if black_market else "挂 牌 市 场")
		hint(body,"价格为首件报价（¢）。↑ 高于常价，↓ 低于常价。")
		if black_market:
			hint(body, "黑市免关税并流通违禁品，但会累积走私嫌疑，离港时可能遭遇巡逻队盘查。")
		var stock: Array = station.black if black_market else station.stock
		var header: HBoxContainer = game.hbox(body)
		game.title(header,"",13).custom_minimum_size.x = 26
		var item_header: Label = game.title(header,"商品",13,game.DIM)
		item_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		market_figures(header,["站存","船舱","买价","卖价"],true)
		game.title(header,"",13).custom_minimum_size.x = 54
		for ware in range(world.WARES.size()):
			if not black_market and ware == 6:
				continue
			if black_market and ware < 3 and stock[ware] == 0 and vessel.cargo[ware] == 0:
				continue
			var row: HBoxContainer = game.hbox(body)
			CargoIcons.show_icon(row,"ware",ware,26)
			var line: Label = game.title(row,world.WARES[ware],14)
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			market_rows[ware] = line
			market_figures(row,["","","",""],false)
			update_market_row(ware,station,vessel,black_market)
			game.button(row,"交易",func(): game.open_trade_table("station",port_id,black_market,ware)).custom_minimum_size.x = 54
	heading(body, "委 托")
	var current: Dictionary = world.contracts.get(world.player, {})
	if current.get("type", -1) == 0:
		var target: Dictionary = world.ports[current.target]
		hint(body, "运送 %d 单位%s → %s · %s" % [current.get("quantity",8),world.WARES[current.get("ware",0)],world.systems[target.system].name,target.name])
		hint(body, "货款按到港收购价结算，另付运费 ¢%d。" % current.get("fee",0))
		game.button(body, "交货", func(): delivery(world, station), port_id == target.id)
	elif current.get("type", -1) == 1:
		hint(body, "赏金：击毁任意裂缝掠夺者。")
	elif not current.is_empty():
		hint(body, "熄火之前：到炉心转运站的联络处交货。")
	else:
		var notice := FreightNotice.offer(world,station)
		if notice.is_empty():
			hint(body,"附近暂无适合本船的采购委托。")
		else:
			var target: Dictionary = world.ports[notice.target]
			hint(body,"%s · %s 求购 %d 单位%s，航程 %d 跳。" % [world.systems[target.system].name,target.name,notice.quantity,world.WARES[notice.ware],notice.jumps])
			hint(body,"当前整批收购价 ¢%d，按到港行情结算。另付运费 ¢%d。" % [notice.estimate,notice.fee])
			game.button(body,"接运输委托",func(): result(FreightNotice.accept(world,notice),"已登记运输委托。","订单条件已变，请查看最新委托。"))
		game.button(body, "接掠夺者赏金  /  ¢180", func():
			world.contracts[world.player] = {"type": 1}
			result(true, "已登记赏金委托。"))
	if not current.is_empty():
		game.button(body, "取消当前委托", func(): world.contracts.erase(world.player); game.refresh())

func market_updated(port_id: int, ware: int, black: bool) -> void:
	if game.tab == "港口" and game.dock_view.mode == "yard" and game.dock_view.station_id == port_id and not black:
		game.refresh()
		return
	if game.tab != "港口" or game.dock_view.mode != "market" or market_context.x != port_id:
		return
	if ware >= 0 and int(black) != market_context.y:
		return
	var world = game.world
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports[port_id]
	var channel := bool(market_context.y)
	if is_instance_valid(market_population):
		market_population.text = market_conditions(station)
	if is_instance_valid(market_tax):
		market_tax.text = market_customs(station,channel)
	if vessel.is_empty() or vessel.dock != port_id:
		return
	var goods: Array = market_rows.keys() if ware < 0 else [ware]
	for item in goods:
		if not is_instance_valid(market_rows.get(item)):
			continue
		update_market_row(item,station,vessel,channel)
	game.update_header()



func can_target_station(flagship: Dictionary, station: Dictionary, _flag: int) -> bool:
	return game.watch_ship_id == 0 and not flagship.is_empty() and not station.is_empty() \
		and not station.get("landing_only",false) \
		and game.Battle.available(flagship,station.system)

func station_attack_incident(station: Dictionary) -> void:
	var world = game.world
	if not world.factions.has(station.flag) or world.hostile(world.active().flag,station.flag):
		return
	var dates: Dictionary = station.get_or_add("raid_dates",{})
	if int(dates.get(world.player,-31)) + 30 > world.day:
		return
	dates[world.player] = world.day
	world.change_faction_trust(station.flag,world.player,-25,"进攻 " + station.name)

func attack(port_id: int, mercenary: bool = false, own_defense: bool = false) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports.get(port_id,{})
	var actor: Dictionary = world.active()
	if not can_target_station(vessel,station,actor.flag) or (mercenary and actor.flag != world.NEUTRAL):
		game.say("请从旗舰视角，在目标星系的本地空间选择可进攻的航站。")
		return
	if own_defense != (station.owner == world.player):
		game.say("空间站产权已变化，请重新选择目标。")
		return
	if vessel.pos.distance_to(station.pos) > 150:
		game.say("先靠近目标空间站（150 距离内）。")
		return
	if game.flight.target(vessel, 395) != 0:
		game.say("附近有敌方守卫，先击退它们。")
		return
	if actor.flag >= 0 and station.flag >= 0 and actor.flag != station.flag and not world.hostile(actor.flag,station.flag):
		station_attack_incident(station)
		world.set_treaty(actor.flag, station.flag, -1)
		result(true, "已宣战；击退守卫后可再次发起强占。")
		return
	for guard in world.ships.values():
		if guard.id == vessel.id or not game.Battle.available(guard,station.system) or guard.pos.distance_to(station.pos) >= 510:
			continue
		var defends: bool = (station.flag >= 0 and guard.flag == station.flag) or guard.get("station_owner",0) == port_id or (station.owner != 0 and guard.owner == station.owner)
		if defends and not world.can_operate(guard):
			station_attack_incident(station)
			world.engage_ship(vessel,guard,0)
			if actor.flag == world.NEUTRAL and station.flag >= 0:
				vessel.raid = station.flag
			result(true,"突袭已暴露，守卫开始反击。")
			return
	if vessel.locked:
		flight_unlock(world, vessel)
	if vessel.hp <= station.defense * 0.5:
		game.say("船体不足以强攻防务。")
		return
	var flag: int = actor.flag
	if not mercenary and station.owner == world.player:
		if station.defense <= 0:
			game.say("本站防务已被摧毁。")
			return
		station_attack_incident(station)
		vessel.hp -= station.defense * 0.5
		station.defense = 0
		result(true,"已摧毁本站防务。")
		return
	if mercenary:
		for candidate in world.factions:
			if world.factions[candidate].alive and world.hostile(candidate, station.flag):
				flag = candidate
				break
		if flag == world.NEUTRAL:
			game.say("没有正在与目标交战的雇主。")
			return
		world.credit(world.player, 280,vessel,"作战委托")
		world.change_faction_trust(flag,world.player,5,"完成夺站委托")
	station_attack_incident(station)
	vessel.hp -= station.defense * 0.5
	Politics.conquer(world, port_id, flag, 0 if mercenary else world.player)
	vessel.raid = world.NEUTRAL
	vessel.flag = actor.flag
	result(true, "空间站已接管。")

func flight_unlock(world, vessel: Dictionary) -> void:
	if game.flight.target(vessel, 380) == 0:
		vessel.locked = false

func person(body: Node) -> void:
	if dossier.person_id != 0:
		dossier.paint(game,body)
		return
	var world = game.world
	var actor: Dictionary = world.active()
	heading(body, actor.name + ("  ·  " + actor.house + "家族" if actor.noble else "  ·  平民"))
	var top = game.hbox(body)
	var face := Portrait.new()
	face.custom_minimum_size = Vector2(125, 140)
	face.look = Portrait.for_actor(world,actor)
	top.add_child(face)
	var info = game.vbox(top)
	var gender_text := "女" if int(actor.get("gender", 0)) == 1 else "男"
	hint(info, "%d 岁 · %s · %s" % [Politics.age(world, actor), gender_text, world.ORIGINS[actor.origin]])
	hint(info, "%s · %s" % [world.TRAITS[actor.trait], world.flag_name(actor.flag)])
	var traits_list: Array = world.Society.trait_labels(actor)
	if not traits_list.is_empty():
		hint(info, "特质：" + " · ".join(traits_list))
	hint(info, "外%d 军%d 管%d 谋%d 学%d 勇%d" % [actor.stats.diplomacy, actor.stats.martial, actor.stats.stewardship, actor.stats.intrigue, actor.stats.learning, actor.stats.prowess])
	var house_renown: int = int(world.campaign.houses.get(actor.house, 0))
	hint(info, "压力 %d/400 (崩溃 %d 级) · 家族威望 %d" % [actor.stress, actor.break_level, house_renown])
	game.button(info,"我的职务与持股",func(): dossier.open(game,actor.id))
	if actor.stress >= 40:
		var cope_row: HBoxContainer = game.hbox(body)
		game.button(cope_row, "宴饮减压 (-65 / ¢40)", func(): result(world.Society.cope_stress(world, "feast"), "宴饮挥霍，压力大幅缓解。", "信用点不足 ¢40。"), actor.wallet >= 40)
		game.button(cope_row, "闭门独处 (-45)", func(): result(world.Society.cope_stress(world, "seclude"), "闭门静思，压力有所缓解。"))
	var focus_row: HBoxContainer = game.hbox(body)
	var tracks: Array = world.Society.rules.lifestyles
	var focus_idx := 0
	for i in range(tracks.size()):
		if tracks[i].id == actor.focus:
			focus_idx = i
			break
	var focus_pick: OptionButton = game.choice(focus_row, tracks.map(func(t): return "重心:" + t.name), focus_idx)
	focus_pick.item_selected.connect(func(i: int):
		world.Society.focus(world, tracks[i].id)
		game.refresh())
	var cur_track: Dictionary = tracks[focus_pick.selected] if not tracks.is_empty() else {}
	var cur_rank: int = int(actor.perks.get(cur_track.get("id", ""), 0))
	game.button(focus_row, "修习晋升 (%d/%d · 经验 %d)" % [cur_rank, 3, actor.experience], func():
		result(world.Society.train(world), "生活方式修习完成！", "经验不足或已达满阶。"))
	var active_scheme: Dictionary = world.campaign.schemes.get(actor.id, {})
	if not active_scheme.is_empty():
		var srow: HBoxContainer = game.hbox(body)
		hint(srow, "计谋[%s] -> %s (阶段 %d/3)" % ["拉拢" if active_scheme.kind == "sway" else "刺探", world.name_of(active_scheme.target), active_scheme.stage])
		game.button(srow, "资助 ¢25", func(): result(world.Society.fund_scheme(world), "已资助计谋特工。"), active_scheme.funded < 3 and actor.wallet >= 25)
		if active_scheme.stage >= 3:
			game.button(srow, "收网", func(): result(world.Society.resolve_scheme(world), "计谋已收网。"))
	if world.regency != 0:
		hint(body,"当前扮演%s · 未成年继承人 %s" % ["摄政" if world.people[world.regency].noble else "监护人",world.name_of(world.regency)])
	heading(body,"家族" if actor.noble else "家庭")
	if actor.spouse > 0:
		game.button(body,"配偶　"+world.name_of(actor.spouse),func(): dossier.open(game,actor.spouse))
	elif actor.loc > 0:
		var candidates: Array = world.people.values().filter(func(p): return p.loc == actor.loc and Politics.marriage_terms(world,actor.id,p.id).eligible)
		if candidates.is_empty():
			hint(body,"未婚 · 当前港口没有符合婚配条件的对象。")
		else:
			var proposal = game.hbox(body)
			var partner = game.choice(proposal,candidates.map(func(p): return p.name+" · "+("贵族" if p.noble else "平民")))
			game.button(proposal,"求婚",func():
				var other: Dictionary = candidates[partner.selected]
				var terms: Dictionary = Politics.marriage_terms(world,actor.id,other.id)
				result(Politics.marry(world,actor.id,other.id),"你与%s结为配偶。" % other.name,terms.reason))
	else:
		hint(body,"未婚 · 靠港后可与当地人见面求婚。")
	if actor.noble:
		hint(body,"继承法　%s" % ("集中继承" if actor.law else "分产"))
		game.button(body, "更改继承制度", func(): result(Politics.change_law(world), "继承制度已更新。"), world.regency == 0)
	var blood: Array = Politics.blood(world, actor.id)
	for relative_id in blood.slice(0, 20):
		var relative: Dictionary = world.people[relative_id]
		var record = game.hbox(body)
		var portrait := Portrait.new()
		portrait.custom_minimum_size = Vector2(53, 61)
		portrait.look = Portrait.for_actor(world,relative)
		record.add_child(portrait)
		var relation := "子女" if relative_id in actor.children else ("父母" if relative_id in actor.parents else "亲属")
		var rel_btn: Button = game.button(record,"%s　%s · %d 岁%s" % [relation,relative.name,Politics.age(world,relative),"" if relative.alive else "（已故）"],func(): dossier.open(game,relative.id))
		bind_character_menu(rel_btn, relative.id)
	heading(body, "当 地 人 物")
	if actor.loc == 0:
		hint(body, "停靠后可见当地人物、谈婚姻或送礼。")
	else:
		for other in world.people.values():
			if other.id == actor.id or not other.alive or other.loc != actor.loc or Politics.age(world, other) < 18:
				continue
			var card := PanelContainer.new()
			body.add_child(card)
			var row: HBoxContainer = game.hbox(card)
			var mini_face := Portrait.new()
			mini_face.custom_minimum_size = Vector2(44, 50)
			mini_face.look = Portrait.for_actor(world, other)
			row.add_child(mini_face)
			var rel_tag := ""
			var rel: String = actor.get("relations", {}).get(other.id, "")
			if rel == "friend":
				rel_tag = " [挚友]"
			elif rel == "rival":
				rel_tag = " [宿敌]"
			elif rel == "lover":
				rel_tag = " [情人]"
			if actor.get("hooks", {}).has(other.id):
				rel_tag += " [把柄]"
			var ot_list: Array = world.Society.trait_labels(other)
			var ot_text := (" · " + "/".join(ot_list.slice(0, 2))) if not ot_list.is_empty() else ""
			var ogender := "女" if int(other.get("gender", 0)) == 1 else "男"
			var meta: VBoxContainer = game.vbox(row)
			meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			game.title(meta, "%s · %s · %s%s" % [other.name, ogender, "贵族" if other.noble else "平民", rel_tag], 16)
			hint(meta, "好感 %+d%s" % [Politics.opinion(world, other.id, actor.id), ot_text])
			var open_btn: Button = game.button(row, "档案", func(): dossier.open(game, other.id))
			bind_character_menu(card, other.id)
			bind_character_menu(open_btn, other.id)
	var watched_ids: Array[int] = world.watched_list()
	if not watched_ids.is_empty():
		heading(body, "★ 特 别 关 注 人 物 (%d)" % watched_ids.size())
		var feed: Array = world.campaign.get("watched_feed", [])
		for wid in watched_ids:
			var wp: Dictionary = world.people[wid]
			var wcard := UIKit.card(body, UIKit.GOLD if wp.alive else UIKit.DIM, true)
			var wrow: HBoxContainer = game.hbox(wcard)
			var wloc_txt := "航行中"
			var wport_id := int(wp.get("loc", 0))
			if wport_id > 0 and world.ports.has(wport_id):
				wloc_txt = world.ports[wport_id].name
			elif int(wp.get("ship", 0)) > 0 and world.ships.has(int(wp.ship)):
				var wsh: Dictionary = world.ships[int(wp.ship)]
				wloc_txt = "超空间" if wsh.get("layer", false) else world.systems[int(wsh.system)].name
			var wlbl: Label = game.title(wrow, "%s%s · %s · %s · ¢%d" % [
				wp.name, "" if wp.alive else " (已故)", world.flag_name(int(wp.flag)), wloc_txt, int(wp.get("wallet", 0))], 13, UIKit.INK)
			wlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var wopen: Button = game.button(wrow, "档案", func(): dossier.open(game, wid))
			if wport_id > 0 and world.ports.has(wport_id) and world.ports[wport_id].build == 0:
				UIKit.action_button(wrow, "导航", func(): game.navigate_to_station(wport_id), "ghost")
			UIKit.action_button(wrow, "取消", func():
				world.toggle_watch(wid)
				game.refresh(), "ghost")
			bind_character_menu(wcard, wid)
			bind_character_menu(wopen, wid)
			for entry in feed:
				if int(entry[1]) == wid:
					hint(wcard, "最新：%s  %s" % [world.date_label(int(entry[0])), str(entry[2])])
					break
	heading(body, "星 区 人 物 名 录")
	var role_row: HBoxContainer = game.hbox(body)
	role_row.add_theme_constant_override("separation", 4)
	for r_label in ["全部", "势力首脑", "站长", "船长", "公司董事", "路人"]:
		var rbtn := UIKit.action_button(role_row, r_label, func():
			roster_role = r_label
			game.refresh(), "primary" if roster_role == r_label else "ghost")
		rbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var filter_row: HBoxContainer = game.hbox(body)
	var roster_input = game.field(filter_row, roster_query)
	roster_input.placeholder_text = "输入姓名筛选，右键可发起外交"
	game.button(filter_row, "筛选", func():
		roster_query = roster_input.text.strip_edges()
		game.refresh())
	var leader_set := {}
	for f in world.factions.values():
		if f.alive and int(f.get("leader", 0)) > 0:
			leader_set[int(f.leader)] = true
	var manager_set := {}
	for st in world.ports.values():
		if int(st.get("manager", 0)) > 0:
			manager_set[int(st.manager)] = true
		if int(st.get("owner", 0)) > 0:
			manager_set[int(st.owner)] = true
	var director_set := {}
	for firm in world.firms.values():
		if int(firm.get("director", 0)) > 0:
			director_set[int(firm.director)] = true
	var roster: Array[Dictionary] = []
	for p in world.people.values():
		if not p.alive or int(p.id) == world.player or int(p.get("flag", world.NEUTRAL)) == world.RAIDERS:
			continue
		var pid := int(p.id)
		var role_txt := "路人"
		if leader_set.has(pid):
			role_txt = "势力首脑"
		elif director_set.has(pid):
			role_txt = "公司董事"
		elif manager_set.has(pid):
			role_txt = "站长"
		elif int(p.get("ship", 0)) > 0:
			role_txt = "船长"
		if roster_role != "全部" and role_txt != roster_role:
			continue
		if not roster_query.is_empty() and roster_query not in str(p.name):
			continue
		roster.append(p)
	roster.sort_custom(func(a, b):
		var ap := int(a.id)
		var bp := int(b.id)
		var a_rank := 3 if leader_set.has(ap) else (2 if (director_set.has(ap) or manager_set.has(ap)) else (1 if int(a.get("ship", 0)) > 0 else 0))
		var b_rank := 3 if leader_set.has(bp) else (2 if (director_set.has(bp) or manager_set.has(bp)) else (1 if int(b.get("ship", 0)) > 0 else 0))
		if a_rank != b_rank:
			return a_rank > b_rank
		return int(a.get("wallet", 0)) > int(b.get("wallet", 0)))
	for p in roster.slice(0, mini(30, roster.size())):
		var pid := int(p.id)
		var role_txt := "路人"
		if leader_set.has(pid):
			role_txt = "势力首脑"
		elif director_set.has(pid):
			role_txt = "公司董事"
		elif manager_set.has(pid):
			role_txt = "站长"
		elif int(p.get("ship", 0)) > 0:
			role_txt = "船长"
		var rcard := UIKit.card(body, UIKit.GOLD if leader_set.has(pid) else Color.TRANSPARENT, true)
		var rrow: HBoxContainer = game.hbox(rcard)
		var r_lbl: Label = game.title(rrow, "%s · %s · %s · ¢%d" % [p.name, role_txt, world.flag_name(int(p.flag)), int(p.get("wallet", 0))], 13, UIKit.INK)
		r_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var open_rbtn: Button = game.button(rrow, "档案", func(): dossier.open(game, pid))
		bind_character_menu(rcard, pid)
		bind_character_menu(open_rbtn, pid)

func routes(list: Array) -> Array:
	var world = game.world
	for port_id in world.ports:
		var station: Dictionary = world.ports[port_id]
		if station.scan and station.build == 0:
			list.append(port_id)
	return list

func crew(world, actor: Dictionary, vessel: Dictionary) -> Array:
	var candidates: Array = []
	for worker in world.people.values():
		if not worker.alive or worker.id == actor.id or Politics.age(world, worker) < 18:
			continue
		if worker.id == vessel.get("captain", 0) or (actor.loc != 0 and worker.loc == actor.loc and worker.ship == 0 and worker.employer in [0, vessel.get("owner", actor.id)]):
			var official := false
			for group in world.factions.values():
				if group.leader == worker.id:
					official = true
					break
			if not official:
				candidates.append(worker.id)
	return candidates

func ship_location_text(world, owned: Dictionary) -> String:
	if owned.dock != 0 and world.ports.has(owned.dock):
		var st: Dictionary = world.ports[owned.dock]
		return "停靠：%s · %s" % [world.systems[st.system].name, st.name]
	if owned.layer:
		return "超空间航行中"
	return "在航：%s" % world.systems[owned.system].name

func ship_status_text(world, owned: Dictionary) -> String:
	if owned.has("route_hold"):
		return "航行待命 · %s" % owned.route_hold
	var queue: Array = owned.get("order_queue", [])
	if not queue.is_empty():
		var head: Dictionary = queue[0]
		var port_name: String = world.ports.get(head.get("port", 0), {}).get("name", "未知站点")
		return "队列(%d)：%s -> %s" % [queue.size(), head.get("kind", ""), port_name]
	var role: String = owned.get("fleet_role", "")
	if not role.is_empty() and owned.get("commander_id", 0) != 0:
		var cmd: Dictionary = world.ships.get(owned.commander_id, {})
		var cmd_name: String = world.HULLS[cmd.kind] if not cmd.is_empty() else "旗舰"
		return "编队[%s] -> %s" % [role, cmd_name]
	var behavior: Dictionary = owned.get("default_behavior", owned.job)
	return "行为：%s" % behavior.get("label", behavior.get("kind", "待命"))

func financial_report(body: Node) -> void:
	var world = game.world
	var summary: Dictionary = world.Finances.report(world,report_days)
	heading(body,"船队与空间站收支简报")
	var actions = game.hbox(body)
	game.button(actions,"返回资产",func(): report_open = false; game.refresh())
	var periods = game.choice(actions,["近 7 日","近 30 日","近 90 日"],world.Finances.PERIODS.find(report_days))
	periods.item_selected.connect(func(index): report_days = world.Finances.PERIODS[index]; game.refresh())
	game.button(actions,"刷新",game.refresh)
	hint(body,"第 %d 至 %d 日 · 已结算信用点" % [summary.from_day,summary.through_day])
	game.title(body,"合计净收支  ¢%+d" % summary.net,20,game.GOLD)
	for key in ["ship","station"]:
		var totals: Dictionary = summary[key]
		game.title(body,"%s　收入 ¢%d　支出 ¢%d　净额 ¢%+d" % ["船队" if key == "ship" else "空间站",totals.income,totals.expense,totals.net],15,game.INK,true)
	hint(body,"站点注资 ¢%d　提款 ¢%d　派发分红 ¢%d" % [summary.capital_in,summary.capital_out,summary.dividends])
	hint(body,"本期股息到账　¢%d" % summary.received_dividends)
	if summary.company_receipts > 0 or summary.company_distributions > 0:
		hint(body,"公司收到站点股息 ¢%d　公司派息 ¢%d" % [summary.company_receipts,summary.company_distributions])
	if summary.assets.is_empty():
		hint(body,"本期尚无资产收支或港口成交。")
		return
	for item: Dictionary in summary.assets:
		var id: int = item.id
		game.button(body,"%s #%d　%s　¢%+d" % [{"ship":"船","station":"站","company":"公司"}[item.type],id,item.label,item.net],func(): report_asset = 0 if report_asset == id else id; game.refresh())
		if id != report_asset:
			continue
		for name in item.lines:
			var line: Dictionary = item.lines[name]
			hint(body,"%s　收入 ¢%d　支出 ¢%d" % [name,line.income,line.expense])
		if item.type == "station":
			hint(body,"公开货市成交　售出 ¢%d　收购 ¢%d" % [item.sales,item.purchases])

func treasury_controls(body: Node, station: Dictionary) -> void:
	var world = game.world
	var book: Dictionary = world.Dividends.statement(world,station)
	hint(body,"运营余额 ¢%d　已预留 ¢%d　未分配净收益 ¢%d" % [book.balance,book.balance-book.available,book.retained_profit])
	var transfer = game.hbox(body)
	transfer.visible = world.oversees(station.owner)
	var amount = game.field(transfer,"",10)
	amount.placeholder_text = "划拨金额"
	for sign_value: int in [1,-1]:
		var allowed: bool = sign_value > 0 or world.Treasury.can_withdraw(world,station,world.player)
		var action = game.button(transfer,"注资" if sign_value > 0 else "提款",func():
			var units: int = amount.text.to_int() if amount.text.is_valid_int() else 0
			result(units > 0 and world.Treasury.transfer(world,station,world.player,sign_value*units),"资金已划拨。","金额须为正整数，且不能超过账户可用余额。"),allowed)
		if not allowed:
			action.tooltip_text = "直接提款仅限本站的独资所有人。股东可按股获得分红。"
	var policy = game.hbox(body)
	game.title(policy,"比例 %",13,game.DIM)
	var percentage = game.field(policy,str(book.percent),3)
	percentage.tooltip_text = "分红比例（0–100%）"
	game.title(policy,"留存 ¢",13,game.DIM)
	var reserve = game.field(policy,str(book.reserve),10)
	reserve.tooltip_text = "保留的最低周转金"
	game.button(policy,"保存分红政策",func():
		result(percentage.text.is_valid_int() and reserve.text.is_valid_int() and world.Dividends.configure(world,station,percentage.text.to_int(),reserve.text.to_int()),"已保存分红政策。","请输入 0–100 的比例和非负周转金。"))
	hint(body,"每 %d 日按未分配净收益的 %d%% 分红，至少保留 ¢%d 周转金。" % [book.period_days,book.percent,book.reserve])
	if station.firm != 0:
		hint(body,"%s · 按当前股东持股比例派发。" % world.firms[station.firm].name)
	game.button(body,"现在分红　¢%d" % book.payable,func(): result(world.Dividends.settle(world,station)>0,"分红已派发。","目前没有可分配金额。"),book.payable>0)

func open_diagnostics(id: int = 0) -> void:
	diagnostic_ship = id
	diagnostics_open = true
	report_open = false
	equity.mode = ""
	game.tab = "资产"
	game.system_chart = false
	if game.side_collapsed:
		game.toggle_side_panel()
	game.refresh()
	var scroll: ScrollContainer = game.side_panel.get_node_or_null("Column/Scroll")
	if scroll:
		scroll.set_deferred("scroll_vertical",0)

func ship_diagnostics(body: Node) -> void:
	var world = game.world
	game.button(body,"返回资产",func(): diagnostics_open = false; game.refresh())
	heading(body,"舰船运行诊断")
	var ids := []
	var names := []
	for vessel: Dictionary in world.ships.values():
		if Economy.Diagnostics.accessible(world,vessel):
			ids.append(vessel.id)
			names.append("#%d %s" % [vessel.id,world.HULLS[vessel.kind]])
	if ids.is_empty():
		hint(body,"当前没有可查看的舰船。")
		return
	var selected := maxi(0,ids.find(diagnostic_ship))
	diagnostic_ship = ids[selected]
	var selector = game.choice(body,names,selected)
	selector.item_selected.connect(func(i): open_diagnostics(ids[i]))
	var d := Economy.Diagnostics.snapshot(world,diagnostic_ship)
	hint(body,"第 %d 天 · %s · %s" % [d.day,d.system,d.status])
	hint(body,"产权归 %s　｜　船长 %s　｜　船长直属上级 %s" % [d.title_holder,d.captain_name,d.employer_name])
	hint(body,"航务调度　%s\n货款账户　%s · 可用 ¢%d" % [d.command,d.account,d.available_funds])
	hint(body,"船长个人余额　%s" % ("¢%d" % d.captain_wallet if d.captain_wallet != null else "—"))
	if d.quarterly_salary:
		hint(body,"每 90 天由 %s 支付船长薪酬 ¢%d" % [d.account,d.quarterly_salary])
	hint(body,"停靠 %s　｜　燃料 %.1f / 100　｜　港口可供油 %s" % [d.port,d.fuel,str(d.pump_available) if d.pump_available!=null else "—"])
	if not d.ware.is_empty():
		hint(body,"%s → %s　%s × %d　已订 %d" % [d.source,d.destination,d.ware,d.job.get("quantity",0),d.reservation.get("qty",0)])
	if not d.navigation.is_empty():
		var nav: Dictionary = d.navigation
		hint(body,"航向 %s　｜　距目标 %.1f　｜　余下跳跃耗油 %.1f" % [nav.leg,nav.get("distance",0),nav.get("fuel_required",0)])
	var manifest := PackedStringArray()
	for ware in d.cargo:
		manifest.append("%s × %d" % [ware,d.cargo[ware]])
	hint(body,"货舱　%s　｜　空位 %d" % ["、".join(manifest) if not manifest.is_empty() else "空",d.free_space])
	heading(body,"第 %d–%d 天收支 · %s" % [d.from_day,d.day,d.book_scope])
	hint(body,"收入 ¢%d　支出 ¢%d　净额 ¢%d" % [d.books.income,d.books.expense,d.books.net])
	for category in d.books.lines:
		var line: Dictionary = d.books.lines[category]
		hint(body,"%s　+¢%d / −¢%d" % [category,line.income,line.expense])
	heading(body,"最近事件")
	if d.events.is_empty():
		hint(body,"尚无事件记录。新发生的接单、补油和收付款会出现在这里。")
	for i in range(d.events.size()-1,maxi(-1,d.events.size()-13),-1):
		var entry: Dictionary = d.events[i]
		var x: Dictionary = entry.details
		var info := JSON.stringify(x)
		if x.has("from"):
			info = "%s → %s　¢%d" % [x.from,x.to,x.amount]
			if x.get("tax",0):
				info += "　另缴税 ¢%d → %s" % [x.tax,x.tax_to]
		elif entry.event == "接单":
			info = "%s → %s　%s × %d" % [Economy.Diagnostics.port_name(world,x.source),Economy.Diagnostics.port_name(world,x.target),world.WARES[x.ware],x.quantity]
		elif entry.event == "请求补油":
			info = "申请 %d　加注 %d　油箱 %.1f / 100" % [x.requested,x.filled,x.tank_after]
		elif entry.event == "内部调拨":
			info = "%s　%s%s × %d　资金变动 ¢0" % [Economy.Diagnostics.port_name(world,x.port),"装载" if x.loading else "卸下",world.WARES[x.ware],x.units]
		elif x.has("reason"):
			info = str(x.reason)
		hint(body,"第 %d 天 · %s\n%s" % [entry.day,entry.event,info])
	if not d.samples.is_empty():
		heading(body,"航行记录")
		for sample: Dictionary in d.samples.slice(-3):
			hint(body,"第 %d 天　坐标 %s　燃料 %.1f　%s" % [sample.day,str(sample.position),sample.fuel,sample.goal])
	game.button(body,"导出本船诊断 JSON",func():
		var path := "user://ship-%d-day-%d.json" % [d.ship,d.day]
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null:
			game.say("无法写入诊断文件。")
			return
		file.store_string(JSON.stringify(d,"  "))
		file.flush()
		game.say("诊断已保存到 " + ProjectSettings.globalize_path(path) if file.get_error() == OK else "写入诊断文件失败。"))

func open_ship_company(ship_id: int) -> void:
	var world = game.world
	var dialog := AcceptDialog.new()
	dialog.title = "#%d 舰船公司登记" % ship_id
	dialog.ok_button_text = "关闭"
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var capital := mini(maxi(0,int(world.active().wallet)-1800),int(Economy.Industry.RULES.equity.founder_cash_limit))
	hint(box,"以本船出资成立公司，注册费 ¢1800，另转入 ¢%d 启动资金。船体归公司，创办人取得股份。" % capital)
	var label := LineEdit.new()
	label.placeholder_text = "新公司名称"
	label.max_length = 20
	box.add_child(label)
	game.button(box,"以本船出资注册",func():
		if Economy.incorporate_ship(world,ship_id,label.text):
			dialog.queue_free()
			result(true,"公司已登记，船体已计入公司资产。")
		else:
			game.say("请填写公司名称，并检查现金、船权与在途货单。"))
	var ids := []
	var names := []
	for id in world.firms:
		if world.firms[id].director == world.player:
			ids.append(id)
			names.append(world.firms[id].name)
	if not ids.is_empty():
		var firms = game.choice(box,names)
		game.button(box,"将整艘船无偿转入所选公司",func():
			var ok := Economy.contribute_ship(world,ship_id,ids[firms.selected])
			if ok: dialog.queue_free()
			result(ok,"舰船产权已转入公司。"))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	game.add_child(dialog)
	dialog.popup_centered(Vector2i(430,260))

func assets(body: Node) -> void:
	var world = game.world
	if diagnostics_open:
		ship_diagnostics(body)
		return
	if not equity.mode.is_empty():
		equity.paint(game,body)
		return
	if report_open:
		financial_report(body)
		return
	game.button(body,"船队与空间站收支简报",func(): report_open = true; game.refresh())
	game.button(body,"舰船运行诊断",func(): open_diagnostics())
	game.button(body,"股权与分红",func(): equity.open(game,"company"))
	var actor: Dictionary = world.active()
	var vessel: Dictionary = world.ride()
	var flagship_id: int = vessel.get("id", 0)
	var owned_ships: Array = []
	for ship_id in world.ships:
		var owned: Dictionary = world.ships[ship_id]
		if world.oversees(world.ship_principal(owned)):
			owned_ships.append(owned)
		elif owned.get("charter",{}).get("operator",0) == actor.id:
			heading(body,"航务局配舰")
			game.entity_menus.bind(game.title(body,world.HULLS[owned.kind],17,game.GOLD),"ship",ship_id)
			var quote := Economy.charter_quote(world,ship_id)
			hint(body,"%s · 登记港 %s · 买断 ¢%d" % [ship_location_text(world,owned),world.ports[quote.port].name,quote.price])
			if actor.loc != 0 and owned.dock == actor.loc and flagship_id != ship_id:
				game.button(body,"登上配舰",func(): result(world.pilot(ship_id),"已登上航务局配舰。"))
	owned_ships.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := 0 if a.id == flagship_id else (1 if actor.loc != 0 and a.dock == actor.loc else 2)
		var b_score := 0 if b.id == flagship_id else (1 if actor.loc != 0 and b.dock == actor.loc else 2)
		return a_score < b_score if a_score != b_score else a.id < b.id)
	heading(body, "管理中的舰船（%d）" % owned_ships.size())
	var filter_row: HBoxContainer = game.hbox(body)
	for pair in [["全部", "all"], ["在本站", "dock"], ["在航/他处", "away"]]:
		var fbtn: Button = game.button(filter_row, pair[0], func():
			asset_filter = pair[1]
			game.refresh(), true, true)
		fbtn.toggle_mode = true
		fbtn.button_pressed = (asset_filter == pair[1])
	for owned in owned_ships:
		if asset_filter == "dock" and not (actor.loc != 0 and owned.dock == actor.loc):
			continue
		if asset_filter == "away" and (actor.loc != 0 and owned.dock == actor.loc):
			continue
		var ship_id: int = owned.id
		var is_flagship := ship_id == flagship_id
		var card_col := UIKit.card(body, UIKit.GOLD if is_flagship else (UIKit.DANGER if float(owned.hp) < float(world.HULL_HP[owned.kind]) * 0.4 else Color.TRANSPARENT))
		game.entity_menus.bind(card_col,"ship",ship_id)
		var ship_row: HBoxContainer = game.hbox(card_col)
		Art.contained(ship_row, Art.ship(owned.kind), Vector2(84, 57))
		var register: VBoxContainer = game.vbox(ship_row)
		register.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title_tag := " [旗舰]" if is_flagship else (" [在本站]" if actor.loc != 0 and owned.dock == actor.loc else "")
		game.title(register, "#%d %s%s" % [ship_id, world.HULLS[owned.kind], title_tag], 16, game.GOLD if is_flagship else UIKit.INK)
		UIKit.meter(register, "船体", float(owned.hp), float(world.HULL_HP[owned.kind]), "danger" if float(owned.hp) < float(world.HULL_HP[owned.kind]) * 0.4 else "ok")
		UIKit.meter(register, "燃料", float(owned.fuel), 100.0, "warn" if float(owned.fuel) < 25.0 else "info")
		var loc_lbl: Label = hint(register, "%s · %s · %s" % [Hulls.CLASS_NAMES[Hulls.MODELS[owned.kind].size], ship_location_text(world, owned), ship_status_text(world, owned)])
		bind_location_menu(loc_lbl, int(owned.get("dock", 0)), int(owned.get("system", -1)))
		if owned.captain != 0 and owned.captain != actor.id:
			var cbtn: Button = game.button(register,"船长：%s" % world.name_of(owned.captain),func(): dossier.open(game,owned.captain))
			bind_character_menu(cbtn, owned.captain)
		game.button(card_col,"查看航程、账目与隶属关系",func(): open_diagnostics(ship_id))
		if owned.has("firm"):
			hint(card_col,"公司所有　" + world.firms[owned.firm].name)
		elif owned.owner != actor.id:
			hint(card_col, "摄政代管  ·  所有权归 " + world.name_of(owned.owner))
		if owned.owner == actor.id:
			game.button(card_col,"登记公司产权…",func(): open_ship_company(ship_id),Economy.contributable(owned))
		var actions: HBoxContainer = game.hbox(card_col)
		if actor.loc != 0 and owned.dock == actor.loc:
			UIKit.action_button(actions, "整备换装", func():
				game.dock_view.refit_ship_id = ship_id
				game.dock_view.slot_index = 0
				game.dock_view.mode = "refit"
				game.tab = "港口"
				game.refresh(), "primary")
		elif int(owned.dock) > 0 and not is_flagship:
			UIKit.action_button(actions, "导航前往", func(): game.navigate_to_station(int(owned.dock)), "ghost")
		if ship_id == flagship_id:
			if owned.dock != 0:
				game.button(actions, "离舰驻站（不驾船）", func():
					result(world.disembark(), "已离舰驻站，不再亲自驾驶飞船。"))
			continue
		var watching: bool = game.watch_ship_id == ship_id
		game.button(actions, "返回旗舰视角" if watching else "观察视角", func():
			game.watch_ship_id = 0 if watching else ship_id
			game.refresh())
		game.button(actions, "登舰接管", func(): result(world.pilot(ship_id), "你已亲自驾驶这艘船。"), actor.loc != 0 and owned.dock == actor.loc)
		var expanded := selected_ship_id == ship_id
		game.button(actions, "收起指挥" if expanded else "指挥 / 编队", func():
			selected_ship_id = 0 if expanded else ship_id
			game.refresh())
		if not expanded:
			continue
		var sub_body := card_col
		var workers := crew(world, actor, owned)
		if owned.captain == 0:
			hint(body, "该船尚未任命船长。同站有闲置人员时可 ¢55 雇佣，或直接 ¢85 招募外派副官。")
			if not workers.is_empty() and actor.loc != 0 and owned.dock == actor.loc:
				var assignee = game.choice(body, workers.map(func(candidate): return world.name_of(candidate) + " · 忠诚 %s" % world.people[candidate].loyalty))
				var quick_hire = game.hbox(body)
				if flagship_id > 0:
					game.button(quick_hire, "雇佣并护航 (¢55)", func():
						var cid: int = workers[assignee.selected]
						var ok := Economy.assign(world, ship_id, cid, "护航", 0, 0) and Economy.assign_role(world, ship_id, flagship_id, "INTERCEPT")
						result(ok, "已任命船长并加入旗舰护航编队。"))
				game.button(quick_hire, "雇佣并自动贸易 (¢55)", func():
					result(Economy.assign(world, ship_id, workers[assignee.selected], "自动贸易", 0, 0), "已任命船长并开始自动贸易。"))
				game.button(quick_hire, "仅任命待命 (¢55)", func():
					result(Economy.assign(world, ship_id, workers[assignee.selected], "停泊待命", actor.loc, 0), "已任命船长并在本站待命。"))
			var remote_hire = game.hbox(body)
			if flagship_id > 0:
				game.button(remote_hire, "外派副官并护航 (¢85)", func():
					result(Economy.hire_remote_captain(world, ship_id, "护航"), "外派副官已赴任并加入旗舰护航。", "资金不足 ¢85。"))
			game.button(remote_hire, "外派副官并待命 (¢85)", func():
				result(Economy.hire_remote_captain(world, ship_id, "停泊待命", owned.dock), "外派副官已赴任待命。", "资金不足 ¢85。"))
			continue
		var area := Economy.OperatingArea.settings(world,owned)
		var selected_area: Dictionary = owned.get("next_operating_area",area)
		var bases: Array = [owned.job.home_port] if owned.job.has("home_port") else routes([])
		if area.port != 0 and area.port not in bases and world.ports.has(area.port):
			bases.append(area.port)
		var base_name: String = world.ports.get(area.port,{}).get("name",world.systems[area.system].name)
		hint(body,"自动作业范围　%s · %d 跳" % [base_name,area.jumps])
		if owned.has("next_operating_area"):
			hint(body,"本单交付后改为 %s · %d 跳" % [world.ports[selected_area.port].name,selected_area.jumps])
		if not bases.is_empty():
			var base = game.choice(body,bases.map(func(id): return "母港：" + world.ports[id].name),maxi(0,bases.find(selected_area.port)))
			var range_row = game.hbox(body)
			var limits := ["仅本星系"]
			for jump in range(1,int(Economy.Industry.RULES.operating_area.maximum_jumps)+1):
				limits.append("%d 跳内" % jump)
			var radius = game.choice(range_row,limits,selected_area.jumps)
			game.button(range_row,"设置作业范围",func():
				result(Economy.OperatingArea.configure(world,ship_id,bases[base.selected],radius.selected),"已更新自动贸易和采矿范围。"))
		var quick_cmd = game.hbox(body)
		if flagship_id > 0:
			game.button(quick_cmd, "护航旗舰", func():
				result(Economy.assign_role(world, ship_id, flagship_id, "INTERCEPT"), "已加入旗舰拦截护航。"))
		game.button(quick_cmd, "自动贸易", func():
			result(Economy.assign(world, ship_id, owned.captain, "自动贸易", 0, 0), "已切换为自动贸易。"))
		game.button(quick_cmd, "自动采矿", func():
			result(Economy.assign(world, ship_id, owned.captain, "自动采矿", 0, 0), "已切换为自动采矿。"))
		if actor.loc != 0:
			game.button(quick_cmd, "停靠本站", func():
				result(Economy.queue_order(world, ship_id, actor.loc, "dock"), "已下达停靠本站指令。"))
		var my_ports: Array = []
		var my_sites: Array = []
		for pid in world.ports:
			var st: Dictionary = world.ports[pid]
			if world.Dividends.can_manage(world, st) and st.build == 0 and Economy.allowed(world,owned,st):
				my_ports.append(pid)
			if world.oversees(st.owner) and not Economy.build_requirements(st).is_empty():
				my_sites.append(pid)
		if owned.has("lease"):
			var lp: Dictionary = world.ports.get(int(owned.lease.get("port", 0)), {})
			var lease_info = game.hbox(body)
			hint(lease_info, "已租赁给 %s · 日租 ¢%d" % [lp.get("name", "空间站"), int(owned.lease.get("daily_rent", 0))])
			game.button(lease_info, "结束租赁收回", func():
				result(Economy.end_ship_lease(world, ship_id), "已终止租赁并收回飞船。"))
		if not my_ports.is_empty():
			var st_row = game.hbox(body)
			var st_pick = game.choice(st_row, my_ports.map(func(pid): return "母港：" + world.ports[pid].name))
			st_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			game.button(st_row, "为该站贸易", func():
				result(Economy.assign_station_duty(world, ship_id, my_ports[st_pick.selected], "站属贸易"), "已指派为该空间站贸易。"))
			game.button(st_row, "为该站采矿", func():
				result(Economy.assign_station_duty(world, ship_id, my_ports[st_pick.selected], "站属采矿"), "已指派为该空间站采矿。"))
			if owned.id != actor.ship:
				game.button(st_row, "过户归属该站", func():
					result(Economy.transfer_ship_to_station(world, ship_id, my_ports[st_pick.selected], "站属贸易"), "飞船已完全归属该空间站。"))
		var lease_ports: Array = []
		for pid in world.ports:
			var st: Dictionary = world.ports[pid]
			if st.build == 0 and not st.get("landing_only", false) and Economy.allowed(world, owned, st) and not world.enemy(actor, st):
				lease_ports.append(pid)
		if not lease_ports.is_empty() and owned.id != actor.ship:
			var lease_row = game.hbox(body)
			var lease_pick = game.choice(lease_row, lease_ports.map(func(pid): return "租赁：%s (¢%d/日)" % [world.ports[pid].name, Economy.lease_daily_rent(world.ports[pid], owned)]))
			lease_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			game.button(lease_row, "租给贸易", func():
				result(Economy.lease_ship_to_station(world, ship_id, lease_ports[lease_pick.selected], "站属贸易"), "已租赁给该空间站执行贸易。"))
			game.button(lease_row, "租给采矿", func():
				result(Economy.lease_ship_to_station(world, ship_id, lease_ports[lease_pick.selected], "站属采矿"), "已租赁给该空间站执行采矿。"))
		if not my_sites.is_empty():
			var stops_all := routes([])
			if not stops_all.is_empty():
				var build_row = game.hbox(body)
				var site_pick = game.choice(build_row, my_sites.map(func(pid): return "工地：" + world.ports[pid].name))
				site_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var mat_src: int = stops_all[0]
				for spid in stops_all:
					if spid != my_sites[0] and world.ports[spid].build == 0 and Economy.Industry.available(world.ports[spid], Economy.Industry.Ware.ALLOY) > 0:
						mat_src = spid
						break
				game.button(build_row, "自动运建材", func():
					result(Economy.supply_construction(world, ship_id, mat_src, my_sites[site_pick.selected]), "已派往自动采购并运送建站建材。"))
		if flagship_id > 0:
			var role_row = game.hbox(body)
			game.title(role_row, "编队职责", 14, game.DIM)
			for pair in [["攻击", "ATTACK"], ["拦截", "INTERCEPT"], ["轰炸", "BOMBARD"], ["防御", "DEFEND"], ["模仿", "MIMIC"]]:
				var active_role: bool = owned.get("commander_id", 0) == flagship_id and owned.get("fleet_role", "") == pair[1]
				var rbtn: Button = game.button(role_row, pair[0], func():
					result(Economy.assign_role(world, ship_id, flagship_id, pair[1]), "编队职责已设为：" + pair[0]), true, true)
				rbtn.toggle_mode = true
				rbtn.button_pressed = active_role
		var queue: Array = owned.get("order_queue", [])
		if not queue.is_empty():
			game.title(body, "当前指令队列 (%d)" % queue.size(), 14, game.GOLD)
			for idx in range(queue.size()):
				var q_row = game.hbox(body)
				var ord: Dictionary = queue[idx]
				var pname: String = world.ports.get(ord.get("port", 0), {}).get("name", "未知")
				hint(q_row, "%d. %s -> %s" % [idx + 1, ord.get("kind", ""), pname])
				game.button(q_row, "取消", func():
					result(Economy.cancel_order(world, ship_id, idx), "已取消该条队列指令。"))
		var stops := routes([])
		if not stops.is_empty():
			var dock_q = game.hbox(body)
			var dest_pick = game.choice(dock_q, stops.map(func(stop): return world.ports[stop].name))
			dest_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			game.button(dock_q, "派往停靠", func():
				result(Economy.queue_order(world, ship_id, stops[dest_pick.selected], "dock"), "已加入停靠指令队列。"))
		var kinds := ["贸易","采矿","护航","停泊待命","自动贸易","自动采矿","巡逻"]
		var behavior: Dictionary = owned.get("default_behavior",owned.job)
		var job_index := kinds.find(behavior.get("label",behavior.get("kind","贸易")))
		var adv_row = game.hbox(body)
		game.title(adv_row, "高级行为", 14, game.DIM)
		var orders = game.choice(adv_row, kinds, maxi(0, job_index))
		var source = game.choice(body, stops.map(func(stop): return "起点：" + world.ports[stop].name))
		var target = game.choice(body, stops.map(func(stop): return "终点：" + world.ports[stop].name), mini(1, stops.size() - 1))
		var refresh_route_vis := func(idx: int):
			var chosen: String = kinds[idx]
			source.visible = chosen in ["贸易", "采矿", "停泊待命", "巡逻"] and not stops.is_empty()
			target.visible = chosen in ["贸易", "采矿"] and stops.size() > 1
		refresh_route_vis.call(orders.selected)
		orders.item_selected.connect(refresh_route_vis)
		game.button(adv_row, "应用", func():
			result(Economy.assign(world, ship_id, owned.captain, orders.get_item_text(orders.selected),
				stops[source.selected] if source.selected >= 0 and not stops.is_empty() else 0, stops[target.selected] if target.selected >= 0 and not stops.is_empty() else 0), "已更新长期默认行为。"))
	heading(body, "空 间 站  /  企 业")
	var build = game.choice(body, world.MODULES)
	game.button(body, "设计轨道工地", func(): StationDesigner.open(game,"foundation",{},build.selected))
	for port_id in world.ports:
		var station: Dictionary = world.ports[port_id]
		if not world.Dividends.can_manage(world, station):
			if station.firm != 0 and actor.shares.get(station.firm,0) > 0:
				game.title(body,station.name)
				hint(body,"%s · 持股 %d 股" % [world.firms[station.firm].name,actor.shares.get(station.firm,0)])
			continue
		game.title(body, station.name)
		treasury_controls(body,station)
		if not station.has("planet_index"):
			game.button(body,"空间站布局",func(): StationDesigner.open(game,"layout",station))
		var mgr_label := "站长 %s（你亲自管理）" % world.name_of(station.manager) if station.manager == world.player else "站长 %s" % world.name_of(station.manager)
		hint(body, "%s  ·  %s" % [mgr_label, "营运中" if station.build == 0 else "施工中"])
		var assigned_ships: Array = []
		for s in world.ships.values():
			if int(s.get("station_owner", 0)) == port_id:
				assigned_ships.append("#%d %s[站产](%s)" % [s.id, world.HULLS[s.kind], s.job.get("kind", "")])
			elif int(s.get("lease", {}).get("port", 0)) == port_id:
				assigned_ships.append("#%d %s[租赁 ¢%d/日](%s)" % [s.id, world.HULLS[s.kind], int(s.lease.get("daily_rent", 0)), s.job.get("kind", "")])
			elif world.oversees(s.owner) and s.job.get("home_port", 0) == port_id:
				assigned_ships.append("#%d %s[指派](%s)" % [s.id, world.HULLS[s.kind], s.job.get("kind", "")])
		if not assigned_ships.is_empty():
			hint(body, "隶属舰船：" + "、".join(assigned_ships))
		if station.build > 0:
			continue
		if vessel.get("dock", 0) == station.id and station.extension == -1 and not station.has("planet_index") and station.modules.size() < Economy.Industry.CONSTRUCTION.max_modules:
			var module = game.choice(body, world.MODULES)
			game.button(body, "设计扩建",func(): StationDesigner.open(game,"expansion",station,module.selected))
		var can_appoint_mgr: bool = world.oversees(station.owner) or world.oversees(world.firms.get(station.firm, {}).get("director", 0))
		if can_appoint_mgr:
			if station.manager != world.player:
				game.button(body, "亲自接管管理", func(): result(Economy.manager(world, port_id, world.player), "你已亲自接管该空间站管理。"))
			var workers := crew(world, actor, {})
			if not workers.is_empty():
				var assignee = game.choice(body, workers.map(func(candidate): return world.name_of(candidate)))
				game.button(body, "任命站长  ¢45", func(): result(Economy.manager(world, port_id, workers[assignee.selected]), "已任命站长。"))
		if station.firm == 0 and station.owner == actor.id:
			var firm_label = game.field(body, actor.name + "工业")
			game.button(body, "注册企业  ¢1800", func(): result(Economy.incorporate(world, port_id, firm_label.text), "企业注册成功。"))
			for owned_firm in world.firms:
				if world.firms[owned_firm].director == world.player:
					game.button(body, "并入 " + world.firms[owned_firm].name, func():
						result(world.Equity.affiliate(world,station.id,owned_firm), "企业网络已扩张。"))
		if station.owner == actor.id and world.factions.get(actor.flag, {}).get("leader", 0) != actor.id:
			var state_label = game.field(body, actor.name + "领")
			var regime = game.choice(body, world.REGIMES)
			game.button(body, "宣布建立势力", func(): result(Politics.found(world, state_label.text, port_id, regime.selected), "新势力已进入星区。"))

func powers(body: Node) -> void:
	var world = game.world
	heading(body,"边 境 组 织")
	for group: Dictionary in world.Outlaws.summary(world):
		var region: Dictionary = world.systems[group.system]
		game.title(body,group.name,17,Color(group.color))
		hint(body,group.description)
		hint(body,"%s · %s · 驻守 %d 艘，预备 %d 艘" % [region.name,group.base_name,group.active,group.reserve])
		var vessel: Dictionary = world.ride()
		if not vessel.is_empty() and vessel.dock == 0:
			if game.galaxy:
				game.button(body,"前往" + region.name,func(): game.set_waypoint(region.pos,region.name))
			elif vessel.system == group.system:
				var base: Dictionary = world.systems[group.system].outlaw_base
				game.button(body,"标记" + group.base_name,func(): game.set_waypoint(base.pos,group.base_name,func(): return base.pos))
	heading(body, "政 体  /  版 图")
	for flag in world.factions:
		var power: Dictionary = world.factions[flag]
		var fcard := UIKit.card(body, world.flag_color(flag))
		hint(fcard,"对你的信任　%+d" % world.faction_trust(flag,world.player))
		var fhead: HBoxContainer = game.hbox(fcard)
		var ftitle: Label = game.title(fhead, power.name + ("  /  已灭亡" if not power.alive else ""), 16, world.flag_color(flag))
		ftitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if power.alive:
			var actor_flag := int(world.active().get("flag", world.NEUTRAL))
			if actor_flag >= 0 and actor_flag != int(flag):
				var tr := int(world.treaty(actor_flag, int(flag)).get("state", 0))
				UIKit.badge(fhead, "同盟" if tr == 1 else ("交战" if tr == -1 else "中立"), "ok" if tr == 1 else ("danger" if tr == -1 else "dim"))
		hint(fcard, "%s  ·  %s  ·  %s  ·  %s 站" % [world.REGIMES[power.regime], world.STYLES[power.style], world.lead_name(flag), world.systems_owned(flag).size()])
		var fbtns: HBoxContainer = game.hbox(fcard)
		if power.alive and world.people.has(power.leader):
			game.button(fbtns,"联络领袖",func(): dossier.open(game,power.leader))
		if power.alive and world.Equity.at_market(world):
			UIKit.action_button(fbtns, "与势力交易", func(): game.open_trade_table("faction", flag), "default")
		var cap_id := int(power.get("capital", 0))
		if power.alive and world.ports.has(cap_id):
			bind_location_menu(ftitle, cap_id)
			UIKit.action_button(fbtns, "导航首都", func(): game.navigate_to_station(cap_id), "ghost")
		var foes: Array = []
		for other in world.factions:
			if world.factions[other].alive and world.hostile(flag, other):
				foes.append(world.flag_name(other))
		if not foes.is_empty():
			hint(fcard, "交战：" + "、".join(foes))
	heading(body, "跨 星 系 企 业")
	for firm_id in world.firms:
		var enterprise: Dictionary = world.firms[firm_id]
		var network := 0
		for station in world.ports.values():
			if station.firm == firm_id:
				network += 1
		var ccard := UIKit.card(body, UIKit.GOLD if enterprise.director == world.player else Color.TRANSPARENT)
		var chead: HBoxContainer = game.hbox(ccard)
		var ctitle: Label = game.title(chead, enterprise.name, 16, UIKit.INK)
		ctitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if enterprise.embargo >= 0:
			UIKit.badge(chead, "禁运:" + world.flag_name(enterprise.embargo), "warn")
		var dir_lbl: Label = hint(ccard, "负责人 %s  /  %d 站  /  资金 ¢%d  /  累计收入 ¢%d" % [world.name_of(enterprise.director), network, int(enterprise.get("treasury", 0)), enterprise.revenue])
		bind_character_menu(dir_lbl, int(enterprise.director))
		var hq_lbl: Label = hint(ccard, "总部 " + world.ports[enterprise.hq].name)
		bind_location_menu(hq_lbl, int(enterprise.hq))
		var cbtns: HBoxContainer = game.hbox(ccard)
		if world.Equity.at_market(world):
			UIKit.action_button(cbtns, "与公司交易", func(): game.open_trade_table("company", firm_id), "default")
		UIKit.action_button(cbtns, "股权董事会", func(): equity.open(game, "company", firm_id), "default")
		UIKit.action_button(cbtns, "导航总部", func(): game.navigate_to_station(int(enterprise.hq)), "ghost")
		if world.CompanyWars.is_pure_company(world, firm_id):
			var wars: Array = world.CompanyWars.active_wars_for_firm(world, firm_id)
			for cw in wars:
				UIKit.badge(ccard, "私掠交战并禁运：%s（%s · %.0f:%.0f · 劫掠 %d 次）" % [
					world.flag_name(int(cw.target_flag)), cw.get("pretext_label", "商业纠纷"),
					float(cw.get("firm_score", 0.0)), float(cw.get("target_score", 0.0)), int(cw.get("raids", 0))], "danger")
				if enterprise.director == world.player:
					var tf := int(cw.target_flag)
					UIKit.action_button(ccard, "私掠停战：" + world.flag_name(tf), func():
						var res: Dictionary = world.CompanyWars.director_action(world,"sign_company_peace",firm_id,tf)
						result(bool(res.get("ok", false)), "已签订商业和约。", String(res.get("reason", ""))), "primary")
			var cb_map: Dictionary = world.campaign.get("casus_belli", {})
			for cb in cb_map.values():
				if int(cb.get("firm_id", 0)) == firm_id:
					var tf := int(cb.get("target_flag", -1))
					if bool(cb.get("ready", false)):
						UIKit.badge(ccard, "借口就绪：%s（%s · 至第 %d 日）" % [world.flag_name(tf), cb.get("label", ""), int(cb.get("expires", 0))], "ok")
					else:
						UIKit.meter(ccard, "借口·" + world.flag_name(tf), float(cb.get("progress", 0)), float(cb.get("required", 45)), "info", "%d/%d 日" % [int(cb.get("progress", 0)), int(cb.get("required", 45))])
		if enterprise.director == world.player:
			var flags: Array = world.factions.keys()
			var emb_row: HBoxContainer = game.hbox(ccard)
			var embargo = UIKit.remembered_choice(emb_row, "firm_emb_%d" % firm_id, ["不禁运"] + flags.map(func(flag): return world.flag_name(flag)))
			embargo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UIKit.action_button(emb_row, "执行贸易政策", func():
				enterprise.embargo = flags[embargo.selected - 1] if embargo.selected > 0 else world.NEUTRAL
				result(true, "企业码头已更新贸易政策。"))
			if world.CompanyWars.is_pure_company(world, firm_id) and not flags.is_empty():
				var war_row: HBoxContainer = game.hbox(ccard)
				var war_target = UIKit.remembered_choice(war_row, "firm_wt_%d" % firm_id, flags.map(func(flag): return world.flag_name(flag)))
				war_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var pretext_keys := ["tariff_dispute", "asset_seizure", "privateer_incident"]
				var pretext_pick = UIKit.remembered_choice(war_row, "firm_pk_%d" % firm_id, ["关税纠纷 (¢1200 / 45日)", "资产纠纷 (¢1800 / 60日)", "袭扰借口 (¢2400 / 30日)"])
				var sel_flag := int(flags[clampi(war_target.selected, 0, flags.size() - 1)])
				var cb_ready: bool = world.CompanyWars.has_ready_pretext(world, firm_id, sel_flag)
				var act_row: HBoxContainer = game.hbox(ccard)
				UIKit.action_button(act_row, "制造战争借口", func():
					var tf := int(flags[war_target.selected])
					var kind: String = pretext_keys[pretext_pick.selected]
					var res: Dictionary = world.CompanyWars.director_action(world,"start_pretext",firm_id,tf,kind)
					result(bool(res.get("ok", false)), "已开始制造公司战争借口。", String(res.get("reason", ""))), "default", not cb_ready, "已存在就绪借口")
				UIKit.action_button(act_row, "凭借口私掠宣战 (¢1500)", func():
					var tf := int(flags[war_target.selected])
					var res: Dictionary = world.CompanyWars.director_action(world,"declare_company_war",firm_id,tf)
					result(bool(res.get("ok", false)), "公司已发起私掠宣战。", String(res.get("reason", ""))), "danger", cb_ready and int(enterprise.get("treasury", 0)) >= world.CompanyWars.CHARTER_FEE, "需先完成借口制造且公司资金 ≥ ¢1500")

func history(body: Node) -> void:
	heading(body, "断 航 纪 事")
	var hrow: HBoxContainer = game.hbox(body)
	hrow.add_theme_constant_override("separation", 4)
	for cat in ["全部", "特别关注", "军事外交", "商业企业", "开拓与个人"]:
		var hbtn := UIKit.action_button(hrow, cat, func():
			history_filter = cat
			game.refresh(), "primary" if history_filter == cat else "ghost")
		hbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if history_filter == "特别关注":
		var feed: Array = game.world.campaign.get("watched_feed", [])
		if feed.is_empty():
			hint(body, "暂无特别关注人物的新动态。可在人物档案或右键菜单中点击「★ 特别关注」。")
		else:
			for item in feed:
				var hcard := UIKit.card(body, UIKit.GOLD, true)
				hint(hcard, game.world.date_label(int(item[0])) + "  ★ " + str(item[2]))
		return
	for entry in game.world.chronicle:
		var txt := str(entry[1])
		var is_mil := ("宣战" in txt or "和约" in txt or "同盟" in txt or "夺取" in txt or "私掠" in txt or "借口" in txt)
		var is_biz := ("企业" in txt or "公司" in txt or "工业" in txt or "禁运" in txt or "赔款" in txt)
		if history_filter == "军事外交" and not is_mil:
			continue
		elif history_filter == "商业企业" and not is_biz:
			continue
		elif history_filter == "开拓与个人" and (is_mil or is_biz):
			continue
		var accent := UIKit.DANGER if ("宣战" in txt or "私掠" in txt) else (UIKit.GOLD if ("和约" in txt or "成立" in txt or "拓荒" in txt or "殖民" in txt) else Color.TRANSPARENT)
		var hcard := UIKit.card(body, accent, true)
		hint(hcard, game.world.date_label(entry[0]) + "  " + txt)

func successor(body: Node) -> void:
	var world = game.world
	heading(body, "一 段 人 生 结 束 了")
	hint(body,"没有在世继承人。你可以作为带船新人在当前宇宙重新启航，或接手星区中另一位有产/领航的成年人。")
	game.button(body, "在当前宇宙创建新角色启航（配初始飞船）", func():
		if Politics.new_adventurer(world):
			game.run_bridge())
	var leader_flags := {}
	for fid in world.factions:
		if world.factions[fid].alive:
			leader_flags[int(world.factions[fid].leader)] = fid
	var director_ids := {}
	for firm in world.firms.values():
		director_ids[int(firm.get("director", 0))] = true
	var owned_port_counts := {}
	var managed_port_counts := {}
	for st in world.ports.values():
		if st.build == 0:
			var o := int(st.get("owner", 0))
			var m := int(st.get("manager", 0))
			if o > 0:
				owned_port_counts[o] = int(owned_port_counts.get(o, 0)) + 1
			if m > 0:
				managed_port_counts[m] = int(managed_port_counts.get(m, 0)) + 1
	var owned_ship_counts := {}
	for sh in world.ships.values():
		var o := int(sh.get("owner", 0))
		if o > 0:
			owned_ship_counts[o] = int(owned_ship_counts.get(o, 0)) + 1
	var candidates: Array[Dictionary] = []
	for actor in world.people.values():
		if not actor.alive or Politics.age(world, actor) < 18 or int(actor.flag) == world.RAIDERS:
			continue
		var pid := int(actor.id)
		var is_leader := leader_flags.has(pid)
		var is_director := director_ids.has(pid)
		var op_cnt := int(owned_port_counts.get(pid, 0))
		var mp_cnt := int(managed_port_counts.get(pid, 0))
		var sh_cnt := int(owned_ship_counts.get(pid, 0))
		var has_ride: bool = int(actor.ship) != 0 and world.ships.has(int(actor.ship))
		var score := (1000 if is_leader else 0) + op_cnt * 300 + mp_cnt * 180 + sh_cnt * 100 + (80 if has_ride else 0) + (120 if is_director else 0)
		if score == 0:
			continue
		score += (20 if actor.noble else 0) + mini(50, int(actor.wallet) / 100)
		candidates.append({"actor": actor, "score": score, "leader": is_leader, "director": is_director, "ports": op_cnt, "managed": mp_cnt, "ships": sh_cnt, "ride": has_ride})
	if candidates.is_empty():
		for actor in world.people.values():
			if actor.alive and Politics.age(world, actor) >= 18:
				candidates.append({"actor": actor, "score": int(actor.wallet), "leader": false, "director": false, "ports": 0, "managed": 0, "ships": 0, "ride": false})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
	for item in candidates:
		var actor: Dictionary = item.actor
		var tags: Array[String] = []
		if item.leader:
			tags.append("势力领袖")
		if item.director:
			tags.append("公司董事")
		if item.ports > 0:
			tags.append("%d领地" % item.ports)
		if item.managed > 0:
			tags.append("%d站长" % item.managed)
		if item.ships > 0:
			tags.append("%d舰" % item.ships)
		elif item.ride:
			tags.append("在航舰长")
		tags.append("¢%d" % int(actor.wallet))
		var role_str := " · ".join(tags)
		game.button(body, "%s · %s · %s | %s" % [actor.name, "贵族" if actor.noble else "平民", world.flag_name(actor.flag), role_str], func():
			if Politics.choose(world, actor.id):
				game.run_bridge())
