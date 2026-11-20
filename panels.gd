extends RefCounted

const Portrait = preload("res://portrait.gd")
const Economy = preload("res://economy.gd")
const Politics = preload("res://politics.gd")
const Art = preload("res://presentation.gd")
const Hulls = preload("res://hull_catalog.gd")
const Celestial = preload("res://celestial.gd")

var game
var black_market := false

func heading(body: Node, text: String) -> void:
	game.title(body, text, 20, game.GOLD)

func hint(body: Node, text: String) -> void:
	game.title(body, text, 14, game.DIM, true)

func result(success: bool, yes: String, no: String = "条件未满足。") -> void:
	game.say(yes if success else no)
	game.refresh()

func delivery(world, station: Dictionary) -> void:
	var current: Dictionary = world.contracts.get(world.player, {})
	if current.get("type", -1) != 0 or current.target != station.id:
		return
	var vessel: Dictionary = world.ride()
	if vessel.get("dock", 0) != station.id or vessel.cargo[0] < 8:
		return
	vessel.cargo[0] -= 8
	station.stock[0] += 8
	world.credit(world.player, 145)
	world.contracts.erase(world.player)
	result(true, "交付成功，收到 145 信用点。")

func port(body: Node) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	var actor: Dictionary = world.active()
	var port_id: int = actor.loc
	var system_index: int = game.current_system()
	if port_id == 0:
		heading(body, "星区导航" if game.galaxy else Art.ENVIRONMENTS[Art.variation(system_index)])
		if not game.galaxy and system_index < 3:
			hint(body, Art.ENV_DESCRIPTIONS[system_index])
		hint(body, "靠近星系信标后按 M 跃入该星系。" if game.galaxy else "到恒星旁的引力点按 M 跃入超空间。接近航站后可按 E 停靠。")
		if game.galaxy:
			var nearby: Array = range(world.systems.size())
			var pos: Vector2 = vessel.galpos
			nearby.sort_custom(func(first, second): return pos.distance_squared_to(world.systems[first].pos) < pos.distance_squared_to(world.systems[second].pos))
			var shown := 0
			for index in nearby:
				if shown >= 12:
					break
				var destination: Dictionary = world.systems[index]
				var label := "%s  ·  %s  ·  %d" % [destination.name, world.flag_name(world.local_flag(index)) if destination.seen else "未勘测", pos.distance_to(destination.pos)]
				game.button(body, label, func():
					game.set_waypoint(destination.pos, destination.name))
				shown += 1
		elif not vessel.is_empty():
			var point := Celestial.gravity_point(world.systems[system_index])
			game.button(body, "追踪恒星引力点  →", func(): game.set_waypoint(point, "恒星引力点"))
			for station_id in world.systems[system_index].ports:
				var station: Dictionary = world.ports[station_id]
				var caption: String = "%s  ·  %s" % [station.name, world.flag_name(station.flag)]
				game.button(body, caption + "  →", func():
					game.set_waypoint(station.pos, station.name))
				if station.flag >= 0 and station.flag != actor.flag and station.build == 0:
					var actions = game.hbox(body)
					game.button(actions, "宣战 / 强占", func(): attack(station_id))
					if actor.flag == world.NEUTRAL:
						game.button(actions, "替雇主夺站", func(): attack(station_id, true))
		return
