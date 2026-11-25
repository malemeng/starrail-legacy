extends RefCounted

const PERIODS := [7,30,90]
const RETENTION := 90

## Keep settled cash separate from the gross value of goods exchanged at a port.
static func record(world, principal: int, asset: Dictionary, category: String, amount: int, market: bool = false, financing: bool = false) -> void:
	if amount == 0 or asset.is_empty():
		return
	if not world.oversees(principal) and asset.get("firm",0) != 0 and principal == asset.owner and category != "股息到账":
		principal = world.firms.get(asset.firm,{}).get("director",0)
	# A hired player can settle a sale on the owner's behalf. Keep the owner's receipt.
	if not world.oversees(principal) and not (principal != 0 and asset.get("captain",0) == world.player):
		return
	var ledger: Dictionary = world.campaign.get_or_add("financial_days",{})
	var day_book: Dictionary = ledger.get_or_add(world.day,{})
	var account: Dictionary = day_book.get_or_add(principal,{})
	var id: int = asset.id
	if not account.has(id):
		var ship := asset.has("hull_id")
		var label: String = world.HULLS[asset.kind] if ship else asset.name
		account[id] = {"id":id,"label":label,"type":asset.get("ledger_type","ship" if ship else "station"),"lines":{},"sales":0,"purchases":0}
	var row: Dictionary = account[id]
	if market:
		row["sales" if amount > 0 else "purchases"] += absi(amount)
		return
	var line: Dictionary = row.lines.get_or_add(category,{"income":0,"expense":0,"financing":financing})
	line["income" if amount > 0 else "expense"] += absi(amount)

static func expire(world) -> void:
	if world.campaign.has("financial_days"):
		world.campaign.financial_days.erase(world.day - RETENTION)

static func report(world, days: int = 30) -> Dictionary:
	var start := maxi(0,world.day-clampi(days,1,RETENTION)+1)
	var result := {"from_day":start,"through_day":world.day,"income":0,"expense":0,"net":0,
		"ship":{"income":0,"expense":0,"net":0},"station":{"income":0,"expense":0,"net":0},"capital_in":0,"capital_out":0,"dividends":0,
		"company_receipts":0,"company_distributions":0,"received_dividends":0,"assets":[]}
	var assets := {}
	var ledger: Dictionary = world.campaign.get("financial_days",{})
	for date: int in ledger:
		if date < start or date > world.day:
			continue
		for principal: int in ledger[date]:
			if not world.oversees(principal):
				continue
			for entry: Dictionary in ledger[date][principal].values():
				var row: Dictionary = assets.get_or_add(entry.id,{"id":entry.id,"label":entry.label,"type":entry.type,"income":0,"expense":0,"net":0,"sales":0,"purchases":0,"lines":{},
					"capital_in":0,"capital_out":0,"dividends":0,"company_receipts":0,"company_distributions":0,"received_dividends":0})
				row.sales += entry.sales
				row.purchases += entry.purchases
				for category in entry.lines:
					var financing: bool = entry.lines[category].get("financing",false)
					var line: Dictionary = row.lines.get_or_add(category,{"income":0,"expense":0,"financing":financing})
					for key in ["income","expense"]:
						var value: int = entry.lines[category][key]
						line[key] += value
						if financing:
							var flow := "capital_in" if key == "income" else "capital_out"
							if category == "分红":
								flow = "dividends"
							elif category == "股息到账":
								flow = "received_dividends"
							elif category == "公司派息":
								flow = "company_distributions"
							elif category == "公司收到站点股息":
								flow = "company_receipts"
							row[flow] += value
							result[flow] += value
							continue
						row[key] += value
						result[row.type][key] += value
						result[key] += value
				row.net = row.income - row.expense
	for key in ["ship","station"]:
		result[key].net = result[key].income - result[key].expense
	result.net = result.income - result.expense
	result.assets = assets.values()
	result.assets.sort_custom(func(a,b): return a.id < b.id)
	return result
