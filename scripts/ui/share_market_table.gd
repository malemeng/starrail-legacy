extends RefCounted

const Icons = preload("res://scripts/ui/cargo_icons.gd")
const Consent = preload("res://scripts/ui/consent_meter.gd")

var table
var game
var world
var view: String
var scope: String
var asset: int
var party: Variant
var buying: bool
var quantity: int
var price: int
var order_id: int
var offer_id: int
var reply := {}
var message := ""
var solicited_order := 0
var show_history := false

func _init(host, args: Dictionary) -> void:
	table = host
	game = host.game
	world = host.world
	view = args.get("view","market")
	scope = args.get("scope","company")
	asset = args.get("asset",0)
	party = args.get("party")
	buying = args.get("buying",true)
	quantity = args.get("quantity",1)
	price = args.get("price",0)
	order_id = args.get("order_id",0)
	offer_id = args.get("offer_id",0)

func release_quote() -> void:
	if solicited_order > 0:
		world.EquityOrders.cancel(world,solicited_order)
		solicited_order = 0

func market(note: String = "") -> void:
	view = "market"
	message = note
	reply = {}
	party = null
	order_id = 0
	quantity = 1
	price = 0
	table.paint()

func paint(layout: Control) -> void:
	var body = game.scroller(layout)
	body.add_theme_constant_override("separation",8)
	if table.buyer != world.player or not world.Equity.at_market(world):
		game.hud.hint(body,"停靠营业港后，可通过交易窗口查询行情并交割股份。")
		return
	var options := []
	var entries: Dictionary = world.firms if scope == "company" else world.ports
	for id: int in entries:
		if scope == "company" or world.StationEquity.listed(world,entries[id]):
			options.append(id)
	var toolbar = game.hbox(body)
	var types = game.choice(toolbar,["公司股票","空间站与行星港股票"],0 if scope == "company" else 1)
	types.disabled = view != "market"
	types.item_selected.connect(func(i):
		scope = "company" if i == 0 else "station"
		asset = 0
		market())
	if options.is_empty() or (view != "market" and asset not in options):
		game.hud.hint(body,"当前没有可交易的已登记证券。")
		if view != "market":
			game.button(body,"返回行情",func(): market())
		return
	if asset not in options:
		asset = options.front()
	var selector = game.choice(toolbar,options.map(func(id): return entries[id].name),options.find(asset))
	selector.name = "StockInstrument"
	selector.fit_to_longest_item = false
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.disabled = view != "market"
	selector.item_selected.connect(func(i): asset = options[i]; market())
	if view != "market" and table.deal_id == 0:
		game.button(toolbar,"返回行情",func(): market())
	var facts: Dictionary = world.Capital.overview(world,scope,asset)
	var quote: Dictionary = world.StockPrices.quote(world,scope,asset)
	var strip = game.hbox(body)
	Icons.show_icon(strip,"company_share" if scope == "company" else "station_share",asset,40)
	game.title(strip,entries[asset].name,22,game.INK)
	game.title(strip,"持有 %d 股　%.2f%%" % [facts.owned,100.0*facts.owned/maxi(1,facts.outstanding)],15,game.DIM)
	var tape := "最近成交　暂无成交" if quote.last <= 0 else "最近成交 ¢%s" % money(quote.last)
	if quote.last > 0 and quote.previous > 0:
		tape += "　较上笔 %+.2f%%" % quote.change_percent
	var price_line = game.title(body,"%s　·　每股净值 ¢%d" % [tape,quote.reference],17,game.GOLD,true)
	price_line.name = "StockQuote"
	if quote.last > 0:
		game.hud.hint(body,"上次成交 %s · %d 股　·　今日成交量 %d 股" % [world.date_label(quote.day),quote.last_volume,quote.volume])
	if not message.is_empty() and not (view == "negotiate" and message == reply.get("reason","")):
		game.title(body,message,15,game.GOLD,true)
	match view:
		"market": paint_market(body,facts)
		"post": paint_post(body,facts)
		"negotiate","order": paint_ticket(body,facts)
		"subscription": paint_subscription(body,facts)

func money(value: float) -> String:
	return str(int(value)) if is_equal_approx(value,roundf(value)) else "%.2f" % value