func market(body: Node, station: Dictionary) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	var actor: Dictionary = world.active()
	var port_id: int = station.id
	if station.firm != 0:
		hint(body, "经营商：" + world.firms[station.firm].name)
	if station.extension >= 0:
		hint(body, "扩建模块：%s%s" % [world.MODULES[station.extension], "（施工 %s 日）" % station.expansion if station.expansion > 0 else ""])
	if station.build > 0:
		hint(body, "工地需合金 %s/20，施工剩余 %s 日。" % [station.stock[1], station.build])
		game.button(body, "交付建材", func(): result(Economy.donate(world, port_id) > 0, "建材已卸到工地。"))
		return
	if not Economy.allowed(world, vessel if not vessel.is_empty() else {"flag": actor.flag}, station):
		hint(body, "战争或企业禁运导致公开市场关闭。")
		if not world.is_regular(station):
			return
	var suspicion := int(actor.get("suspicion", 0))
	var colony_info := "人口 %d/%d · 稳定度 %d%% · 关税 %d%%" % [station.get("pop", 0), station.get("pop_cap", 0), roundi(station.get("stability", 0.0)), roundi(station.get("tax_rate", 0.0) * 100.0)]
	if suspicion > 0:
		colony_info += " · 嫌疑 %d%%" % suspicion
	hint(body, colony_info)
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
		var regular: bool = world.is_regular(station)
		if not regular:
			black_market = false
		if regular:
			var mode_row = game.hbox(body)
			var pub_btn: Button = game.button(mode_row, "公开市场", func(): black_market = false; game.refresh(), true, true)
			pub_btn.toggle_mode = true
			pub_btn.button_pressed = not black_market
			var blk_btn: Button = game.button(mode_row, "黑市（免税）", func(): black_market = true; game.refresh(), true, true)
			blk_btn.toggle_mode = true
			blk_btn.button_pressed = black_market
		heading(body, "黑 市 交 易" if black_market else "挂 牌 市 场")
		if black_market:
			hint(body, "黑市免关税并流通违禁品，但会累积走私嫌疑，离港时可能遭遇巡逻队盘查。")
		var stock: Array = station.black if black_market else station.stock
		for ware in range(world.WARES.size()):
			if not black_market and ware == 6:
				continue
			if black_market and ware < 3 and stock[ware] == 0 and vessel.cargo[ware] == 0:
				continue
			var buy_p := Economy.price(station, ware, true, actor.origin, black_market)
			var sell_p := Economy.price(station, ware, false, actor.origin, black_market)
			var trend := "↑" if buy_p > int(Economy.BASE[ware] * 1.15) else ("↓" if buy_p < int(Economy.BASE[ware] * 0.9) else "·")
			var row = game.hbox(body)
			var line = game.title(row, "%s%s %d/仓%d · 买%d 卖%d" % [world.WARES[ware], trend, stock[ware], vessel.cargo[ware], buy_p, sell_p], 14)
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			game.button(row, "买5", func(): transaction(world, port_id, ware, 5, black_market))
			game.button(row, "买满", func(): transaction(world, port_id, ware, 200, black_market))
			game.button(row, "卖光", func(): transaction(world, port_id, ware, -200, black_market))
	heading(body, "委 托")
	var current: Dictionary = world.contracts.get(world.player, {})
	if current.get("type", -1) == 0:
		var target: Dictionary = world.ports[current.target]
		hint(body, "运送 8 矿石 → " + target.name)
		game.button(body, "交货", func(): delivery(world, station), port_id == target.id)
	elif current.get("type", -1) == 1:
		hint(body, "赏金：击毁任意裂缝掠夺者。")
	elif not current.is_empty():
		hint(body, "熄火之前：到炉心转运站的联络处交货。")
	else:
		game.button(body, "接运输委托  /  ¢145", func():
			var target: int = world.systems[1].ports[1] if station.system != 1 else world.systems[0].ports[0]
			world.contracts[world.player] = {"type": 0, "target": target}
			result(true, "已登记运输委托。"))
		game.button(body, "接掠夺者赏金  /  ¢180", func():
			world.contracts[world.player] = {"type": 1}
			result(true, "已登记赏金委托。"))
	if not current.is_empty():
		game.button(body, "取消当前委托", func(): world.contracts.erase(world.player); game.refresh())

