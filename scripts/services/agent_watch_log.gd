extends RefCounted

const SILENT := ["observe","watch_frame","quit"]
const LABELS := {
	"assault_station":"进攻空间站",
	"disembark":"离舰驻站","board_liner":"购票登船","disembark_liner":"客船下客","assign_passenger_liner":"开通客运班线",
	"assign_contractor":"派遣工程舰","debug_ship":"查看舰船","hire_captain":"招募船长","assign_ship":"指派船长","wait":"等待","cheat":"执行作弊指令",
	"new_game":"登记起航","dock":"靠港","depart":"解除系泊","jump":"跃迁","waypoint":"设定航点",
	"freight_offer":"查看运输委托","accept_freight":"接运输委托","deliver_freight":"交付货物","market_quote":"查询整批货价",
	"accept_first_job":"接下首航委托","deliver_first_job":"交付首航委托","claim_return_bonus":"领取返航津贴",
	"sensor_ping":"主动扫描","mine_or_salvage":"采矿或打捞","refuel":"补充燃料","repair":"维修船体",
	"system":"启动舰载系统","vent":"排散幅能","order":"指挥僚舰","group":"切换武器组","auto_battle":"结算遭遇战",
	"ship_quote":"查看造船报价","buy_ship":"购买舰船","buyout_charter":"买断租船","pilot_ship":"接掌舰船",
	"refit_slot":"更换武器","refit_quote":"核算改装","refit_preset":"安装配装","refit_offers":"浏览武器","refit_wing":"调整舰载机","refit_tuning":"调整配点",
	"trade_partners":"查看交易对象","trade_catalog":"查看可交易资产","preview_deal":"预览条款","propose_deal":"提交条款","confirm_deal":"确认交割","cancel_deal":"撤回条款",
	"financial_report":"查看收支","station_finance":"查看空间站账户","stock_quote":"查看股价","equity":"查看股权","trade_equity":"交易股份",
	"set_operating_area":"设置作业范围","assign_escort":"指派护航","assign_role":"分配舰队职责","set_default_behavior":"设置舰队任务",
	"hire_builder":"雇佣工程舰","deploy_station":"部署空间站","donate_materials":"交付建材","found_planet_port":"建设行星港",
	"marriage_terms":"查看婚配意愿","diplomacy_action":"开展人物交涉","event_choice":"回应事件","choose_successor":"选择继承人",
	"enact_securities_law":"颁布证券法","my_share_listings":"查看挂牌","cancel_share_listing":"撤销挂牌","quote_share_order":"核算股单","sign_share_order":"签署股单","post_share_listing":"挂牌股份",
	"share_capital":"查看股本","securities_law":"查询证券法","request_share_permit":"申请持股许可","issue_shares":"发行新股","solicit_issue":"提出融资","subscribe_shares":"认购新股","withdraw_issue":"撤回发行",
	"equity_catalog":"查找可投资产","equity_person":"查看股东","cancel_equity_inquiry":"撤回询价","equity_inquiry":"股份询价","equity_preview":"预览持股条款","board_support":"争取股东支持","board_vote":"投董事长票",
	"company_dividend_policy":"调整企业分红","pay_company_dividend":"派发企业股息","transfer_station_funds":"划拨站点资金","set_dividend_policy":"调整站点分红","pay_dividend":"派发站点股息",
	"station_overview":"查看站务","cancel_builder":"解除工程合同","station_expand":"扩建站点","order_hull":"下单建造舰船","queue_dock":"安排舰船停靠","queue_fleet_order":"下达舰队指令","cancel_fleet_order":"撤销舰队指令",
	"supply_construction":"调拨工程物料","set_method":"选择建造工艺","set_blacklist":"设置贸易限制","ultimatum":"发出最后通牒","resolve_scheme":"结算计谋","set_focus":"切换人生重心","train":"训练角色",
	"crisis":"处置危机","project":"发起项目","civic":"处理政务","journey":"组织远征","boarding":"开始登舰"
}
const STOPS := {"arrival":"抵达航点","encounter":"发现敌情","event":"有事件待处理","attention":"需要决策","target_lost":"已失去目标","tick_limit":"本段指令结束"}
const REASONS := {"not_docked":"需要停靠港口","not_in_flight":"需要先离港","cannot_jump":"尚未抵达跃迁点",
	"trade_rejected":"当前无法成交","speed_restricted":"当前航行状态限制加速","unknown_target":"目标不在可见范围",
	"freight_offer_changed":"港口报价已变","freight_unavailable":"当前无可接委托","delivery_unavailable":"尚未满足交货条件",
	"unknown_action":"没有这项操作","invalid_intent":"目标说明无效","aim_required":"缺少瞄准目标"}

