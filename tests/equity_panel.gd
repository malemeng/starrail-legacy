extends SceneTree

const Game = preload("res://game.tscn")
var game
var checks := 0
var failures := 0
var final_scores := {}

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
	return ok

func find_button(container: Node, caption: String) -> Button:
	for button: Button in container.find_children("*","Button",true,false):
		if button.text.begins_with(caption):
			return button
	return null

func click(button: Button, allow_disabled: bool = false) -> bool:
	if not check(is_instance_valid(button) and (allow_disabled or not button.disabled),"action exists and is available in its expected state"):
		return false
	var scroller := game.body.get_parent() as ScrollContainer
	await process_frame
	if scroller.is_ancestor_of(button):
		scroller.ensure_control_visible(button)
	await process_frame
	var bounds := button.get_global_rect()
	var point := bounds.get_center()
	var clip := scroller.get_global_rect() if scroller.is_ancestor_of(button) else Rect2(Vector2.ZERO,Vector2(root.size))
	if not check(clip.has_point(point) and bounds.position.x >= clip.position.x - 1.0 and bounds.end.x <= clip.end.x + 1.0,"the complete button width fits in the sidebar"):
		return false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		root.push_input(event,true)
	await process_frame
	return true

func active_surface() -> Node:
	return game.trade_table if is_instance_valid(game.trade_table) else game.body

func holder_action(holder: int, caption: String) -> Button:
	for box: HBoxContainer in game.body.find_children("*","HBoxContainer",true,false):
		if box.get_meta("shareholder",-1) == holder:
			return find_button(box,caption)
	return null

func close_trade() -> bool:
	return await click(find_button(game.trade_table,"关闭"))

func select_option(needle: String) -> bool:
	for picker: OptionButton in active_surface().find_children("*","OptionButton",true,false):
		for index in picker.item_count:
			if needle in picker.get_item_text(index):
				if picker.selected != index:
					picker.select(index)
					picker.item_selected.emit(index)
					await process_frame
				return true
	return check(false,"there is a selectable account for "+needle)

func fill_proposal(amount: int, limit: int) -> bool:
	var fields: Array = active_surface().find_children("*","LineEdit",true,false)
	if not check(fields.size() == 2,"the negotiation form contains quantity and limit-price fields"):
		return false
	for i in fields.size():
		var field := fields[i] as LineEdit
		var digits := str([amount,limit][i])
		field.grab_focus()
		field.select_all()
		for digit in digits:
			for down in [true,false]:
				var key := InputEventKey.new()
				key.keycode = digit.unicode_at(0)
				key.unicode = digit.unicode_at(0)
				key.pressed = down
				root.push_input(key,true)
		await process_frame
		if not check(is_instance_valid(field) and field.text == digits and field.has_focus(),"normal per-character input retains focus and the complete numeric value"):
			return false
	return true

func propose(amount: int, limit: int) -> bool:
	var world = game.world
	var order_book: Dictionary = world.campaign.get("equity_orders",{}).duplicate(true)
	var wallet: int = world.active().wallet
	var shares: Dictionary = world.active().shares.duplicate(true)
	if not await fill_proposal(amount,limit):
		return false
	var view = game.trade_table.stocks
	var meter := game.trade_table.find_child("ConsentMeter",true,false) as ProgressBar
	var estimate: Dictionary = world.EquityOrders.preview(world,view.scope,view.asset,view.party,amount,view.buying,limit)
	if not check(meter != null and int(meter.value)==estimate.score and contains_text("同意度　%d / 100　%s" % [estimate.score,estimate.label]) and contains_text(estimate.reason) and not estimate.factors.is_empty() and contains_text(estimate.factors[0]),"typing updates the actual consent bar, agreement state, rationale and factors before submission"):
		return false
	if not check(wallet==world.active().wallet and shares==world.active().shares and order_book==world.campaign.get("equity_orders",{}),"editing the form does not create a reservation, change any order, transfer money or move shares"):
		return false
	if not await click(find_button(game.trade_table,"提出交易")):
		return false
	final_scores[str(amount)+":"+str(limit)] = estimate.score
	return check(estimate.accepted==view.reply.get("accepted",false) and estimate.accepted==(int(estimate.score)>=int(world.EquityOrders.TERMS.consent_threshold)),"the submitted terms and preview agree on which side of the signing threshold the offer falls")

