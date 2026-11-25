extends ColorRect

const ConsentMeter = preload("res://scripts/ui/consent_meter.gd")
const CargoIcons = preload("res://scripts/ui/cargo_icons.gd")
const Securities = preload("res://scripts/ui/share_market_table.gd")
const Portrait = preload("res://portrait.gd")
const TYPES := {"station":"空间站与行星港","person":"人物","company":"公司","faction":"势力"}

var game
var world
var partners := []
var kind := "station"
var partner_id := -1
var black := false
var catalog := {}
var give := []
var want := []
var quick_ware := -1
var quick_buy := true
var quick_count := 1
var quick_max := 0
var deal_id := 0
var message := ""
var remembered := {}
var buyer: int
var contents: VBoxContainer
var status: Label
var totals: Label
var meter
var submit: Button
var stocks
var stock_page := false

func open(screen, initial_kind: String, id: int, illicit: bool, ware: int, security: Dictionary = {}) -> void:
	game = screen
	world = game.world
	buyer = world.player
	name = "TradeTable"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color("0b121ae8")
	mouse_filter = Control.MOUSE_FILTER_STOP
	kind = initial_kind
	partner_id = id
	black = illicit
	quick_ware = ware
	stocks = Securities.new(self,security)
	stock_page = not security.is_empty()
	partners = world.DiplomaticTrade.contacts(world)
	read_catalog()
	if quick_ware >= 0 and amount_of(catalog.get("want",[]),"ware",quick_ware) == 0:
		quick_buy = amount_of(catalog.get("give",[]),"ware",quick_ware) == 0
	paint()

func close() -> void:
	if deal_id > 0:
		world.DiplomaticTrade.cancel(world,deal_id)
	if stock_page:
		stocks.release_quote()
	game.trade_table = null
	get_parent().remove_child(self)
	game.refresh()
	queue_free()

func read_catalog() -> void:
	catalog = world.DiplomaticTrade.catalog(world,kind,partner_id,black)

func matching_partner() -> Dictionary:
	for item: Dictionary in partners:
		if item.kind == kind and item.id == partner_id and bool(item.get("black",false)) == black:
			return item
	return {}

func amount_of(rows: Array, asset: String, id: int) -> int:
	for row: Dictionary in rows:
		if row.kind == asset and row.id == id:
			return int(row.quantity)
	return 0

func draft_key() -> String:
	return "%s/%d/%s" % [kind,partner_id,black]

func switch_to(entry: Dictionary) -> void:
	remembered[draft_key()] = {"give":give,"want":want,"quick":quick_ware,"buy":quick_buy,"count":quick_count}
	kind = entry.kind
	partner_id = entry.id
	black = entry.get("black",false)
	var draft: Dictionary = remembered.get(draft_key(),{})
	give = draft.get("give",[])
	want = draft.get("want",[])
	quick_ware = draft.get("quick",-1)
	quick_buy = draft.get("buy",true)
	quick_count = draft.get("count",1)
	message = ""
	read_catalog()
	paint()

