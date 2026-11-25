extends RefCounted

const Crises = preload("res://scripts/campaign/crises.gd")
const Society = preload("res://scripts/campaign/society.gd")
const Operations = preload("res://scripts/campaign/operations.gd")
const WarPeace = preload("res://scripts/campaign/war_peace.gd")
const Bounties = preload("res://scripts/campaign/bounties.gd")
const Economy = preload("res://economy.gd")
const Hulls = preload("res://hull_catalog.gd")
const FleetOrder = preload("res://scripts/models/fleet_order.gd")
const CargoIcons = preload("res://scripts/ui/cargo_icons.gd")
const Blueprint = preload("res://scripts/ui/refit_blueprint.gd")
const WingPreview = preload("res://scripts/ui/wing_preview.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")

var game
var section := 0
var index_group := 0
var fleet_ship := 0
var fleet_kind := "dock"
var fleet_port := 0
var fleet_ware := 0
var fleet_quantity := 1
var displayed_orders: Array = []
var displayed_receipt: Dictionary = {}

func fleet_status_changed() -> bool:
	if section != 2:
		return false
	var ship: Dictionary = game.world.ships.get(fleet_ship,{})
	return ship.get("order_queue",[]) != displayed_orders or ship.get("last_order",{}) != displayed_receipt

func done(ok: bool, message: String) -> void:
	game.say(message if ok else "条件不足，请检查权限、资金、位置和所需物资。")
	game.refresh()

func event_buttons(body: Control, event: Dictionary) -> void:
	var world = game.world
	for index in range(event.options.size()):
		var option: Dictionary = event.options[index]
		var caption: String = option.label if option.enabled else "%s（%s）" % [option.label, option.reason]
		var button = game.button(body, caption, func():
			done(Society.decide(world, event.id, index), option.label), option.enabled)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = option.reason

func show(body: Control) -> void:
	var nav = game.choice(body, ["人物与家族", "港务与研究", "航行与舰队", "全舰档案", "星区危机"], section)
	nav.item_selected.connect(func(i: int): section = i; game.refresh())
	match section:
		0: court(body)
		1: industry(body)
		2: travel(body)
		3: index(body)
		4: crises(body)