func transaction(world, port_id: int, ware: int, amount: int, black: bool = false) -> void:
	var moved := Economy.trade(world, port_id, ware, amount, black)
	result(moved != 0, "已%s %d 单位%s。" % ["买入" if moved > 0 else "卖出", absi(moved), world.WARES[ware]], "没有足够库存、货物、信用点、仓位或日吞吐额度。")

func attack(port_id: int, mercenary: bool = false) -> void:
	var world = game.world
	var vessel: Dictionary = world.ride()
	var station: Dictionary = world.ports[port_id]
	var actor: Dictionary = world.active()
	if vessel.is_empty() or vessel.dock != 0 or vessel.pos.distance_to(station.pos) > 150:
		game.say("先靠近目标空间站（150 距离内）。")
		return
	if game.flight.target(vessel, 395) != 0:
		game.say("附近有敌方守卫，先击退它们。")
		return
	if actor.flag >= 0 and not world.hostile(actor.flag, station.flag):
		world.set_treaty(actor.flag, station.flag, -1)
		result(true, "已宣战；击退守卫后可再次发起强占。")
		return
	for guard in world.ships.values():
		if guard.flag == station.flag and guard.system == station.system and guard.dock == 0 and guard.pos.distance_to(station.pos) < 510:
			if actor.flag == world.NEUTRAL:
				vessel.raid = station.flag
				result(false, "", "突袭已暴露：守卫现在会攻击你。先击毁守卫。")
				return
	if vessel.locked:
		flight_unlock(world, vessel)
	if vessel.hp <= station.defense * 0.5:
		game.say("船体不足以强攻防务。")
		return
	var flag: int = actor.flag
	if mercenary:
		for candidate in world.factions:
			if world.factions[candidate].alive and world.hostile(candidate, station.flag):
				flag = candidate
				break
		if flag == world.NEUTRAL:
			game.say("没有正在与目标交战的雇主。")
			return
		world.credit(world.player, 280)
	vessel.hp -= station.defense * 0.5
	Politics.conquer(world, port_id, flag, 0 if mercenary else world.player)
	vessel.raid = world.NEUTRAL
	vessel.flag = actor.flag
	result(true, "空间站已接管。")

func flight_unlock(world, vessel: Dictionary) -> void:
	if game.flight.target(vessel, 380) == 0:
		vessel.locked = false

func person(body: Node) -> void:
	var world = game.world
	var actor: Dictionary = world.active()
	heading(body, actor.name + ("  ·  " + actor.house + "家族" if actor.noble else "  ·  平民"))
	var top = game.hbox(body)
	var face := Portrait.new()
	face.custom_minimum_size = Vector2(125, 140)
	face.look = actor.look
	top.add_child(face)
	var info = game.vbox(top)
	hint(info, "%d 岁 · %s" % [Politics.age(world, actor), world.ORIGINS[actor.origin]])
	hint(info, "%s · %s" % [world.TRAITS[actor.trait], world.flag_name(actor.flag)])
	if world.regency != 0:
		hint(body, "当前扮演摄政；未成年继承人：" + world.name_of(world.regency))
	if actor.noble:
		heading(body, "家 族")
		hint(body, "配偶 %s  /  继承法：%s" % [world.name_of(actor.spouse), "集中继承" if actor.law else "分产"])
		game.button(body, "更改继承制度", func(): result(Politics.change_law(world), "继承制度已更新。"), world.regency == 0)
		var blood: Array = Politics.blood(world, actor.id)
		for relative_id in blood.slice(0, 20):
			var relative: Dictionary = world.people[relative_id]
			var record = game.hbox(body)
			var portrait := Portrait.new()
			portrait.custom_minimum_size = Vector2(53, 61)
			portrait.look = relative.look
			record.add_child(portrait)
			hint(record, "%s · %s · %d 岁%s" % [relative.house, relative.name, Politics.age(world, relative), "" if relative.alive else "（已故）"])
	else:
		hint(body, "平民不建立贵族家谱。夺取领地后可晋身贵族；开办企业不需要贵族头衔。")
	heading(body, "当 地 人 物")
	if actor.loc == 0:
		hint(body, "停靠后可见当地人物、谈婚姻或送礼。")
		return
	for other in world.people.values():
		if other.id == actor.id or not other.alive or other.loc != actor.loc or Politics.age(world, other) < 18:
			continue
		var row = game.hbox(body)
		var line = game.title(row, "%s · %s · 好感 %d" % [other.name, "贵族" if other.noble else "平民", Politics.opinion(world, other.id, actor.id)])
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.button(row, "送礼", func(): result(Politics.influence(world, other.id), "赠礼已送达。"), actor.wallet >= 35)
		if actor.noble and other.noble and actor.spouse == 0 and other.spouse == 0:
			game.button(row, "联姻", func(): result(Politics.marry(world, actor.id, other.id), "联姻成立。", "对方不愿意，或存在血亲关系。"))

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

