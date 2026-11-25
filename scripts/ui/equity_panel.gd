extends RefCounted

const Relations = preload("res://scripts/campaign/shareholder_relations.gd")
const CapitalView = preload("res://scripts/ui/capital_panel.gd")

var mode := ""
var target_id := 0
var inspecting_capital := false
var capital_message := ""
var board_message := ""

func open(game, kind: String, id: int = 0) -> void:
	game.tab = "资产"
	game.hud.report_open = false
	game.hud.diagnostics_open = false
	mode = kind
	target_id = id
	inspecting_capital = false
	capital_message = ""
	board_message = ""
	game.refresh()

func paint(game, body: Node) -> void:
	var world = game.world
	game.hud.heading(body,"股权与分红")
	var nav = game.hbox(body)
	game.button(nav,"公司股",func(): open(game,"company"),mode != "company")
	game.button(nav,"单站股",func(): open(game,"station"),mode != "station")
	game.button(nav,"返回资产",func(): mode = ""; game.refresh())
	var company := mode == "company"
	var choices := []
	var catalog: Dictionary = world.firms if company else world.ports
	for id: int in catalog:
		if not company:
			var site: Dictionary = catalog[id]
			if not world.StationEquity.listed(world,site):
				continue
		choices.append(id)
	if choices.is_empty():
		game.hud.hint(body,"当前没有可查看的公司。" if company else "尚未发现有可登记股份的空间站或行星港。")
		return
	if target_id not in choices:
		target_id = choices.front()
	var select = game.choice(body,choices.map(func(id): return catalog[id].name),choices.find(target_id))
	select.item_selected.connect(func(index): target_id = choices[index]; capital_message = ""; board_message = ""; game.refresh())
	var id := target_id
	if inspecting_capital:
		game.button(body,"返回股东名册",func(): open(game,mode,id))
		CapitalView.paint(game,body,self,mode,id)
		return
	var at_market: bool = world.Equity.at_market(world)
	game.button(body,"进入股票市场",func(): game.open_share_market(mode,id),at_market)
	game.button(body,"联系股东洽谈",func(): game.open_equity_trade(mode,id),at_market)
	if not at_market:
		game.hud.hint(body,"停靠营业港后可进入股票市场、联络股东。")
	game.button(body,"股本、发行与法律",func(): inspecting_capital = true; capital_message = ""; game.refresh())
	if company:
		var info: Dictionary = world.Equity.overview(world,id)
		var firm: Dictionary = world.firms[id]
		var group: String = world.flag_name(info.flag) if info.flag >= 0 else "独立公司"
		game.hud.hint(body,"%s　董事长 %s　总部 %s" % [group,world.name_of(info.director),world.ports[info.hq].name])
		game.title(body,"你的公司股　%d 股 · 占表决权 %.2f%%" % [info.owned,100.0*info.owned/maxi(1,info.issued-info.treasury_shares)],17,game.GOLD)
		game.hud.hint(body,"参考估值 ¢%d/股　公司资金 ¢%d　未分配收益 ¢%d" % [info.unit_price,firm.treasury,firm.operating_profit])
		for ship_id: int in info.ships:
			var ship: Dictionary = world.ships[ship_id]
			var caption := "公司舰船 #%d　%s" % [ship_id,world.HULLS[ship.kind]]
			if world.can_operate(ship):
				game.button(body,caption,func(): game.hud.open_diagnostics(ship_id))
			else:
				game.hud.hint(body,caption)
		for holding in info.holdings:
			var site: Dictionary = world.ports[holding.port]
			var table: Dictionary = world.StationEquity.cap_table(world,site)
			game.button(body,"%s　公司 %d 股 · 你直接 %d 股" % [site.name,holding.units,table.people.get(world.player,0)],func(): open(game,"station",site.id))
		var ballot := []
		for holder: Dictionary in info.holders:
			game.hud.hint(body,"%s　%d 股　董事会支持票 %d" % [world.name_of(holder.person),holder.shares,holder.votes])
			var person: int = holder.person
			var actions = game.hbox(body)
			actions.set_meta("shareholder",person)
			game.button(actions,"人物档案",func(): game.hud.dossier.open(game,person))
			if world.Equity.adult(world,world.people[person]):
				ballot.append(person)
				if person != world.player and info.owned > 0 and not world.oversees(person):
					game.button(actions,"争取董事会支持",func():
						board_message = Relations.request_support(world,id,person).reason
						game.refresh(),at_market)
		if not board_message.is_empty():
			game.title(body,board_message,14,game.GOLD,true)
		if info.owned > 0 and not ballot.is_empty():
			var row = game.hbox(body)
			var candidate = game.choice(row,ballot.map(func(person): return world.name_of(person)))
			game.button(row,"投董事长票",func(): game.hud.result(world.Equity.vote(world,id,ballot[candidate.selected]),"表决已登记。"))
		if world.oversees(firm.director):
			var terms: Dictionary = world.Dividends.company_statement(world,id)
			var policy = game.hbox(body)
			game.title(policy,"分红 %",13,game.DIM)
			var percent = game.field(policy,str(terms.percent),3)
			game.title(policy,"留存 ¢",13,game.DIM)
			var reserve = game.field(policy,str(terms.reserve),10)
			game.button(policy,"保存",func(): game.hud.result(percent.text.is_valid_int() and reserve.text.is_valid_int() and world.Dividends.configure_company(world,id,percent.text.to_int(),reserve.text.to_int()),"公司分红政策已保存。"))
			game.button(body,"公司派息　¢%d" % terms.payable,func(): game.hud.result(world.Dividends.settle_company(world,id)>0,"公司分红已派发。"),terms.payable>0)
	else:
		var site: Dictionary = world.ports[id]
		var table: Dictionary = world.StationEquity.cap_table(world,site)
		game.title(body,"你的单站股份　%d 股 · 占表决权 %.2f%%" % [table.people.get(world.player,0),100.0*table.people.get(world.player,0)/maxi(1,table.total-table.get("treasury_units",0))],17,game.GOLD)
		game.hud.hint(body,"%s　参考估值 ¢%d/股　本站运营资金 ¢%d" % [world.systems[site.system].name,world.StationEquity.unit_price(site),site.treasury])
		for holder: int in table.people:
			game.hud.hint(body,"%s　直接持有 %d 股" % [world.name_of(holder),table.people[holder]])
			game.button(body,"人物档案",func(): game.hud.dossier.open(game,holder))
		if table.company_units > 0:
			var issuer: Dictionary = world.firms[table.company]
			var stake: int = world.active().shares.get(table.company,0)
			game.button(body,"%s　持有本站 %d 股" % [issuer.name,table.company_units],func(): open(game,"company",table.company))
			var outstanding := int(issuer.issued) - int(issuer.treasury_shares)
			var site_outstanding := int(table.total) - int(table.get("treasury_units",0))
			if stake > 0 and outstanding > 0 and site_outstanding > 0:
				var indirect := float(stake)/outstanding * float(table.company_units)/site_outstanding
				game.hud.hint(body,"你另持公司 %d 股，对应本站 %.2f%% 的间接权益。公司派息时到账。" % [stake,100*indirect])