func court(body: Control) -> void:
	var world = game.world
	var actor: Dictionary = world.active()
	for event: Dictionary in Society.pending_all(world):
		game.hud.heading(body, event.title)
		game.hud.hint(body, event.body)
		event_buttons(body, event)
	var concept = game.title(body,"性格与压力",17,game.GOLD)
	game.glossary.bind(concept,"stress")
	var map_row = game.hbox(body)
	game.button(map_row, "战略地图", func(): game.open_strategic_map("strategic"))
	var active_wars := WarPeace.active_wars(world, int(actor.get("flag", -1)))
	if not active_wars.is_empty():
		game.button(map_row, "和谈地图（%d 场战争）" % active_wars.size(), func(): game.open_strategic_map("peace", active_wars[0].enemy))
		for w in active_wars:
			game.hud.hint(body, "对 %s 之战（%d 日）：战分 %.0f vs %.0f | 厌战 %.0f%% / %.0f%% | 占领 %d 站" % [
				world.flag_name(w.enemy), w.days, w.my_score, w.enemy_score, w.my_exhaustion, w.enemy_exhaustion, w.occupied_by_me.size()])
	game.hud.heading(body, "%s · %s家族" % [actor.name, actor.house])
	game.hud.hint(body, "压力 %d / 400　正统性 %d　威望 %d　功绩 %d　家族传承 %d" % [actor.stress, actor.legitimacy, actor.prestige, actor.merit, world.campaign.houses.get(actor.house,0)])
	game.hud.hint(body, "外交 %d　军事 %d　管理 %d　谋略 %d　学识 %d　勇武 %d" % [actor.stats.diplomacy,actor.stats.martial,actor.stats.stewardship,actor.stats.intrigue,actor.stats.learning,actor.stats.prowess])
	var tracks: Array = Society.rules.lifestyles
	var ids := tracks.map(func(row): return row.id)
	var focus = game.choice(body, tracks.map(func(row): return row.name), maxi(0,ids.find(actor.focus)))
	var row = game.hbox(body)
	game.button(row, "选择生活方式", func(): done(Society.focus(world, ids[focus.selected]), "已开始修习。"))
	game.button(row, "升阶 · 经验 %d" % actor.experience, func(): done(Society.train(world), "技能已提升。"), not actor.focus.is_empty())
	var op: Dictionary = world.campaign.schemes.get(actor.id, {})
	if not op.is_empty():
		game.hud.hint(body, "%s · %s · 第 %d / 3 阶段" % [world.name_of(op.target), "调查" if op.kind == "find_secrets" else "拉拢", op.stage])
		game.button(body, "资助调查 ¢25", func(): done(Society.fund_scheme(world), "已追加资助。"), op.stage < 3 and op.funded < 3)
		game.button(body, "收网", func(): done(Society.resolve_scheme(world), "行动已结束，详见纪事。"), op.stage >= 3)
	for target in actor.hooks:
		game.button(body, "使用把柄 · " + world.name_of(target), func(): done(Society.use_hook(world,target), "对方已退出反对派。"))
	if actor.loc == 0:
		return
	game.button(body, "参加任官考试 ¢10", func(): done(Operations.civic(world,"examination",0),"功绩已登记。"))
	var locals: Array = world.people.values().filter(func(other): return actor.loc != 0 and other.alive and other.id != actor.id and other.loc == actor.loc)
	if not locals.is_empty():
		var pick = game.choice(body, locals.map(func(other): return other.name))
		var tools = game.hbox(body)
		game.button(tools, "拉拢", func(): done(Society.scheme(world,locals[pick.selected].id,"sway"),"开始接触目标。"), op.is_empty())
		game.button(tools, "调查秘密", func(): done(Society.scheme(world,locals[pick.selected].id,"find_secrets"),"开始调查。"), op.is_empty())
		game.button(tools, "任命站长", func(): done(Operations.civic(world,"appoint",locals[pick.selected].id),"任命已生效。"), Operations.rights(world,world.ports[actor.loc]))
	if not actor.children.is_empty() and actor.noble:
		var heirs = game.choice(body, actor.children.map(func(id): return world.name_of(id)))
		game.button(body, "指定继承人", func(): done(Operations.civic(world,"designate",actor.children[heirs.selected]),"家族遗嘱已更新。"))
	for flag in world.campaign.movements:
		if not Society.player_governs(world,flag):
			continue
		var movement: Dictionary = world.campaign.movements[flag]
		if movement.get("members",[]).is_empty():
			continue
		var demand: String = movement.get("demand","地方自治")
		game.hud.hint(body,"%s · 不满 %d/100 · 反对派战力 %d / 忠诚派 %d" % [demand,movement.discontent,movement.get("rebel_power",0),movement.get("loyal_power",0)])
		if movement.ultimatum:
			var replies = game.hbox(body)
			game.button(replies,"接受诉求",func(): done(Society.answer_ultimatum(world,flag,true),"已签署协议。"))
			game.button(replies,"拒绝通牒",func(): done(Society.answer_ultimatum(world,flag,false),"派系已响应。"))