func assets(body: Node) -> void:
	var world = game.world
	var actor: Dictionary = world.active()
	var vessel: Dictionary = world.ride()
	heading(body, "私 有 舰 船")
	for ship_id in world.ships:
		var owned: Dictionary = world.ships[ship_id]
		if not world.oversees(owned.owner):
			continue
		var ship_row = game.hbox(body)
		Art.contained(ship_row, Art.ship(owned.kind), Vector2(84, 57))
		var register = game.vbox(ship_row)
		game.title(register, world.HULLS[owned.kind], 17)
		hint(register, "%s · %s" % [Hulls.CLASS_NAMES[Hulls.MODELS[owned.kind].size], world.name_of(owned.captain)])
		if owned.owner != actor.id:
			hint(body, "摄政代管  ·  所有权归 " + world.name_of(owned.owner))
		if owned.id == vessel.get("id", 0):
			hint(body, "正在驾驶")
			continue
		game.button(body, "登舰接管", func(): result(world.pilot(ship_id), "你已亲自驾驶这艘船。"), actor.loc != 0 and owned.dock == actor.loc)
		var workers := crew(world, actor, owned)
		if workers.is_empty():
			continue
		var assignee = game.choice(body, workers.map(func(candidate): return world.name_of(candidate) + " · 忠诚 %s" % world.people[candidate].loyalty))
		var kinds := ["贸易", "采矿", "护航"]
		var job_index := kinds.find(owned.job.get("kind", "贸易"))
		var orders = game.choice(body, kinds, maxi(0, job_index))
		var stops := routes([])
		var source = game.choice(body, stops.map(func(stop): return "起：" + world.ports[stop].name))
		var target = game.choice(body, stops.map(func(stop): return "终：" + world.ports[stop].name), mini(1, stops.size() - 1))
		game.button(body, "任命 / 派单（新聘 ¢55）", func():
			result(Economy.assign(world, ship_id, workers[assignee.selected], orders.get_item_text(orders.selected),
				stops[source.selected] if source.selected >= 0 else 0, stops[target.selected] if target.selected >= 0 else 0), "船长已收到长期指令。"))
	heading(body, "空 间 站  /  企 业")
	if not vessel.is_empty() and not game.galaxy and vessel.dock == 0 and not vessel.locked:
		var build = game.choice(body, world.MODULES)
		game.button(body, "在当前位置设工地  ¢120", func():
			result(Economy.deploy(world, build.selected, vessel.pos) != 0, "工地登记完成，停靠后交付 20 合金。", "离其他空间站至少 145 距离，费用 ¢120。"))
	for port_id in world.ports:
		var station: Dictionary = world.ports[port_id]
		if not world.oversees(station.owner):
			continue
		game.title(body, station.name)
		hint(body, "站长 %s  ·  %s" % [world.name_of(station.manager), "营运中" if station.build == 0 else "施工中"])
		if station.build > 0:
			continue
		if vessel.get("dock", 0) == station.id and station.extension == -1:
			var module = game.choice(body, world.MODULES)
			game.button(body, "扩建  /  ¢90 + 合金 16", func(): result(Economy.expand(world, port_id, module.selected), "已开工扩建。"))
		var workers := crew(world, actor, {})
		if not workers.is_empty():
			var assignee = game.choice(body, workers.map(func(candidate): return world.name_of(candidate)))
			game.button(body, "任命站长  ¢45", func(): result(Economy.manager(world, port_id, workers[assignee.selected]), "已任命站长。"))
		if station.firm == 0 and station.owner == actor.id:
			var firm_label = game.field(body, actor.name + "工业")
			game.button(body, "注册企业  ¢180", func(): result(Economy.incorporate(world, port_id, firm_label.text), "企业注册成功。"))
			for owned_firm in world.firms:
				if world.firms[owned_firm].director == world.player:
					game.button(body, "并入 " + world.firms[owned_firm].name, func():
						station.firm = owned_firm
						result(true, "企业网络已扩张。"))
		if station.owner == actor.id and world.factions.get(actor.flag, {}).get("leader", 0) != actor.id:
			var state_label = game.field(body, actor.name + "领")
			var regime = game.choice(body, world.REGIMES)
			game.button(body, "宣布建立势力", func(): result(Politics.found(world, state_label.text, port_id, regime.selected), "新势力已进入星区。"))

