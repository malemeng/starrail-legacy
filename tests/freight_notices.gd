extends SceneTree

const Game = preload("res://game.tscn")
const World = preload("res://world.gd")
const Notice = preload("res://scripts/economy/freight_notice.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const OPTIONS := {"seed":"anchor","systems":16,"factions":4,"avatar":{"noble":false,"origin":0}}
var game
var checks := 0
var failures := 0

func check(value: bool, reason: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ",reason)
	return value

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	check_offers()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440,900)
	game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	await board_and_delivery()
	check_agent_orders()
	game.free()
	print("Public freight notices %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)

func check_agent_orders() -> void:
	var bridge := preload("res://agent_bridge.gd").new()
	bridge.game = game
	var world = game.world
	world.new_game(OPTIONS)
	var ship: Dictionary = world.ride()
	var source: Dictionary = world.ports[world.systems[2].ports[0]]
	world.berth(ship,source.id)
	var inquiry: Dictionary = bridge.dispatch("freight_offer",{})
	if not check(inquiry.ok and not inquiry.result.offer.is_empty(),"an agent reads the same public procurement notice"):
		return
	var offer: Dictionary = JSON.parse_string(JSON.stringify(inquiry.result.offer))
	check(inquiry.result.route.back()==inquiry.result.destination.system and inquiry.result.destination.port==offer.target,"a freight order identifies the receiving port and the actual connected systems to fly")
	var altered := offer.duplicate()
	altered.fee += 1
	check(not bridge.dispatch("accept_freight",{"offer":altered}).ok and not world.contracts.has(world.player),"a changed price cannot be signed through the agent")
	check(bridge.dispatch("accept_freight",{"offer":offer}).ok,"the JSON-encoded order can be signed through the agent")
	var order := {"ware":offer.ware,"amount":offer.quantity}
	var previous: int = world.active().wallet
	var quote: Dictionary = bridge.dispatch("market_quote",order)
	check(quote.ok and quote.result.units==offer.quantity and world.active().wallet==previous,"agent obtains an executable full-lot invoice without buying")
	var bought: Dictionary = bridge.dispatch("trade",order)
	check(bought.ok and previous-world.active().wallet==quote.result.total,"the signed lot costs the real invoice amount")
	check(not bridge.dispatch("deliver_freight",{}).ok,"agent cannot deliver at the issuing port")
	world.berth(ship,int(offer.target))
	previous = world.active().wallet
	var sale: Dictionary = bridge.dispatch("market_quote",{"ware":offer.ware,"amount":-offer.quantity})
	var paid: Dictionary = bridge.dispatch("deliver_freight",{})
	check(paid.ok and paid.result.paid==sale.result.total+offer.fee and world.active().wallet-previous==paid.result.paid,"agent receives the taxed sale and haulage once")
	check(not bridge.dispatch("deliver_freight",{}).ok,"the agent cannot replay a settled delivery")

func check_offers() -> void:
	var world := World.new()
	world.new_game(OPTIONS)
	var ship := world.ride()
	var source: Dictionary = world.ports[world.systems[2].ports[0]]
	world.berth(ship,source.id)
	var notice := Notice.offer(world,source)
	if not check(not notice.is_empty() and notice.jumps>0,"a commoner can find a cross-system job with their ordinary opening capital"):
		return
	var dest: Dictionary = world.ports[notice.target]
	var ware: int = notice.ware
	var units: int = notice.quantity
	# Keep one counterparty so a correctly rejected job cannot be replaced by another viable offer.
	for site: Dictionary in world.ports.values():
		site.imports = []
	dest.imports = [ware]
	source.exports = [ware]
	var stock: int = dest.stock[ware]
	dest.stock[ware] = int(Industry.stock_target(ware))
	check(Notice.offer(world,source).is_empty(),"a fully stocked buyer does not post a procurement order")
	dest.stock[ware] = stock
	dest.inbound[ship.id] = {"ware":ware,"qty":int(Industry.stock_target(ware))-stock}
	check(Notice.offer(world,source).is_empty(),"another carrier's incoming supply satisfies the shortage")
	dest.inbound.erase(ship.id)
	var supplier_stock: int = source.stock[ware]
	source.stock[ware] = units-1
	check(Notice.offer(world,source).is_empty(),"an undersupplied exporter cannot promise a full shipment")
	source.stock[ware] = supplier_stock
	ship.trade_rules = {"travel":[dest.system]}
	check(Notice.offer(world,source).is_empty(),"a forbidden destination is not an offered route")
	ship.erase("trade_rules")
	var fuel: int = source.stock[Industry.Ware.FUEL]
	ship.fuel = 0
	source.stock[Industry.Ware.FUEL] = 0
	check(Notice.offer(world,source).is_empty(),"a dry tank and dry pump rule out an interstellar delivery")
	var route: Dictionary = world.Economy.trip_plan(world,ship,source.system,source.pos,false,dest)
	var carried := ceili(float(route.fuel))
	ship.cargo[Industry.Ware.FUEL] = carried
	check(Notice.offer(world,source)==notice and ship.cargo[Industry.Ware.FUEL]==carried and ship.fuel==0,
		"a pilot carrying enough spare fuel can take a job even with a dry dock pump; preview consumes nothing")
	ship.cargo[Industry.Ware.FUEL] = 0
	source.stock[Industry.Ware.FUEL] = fuel
	var wallet: int = world.active().wallet
	world.active().wallet = Industry.lot_quote(source,ware,units,true,world.active().origin).y
	check(Notice.offer(world,source).is_empty(),"money spent on the cargo cannot also pay for the required refuel")
	world.active().wallet = wallet
	ship.fuel = 100
	ship.cargo[Industry.Ware.SCRAP] = world.cargo_free(ship)
	check(Notice.offer(world,source).is_empty(),"a full hold cannot promise to carry the advertised lot")
	ship.cargo[Industry.Ware.SCRAP] = 0
	var treasury: int = dest.treasury
	dest.treasury = Industry.lot_invoice(dest,ware,units,false).base+int(notice.fee)-1
	check(Notice.offer(world,source).is_empty() and not Notice.accept(world,notice) and world.contracts.is_empty(),
		"a displayed quote is rejected if the buyer can no longer cover goods, tax and haulage together")
	dest.treasury = treasury
	check(Notice.offer(world,source)==notice,"restoring capacity and solvency makes the real demand available again")

func find_button(container: Node, caption: String) -> Button:
	for button: Button in container.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and button.text.begins_with(caption):
			return button
	return null

func click(container: Node, caption: String) -> bool:
	var button := find_button(container,caption)
	if not check(button!=null and not button.disabled,"available button "+caption):
		return false
	var scroll := game.body.get_parent() as ScrollContainer
	if scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)
	await process_frame
	var point := button.get_global_rect().get_center()
	var area := scroll.get_global_rect() if scroll.is_ancestor_of(button) else Rect2(Vector2.ZERO,root.size)
	if not check(area.has_point(point),"button inside the visible viewport "+caption):
		return false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event,true)
	await process_frame
	return true