func industry(body: Control) -> void:
	var concept = game.title(body,"库存与预留",17,game.GOLD)
	game.glossary.bind(concept,"reservation")
	var world = game.world
	var active_bounties: Array = Bounties.active(world)
	if not active_bounties.is_empty():
		game.hud.heading(body, "星区自动悬赏（无需接取，非敌对击毁即领）")
		for b: Dictionary in active_bounties:
			var scope_text: String = "%s 星系" % world.systems[int(b.system)].name if int(b.system) >= 0 else "全星区"
			var rel_ok: bool = not world.hostile(world.active().flag, int(b.issuer_flag))
			var status_text: String = "可自动领取" if rel_ok else "敌对不可领"
			game.hud.hint(body, "%s 悬赏 %s · 范围：%s · 基础 ¢%d+ · 剩余 %d 天 · %s" % [world.flag_name(int(b.issuer_flag)), world.flag_name(int(b.target_flag)), scope_text, int(b.base_reward), maxi(0, int(b.expires) - world.day), status_text])
	var site: Dictionary = world.ports.get(world.active().loc, {})
	if site.is_empty():
		game.hud.hint(body, "停靠后可查看本站的物流、订货和研究。")
		return
	game.hud.heading(body, site.name)
	var names: Array = site.modules.map(func(id): return world.MODULES[id])
	game.hud.hint(body, "生产模块　" + "、".join(names))
	game.hud.hint(body, "入库预留 %d　出库预留 %d　生产订单 %d" % [site.inbound.size(),site.outbound.size(),site.production_orders.size()])
	for i in range(world.WARES.size()):
		if site.stock[i] or site.build_storage[i]:
			game.hud.hint(body, "%s　库存 %d　施工仓 %d" % [world.WARES[i],site.stock[i],site.build_storage[i]])
	if not Operations.rights(world, site):
		return
	var methods = ["universal", "direct", "recycling"]
	var selector = game.choice(body, ["通用工业链","短链制造","回收制造"],maxi(0,methods.find(site.method)))
	game.button(body,"切换生产法",func(): done(Economy.set_method(world,site.id,methods[selector.selected]),"已更新生产法。"))
	var project: Dictionary = world.campaign.projects.get(site.id, {})
	if not project.is_empty():
		var spec := Society.candidates(Society.rules.projects,project.id)
		game.hud.hint(body, "%s　%d / %d 日" % [spec.name,project.progress,spec.days])
	else:
		var research = game.choice(body, Society.rules.projects.map(func(p): return p.name))
		var details = game.title(body,"",14,game.DIM,true)
		var explain := func(i: int):
			var p: Dictionary = Society.rules.projects[i]
			var items := []
			for m in p.materials:
				items.append("%s ×%d" % [world.WARES[int(m[0])],int(m[1])])
			details.text = "%d 日 · %s" % [p.days, "、".join(items)]
		explain.call(0)
		research.item_selected.connect(explain)
		game.button(body,"立项并交付物资",func(): done(Operations.start_project(world,site.id,Society.rules.projects[research.selected].id),"项目已进入施工队列。"))
	var laws = game.hbox(body)
	game.button(laws,"降低税率",func(): done(Operations.civic(world,"charter",-1),"契约已更新。"))
	game.button(laws,"文化交流",func(): done(Operations.civic(world,"integrate",0),"港区已接纳本地文化。"))
	game.button(laws,"改革信约",func(): done(Operations.civic(world,"reform",0),"信约已更替。"))

func travel(body: Control) -> void:
	var world = game.world
	var actor: Dictionary = world.active()
	if actor.has("journey"):
		game.hud.hint(body, "目的地 %s · 预计 %s 抵达" % [world.ports[actor.journey.target].name,world.date_label(actor.journey.arrives)])
		return
	if actor.loc != 0:
		var sites: Array = world.ports.values().filter(func(p): return p.scan or p.flag == actor.flag)
		if not sites.is_empty():
			var destination = game.choice(body,sites.map(func(p): return p.name))
			var visits = ["tour","festival","wedding","coronation","funeral","pilgrimage","embassy","quarantine"]
			var purpose = game.choice(body,["巡游","竞技庆典","婚礼","加冕","葬礼","朝圣","使团","隔离巡查"])
			game.button(body,"安排旅程 ¢25",func(): done(Operations.expedition(world,visits[purpose.selected],sites[destination.selected].id),"已启程，请推进时间。"))
			if Operations.rights(world,world.ports[actor.loc]):
				game.button(body,"登记宣称",func(): done(Operations.civic(world,"claim",sites[destination.selected].id),"法理宣称已登记。"))
				game.button(body,"依宣称开战",func(): done(Operations.civic(world,"press_claim",sites[destination.selected].id),"已通告交战双方。"))
				game.button(body,"建立朝贡 ¢50",func(): done(Operations.civic(world,"tribute",sites[destination.selected].id),"朝贡条约已生效。"))
	var lead: Dictionary = world.ride()
	if lead.is_empty():
		return
	if lead.dock == 0 and not lead.layer:
		game.button(body,"向选定敌舰投送登舰队",func(): done(Operations.begin_boarding(world,game.selected_target),"登舰队已出发。"))
	var escorts: Array = world.ships.values().filter(func(v): return world.oversees(world.ship_principal(v)) and v.id != lead.id)
	if escorts.is_empty():
		return
	var ids := escorts.map(func(v): return v.id)
	var escort = game.choice(body,escorts.map(func(v): return "%s · #%d" % [world.HULLS[v.kind],v.id]),maxi(0,ids.find(fleet_ship)))
	var ship: Dictionary = escorts[escort.selected]
	fleet_ship = ship.id
	escort.item_selected.connect(func(i: int): fleet_ship = ids[i]; game.refresh())
	var roles := FleetOrder.ROLES.keys()
	var role = game.choice(body,FleetOrder.ROLES.values(),maxi(0,roles.find(ship.get("fleet_role",""))))
	game.button(body,"分派舰队职责",func(): done(Economy.assign_role(world,ship.id,lead.id,roles[role.selected]),"职责已下达。"),ship.captain != 0)
	game.button(body,"传送至舰桥",func(): done(Operations.teleport(world,ship.id),"已抵达目标舰桥。"))
	fleet_orders(body,ship)