func powers(body: Node) -> void:
	var world = game.world
	heading(body, "政 体  /  版 图")
	for flag in world.factions:
		var power: Dictionary = world.factions[flag]
		game.title(body, power.name + ("  /  已灭亡" if not power.alive else ""), 17, world.flag_color(flag))
		hint(body, "%s  ·  %s  ·  %s  ·  %s 站" % [world.REGIMES[power.regime], world.STYLES[power.style], world.lead_name(flag), world.systems_owned(flag).size()])
		var foes: Array = []
		for other in world.factions:
			if world.factions[other].alive and world.hostile(flag, other):
				foes.append(world.flag_name(other))
		if not foes.is_empty():
			hint(body, "交战：" + "、".join(foes))
	heading(body, "跨 星 系 企 业")
	for firm_id in world.firms:
		var enterprise: Dictionary = world.firms[firm_id]
		var network := 0
		for station in world.ports.values():
			if station.firm == firm_id:
				network += 1
		game.title(body, enterprise.name)
		hint(body, "负责人 %s  /  %d 站  /  累计收入 ¢%d" % [world.name_of(enterprise.director), network, enterprise.revenue])
		hint(body, "总部 " + world.ports[enterprise.hq].name)
		if enterprise.embargo >= 0:
			hint(body, "禁运：" + world.flag_name(enterprise.embargo))
		if enterprise.director == world.player:
			var flags: Array = world.factions.keys()
			var embargo = game.choice(body, ["不禁运"] + flags.map(func(flag): return world.flag_name(flag)))
			game.button(body, "执行贸易政策", func():
				enterprise.embargo = flags[embargo.selected - 1] if embargo.selected > 0 else world.NEUTRAL
				result(true, "企业码头已更新贸易政策。"))

func history(body: Node) -> void:
	heading(body, "断 航 纪 事")
	for entry in game.world.chronicle:
		hint(body, game.world.date_label(entry[0]) + "  " + entry[1])

func successor(body: Node) -> void:
	var world = game.world
	heading(body, "一 段 人 生 结 束 了")
	hint(body, "没有可继续扮演的血亲。改选当前宇宙中的任意成年人物，保留其原有处境；不会带走旧角色的财产。")
	for actor in world.people.values():
		if actor.alive and Politics.age(world, actor) >= 18:
			game.button(body, "%s  ·  %s  ·  %s" % [actor.name, "贵族" if actor.noble else "平民", world.flag_name(actor.flag)], func():
				if Politics.choose(world, actor.id):
					game.run_bridge())