func contains_text(needle: String) -> bool:
	for label: Label in active_surface().find_children("*","Label",true,false):
		if needle in label.text:
			return true
	return false

func local_dossier(person: String) -> Button:
	for card: PanelContainer in game.body.find_children("*","PanelContainer",true,false):
		for label: Label in card.find_children("*","Label",true,false):
			if label.text.begins_with(person+" · "):
				return find_button(card,"档案")
	return null

func give_gift(world, signer: Dictionary, wait_for_next: bool = true) -> bool:
	if wait_for_next:
		var day: int = world.day
		world.tick(30)
		if not check(world.day==day+30,"the simulation actually advances a month between gifts"):
			return false
		if signer.loc != world.active().loc:
			if not check(world.ports.has(signer.loc) and world.berth(world.ride(),signer.loc),"the customer meets the travelling shareholder at their actual current port"):
				return false
		game.refresh()
		await process_frame
	var wallet: int = world.active().wallet
	var theirs: int = signer.wallet
	var gift := find_button(game.body,"赠礼 ¢")
	if not is_instance_valid(gift) or gift.disabled:
		printerr("Gift unavailable on day %d, actor at %d, signer %s #%d at %d, signer alive %s, attitude %d, gift_wait %d, wallet %d" % [world.day,world.active().loc,signer.name,signer.id,signer.loc,signer.alive,world.Politics.opinion(world,signer.id,world.player),world.Politics.gift_wait(world,signer.id),world.active().wallet])
	if not await click(gift):
		return false
	return check(world.active().wallet==wallet-35 and signer.wallet==theirs+35,"one accepted in-person gift settles on both wallets")

func balances(world, company: int, chief: int, site: Dictionary) -> Dictionary:
	return {"player_wallet":world.active().wallet,"chief_wallet":world.people[chief].wallet,"chief_escrow":world.EquityOrders.escrow_for(world,chief),
		"company_treasury":world.firms[company].treasury,"station_treasury":site.treasury,
		"player_shares":world.active().shares.duplicate(),"chief_shares":world.people[chief].shares.duplicate(),
		"station_shares":world.StationEquity.cap_table(world,site).duplicate(true),
		"attention":world.attention}