var game
var panel: PanelContainer
var state := {"intent":"","target":"","action":"","result":"","history":[],"progress":-1.0,"progress_text":""}
var stated_target := ""
var starting_wallet := 0
var initial_distance := 0.0

func _init(session, view: PanelContainer) -> void:
	game = session
	panel = view
	panel.bind_game(game)
	panel.present(state)

func balance() -> int:
	return int(game.world.active().get("wallet",0))

func distance_left() -> float:
	var ship: Dictionary = game.world.ride()
	if ship.is_empty() or not game.waypoint_live:
		return 0.0
	var position: Vector2 = ship.galpos if game.galaxy else ship.pos
	return position.distance_to(game.waypoint)

func begin(action: String, args: Dictionary) -> void:
	if action in SILENT or action == "set_intent":
		return
	starting_wallet = balance()
	if game.playing and not game.world.succession and game.world.ride().get("dock",0) > 0:
		var room := ""
		match action:
			"trade","market_quote","freight_offer","accept_freight","deliver_freight": room = "market"
			"ship_quote","buy_ship","buyout_charter": room = "yard"
		if not room.is_empty() and (game.tab != "港口" or game.dock_view.mode != room):
			game.tab = "港口"
			game.dock_view.mode = room
			game.refresh()
	initial_distance = distance_left() if action == "step" else 0.0
	state.target = game.waypoint_label if action == "step" and game.waypoint_live else stated_target
	state.result = ""
	state.progress = -1.0
	state.progress_text = ""
	state.action = LABELS.get(action,action)
	if action == "step":
		if args.get("fire",false) == true:
			state.action = "瞄准并开火"
		elif args.get("shield",false) == true:
			state.action = "维持护盾"
		else:
			state.action = "沿航线飞行" if game.waypoint_live else ("港内待命" if game.world.ride().get("dock",0) else "驾驶舰船")
	elif action == "trade":
		var ware: Variant = args.get("ware")
		var amount: Variant = args.get("amount")
		state.action = "交易货物"
		if typeof(ware) in [TYPE_INT,TYPE_FLOAT] and typeof(amount) in [TYPE_INT,TYPE_FLOAT] and int(ware) in range(game.world.WARES.size()):
			state.action = "%s%s" % ["买入" if amount > 0 else "卖出",game.world.WARES[int(ware)]]
	panel.present(state)

func progress(processed: int, ticks: int) -> void:
	if initial_distance > 0.0:
		var left := distance_left()
		state.progress = clampf(1.0-left/initial_distance,0.0,1.0)
		state.progress_text = "距航点 %.0f" % left
	else:
		state.progress = float(processed) / maxi(1,ticks)
		state.progress_text = "本段已推进 %.1f 秒" % (float(processed) / Engine.physics_ticks_per_second)
	panel.present(state)

func finish(action: String, args: Dictionary, response: Dictionary) -> void:
	if action in SILENT:
		return
	if action == "set_intent" and response.get("ok",false):
		state.intent = args.text.strip_edges()
		stated_target = str(args.get("target","")).strip_edges()
		state.target = stated_target
		panel.present(state)
		return
	if action == "new_game" and response.get("ok",false):
		state.history.clear()
	if action == "set_intent":
		state.action = "设置本次意图"
	state.result = receipt(action,response)
	if game.playing and not game.world.succession and response.get("ok",false) and is_instance_valid(game.header):
		game.update_header()
	state.progress = -1.0
	state.progress_text = ""
	var items: Array = state.history
	var entry := {"action":state.action,"result":state.result}
	if items.is_empty() or items.back() != entry:
		items.append(entry)
		if items.size() > 6:
			items.pop_front()
	panel.present(state)

