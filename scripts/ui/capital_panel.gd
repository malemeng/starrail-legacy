extends RefCounted

static func paint(game, body: Node, page, scope: String, id: int) -> void:
	var world = game.world
	var facts: Dictionary = world.Capital.overview(world,scope,id)
	var law: Dictionary = world.TradeLaw.jurisdiction(world,scope,id)
	if facts.is_empty() or law.is_empty():
		return
	game.hud.heading(body,"股本登记")
	game.title(body,"已发行 %d 股　·　在外 %d 股" % [facts.issued,facts.outstanding],17,game.GOLD)
	game.hud.hint(body,"库存股 %d 股　·　每股面值 ¢%d　·　每股净值 ¢%d" % [facts.treasury_units,facts.par_value,facts.unit_price])
	game.hud.hint(body,"实缴资本 ¢%d　·　其中股本溢价 ¢%d" % [facts.paid_in_capital,facts.share_premium])
	game.hud.hint(body,"在外普通股每股一票，按股分红。库存股停票、停息。")
	for holder: Dictionary in facts.holders:
		var party: int = holder.get("party",0)
		var holder_name: String
		if holder.get("public",false):
			holder_name = world.flag_name(holder.flag)
		elif party < 0:
			holder_name = world.firms[-party].name
		else:
			holder_name = world.name_of(party)
		game.hud.hint(body,"%s　%d 股　%.2f%%" % [holder_name,holder.units,holder.percent])
	game.hud.heading(body,"适用法律")
	var state: String = world.flag_name(law.flag) if law.flag >= 0 else "无主星系"
	game.title(body,"%s · %s" % [state,law.name],16,game.INK,true)
	game.hud.hint(body,"%s　%s · 单次增发限已发行股本的 %d%%" % ["公司注册地" if scope == "company" else "站点所在星系",world.systems[law.system].name,law.issue_limit])
	if law.flag >= 0:
		game.hud.hint(body,"与交战方停止股权过户。外部持股上限 %d%%。" % law.foreign_limit)
		if world.Society.player_governs(world,law.flag):
			var bills: Array = world.TradeLaw.Rules.data.codes.keys().filter(func(key): return key != "frontier" and key != law.code)
			var council = game.hbox(body)
			var select = game.choice(council,bills.map(func(key): return world.TradeLaw.Rules.data.codes[key].name))
			var description = game.title(body,"",13,game.DIM,true)
			var details := func(i: int):
				var bill: Dictionary = world.TradeLaw.Rules.data.codes[bills[i]]
				var permit := "外资免许可" if bill.foreign_review == 0 else "外资达到 %d%% 须许可" % bill.foreign_review
				description.text = "拟议条款　%s，上限 %d%%，单次增发限 %d%%。" % [permit,bill.foreign_limit,bill.issue_limit]
			select.item_selected.connect(details)
			details.call(0)
			game.button(council,"颁布新法",func():
				page.capital_message = world.TradeLaw.enact(world,law.flag,bills[select.selected]).reason
				game.refresh())
	if law.foreign_review > 0:
		game.hud.hint(body,"外部持股达到 %d%% 须由 %s 批准。" % [law.foreign_review,world.name_of(law.ruler)])
		if world.active().flag != law.flag:
			var permit: Dictionary = world.TradeLaw.active_permit(world,scope,id,world.player,law)
			if permit.is_empty():
				game.button(body,"申请持股许可",func():
					page.capital_message = world.TradeLaw.request_permit(world,scope,id).reason
					game.refresh(),world.Equity.at_market(world))
			else:
				game.hud.hint(body,"你的许可有效至 %s。" % world.date_label(permit.expires))
	game.hud.heading(body,"新股认购")
	if not page.capital_message.is_empty():
		game.title(body,page.capital_message,15,game.GOLD,true)
	var at_port: bool = world.Equity.at_market(world)
	if not facts.offer.is_empty():
		var offer: Dictionary = facts.offer
		game.hud.hint(body,"%s已授权 %d 股，每股 ¢%d。剩余 %d 股，%s 截止。" % [world.name_of(offer.signer),offer.quantity,offer.unit_price,offer.remaining,world.date_label(offer.expires)])
		var row = game.hbox(body)
		game.title(row,"认购股数",14,game.DIM)
		var units = game.field(row,"1",9)
		var preview = game.title(body,"",14,game.DIM,true)
		var buy = game.button(row,"认购新股",func():
			game.open_equity_subscription(scope,id,offer.id,offer.unit_price,units.text.to_int()))
		var quote := func(_text: String = ""):
			var n: int = units.text.to_int() if units.text.is_valid_int() else 0
			var allowed: Dictionary = world.TradeLaw.check(world,"subscribe",scope,id,world.player,0,n)
			buy.disabled = not at_port or not allowed.allowed or n <= 0 or n > offer.remaining or n*offer.unit_price > world.active().wallet
			preview.text = "需付 ¢%d · 认购后持股 %.2f%%　%s" % [n*offer.unit_price,100.0*(facts.owned+n)/maxi(1,facts.outstanding+n),allowed.reason]
		units.text_changed.connect(quote)
		quote.call()
		if facts.can_issue:
			game.button(body,"撤回剩余发行",func():
				page.capital_message = "剩余发行已撤回。" if world.Capital.cancel(world,scope,id) else "当前无权撤回。"
				game.refresh(),at_port)
		return
	if not facts.can_issue and not facts.can_solicit:
		game.hud.hint(body,"目前没有公开认购。"+("发行人运营资金充足。" if facts.capital_needed == 0 else "发行需取得多数表决权授权。"))
		return
	var cap: int = facts.max_quantity
	game.hud.hint(body,"本次最多 %d 股，发行底价 ¢%d。认购款进入发行人的运营账户，原股东持股比例随之下降。" % [cap,facts.minimum_price])
	var fields = game.hbox(body)
	game.title(fields,"股数",14,game.DIM)
	var units = game.field(fields,"1",9)
	game.title(fields,"每股 ¢",14,game.DIM)
	var price = game.field(fields,str(facts.minimum_price),9)
	var issue = game.button(body,"授权发行新股" if facts.can_issue else "向发行人提议增发",func():
		var decision: Dictionary = world.Capital.authorize(world,scope,id,units.text.to_int(),price.text.to_int()) if facts.can_issue else world.Capital.solicit(world,scope,id,units.text.to_int(),price.text.to_int())
		page.capital_message = decision.reason
		game.refresh())
	var estimate = game.title(body,"",13,game.DIM,true)
	var recalculate := func(_text: String = ""):
		var n: int = units.text.to_int() if units.text.is_valid_int() else 0
		var strike: int = price.text.to_int() if price.text.is_valid_int() else 0
		issue.disabled = not at_port or n <= 0 or n > cap or strike < facts.minimum_price
		if n <= 0 or n > cap or strike < facts.minimum_price:
			estimate.text = "股数须在 1 至 %d 之间，单价至少 ¢%d。" % [cap,facts.minimum_price]
		else:
			estimate.text = "全部认购将筹得 ¢%d，新增股份占增发后在外股数的 %.2f%%。" % [n*strike,100.0*n/(facts.outstanding+n)]
	units.text_changed.connect(recalculate)
	price.text_changed.connect(recalculate)
	recalculate.call()