func capture(file: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args():
		return
	var scroller := game.body.get_parent() as ScrollContainer
	scroller.scroll_vertical = 0
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var viewport := root.get_texture().get_image()
	var bounds := Rect2i(Vector2i.ZERO,viewport.get_size())
	if not is_instance_valid(game.trade_table):
		bounds = Rect2i(scroller.get_global_rect().grow(5)).intersection(bounds)
		bounds.size.y = mini(bounds.size.y,ceili(game.body.get_child(-1).get_global_rect().end.y)+10-bounds.position.y)
	check(viewport.get_region(bounds).save_png(OS.get_temp_dir().path_join(file)) == OK,"capture the settled "+file+" from the game viewport")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440,900)
	game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	var world = game.world
	world.new_game({"seed":"enterprise-register","systems":12,"factions":3,"overrides":[{"regime":2},{"regime":4}],"avatar":{"name":"柳棠","house":"青岬"}})
	world.active().wallet = 1000000
	var company: int = world.firms.keys().front()
	var firm: Dictionary = world.firms[company]
	var chief: int = firm.director
	var signer: Dictionary = world.people[chief]
	signer.opinions[world.player] = -100
	signer.trait = 3
	signer.wallet = 20
	signer.personality.boldness = 32
	world.active().stats.diplomacy = signer.stats.diplomacy
	firm.treasury = 0
	check(world.berth(world.ride(),signer.loc),"begin at an operating port where the director can meet the player")
	game.run_bridge()
	game.set_physics_process(false)
	await process_frame
	if not await click(find_button(game.tabs,"人物")) or not await click(local_dossier(signer.name)):
		finish()
		return
	check(game.hud.dossier.person_id==chief and contains_text(firm.name + "董事长"),"a real local person opens the same registered company director and share accounts")
	if not await click(find_button(game.body,"返回人物列表")):
		finish()
		return
	if not await click(find_button(game.tabs,"资产")) or not await click(find_button(game.body,"股权与分红")):
		finish()
		return
	var overview: Dictionary = world.Equity.overview(world,company)
	var site: Dictionary = {}
	for holding in overview.holdings:
		site = world.ports[holding.port]
		if not site.scan:
			break
	if not check(game.hud.equity.target_id == company and not site.is_empty() and not site.scan,"a real unscanned subsidiary is disclosed in the registry"):
		finish()
		return
	if not await click(find_button(game.body,"进入股票市场")):
		finish()
		return
	check(game.trade_table.stock_page and game.trade_table.stocks.asset==company and contains_text("市场卖单") and contains_text("市场买单"),"the registry opens both sides of the exchange inside the regular trade window")
	if not await close_trade() or not await click(holder_action(chief,"人物档案")):
		finish()
		return
	check(game.hud.dossier.person_id == chief and contains_text(firm.name + "董事长"),"the registered asset points to the named director's actual dossier")
	if not await select_option(firm.name+" · 私人") or not await click(find_button(game.body,"洽谈股份")):
		finish()
		return
	var before := balances(world,company,chief,site)
	var limit: int = overview.unit_price*2
	if not await propose(7,limit):
		finish()
		return
	check(game.trade_table.stocks.reply.get("decider",0) == chief and not game.trade_table.stocks.reply.get("accepted",true) and contains_text("好感") and not contains_text("到期。确认后") and find_button(game.trade_table,"确认交割")==null,"a hostile director can refuse even an offer at twice the valuation")
	check(balances(world,company,chief,site) == before,"refusal moves neither personal wallets, treasuries, shares nor attention")
	await capture("starrail-equity-refusal.png")
	if not await close_trade():
		finish()
		return
	if not await give_gift(world,signer,false):
		finish()
		return
	var opinion: int = world.Politics.opinion(world,chief,world.player)
	var gift_accounts := balances(world,company,chief,site)
	if not await click(find_button(game.body,"赠礼 ¢"),true):
		finish()
		return
	check(world.Politics.opinion(world,chief,world.player)==opinion and balances(world,company,chief,site)==gift_accounts,"an immediate second gift to the same person neither charges nor raises opinion")
	for i in 7:
		if not await give_gift(world,signer):
			finish()
			return
	check(world.Politics.opinion(world,chief,world.player)>20,"gifts spaced over seven months can establish a working relationship")
	limit = world.Equity.overview(world,company).unit_price*2
	if not await select_option(firm.name+" · 私人") or not await click(find_button(game.body,"洽谈股份")):
		finish()
		return
	before = balances(world,company,chief,site)
	if not await propose(7,1):
		finish()
		return
	check(not game.trade_table.stocks.reply.get("accepted",true) and game.trade_table.stocks.reply.get("decider",0) == chief and find_button(game.trade_table,"确认交割")==null and balances(world,company,chief,site)==before,"even a friendly signer declines a one-credit bid with both sides' ledgers intact")
	if not await propose(7,limit):
		finish()
		return
	var quote: Dictionary = game.trade_table.stocks.reply
	check(final_scores["7:1"] < final_scores["7:"+str(limit)],"the actual price entry raises the displayed willingness from the refused range into the agreement range")
	if not check(quote.get("accepted",false) and quote.get("decider",0)==chief and quote.get("order_id",0)>0 and quote.get("expires",0)>world.day and game.trade_table.deal_id>0 and world.active().wallet==before.player_wallet-7*int(quote.unit_price) and signer.wallet==before.chief_wallet and world.active().shares==before.player_shares and signer.shares==before.chief_shares,"the shareholder signs a dated quote, the buyer's cash is held in escrow, and no one receives the other's assets until confirmation"):
		finish()
		return
	var unit: int = quote.unit_price
	await capture("starrail-equity-consent.png")
	if not await click(find_button(game.trade_table,"确认交割")):
		finish()
		return
	check(world.active().shares.get(company,0) == 7 and world.active().wallet == before.player_wallet-7*unit and signer.wallet == before.chief_wallet+7*unit,"accepting seven shares settles exactly the mutually agreed amount to the person")
	if not await close_trade() or not await click(find_button(game.body,"返回资产")):
		finish()
		return
	var vote := find_button(game.body,"投董事长票")
	if not check(vote != null,"a voting form appears after the first share is settled"):
		finish()
		return
	var ballot: OptionButton = vote.get_parent().get_child(0)
	for index in ballot.item_count:
		if ballot.get_item_text(index) == world.name_of(chief):
			ballot.select(index)
			break
	await click(vote)
	check(world.firms[company].ballots.get(world.player,0) == chief,"the chosen director receives the real shareholder ballot")
	if not await click(find_button(game.body,site.name+"　公司")):
		finish()
		return
	if not check(game.hud.equity.mode == "station" and game.hud.equity.target_id == site.id,"the disclosed branch opens the requested station"):
		finish()
		return
	if not await click(find_button(game.body,"联系股东洽谈")) or not await select_option(firm.name+" · 签字人"):
		finish()
		return
	before = balances(world,company,chief,site)
	if not await propose(5,world.StationEquity.unit_price(site)*2):
		finish()
		return
	quote = game.trade_table.stocks.reply
	if not check(quote.get("accepted",false) and quote.get("decider",0)==chief and quote.get("person",0)==-company,"a legal person supplies a named human representative for subsidiary shares") or not await click(find_button(game.trade_table,"确认交割")):
		finish()
		return
	unit = quote.unit_price
	if not await close_trade():
		finish()
		return
	var table: Dictionary = world.StationEquity.cap_table(world,site)
	var retained: int = before.station_shares.company_units-5
	var parent_outstanding := int(firm.issued)-int(firm.treasury_shares)
	var site_outstanding := int(table.total)-int(table.treasury_units)
	var indirect: float = 100.0*world.active().shares[company]/parent_outstanding*table.company_units/site_outstanding
	check(table.people.get(world.player,0) == 5 and table.company_units == retained and world.active().wallet == before.player_wallet-5*unit and firm.treasury == before.company_treasury+5*unit and signer.wallet+world.EquityOrders.escrow_for(world,chief) == before.chief_wallet+before.chief_escrow,"the parent receives proceeds for five subsidiary shares and the director's personal assets including published bid escrow stay separate")
	check(contains_text("公司 7 股") and contains_text("%.2f%%" % indirect),"direct shares and the exact indirect percentage through the real issued and circulating capital are displayed together")
	await capture("starrail-equity.png")
	if not await click(find_button(game.body,world.firms[company].name+"　持有本站")):
		finish()
		return
	check(game.hud.equity.mode == "company" and game.hud.equity.target_id == company and find_button(game.body,site.name+"　公司 %d 股 · 你直接 5 股" % retained) != null,"the parent company page shows the same settled branch register")
	await capture("starrail-equity-board.png")
	var chief_votes: int = world.Equity.supporters(world,company).get(chief,0)
	var election := balances(world,company,chief,site)
	if not await click(holder_action(chief,"争取董事会支持")):
		finish()
		return
	check(contains_text("把票留给自己") and world.firms[company].director==chief and balances(world,company,chief,site)==election,"an incumbent can decline to support the player's board candidacy")
	if not await click(holder_action(chief,"人物档案")):
		finish()
		return
	for i in 3:
		if not await give_gift(world,signer):
			finish()
			return
	if not await click(find_button(game.body,"返回资产")):
		finish()
		return
	election = balances(world,company,chief,site)
	if not await click(holder_action(chief,"争取董事会支持")):
		finish()
		return
	check(world.firms[company].director == world.player and world.firms[company].ballots[chief] == world.player and balances(world,company,chief,site)==election,"the shareholder can later back the player and retain his shares, dividends and wallet")
	if not await click(find_button(game.body,"股本、发行与法律")):
		finish()
		return
	var issue: Dictionary = world.Capital.overview(world,"company",company)
	var law: Dictionary = world.TradeLaw.jurisdiction(world,"company",company)
	check(contains_text("已发行 %d 股" % issue.issued) and contains_text("在外 %d 股" % issue.outstanding) and contains_text(law.name),"the actual capital page shows the registration, voting base, and the law for this issuer's jurisdiction")
	if not await fill_proposal(2,issue.minimum_price) or not await click(find_button(game.body,"授权发行新股")):
		finish()
		return
	var offer: Dictionary = world.Capital.overview(world,"company",company).offer
	if not check(offer.get("remaining",0)==2 and firm.issued==issue.issued and world.active().shares.get(company,0)==issue.owned,"authorizing an offer does not create any share until an investor subscribes"):
		finish()
		return
	await capture("starrail-capital-register.png")
	var investor_cash: int = world.active().wallet
	var issuer_cash: int = firm.treasury
	if not await click(find_button(game.body,"认购新股")):
		finish()
		return
	check(game.trade_table.stocks.view=="subscription" and game.trade_table.stocks.offer_id==offer.id and firm.issued==issue.issued and firm.treasury==issuer_cash and world.active().wallet==investor_cash,"opening the original subscription offer leaves the issue and both accounts intact")
	if not await click(find_button(game.trade_table,"确认认购")) or not await close_trade():
		finish()
		return
	check(firm.issued==issue.issued+1 and world.active().shares.get(company,0)==issue.owned+1 and firm.treasury==issuer_cash+offer.unit_price and world.active().wallet==investor_cash-offer.unit_price,"a lawful subscription issues one new share in return for cash paid into the issuer's treasury")
	if not await click(find_button(game.body,"撤回剩余发行")):
		finish()
		return
	check(world.Capital.overview(world,"company",company).offer.is_empty() and firm.issued==issue.issued+1,"withdrawing the unused authorization preserves subscribed capital")
	if not await click(find_button(game.body,"返回股东名册")) or not await click(find_button(game.body,"进入股票市场")) or not await click(find_button(game.trade_table,"挂牌出售")):
		finish()
		return
	var prior_shares: int = world.active().shares[company]
	var prior_wallet: int = world.active().wallet
	if not await fill_proposal(2,99999) or not await click(find_button(game.trade_table,"确认挂牌")):
		finish()
		return
	var listing: Dictionary = world.ShareExchange.listings(world).front()
	check(listing.remaining==2 and listing.unit_price==99999 and listing.sold==0 and world.active().shares[company]==prior_shares and world.active().wallet==prior_wallet and world.ShareExchange.reserved(world,"company",company,world.player)==2,"listing two shares at a chosen limit reserves only those shares and pays no proceeds")
	if not await click(find_button(game.trade_table,"撤回挂牌")):
		finish()
		return
	check(world.ShareExchange.reserved(world,"company",company,world.player)==0 and world.active().shares[company]==prior_shares and world.active().wallet==prior_wallet,"cancelling an unfilled public ask releases the entire reservation with balances intact")
	if not await click(find_button(game.trade_table,"查看买单")):
		finish()
		return
	var original_id: int = game.trade_table.stocks.order_id
	var signed_price: int = game.trade_table.stocks.price
	var locked_price := game.trade_table.find_child("StockPrice",true,false) as LineEdit
	check(original_id>0 and not locked_price.editable and int(locked_price.text)==signed_price,"opening a named buyer's published bid locks the original limit and order number")
	if not await click(find_button(game.trade_table,"按挂牌价签约")):
		finish()
		return
	check(game.trade_table.deal_id>0 and world.active().shares[company]==prior_shares and world.active().wallet==prior_wallet,"signing the order reserves one share pending settlement without paying the seller")
	if not await click(find_button(game.trade_table,"放弃这次交易")):
		finish()
		return
	check(game.trade_table.deal_id==0 and world.DiplomaticTrade.reserved_shares(world,"company",company,world.player)==0 and world.active().shares[company]==prior_shares and world.active().wallet==prior_wallet,"abandoning the ticket releases the reserved share without consuming the buyer's standing bid")
	if not await click(find_button(game.trade_table,"挂牌出售")) or not await fill_proposal(2,1) or not await click(find_button(game.trade_table,"确认挂牌")):
		finish()
		return
	await capture("starrail-equity-listing.png")
	if not await close_trade():
		finish()
		return
	world.tick(1)
	if not await click(find_button(game.body,"进入股票市场")):
		finish()
		return
	listing = world.ShareExchange.listings(world).front()
	check(listing.sold>0 and listing.last_buyer>0 and listing.proceeds>=listing.sold and world.active().shares[company]==prior_shares-listing.sold and contains_text("最近买家") and contains_text("最近成交"),"a named independent buyer matches a public ask and the settled price and proceeds appear on the exchange")
	await capture("starrail-equity-settled.png")
	print("Secondary UI positions: company 7/%d, station 5/%d plus %.4f%% indirect, prior board votes %d; subscription increased issued capital to %d" % [parent_outstanding,site_outstanding,indirect,chief_votes,firm.issued])
	finish()

func finish() -> void:
	game.free()
	print("Equity panel %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