func receipt(action: String, response: Dictionary) -> String:
	if not response.get("ok",false):
		var detail := str(response.get("detail","")).strip_edges()
		var error := str(response.get("error",""))
		return "未执行 · %s" % (detail if not detail.is_empty() and error != "unknown_action" else str(REASONS.get(error,error)))
	var result: Dictionary = response.get("result",{})
	var world = game.world
	var ship: Dictionary = world.ride()
	match action:
		"assault_station":
			return str(result.message)
		"board_liner":
			return "票款 ¢%d · 前往%s · %s" % [result.fare, port_label(result.dest), ship_label(result.ship)]
		"disembark","disembark_liner":
			return "已从%s下船 · %s" % [ship_label(result.ship), port_label(result.port)]
		"assign_passenger_liner":
			var stops := PackedStringArray()
			for port in result.route:
				stops.append(port_label(port))
			return "%s · %s" % [ship_label(result.ship), " → ".join(stops)]
		"assign_contractor":
			return "%s · 母港%s · 已开始承接工程" % [ship_label(result.ship), port_label(result.home_port)]
		"debug_ship":
			return "%s · %s" % [ship_label(result.ship), result.status]
		"hire_captain":
			return "%s · 船长%s" % [ship_label(result.ship), world.name_of(result.captain)]
		"wait":
			if result.get("stopped","") == "disembarked":
				return "%s已在%s下客" % [ship_label(result.ship), port_label(result.port)]
			return "已推进 %d 天" % result.days_elapsed
		"cheat":
			match result.kind:
				"credits": return "信用点余额 ¢%d" % result.credits
				"fuel": return "燃料已加至 %d" % result.fuel
				"repair": return "已修复 %d 艘舰船" % result.repaired
				"trust": return "阵营信任变为 %d" % result.score
				"opinion": return "人物好感变为 %d" % result.opinion
				"tick": return "已推进至第 %d 天" % result.day
				"reveal": return "已揭示 %d 个星系" % result.systems
		"step":
			return STOPS.get(result.get("stopped",""),"本段指令结束")
		"trade":
			return "成交 %d 单位 · %s¢%d" % [absi(int(result.moved)),"收入 " if result.moved < 0 else "支出 ",absi(balance()-starting_wallet)]
		"dock","new_game":
			return "已停靠%s" % world.ports.get(ship.get("dock",0),{}).get("name","港口")
		"depart":
			return "已离港"
		"jump":
			return "进入超空间" if game.galaxy else "进入%s" % world.systems[ship.system].name
		"waypoint":
			return game.waypoint_label
		"deliver_freight","deliver_first_job","claim_return_bonus":
			return "到账 ¢%d" % (balance()-starting_wallet)
		"market_quote":
			return "%d 单位 · 整批 ¢%d" % [result.units,result.total]
		"ship_quote":
			return "整舰报价 ¢%d" % result.price
		"buy_ship":
			return "购入舰船 #%d · 支出 ¢%d" % [int(result.ship),absi(balance()-starting_wallet)]
		"freight_offer":
			return "暂无可接委托" if result.offer.is_empty() else "%s · %d 跳" % [result.destination.name,result.offer.jumps]
		"sensor_ping":
			return "扫描脉冲已发出"
		"accept_first_job","accept_freight":
			return "已接单"
	if result.has("reason") and not str(result.reason).is_empty():
		return str(result.reason)
	if result.get("accepted",true) == false or result.get("ok",true) == false or result.get("cancelled",true) == false:
		return "请求未获接受"
	return "已收到回执"

func port_label(id: int) -> String:
	return str(game.world.ports.get(id, {}).get("name", "#%d" % id))

func ship_label(id: int) -> String:
	var vessel: Dictionary = game.world.ships.get(id, {})
	return "#%d %s" % [id, game.world.HULLS[vessel.kind]] if not vessel.is_empty() else "#%d" % id