func fleet_orders(body: Control, ship: Dictionary) -> void:
	var world = game.world
	if ship.captain == 0:
		game.hud.hint(body,"在资产页任命船长后即可下达指令。")
		return
	var behavior: Dictionary = ship.get("default_behavior",ship.job)
	var duty: String = FleetOrder.ROLES.get(ship.get("fleet_role",""),"")
	game.hud.heading(body,"舰船指令队列")
	game.hud.hint(body,"默认行为　%s %s" % [behavior.get("label",behavior.get("kind","待命")),duty])
	var orders: Array = ship.get("order_queue",[])
	displayed_orders = orders.duplicate(true)
	for i in orders.size():
		var row = game.hbox(body)
		game.hud.hint(row,("%s　" % ("执行中" if i == 0 else str(i + 1))) + FleetOrder.describe(world,orders[i]))
		game.button(row,"撤单",func(): done(Economy.cancel_order(world,ship.id,i),"已撤销指令。"))
	var last: Dictionary = ship.get("last_order",{})
	displayed_receipt = last.duplicate(true)
	if not last.is_empty():
		var moved := "　实际 %d" % last.moved if FleetOrder.carries_goods(last.order.kind) else ""
		game.hud.hint(body,"上次　%s　%s%s" % [FleetOrder.describe(world,last.order),last.result,moved])
	var sites: Array = world.ports.values().filter(func(p): return (p.scan or p.flag == world.active().flag or world.oversees(p.owner)) and Economy.allowed(world,ship,p) and not Economy.forbidden(ship,p))
	if sites.is_empty():
		game.hud.hint(body,"没有已知且允许停靠的目的港。")
		return
	var kinds := FleetOrder.LABELS.keys()
	var kind = game.choice(body,FleetOrder.LABELS.values(),kinds.find(fleet_kind))
	var port_ids := sites.map(func(p): return p.id)
	var port = game.choice(body,sites.map(func(p): return "%s · %s" % [world.systems[p.system].name,p.name]),maxi(0,port_ids.find(fleet_port)))
	port.item_selected.connect(func(i: int): fleet_port = port_ids[i])
	var cargo = game.hbox(body)
	var ware: OptionButton = game.choice(cargo,world.WARES,fleet_ware)
	for i in ware.item_count:
		ware.set_item_icon(i,CargoIcons.texture("ware",i))
	ware.item_selected.connect(func(i: int): fleet_ware = i)
	var quantity := SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = maxi(1,world.HULL_CARGO[ship.kind])
	quantity.value = fleet_quantity
	quantity.value_changed.connect(func(n: float): fleet_quantity = int(n))
	cargo.add_child(quantity)
	cargo.visible = FleetOrder.carries_goods(fleet_kind)
	kind.item_selected.connect(func(i: int): fleet_kind = kinds[i]; cargo.visible = FleetOrder.carries_goods(fleet_kind))
	game.button(body,"加入队尾",func(): done(Economy.queue_order(world,ship.id,sites[port.selected].id,kinds[kind.selected],ware.selected,int(quantity.value)),"已加入指令队列。"),orders.size() < FleetOrder.LIMIT)