func visible_text(needle: String) -> bool:
	for label: Label in game.body.find_children("*","Label",true,false):
		if label.is_visible_in_tree() and needle in label.text:
			return true
	return false

func buy_wares(ware: int, units: int) -> bool:
	var label: Label = game.hud.market_rows[ware]
	if not await click(label.get_parent(),"交易"):
		return false
	var table = game.trade_table
	var field: LineEdit = table.find_child("TradeQuantity",true,false)
	field.grab_focus()
	field.select_all()
	for digit in str(units):
		for pressed in [true,false]:
			var key := InputEventKey.new()
			key.keycode = digit.unicode_at(0)
			key.unicode = key.keycode
			key.pressed = pressed
			root.push_input(key,true)
	await process_frame
	return await click(table,"确认买入") and await click(table,"关闭")

func settlement_state(world, dest: Dictionary) -> Dictionary:
	return {"wallet":world.active().wallet,"cargo":world.ride().cargo.duplicate(),"tax":world.factions[dest.tariff_flag].treasury,
		"stock":dest.stock.duplicate(),"funds":dest.treasury,"profit":dest.operating_profit,
		"orders":world.contracts.duplicate(true),"ledger":world.campaign.get("financial_days",{}).duplicate(true)}

func rejected_delivery(world, dest: Dictionary, reason: String) -> void:
	var before := settlement_state(world,dest)
	check(Notice.deliver(world,dest)==0 and settlement_state(world,dest)==before,reason)