func paint_market(body: Control, facts: Dictionary) -> void:
	var actions = game.hbox(body)
	var tape: Dictionary = world.StockPrices.quote(world,scope,asset)
	var free: int = facts.owned - world.DiplomaticTrade.reserved_shares(world,scope,asset,world.player)
	game.button(actions,"挂牌出售",func():
		price = facts.unit_price
		quantity = 1
		message = ""
		view = "post"
		table.paint(),free > 0)
	game.button(actions,"联系股东洽谈",func():
		party = null
		buying = true
		price = facts.unit_price
		quantity = 1
		message = ""
		view = "negotiate"
		table.paint())
	if not facts.offer.is_empty():
		game.button(actions,"认购新股",func():
			offer_id = facts.offer.id
			price = facts.offer.unit_price
			quantity = 1
			message = ""
			view = "subscription"
			table.paint())
	if not tape.history.is_empty():
		game.button(actions,"收起价量记录" if show_history else "价量记录",func(): show_history = not show_history; table.paint())
		if show_history:
			var sessions: Array = tape.history.slice(maxi(0,tape.history.size()-8))
			sessions.reverse()
			for session: Dictionary in sessions:
				game.hud.hint(body,"%s　收盘 ¢%s　成交 %d 股" % [world.date_label(session.day),money(session.price),session.volume])
	var columns = game.hbox(body)
	columns.add_theme_constant_override("separation",16)
	world.EquityOrders.publish(world,scope,asset,facts.unit_price,world.EquityOrders.participants(world,scope,asset))
	for purchasing in [true,false]:
		var side = game.vbox(columns)
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.title(side,"市场卖单" if purchasing else "市场买单",18,game.INK)
		var orders: Array = world.EquityOrders.quotes(world,scope,asset,purchasing)
		orders.sort_custom(func(a,b):
			if a.unit_price == b.unit_price:
				return a.order_id < b.order_id
			return a.unit_price < b.unit_price if purchasing else a.unit_price > b.unit_price)
		if orders.is_empty():
			game.hud.hint(side,"暂无其他卖家挂牌。" if purchasing else "暂无买家出价。")
			continue
		var picker = game.choice(side,orders.map(func(row): return "¢%d/股 · %d 股 · %s" % [row.unit_price,row.quantity,row.name]))
		picker.fit_to_longest_item = false
		game.button(side,"查看卖单" if purchasing else "查看买单",func():
			var selected: Dictionary = orders[picker.selected]
			party = selected.person
			buying = purchasing
			order_id = selected.order_id
			price = selected.unit_price
			quantity = 1
			message = ""
			view = "order"
			table.paint())
	game.title(body,"我的挂牌",18,game.INK)
	var found := false
	for row: Dictionary in world.ShareExchange.listings(world):
		if row.seller != world.player or row.scope != scope or row.asset != asset:
			continue
		found = true
		var entry = game.hbox(body)
		var caption: String = "¢%d/股　已售 %d / %d 股　实收 ¢%d" % [row.unit_price,row.sold,row.quantity,row.proceeds]
		if row.last_buyer > 0:
			caption += "　最近买家 " + world.name_of(row.last_buyer)
		game.title(entry,caption,15,game.INK,true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if row.status == "open":
			game.button(entry,"撤回挂牌",func():
				market("剩余 %d 股已撤回。" % row.remaining if world.ShareExchange.cancel(world,row.id) else "这笔卖单已经结束。"))
		else:
			var labels := {"filled":"已售完","cancelled":"已撤回","expired":"已到期","void":"已失效"}
			game.title(entry,labels.get(row.status,"已结束"),14,game.DIM)
	if not found:
		game.hud.hint(body,"你尚未挂牌出售这只股票。")

func number_field(row: Control, caption: String, start: int, tag: String) -> LineEdit:
	game.title(row,caption,15,game.DIM)
	var field = game.field(row,str(start),9)
	field.name = tag
	field.custom_minimum_size.x = 78
	return field

func paint_post(body: Control, facts: Dictionary) -> void:
	game.title(body,"挂牌出售",19,game.INK)
	var free: int = facts.owned-world.DiplomaticTrade.reserved_shares(world,scope,asset,world.player)
	game.hud.hint(body,"可挂牌 %d 股。挂牌后锁定这些股份；买方接受要价并成交后，货款才会到账。" % free)
	var fields = game.hbox(body)
	var qty := number_field(fields,"出售股数",quantity,"StockQuantity")
	var strike := number_field(fields,"每股要价 ¢",price,"StockPrice")
	var summary = game.title(body,"",16,game.INK,true)
	var action = game.button(body,"确认挂牌",func():
		var result: Dictionary = world.ShareExchange.post(world,scope,asset,quantity,price)
		market(result.reason))
	var update := func(_value: String = ""):
		quantity = qty.text.to_int() if qty.text.is_valid_int() else 0
		price = strike.text.to_int() if strike.text.is_valid_int() else 0
		action.disabled = quantity <= 0 or quantity > free or price < 1
		summary.text = "%d 股，占在外股份 %.2f%%　·　全部售出可收 ¢%d" % [quantity,100.0*quantity/maxi(1,facts.outstanding),quantity*price]
	qty.text_changed.connect(update)
	strike.text_changed.connect(update)
	update.call()

func paint_ticket(body: Control, facts: Dictionary) -> void:
	var locked: bool = table.deal_id > 0
	var fixed_order := view == "order"
	if not fixed_order:
		var contacts: Array = world.EquityOrders.contacts(world,scope,asset)
		if contacts.is_empty():
			game.hud.hint(body,"当前没有能签字的交易对手。")
			return
		var index := contacts.find_custom(func(row): return row.person == party)
		if index < 0:
			index = 0
			party = contacts.front().person
		var account = game.choice(body,contacts.map(func(row): return "%s · 签字人 %s" % [row.name,world.name_of(row.decider)]),index)
		account.name = "StockPartner"
		account.disabled = locked
		account.item_selected.connect(func(i):
			party = contacts[i].person
			reply = {}
			message = ""
			table.paint())
		var side = game.choice(body,["我向对方买股","我向对方卖股"],0 if buying else 1)
		side.name = "TradeSide"
		side.disabled = locked
		side.item_selected.connect(func(i): buying = i == 0; reply = {}; message = ""; table.paint())
	else:
		game.title(body,"买入挂牌股份" if buying else "向挂牌买家卖出",19,game.INK)
	if price <= 0: price = facts.unit_price
	var fields = game.hbox(body)
	var qty := number_field(fields,"股数",quantity,"StockQuantity")
	var strike := number_field(fields,"每股 ¢",price,"StockPrice")
	qty.editable = not locked
	strike.editable = not fixed_order and not locked
	var summary = game.title(body,"",16,game.GOLD,true)
	var meter := Consent.new()
	body.add_child(meter)
	meter.setup(game,int(world.EquityOrders.TERMS.consent_threshold))
	var actions = game.hbox(body)
	var submit = game.button(actions,"确认交割" if locked else ("按挂牌价签约" if fixed_order else "提出交易"),func(): submit_ticket())
	submit.name = "TradeSubmit"
	if locked:
		game.button(actions,"放弃这次交易",func():
			world.DiplomaticTrade.cancel(world,table.deal_id)
			table.deal_id = 0
			release_quote()
			market("已撤回，托管资产已返还。"))
	var update := func(_text: String = ""):
		quantity = qty.text.to_int() if qty.text.is_valid_int() else 0
		price = strike.text.to_int() if strike.text.is_valid_int() else 0
		var legal: Dictionary = world.TradeLaw.check_transfer(world,scope,asset,party,buying,quantity)
		var preview: Dictionary
		if locked:
			preview = {"score":100,"label":"已签字","accepted":true,"reason":"确认后按已签股数和单价交割。"}
		elif fixed_order:
			preview = world.DiplomaticTrade.quote_order(world,order_id,quantity)
		else:
			preview = world.EquityOrders.preview(world,scope,asset,party,quantity,buying,price)
		meter.present(preview)
		summary.text = "%d 股 × ¢%d = ¢%d　·　占当前在外股份 %.2f%%\n%s　%s" % [quantity,price,quantity*price,100.0*quantity/maxi(1,facts.outstanding),legal.name,legal.reason]
		if not locked:
			submit.disabled = not preview.get("accepted",false) if fixed_order else (quantity <= 0 or price <= 0)
	qty.text_changed.connect(update)
	strike.text_changed.connect(update)
	update.call()

func submit_ticket() -> void:
	if table.deal_id > 0:
		var result: Dictionary = world.DiplomaticTrade.confirm(world,table.deal_id)
		table.deal_id = 0
		release_quote()
		game.update_header()
		market("已按 ¢%d/股交割 %d 股。" % [price,quantity] if result.accepted else result.reason)
		return
	if view == "negotiate":
		reply = world.EquityOrders.propose(world,scope,asset,party,quantity,buying,price)
		if not reply.accepted:
			message = reply.reason
			table.paint()
			return
		order_id = reply.order_id
		if reply.get("solicited",false): solicited_order = order_id
		price = reply.unit_price
	var pledge: Dictionary = world.DiplomaticTrade.sign_order(world,order_id,quantity,price)
	if not pledge.accepted:
		release_quote()
		message = pledge.reason
	else:
		table.deal_id = pledge.deal_id
		message = "签字人 %s　·　%s 到期" % [world.name_of(pledge.decider),world.date_label(pledge.expires)]
	table.paint()

func paint_subscription(body: Control, facts: Dictionary) -> void:
	var offer: Dictionary = facts.offer
	if offer.is_empty() or offer.id != offer_id or offer.unit_price != price:
		game.hud.hint(body,"这次发行已经结束或条款已变更。")
		return
	game.title(body,"公开发行认购",19,game.INK)
	game.hud.hint(body,"%s签署　·　每股 ¢%d　·　可认购 %d 股　·　%s 截止" % [world.name_of(offer.signer),price,offer.remaining,world.date_label(offer.expires)])
	var row = game.hbox(body)
	var qty := number_field(row,"认购股数",quantity,"StockQuantity")
	var total = game.title(body,"",16,game.GOLD,true)
	var submit = game.button(body,"确认认购",func():
		var receipt: Dictionary = world.Capital.subscribe(world,scope,asset,quantity,price,offer_id)
		game.update_header()
		market(receipt.reason))
	submit.name = "TradeSubmit"
	var update := func(_text: String = ""):
		quantity = qty.text.to_int() if qty.text.is_valid_int() else 0
		var law: Dictionary = world.TradeLaw.check(world,"subscribe",scope,asset,world.player,0,quantity)
		total.text = "认购款 ¢%d　·　认购后占 %.2f%%　·　%s" % [quantity*price,100.0*(facts.owned+quantity)/maxi(1,facts.outstanding+quantity),law.reason]
		submit.disabled = not law.allowed or quantity > offer.remaining or quantity*price > world.active().wallet
	qty.text_changed.connect(update)
	update.call()
