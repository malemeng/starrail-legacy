extends RefCounted

const Rules = preload("res://data/campaign/securities_laws.json")

static func realm_code(world, flag: int) -> String:
	var group: Dictionary = world.factions.get(flag,{})
	var regime: int = group.get("regime",-1)
	if regime < 0 or regime >= world.Society.rules.governments.size():
		return "frontier"
	var enacted: Dictionary = group.get("securities_statute",{})
	if enacted.get("regime",-1) == regime and Rules.data.codes.has(enacted.get("code","")):
		return enacted.code
	return Rules.data.regimes.get(world.Society.rules.governments[regime].id,"licensed")

static func enact(world, flag: int, code: String) -> Dictionary:
	var group: Dictionary = world.factions.get(flag,{})
	if not group.get("alive",false) or not world.Society.player_governs(world,flag):
		return {"allowed":false,"reason":"只有该政权的在位统治者或摄政可以颁布证券法。"}
	if not Rules.data.codes.has(code) or code == "frontier" or realm_code(world,flag) == code:
		return {"allowed":false,"reason":"请选择一项与现行法规不同的政权法案。"}
	group.securities_statute = {"regime":group.regime,"code":code}
	var permits: Dictionary = world.campaign.get("securities_permits",{})
	for key in permits.keys():
		if permits[key].get("flag",-1) == flag:
			permits.erase(key)
	world.EquityOrders.audit(world)
	world.ShareExchange.audit(world)
	world.ShareExchange.audit(world)
	world.DiplomaticTrade.daily(world)
	world.Capital.audit(world,flag)
	var notice := "%s颁布《%s》。" % [world.flag_name(flag),Rules.data.codes[code].name]
	world.event(notice)
	return {"allowed":true,"reason":notice}

static func jurisdiction(world, scope: String, id: int) -> Dictionary:
	var site: Dictionary = world.ports.get(world.firms.get(id,{}).get("hq",0) if scope == "company" else id,{})
	if site.is_empty() or scope not in ["company","station"]:
		return {}
	var flag: int = world.sovereign(site.system)
	var group: Dictionary = world.factions.get(flag,{})
	var regime: int = group.get("regime",-1)
	var code := realm_code(world,flag)
	var law: Dictionary = Rules.data.codes[code].duplicate()
	law.merge({"flag":flag,"regime":regime,"ruler":group.get("leader",0),"site":site.id,"system":site.system,"code":code})
	return law

static func account_flag(world, scope: String, id: int, party: int) -> int:
	if party > 0:
		return world.people.get(party,{}).get("flag",world.NEUTRAL)
	if party == world.StationEquity.TREASURY_PARTY:
		return jurisdiction(world,"station",id).get("flag",world.NEUTRAL)
	var firm_id := id if party == 0 and scope == "company" else -party
	return jurisdiction(world,"company",firm_id).get("flag",world.NEUTRAL)

static func check_transfer(world, scope: String, id: int, party: int, buying: bool, quantity: int) -> Dictionary:
	return check(world,"transfer",scope,id,world.player if buying else party,party if buying else world.player,quantity)

static func permit_key(scope: String, id: int, party: int) -> String:
	return "%s/%d/%d" % [scope,id,party]

static func active_permit(world, scope: String, id: int, party: int, law: Dictionary) -> Dictionary:
	var permits: Variant = world.campaign.get("securities_permits",{})
	if not permits is Dictionary:
		return {}
	var permit: Variant = permits.get(permit_key(scope,id,party),{})
	if permit is Dictionary and int(permit.get("expires",0)) > world.day and permit.get("ruler",0) == law.ruler and permit.get("flag",-1) == law.flag and permit.get("code","") == law.code:
		return permit
	return {}