func index(body: Control) -> void:
	var groups := ["hulls","skins","wings","variants"]
	var source := Hulls.manifest()
	var labels := {"hulls":"基础舰体","skins":"派生舰体","wings":"战机联队","variants":"预设装配"}
	var categories := {"ship":"独立舰型","fighter":"舰载机","station":"空间站","module":"附属模块","auxiliary":"辅助实体"}
	var options := PackedStringArray(["全部类别"])
	for key in groups:
		options.append("%s · %d" % [labels[key],source[key].size()])
	var pick = game.choice(body,Array(options),index_group)
	var query := LineEdit.new()
	query.placeholder_text = "搜索本作舰名、原型名或 ID"
	body.add_child(query)
	var tally = game.title(body,"",13,game.DIM)
	var list := ItemList.new()
	list.custom_minimum_size.y = 200
	body.add_child(list)
	var info = game.title(body,"",14,game.INK,true)
	var preview_card := UIKit.card(body, UIKit.CYAN)
	var present := func(i: int):
		for child in preview_card.get_children():
			child.queue_free()
		if i < 0:
			info.text = ""
			preview_card.get_parent().visible = false
			return
		preview_card.get_parent().visible = true
		var r: Dictionary = list.get_item_metadata(i)
		var kind := Hulls.kind_for_id(r.project_id)
		var lines := PackedStringArray()
		lines.append(str(r.name))
		lines.append("原型  %s   ·   %s" % [r.get("reference_name",r.id),r.id])
		if r.record_type == "wings":
			var roles := {"fighter":"制空","bomber":"轰炸","interceptor":"截击","support":"支援"}
			lines.append("%s联队  ·  %d 架  ·  补充 %.1f 秒" % [roles.get(r.role,r.role),r.count,r.refit])
			lines.append("机体  %s   ·   装配  %s" % [r.airframe,r.variant])
			var wing := Hulls.wing_spec(r.id)
			lines.append("港口整备 → 舰载联队 · %s · ¢%d" % [wing.specialty,wing.price])
			if not wing.native_trade:
				lines.append("本作提供通用机库转接规格，原型使用特殊投放渠道。")
			if r.carriers.is_empty():
				lines.append("在可换装机库按需制造。")
			else:
				lines.append("出厂搭载  "+ "、".join(r.carriers))
			var wing_view := WingPreview.new()
			wing_view.configure(r.id)
			preview_card.add_child(wing_view)
			var badges := HBoxContainer.new()
			badges.add_theme_constant_override("separation", 6)
			preview_card.add_child(badges)
			UIKit.badge(badges, roles.get(r.role, r.role) + "联队", "info")
			UIKit.badge(badges, "%d 架" % int(r.count), "gold")
			UIKit.badge(badges, "补充 %.1fs" % float(r.refit), "ok")
			UIKit.badge(badges, "¢%d" % int(wing.price), "dim")
		elif r.record_type == "variants":
			lines.append("所属原型  %s   ·   %s" % [r.parent_name,r.hull])
			if kind >= 0:
				lines.append("可在该舰整备页申请本作对应预设，费用与可用装备由停靠港决定。")
			else:
				lines.append("所属类别  %s。此配置用于参考附属单元。" % categories.get(r.category,r.category))
			lines.append("装备组 %d   ·   联队 %d   ·   模块 %d" % [r.guns.size(),r.wings.size(),r.modules.size()])
			lines.append(r.path)
			if kind >= 0:
				var fit: Dictionary = Hulls.preset_fit(kind, r.path)
				var bp := Blueprint.new()
				bp.custom_minimum_size = Vector2(0, 168)
				bp.configure(kind, -1, fit.get("weapons", []))
				preview_card.add_child(bp)
				var model := Hulls.hull_spec(kind)
				var badges := HBoxContainer.new()
				badges.add_theme_constant_override("separation", 6)
				preview_card.add_child(badges)
				UIKit.badge(badges, Hulls.CLASS_NAMES[model.size], "gold")
				UIKit.badge(badges, model.role, "info")
				UIKit.badge(badges, "预设装配", "ok")
		elif kind >= 0:
			var model := Hulls.hull_spec(kind)
			var rect := Rect2(model.bounds[0],Vector2.ZERO)
			for point: Vector2 in model.bounds:
				rect = rect.expand(point)
			lines.append("%s   ·   %s   ·   %s" % [Hulls.CLASS_NAMES[model.size],model.role,"船坞可供" if Hulls.available_for_market(kind) else "专用舰型，船坞不列售"])
			lines.append("战场长度 %.1f   ·   型宽 %.1f   ·   每贴图像素 %.2f 战场单位" % [rect.size.x,rect.size.y,model.sprite_scale])
			lines.append("武器位 %d   ·   机库 %d   ·   部署 %d   ·   装配点 %d" % [model.mounts.size(),model.fighter_bays,model.dp,model.combat.op])
			if r.has("base"):
				lines.append("派生母型  "+str(r.base))
			var bp := Blueprint.new()
			bp.custom_minimum_size = Vector2(0, 168)
			bp.configure(kind, -1, Hulls.stock_fit(kind).weapons)
			preview_card.add_child(bp)
			var badges := HBoxContainer.new()
			badges.add_theme_constant_override("separation", 6)
			preview_card.add_child(badges)
			UIKit.badge(badges, Hulls.CLASS_NAMES[model.size], "gold")
			UIKit.badge(badges, model.role, "info")
			UIKit.badge(badges, "船坞可供" if Hulls.available_for_market(kind) else "专用舰型", "ok" if Hulls.available_for_market(kind) else "dim")
			UIKit.meter(preview_card, "船体", float(model.hp), 1600.0, "ok", "%d" % int(model.hp))
			UIKit.meter(preview_card, "装甲", float(model.combat.armor), 320.0, "gold", "%.0f" % float(model.combat.armor))
			UIKit.meter(preview_card, "幅能", float(model.combat.capacity), 1200.0, "info", "%.0f" % float(model.combat.capacity))
			UIKit.meter(preview_card, "装配", float(model.combat.op), 160.0, "info", "%d OP" % int(model.combat.op))
		else:
			var technical := Hulls.attachment_spec(r.id)
			lines.append("归类  %s   ·   附属定义与原型档案" % categories.get(r.category,r.category))
			lines.append("耐久 %.0f   ·   装甲 %.0f   ·   挂点 %d" % [technical.get("hp",0),technical.get("armor",0),technical.get("banks",0)])
			if not technical.get("modules",[]).is_empty():
				lines.append("挂载子模块  %d" % technical.modules.size())
			var badges := HBoxContainer.new()
			badges.add_theme_constant_override("separation", 6)
			preview_card.add_child(badges)
			UIKit.badge(badges, categories.get(r.category, r.category), "info")
			UIKit.badge(badges, "附属模块", "dim")
			UIKit.meter(preview_card, "耐久", float(technical.get("hp", 0)), 3000.0, "ok", "%.0f" % float(technical.get("hp", 0)))
			UIKit.meter(preview_card, "装甲", float(technical.get("armor", 0)), 500.0, "gold", "%.0f" % float(technical.get("armor", 0)))
		lines.append("本作 ID   "+str(r.project_id))
		info.text = "\n".join(lines)
	var populate := func(term: String):
		list.clear()
		var needle := term.strip_edges().to_lower()
		for key in groups:
			if index_group > 0 and key != groups[index_group - 1]:
				continue
			for r in source[key]:
				var fields := "%s %s %s %s %s %s %s" % [r.name,r.id,r.project_id,r.reference_name,r.get("base",""),r.get("parent_name",""),r.get("hull","")]
				if not needle.is_empty() and not fields.to_lower().contains(needle):
					continue
				var item := list.add_item("%s   ·   %s" % [r.name,r.id])
				list.set_item_metadata(item,r)
		tally.text = "%d 条档案  ·  原作 0.98a-RC8" % list.item_count
		if list.item_count:
			list.select(0)
			present.call(0)
		else:
			present.call(-1)
			info.text = "没有匹配的舰型或装备记录。"
	pick.item_selected.connect(func(i: int): index_group = i; populate.call(query.text))
	query.text_changed.connect(populate)
	list.item_selected.connect(present)
	populate.call("")