func paint() -> void:
	game.clear(self)
	var panel := PanelContainer.new()
	add_child(panel)
	var compact := not stock_page and quick_ware >= 0 and get_viewport_rect().size.x >= 950
	panel.anchor_left = 0.22 if compact else 0.065
	panel.anchor_right = 1.0-panel.anchor_left
	panel.anchor_top = 0.145 if compact else 0.065
	panel.anchor_bottom = 1.0-panel.anchor_top
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14222e")
	style.border_color = Color("486072")
	style.set_border_width_all(1)
	for edge in [SIDE_TOP,SIDE_BOTTOM,SIDE_LEFT,SIDE_RIGHT]:
		style.set_content_margin(edge,20)
	panel.add_theme_stylebox_override("panel",style)
	var layout = game.vbox(panel)
	layout.add_theme_constant_override("separation",10)
	var top = game.hbox(layout)
	var heading = game.title(top,"交易",26,game.GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.button(top,"商品与协商",func(): stock_page = false; paint(),stock_page and deal_id == 0)
	game.button(top,"股票市场",func(): stock_page = true; paint(),not stock_page and deal_id == 0)
	game.button(top,"关闭" if game.mobile_play else "关闭　Esc",close)
	if stock_page:
		stocks.paint(layout)
		return
	var group = game.hbox(layout)
	var kinds := []
	for category: String in TYPES:
		if category == kind or partners.any(func(entry): return entry.kind == category):
			kinds.append(category)
	var types = game.choice(group,kinds.map(func(key): return TYPES[key]),kinds.find(kind))
	types.disabled = deal_id > 0
	types.item_selected.connect(func(index):
		for entry: Dictionary in partners:
			if entry.kind == kinds[index]:
				switch_to(entry)
				break)
	var qualified := partners.filter(func(p): return p.kind == kind)
	var selected := qualified.find_custom(func(p): return p.id == partner_id and bool(p.get("black",false)) == black)
	var counts := {}
	for entry: Dictionary in qualified:
		counts[entry.name] = int(counts.get(entry.name,0)) + 1
	var names := []
	for entry: Dictionary in qualified:
		var label := str(entry.name)
		if entry.kind == "person" and counts[entry.name] > 1:
			for firm: Dictionary in world.firms.values():
				if firm.director == entry.id:
					label += " · " + firm.name + "董事长"
					break
			label += " #%d" % entry.id
		if entry.get("black",false):
			label += " · 黑市"
		names.append(label)
	if selected < 0:
		names.push_front("当前对象无法洽谈")
	var counterparty = game.choice(group,names,maxi(selected,0))
	for i in qualified.size():
		counterparty.set_item_metadata(i + (1 if selected < 0 else 0),{"id":qualified[i].id,"black":qualified[i].get("black",false)})
	counterparty.name = "TradePartner"
	counterparty.fit_to_longest_item = false
	counterparty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counterparty.disabled = deal_id > 0 or qualified.is_empty()
	counterparty.item_selected.connect(func(index):
		var next: int = index-1 if selected < 0 else index
		if next >= 0: switch_to(qualified[next]))
	contents = game.scroller(layout)
	contents.add_theme_constant_override("separation",8)
	if selected < 0 or buyer != world.player:
		game.hud.hint(contents,"当前无法联系有权签字的对手。可以在上方选择其他账户。")
		return
	var party: Dictionary = qualified[selected]
	var rep: Dictionary = world.people.get(party.representative,{})
	if not rep.is_empty():
		var bio = game.hbox(contents)
		var face := Portrait.new()
		face.custom_minimum_size = Vector2(50,56)
		face.look = Portrait.for_actor(world,rep)
		bio.add_child(face)
		var bio_text = game.vbox(bio)
		game.title(bio_text,"%s　·　%s" % [rep.name,"私人账户" if kind == "person" else party.name],17,game.INK)
		game.hud.hint(bio_text,"%s　对你好感 %+d%s" % [world.TRAITS[rep.trait],world.Politics.opinion(world,rep.id,buyer),"　·　黑市" if black else ""])
	if quick_ware >= 0 and kind == "station":
		quick_form()
	elif deal_id > 0:
		signed_form()
	else:
		combination_form()
	totals = game.title(layout,"",16,game.GOLD,true)
	totals.name = "TradeTotals"
	meter = ConsentMeter.new()
	layout.add_child(meter)
	meter.setup(game,int(world.EquityOrders.TERMS.consent_threshold))
	status = game.title(layout,message,14,game.INK,true)
	status.visible = not message.is_empty()
	var actions = game.hbox(layout)
	actions.alignment = BoxContainer.ALIGNMENT_END
	if deal_id > 0:
		game.button(actions,"撤回提案",func():
			world.DiplomaticTrade.cancel(world,deal_id)
			deal_id = 0
			message = "已撤回，可以继续调整。"
			paint())
	submit = game.button(actions,"确认交割" if deal_id > 0 else ("确认买入" if quick_buy else "确认卖出") if quick_ware >= 0 else "提出交易",commit)
	submit.custom_minimum_size.x = 155
	for state in ["normal","hover","pressed"]:
		var accent := StyleBoxFlat.new()
		accent.bg_color = Color("21645c") if state == "normal" else Color("357c70") if state == "hover" else Color("194d48")
		accent.set_corner_radius_all(4)
		accent.set_content_margin(SIDE_TOP,6)
		accent.set_content_margin(SIDE_BOTTOM,6)
		submit.add_theme_stylebox_override(state,accent)
	submit.name = "TradeSubmit"
	refresh_preview()

func quick_form() -> void:
	var site: Dictionary = world.ports[partner_id]
	var row = game.hbox(contents)
	CargoIcons.show_icon(row,"ware",quick_ware,48)
	game.title(row,world.WARES[quick_ware],21,game.INK)
	var side = game.choice(row,["买入","卖出"],0 if quick_buy else 1)
	side.name = "TradeSide"
	side.item_selected.connect(func(index):
		quick_buy = index == 0
		quick_count = 1
		message = ""
		paint())
	var ship: Dictionary = world.ride()
	var capacity: int = world.HULL_CARGO[ship.kind] if not ship.is_empty() else 0
	quick_max = world.Economy.trade_quote(world,site,quick_ware,capacity if quick_buy else -capacity,black).x
	var available := amount_of(catalog.get("want" if quick_buy else "give",[]),"ware",quick_ware)
	var budget := amount_of(catalog.get("give" if quick_buy else "want",[]),"cash",0)
	quick_max = world.Economy.lot_quote(site,quick_ware,mini(quick_max,available),quick_buy,world.active().origin,black,budget).x
	game.hud.hint(contents,"首件 ¢%d　·　当前最多 %d 单位" % [world.Economy.price(site,quick_ware,quick_buy,world.active().origin,black),quick_max])
	var controls = game.hbox(contents)
	game.title(controls,"数量",15,game.DIM)
	var qty = game.field(controls,str(quick_count),8)
	qty.name = "TradeQuantity"
	qty.text_changed.connect(func(value):
		quick_count = value.to_int() if value.is_valid_int() else 0
		message = ""
		refresh_preview())
	game.button(controls,"最大",func():
		quick_count = quick_max
		qty.text = str(quick_count)
		refresh_preview(),quick_max > 0)
	game.button(controls,"组合交易",func():
		quick_ware = -1
		message = ""
		paint())

func line(asset: String, id: int, qty: int) -> Dictionary:
	return {"kind":asset,"id":id,"quantity":qty}

func combination_form() -> void:
	var columns = game.hbox(contents)
	columns.add_theme_constant_override("separation",18)
	edit_side(columns,true)
	edit_side(columns,false)
	game.button(contents,"补齐差价",balance_cash)

func edit_side(parent: Node, giving: bool) -> void:
	var col = game.vbox(parent)
	col.name = "GiveColumn" if giving else "WantColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.title(col,"我给出" if giving else "我想要",19,Color("f1bd78") if giving else Color("83d7cb"))
	var assets: Array = catalog.get("give" if giving else "want",[])
	var items: Array = give if giving else want
	var addition = game.hbox(col)
	var names := assets.map(func(asset): return "%s（可用 %d）" % [asset.name,asset.quantity])
	var pick = game.choice(addition,names if not names.is_empty() else ["暂无可选资产"])
	pick.name = "GiveAsset" if giving else "WantAsset"
	pick.add_theme_constant_override("icon_max_width",24)
	for i in assets.size():
		pick.set_item_icon(i,CargoIcons.texture(assets[i].kind,assets[i].id))
	pick.fit_to_longest_item = false
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.button(addition,"添加",func():
		var asset: Dictionary = assets[pick.selected]
		for item: Dictionary in items:
			if item.kind == asset.kind and item.id == asset.id:
				item.quantity += 1
				message = ""
				paint()
				return
		items.append(line(asset.kind,asset.id,1))
		message = ""
		paint(),not assets.is_empty())
	for item: Dictionary in items:
		var row = game.hbox(col)
		CargoIcons.show_icon(row,item.kind,item.id,28)
		var title = game.title(row,asset_name(assets,item),15,game.INK,true)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var qty = game.field(row,str(item.quantity),9)
		qty.size_flags_horizontal = Control.SIZE_SHRINK_END
		qty.custom_minimum_size.x = 80
		var ownership: Label
		if item.kind in ["company_share","station_share"]:
			ownership = game.title(col,share_description(item,giving),13,game.DIM,true)
		qty.text_changed.connect(func(value):
			item.quantity = value.to_int() if value.is_valid_int() else 0
			message = ""
			if is_instance_valid(ownership):
				ownership.text = share_description(item,giving)
			refresh_preview())
		game.button(row,"移除",func():
			items.erase(item)
			message = ""
			paint())

func asset_name(assets: Array, item: Dictionary) -> String:
	for asset: Dictionary in assets:
		if asset.kind == item.kind and asset.id == item.id:
			return asset.name
	return "信用点" if item.kind == "cash" else "已不可用"

func share_description(item: Dictionary, giving: bool) -> String:
	var scope := "company" if item.kind == "company_share" else "station"
	var units: int
	if scope == "company":
		var firm: Dictionary = world.firms[item.id]
		units = firm.issued - firm.treasury_shares
	else:
		var table: Dictionary = world.StationEquity.cap_table(world,world.ports[item.id])
		units = table.total - table.get("treasury_units",0)
	var party: int = world.DiplomaticTrade.share_party(world,scope,item.id,kind,partner_id)
	var legal: Dictionary = world.TradeLaw.check_transfer(world,scope,item.id,party,not giving,item.quantity)
	return "占当前在外股份 %.2f%% · %s　%s" % [100.0*item.quantity/maxi(1,units),legal.name,legal.reason]

func signed_form() -> void:
	game.title(contents,"对方已签，请核对交割清单",20,game.GOLD)
	for giving in [true,false]:
		var assets: Array = catalog.get("give" if giving else "want",[])
		game.title(contents,"我给出" if giving else "我想要",16,game.DIM)
		for item: Dictionary in (give if giving else want):
			var row = game.hbox(contents)
			CargoIcons.show_icon(row,item.kind,item.id,28)
			game.title(row,"%s × %d" % [asset_name(assets,item),item.quantity],16,game.INK,true)
			if item.kind in ["company_share","station_share"]:
				game.hud.hint(contents,share_description(item,giving))

func tax_summary(invoice: Dictionary) -> String:
	if int(invoice.get("goods_given",0)) + int(invoice.get("goods_received",0)) == 0:
		return ""
	if black or int(invoice.get("tax_flag",-1)) < 0:
		return "\n商品税 ¢0　·　%s" % ("黑市交易" if black else "无主星系免税")
	return "\n商品税 ¢%d　·　缴入%s国库" % [invoice.tax,invoice.tax_name]

func balance_cash() -> void:
	var our_goods := give.filter(func(x): return x.kind != "cash")
	var their_goods := want.filter(func(x): return x.kind != "cash")
	var appraisal: Dictionary = world.DiplomaticTrade.preview(world,kind,partner_id,our_goods,their_goods,black)
	var difference := int(appraisal.get("cash_delta",int(appraisal.want_value)-int(appraisal.give_value)))
	if difference > 0:
		our_goods.append(line("cash",0,difference))
	elif difference < 0:
		their_goods.append(line("cash",0,-difference))
	give = our_goods
	want = their_goods
	message = ""
	paint()

func refresh_preview() -> void:
	if not is_instance_valid(meter) or not is_instance_valid(submit):
		return
	if deal_id > 0:
		meter.present({"score":100,"label":"已签字","accepted":true,"reason":"按上面列出的数量和款项交割。"})
		totals.text = "等待你的确认" + tax_summary(world.campaign.get("diplomatic_deal",{}))
		return
	if quick_ware >= 0:
		give = []
		want = []
		if quick_count < 1 or quick_count > quick_max:
			var reason := "请输入 1 至 %d 之间的数量。" % quick_max if quick_max > 0 else "当前可交易数量为零，请检查库存、货舱和资金。"
			meter.present({"score":0,"accepted":false,"label":"无法成交","reason":reason})
			var firm_id := int(catalog.get("market_firm",0))
			totals.text = "公司可用余额 ¢%d" % world.firms[firm_id].treasury if firm_id != 0 else "可用余额 ¢%d" % world.active().wallet
			submit.disabled = true
			return
		var quote: Vector2i = world.Economy.lot_quote(world.ports[partner_id],quick_ware,quick_count,quick_buy,world.active().origin,black)
		var cash := line("cash",0,quote.y)
		var goods := line("ware",quick_ware,quick_count)
		give = [cash if quick_buy else goods]
		want = [goods if quick_buy else cash]
	var preview: Dictionary = world.DiplomaticTrade.preview(world,kind,partner_id,give,want,black)
	meter.present({"accepted":preview.accepted,"score":preview.score,"label":preview.get("label","愿意签字" if preview.accepted else "尚未同意"),"reason":preview.reason,"factors":preview.get("factors",[])})
	var firm := int(preview.get("client_firm",0))
	var funds: int = world.firms[firm].treasury if firm != 0 else world.active().wallet
	var balance: int = funds + amount_of(want,"cash",0) - amount_of(give,"cash",0)
	if quick_ware >= 0:
		totals.text = "%s ¢%d　·　成交后余额 ¢%d" % ["共付" if quick_buy else "共收",amount_of(give if quick_buy else want,"cash",0),balance]
	else:
		totals.text = "给出估值 ¢%d　·　索取估值 ¢%d　·　成交后余额 ¢%d" % [preview.give_value,preview.want_value,balance]
	totals.text += tax_summary(preview)
	if firm != 0:
		totals.text += "　·　" + str(world.firms[firm].name) + "账户"
	status.visible = not message.is_empty()
	submit.disabled = not preview.accepted

func commit() -> void:
	if deal_id == 0:
		var offer: Dictionary = world.DiplomaticTrade.propose(world,kind,partner_id,give,want,black)
		message = offer.reason
		if not offer.accepted:
			paint()
			return
		deal_id = offer.deal_id
		if quick_ware < 0:
			paint()
			return
	var result: Dictionary = world.DiplomaticTrade.confirm(world,deal_id)
	message = result.reason
	if not result.accepted:
		world.DiplomaticTrade.cancel(world,deal_id)
	deal_id = 0
	if result.accepted:
		give = []
		want = []
		quick_count = 1
		if quick_ware >= 0:
			message = "已成交。%s" % result.reason
	read_catalog()
	game.update_header()
	paint()