static func check(world, action: String, scope: String, id: int, buyer: int = -1, seller: int = 0, quantity: int = 0) -> Dictionary:
	var law := jurisdiction(world,scope,id)
	var result := {"allowed":false,"reason":"","approval_required":false,"regime":law.get("regime",-1),"flag":law.get("flag",-1),"code":law.get("code",""),"name":law.get("name","无登记")}
	if law.is_empty() or quantity <= 0 or action not in ["issue","transfer","subscribe"]:
		result.reason = "缺少有效的股权登记或股数。"
		return result
	var issued: int
	var stock: int
	var units: int
	var party: int = world.player if buyer == -1 else buyer
	if scope == "company":
		var firm: Dictionary = world.firms[id]
		issued = firm.issued
		stock = firm.treasury_shares
		units = world.people.get(party,{}).get("shares",{}).get(id,0)
	else:
		var register: Dictionary = world.StationEquity.cap_table(world,world.ports[id])
		issued = register.total
		stock = register.get("treasury_units",0)
		units = register.company_units if party < 0 and -party == register.company else int(register.people.get(party,0))
	var foreign_flag := account_flag(world,scope,id,party)
	if action == "issue":
		if quantity*100 > issued*int(law.issue_limit):
			result.reason = "%s规定，单次增发最多为已发行股本的 %d%%。" % [law.name,law.issue_limit]
			return result
	elif law.flag >= 0:
		if world.hostile(law.flag,foreign_flag) or (action == "transfer" and world.hostile(law.flag,account_flag(world,scope,id,seller))):
			result.reason = "%s禁止登记与交战方之间的股份交易。" % law.name
			return result
		var released: bool = action == "subscribe" or (action == "transfer" and (seller == world.StationEquity.TREASURY_PARTY or (scope == "company" and seller == 0)))
		var outstanding := maxi(1,issued-stock+(quantity if released else 0))
		if foreign_flag != law.flag and (units+quantity)*100 > outstanding*int(law.foreign_limit):
			result.reason = "%s规定外部投资者最多持有 %d%% 表决权。" % [law.name,law.foreign_limit]
			return result
		if foreign_flag != law.flag and law.foreign_review > 0 and (units+quantity)*100 >= outstanding*int(law.foreign_review):
			if active_permit(world,scope,id,party,law).is_empty():
				result.approval_required = true
				result.reason = "外部持股达到 %d%%，须取得%s的持股许可。" % [law.foreign_review,world.flag_name(law.flag)]
				return result
	result.allowed = true
	result.reason = "可依法登记。"
	return result

static func request_permit(world, scope: String, id: int) -> Dictionary:
	var law := jurisdiction(world,scope,id)
	var answer := {"allowed":false,"reason":""}
	if law.is_empty() or int(law.foreign_review) == 0 or not world.Equity.at_market(world):
		answer.reason = "此处无需持股许可，或未连接营业港登记处。"
		return answer
	var actor: Dictionary = world.active()
	if actor.flag == law.flag:
		answer.reason = "本国持股无需申请外部投资许可。"
		return answer
	if not world.Equity.adult(world,actor) or not world.Equity.adult(world,world.people.get(law.ruler,{})) or world.hostile(actor.flag,law.flag):
		answer.reason = "当前身份或外交关系不符合许可条件。"
		return answer
	if not world.oversees(law.ruler) and world.Politics.opinion(world,law.ruler,actor.id) < int(Rules.data.minimum_regulator_opinion):
		answer.reason = "%s不愿为你批准这项持股许可。" % world.name_of(law.ruler)
		return answer
	var expiry := int(world.day) + int(Rules.data.permit_days)
	var permits: Dictionary = world.campaign.get_or_add("securities_permits",{})
	permits[permit_key(scope,id,actor.id)] = {"expires":expiry,"ruler":law.ruler,"flag":law.flag,"code":law.code}
	answer.allowed = true
	answer.reason = "%s批准了你的持股许可，有效至 %s。" % [world.name_of(law.ruler),world.date_label(expiry)]
	return answer

static func valid(data: Dictionary) -> bool:
	for group: Dictionary in data.factions.values():
		if not group.has("securities_statute"):
			continue
		var statute: Variant = group.securities_statute
		if not statute is Dictionary or not statute.get("regime") is int or not statute.get("code") is String or not Rules.data.codes.has(statute.code) or statute.code == "frontier":
			return false
	var permits: Variant = data.campaign.get("securities_permits",{})
	if not permits is Dictionary:
		return false
	for key in permits:
		var permit: Variant = permits[key]
		if not key is String or not permit is Dictionary or not permit.get("expires") is int or not permit.get("ruler") is int or not permit.get("flag") is int or not Rules.data.codes.has(permit.get("code","")):
			return false
		var parts: PackedStringArray = key.split("/")
		if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int() or not data.people.has(int(parts[2])) or not data.people.has(permit.ruler) or not data.factions.has(permit.flag):
			return false
		if parts[0] not in ["company","station"] or not (data.firms if parts[0] == "company" else data.ports).has(int(parts[1])):
			return false
	return true