func crises(body: Control) -> void:
	var world = game.world
	var current := Crises.summary(world)
	for signal_entry in current.signals:
		game.hud.hint(body, "%s 的矿带有异常回波。" % world.systems[signal_entry.system].name)
	var lead: Dictionary = world.ride()
	if not lead.is_empty() and lead.dock == 0 and not lead.layer:
		game.button(body, "侦察附近矿带", func(): done(Crises.act(world,"investigate"), "异常信号已定位。"))
		if world.systems[lead.system].get("wild",false) and not current.has("swarm"):
			game.button(body, "唤醒遗弃制造母舰", func(): done(Crises.act(world,"swarm"), "制造舰群已启动。"))
	if current.has("swarm"):
		game.hud.hint(body, "%s 制造舰群 · 已造 %d 艘" % [world.systems[current.swarm.system].name,current.swarm.built])
	if current.has("blockade"):
		var blockade: Dictionary = current.blockade
		game.hud.hint(body, "封锁目标 · " + world.ports[blockade.target].name)
		if world.active().loc == blockade.target and blockade.status in ["mobilizing","active"]:
			game.button(body, "支付谈判费用 ¢%d" % int(Crises.rules.blockade.fee),func(): done(Crises.act(world,"negotiate"), "封锁舰队已接受协议。"))
	elif world.active().loc and Crises.assets(world) >= int(Crises.rules.blockade.asset_threshold):
		game.button(body,"宣告对抗封锁舰队",func(): done(Crises.act(world,"challenge",world.active().loc),"封锁舰队正在集结。"))
	elif current.signals.is_empty() and not current.has("swarm"):
		game.hud.hint(body, "当前没有已知的危机。持续采矿会引来异常活动，边缘星系中也有沉睡的制造舰。")