func board_and_delivery() -> void:
	var world = game.world
	world.new_game(OPTIONS)
	var source: Dictionary = world.ports[world.systems[2].ports[0]]
	world.berth(world.ride(),source.id)
	var notice := Notice.offer(world,source)
	if not check(not notice.is_empty() and notice.jumps>0 and world.ports[notice.target].tariff_flag>=0,"natural source offers a taxable order in another system"):
		return
	var dest: Dictionary = world.ports[notice.target]
	var ware: int = notice.ware
	var units: int = notice.quantity
	game.run_bridge()
	game.set_physics_process(false)
	await process_frame
	if not await click(game.dock_view.stage,"货栈"):
		return
	check(visible_text(dest.name) and visible_text(world.WARES[ware]) and visible_text("航程 %d 跳" % notice.jumps)
			and visible_text("当前整批收购价 ¢%d" % notice.estimate) and visible_text("另付运费 ¢%d" % notice.fee),"board names the receiver, cargo, distance, expected market proceeds and separate fee")
	var stock: int = dest.stock[ware]
	dest.stock[ware] += 10
	if not check(Notice.offer(world,source)!=notice,"a change in the receiving market invalidates the displayed terms"):
		return
	if not await click(game.body,"接运输委托"):
		return
	check(not world.contracts.has(world.player) and "订单条件已变" in game.notice_text,"clicking an old price rejects the displayed offer and refreshes the board")
	dest.stock[ware] = stock
	game.refresh()
	await process_frame
	var before := settlement_state(world,dest)
	if not await click(game.body,"接运输委托"):
		return
	var accepted := settlement_state(world,dest)
	check(accepted.orders.get(world.player,{})==notice and find_button(game.body,"交货").disabled and not Notice.accept(world,notice),
		"signing registers a single job with delivery unavailable at the origin")
	before.orders = accepted.orders
	check(accepted==before,"signing has no cash, stock or accounting effect")
	rejected_delivery(world,dest,"remote delivery cannot debit the buyer or move cargo")
	var purchase: Dictionary = world.Economy.trade_invoice(world,source,ware,units)
	if not await buy_wares(ware,units):
		return
	check(world.active().wallet==before.wallet-purchase.total and world.ride().cargo[ware]==before.cargo[ware]+units,"ordinary cargo purchase fills the manifest at the actual source price")
	var save_path := OS.get_temp_dir().path_join("starrail-freight-%d.dat" % OS.get_process_id())
	var saved: bool = game.save_game(save_path,true)
	if saved:
		world.contracts.erase(world.player)
	var loaded: bool = saved and game.load_game(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	if not check(loaded and world.contracts.get(world.player,{})==notice and world.ride().cargo[ware]==before.cargo[ware]+units,"the signed manifest and bought cargo survive an actual save and reload"):
		return
	game.set_physics_process(false)
	dest = world.ports[notice.target]
	world.berth(world.ride(),dest.id)
	game.refresh()
	await process_frame
	if not await click(game.dock_view.stage,"货栈"):
		return
	var ship: Dictionary = world.ride()
	ship.cargo[ware] -= 1
	rejected_delivery(world,dest,"a missing unit leaves the entire invoice and the job intact")
	ship.cargo[ware] += 1
	var group: int = Industry.STORAGE[ware]
	var capacity: int = dest.storage_cap[group]
	dest.storage_cap[group] -= Industry.space(dest,ware) - (units-1)
	rejected_delivery(world,dest,"insufficient buyer storage cannot produce a partial sale")
	dest.storage_cap[group] = capacity
	dest.blockaded = true
	rejected_delivery(world,dest,"a newly blockaded receiving port cannot settle its outstanding job")
	dest.blockaded = false
	dest.stock[ware] += 20
	var seat: Dictionary = world.ports[world.systems[dest.system].ports[0]]
	seat.tax_rate = 0.20
	world.refresh_tariffs(dest.system)
	var invoice: Dictionary = world.Economy.trade_invoice(world,dest,ware,-units)
	var funds: int = dest.treasury
	dest.treasury = invoice.base+int(notice.fee)-1
	rejected_delivery(world,dest,"even one credit short of the full fee prevents all settlement")
	dest.treasury = funds
	check(invoice.units==units and invoice.total!=notice.estimate and invoice.tax==roundi(invoice.base*0.20) and invoice.tax>0,"arrival prices and current sovereign tax differ from the issuer's opening estimate")
	game.refresh()
	await process_frame
	before = settlement_state(world,dest)
	if not await click(game.body,"交货"):
		return
	var after := settlement_state(world,dest)
	var received: int = invoice.total+notice.fee
	check(after.wallet==before.wallet+received and after.profit==before.profit-invoice.base-notice.fee
			and after.funds==before.funds-invoice.base-notice.fee and after.tax==before.tax+invoice.tax,
		"receiving port funds goods and freight, the player receives net proceeds and the sovereign receives its exact tax")
	check(after.stock[ware]==before.stock[ware]+units and after.cargo[ware]==before.cargo[ware]-units
			and not after.orders.has(world.player) and ("¢%d" % received) in game.notice_text,
		"delivery moves the entire lot once and confirms the exact settlement to the player")
	var lines: Dictionary = after.ledger[world.day][world.player][ship.id].lines
	check(lines.get("货物销售",{}).get("income",0)==invoice.total and lines.get("货运委托",{}).get("income",0)==notice.fee,
		"the ship records market proceeds and transport fees in distinct financial-report entries")
	rejected_delivery(world,dest,"a settled order cannot be submitted for another payment")
	print("Cross-system freight %s -> %s: %d units, origin cost %d, expected goods %d, actual goods %d, tax %d, fee %d, player receives %d" %
			[source.name,dest.name,units,purchase.total,notice.estimate,invoice.total,invoice.tax,notice.fee,received])
