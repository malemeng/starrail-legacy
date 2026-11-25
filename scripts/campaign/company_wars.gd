extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")

const CHARTER_FEE := 1500
const MIN_WAR_TREASURY := 9000
const TRUCE_DAYS := 120
const NPC_MIN_TREASURY := 15000
const NPC_MIN_STATIONS := 2
const NPC_MIN_REVENUE := 6000
const NPC_WAR_COOLDOWN := 150

const PRETEXT_KINDS := {
	"tariff_dispute": {"label": "关税纠纷", "cost": 1200, "days": 45, "duration": 180},
	"asset_seizure": {"label": "资产纠纷", "cost": 1800, "days": 60, "duration": 210},
	"privateer_incident": {"label": "袭扰借口", "cost": 2400, "days": 30, "duration": 150},
}

## Ensure company-war and casus-belli tables exist inside world.campaign.
static func ensure_state(world) -> void:
	if not world.campaign.has("casus_belli") or not (world.campaign.casus_belli is Dictionary):
		world.campaign["casus_belli"] = {}
	if not world.campaign.has("company_wars") or not (world.campaign.company_wars is Dictionary):
		world.campaign["company_wars"] = {}
	if not world.campaign.has("company_truces") or not (world.campaign.company_truces is Dictionary):
		world.campaign["company_truces"] = {}

static func _key(firm_id: int, target_flag: int) -> String:
	return "%d:%d" % [firm_id, target_flag]

## Return true if firm_id is a pure commercial corporation (not a sovereign faction's holding firm).
static func is_pure_company(world, firm_id: int) -> bool:
	var firm: Dictionary = world.firms.get(firm_id, {})
	if firm.is_empty():
		return false
	return int(firm.get("flag", world.NEUTRAL)) == world.NEUTRAL

static func operated_stations(world, firm_id: int) -> int:
	var count := 0
	for station in world.ports.values():
		if int(station.get("firm", 0)) == firm_id:
			count += 1
	return count

static func in_truce(world, firm_id: int, target_flag: int) -> bool:
	ensure_state(world)
	var until := int(world.campaign.company_truces.get(_key(firm_id, target_flag), 0))
	return until > int(world.day)

static func at_war(world, firm_id: int, target_flag: int) -> bool:
	var wars: Dictionary = world.campaign.get("company_wars",{})
	return not wars.is_empty() and wars.has(_key(firm_id, target_flag))

static func active_wars_for_firm(world, firm_id: int) -> Array:
	ensure_state(world)
	var list: Array = []
	for war in world.campaign.company_wars.values():
		if int(war.get("firm_id", 0)) == firm_id:
			list.append(war)
	return list

static func get_pretext(world, firm_id: int, target_flag: int) -> Dictionary:
	ensure_state(world)
	return world.campaign.casus_belli.get(_key(firm_id, target_flag), {})

static func has_ready_pretext(world, firm_id: int, target_flag: int) -> bool:
	var cb := get_pretext(world, firm_id, target_flag)
	return not cb.is_empty() and bool(cb.get("ready", false)) and int(cb.get("expires", 0)) >= int(world.day)

## Begin fabricating a casus belli for a pure commercial company against a target faction.
static func start_pretext(world, firm_id: int, target_flag: int, kind: String = "tariff_dispute") -> Dictionary:
	ensure_state(world)
	if not is_pure_company(world, firm_id):
		return {"ok": false, "reason": "仅纯商业公司可制造公司战争借口。"}
	if not world.factions.get(target_flag, {}).get("alive", false):
		return {"ok": false, "reason": "目标势力不存在或已覆灭。"}
	if at_war(world, firm_id, target_flag):
		return {"ok": false, "reason": "公司已与该势力处于私掠交战状态。"}
	if in_truce(world, firm_id, target_flag):
		return {"ok": false, "reason": "双方尚在商业停战休战期内。"}
	var k := _key(firm_id, target_flag)
	if world.campaign.casus_belli.has(k):
		return {"ok": false, "reason": "已存在针对该势力的借口或正在制造中。"}
	if not PRETEXT_KINDS.has(kind):
		return {"ok": false, "reason": "未知的战争借口类型。"}
	var spec: Dictionary = PRETEXT_KINDS[kind]
	var firm: Dictionary = world.firms[firm_id]
	var cost := int(spec.cost)
	if int(firm.get("treasury", 0)) < cost:
		return {"ok": false, "reason": "公司资金不足（需要 ¢%d）。" % cost}
	firm.treasury = int(firm.treasury) - cost
	var entry := {
		"firm_id": firm_id,
		"target_flag": target_flag,
		"kind": kind,
		"label": spec.label,
		"cost": cost,
		"progress": 0,
		"required": int(spec.days),
		"ready": false,
		"started": int(world.day),
		"expires": 0,
	}
	world.campaign.casus_belli[k] = entry
	world.event("【借口制造】%s 耗资 ¢%d 开始针对 %s 制造「%s」战争借口（预计 %d 日）。" % [
		firm.name, cost, world.flag_name(target_flag), spec.label, int(spec.days)
	])
	return {"ok": true, "pretext": entry}

## Directly grant a ready casus belli (e.g. from future events or incidents).
static func grant_pretext(world, firm_id: int, target_flag: int, kind: String = "tariff_dispute", duration: int = 120) -> Dictionary:
	ensure_state(world)
	if not is_pure_company(world, firm_id) or not world.factions.get(target_flag, {}).get("alive", false):
		return {}
	var spec: Dictionary = PRETEXT_KINDS.get(kind, PRETEXT_KINDS["tariff_dispute"])
	var k := _key(firm_id, target_flag)
	var entry := {
		"firm_id": firm_id,
		"target_flag": target_flag,
		"kind": kind,
		"label": spec.label,
		"cost": 0,
		"progress": int(spec.days),
		"required": int(spec.days),
		"ready": true,
		"started": int(world.day),
		"expires": int(world.day) + maxi(1, duration),
	}
	world.campaign.casus_belli[k] = entry
	return entry

## Declare a privateer commercial war using a ready casus belli (no sovereign statehood).
static func declare_war(world, firm_id: int, target_flag: int) -> Dictionary:
	ensure_state(world)
	if not is_pure_company(world, firm_id):
		return {"ok": false, "reason": "仅纯商业公司可发起公司私掠宣战。"}
	if not world.factions.get(target_flag, {}).get("alive", false):
		return {"ok": false, "reason": "目标势力不存在或已覆灭。"}
	if at_war(world, firm_id, target_flag):
		return {"ok": false, "reason": "已处于私掠交战状态。"}
	if in_truce(world, firm_id, target_flag):
		return {"ok": false, "reason": "尚在停战休战期内。"}
	if not has_ready_pretext(world, firm_id, target_flag):
		return {"ok": false, "reason": "缺乏有效的战争借口，请先制造战争借口。"}
	var firm: Dictionary = world.firms[firm_id]
	if int(firm.get("treasury", 0)) < CHARTER_FEE:
		return {"ok": false, "reason": "公司资金不足，无法支付私掠特许费用 ¢%d。" % CHARTER_FEE}
	var k := _key(firm_id, target_flag)
	var cb: Dictionary = world.campaign.casus_belli[k]
	world.campaign.casus_belli.erase(k)
	firm.treasury = int(firm.treasury) - CHARTER_FEE
	firm["last_company_war"] = int(world.day)
	var war := {
		"firm_id": firm_id,
		"target_flag": target_flag,
		"embargo": target_flag,
		"pretext": cb.get("kind", "tariff_dispute"),
		"pretext_label": cb.get("label", "商业纠纷"),
		"started": int(world.day),
		"firm_score": 0.0,
		"target_score": 0.0,
		"raids": 0,
		"looted": 0,
	}
	world.campaign.company_wars[k] = war
	world.event("【商业宣战】%s 以「%s」为由向 %s 发起私掠宣战（不占领主权，执行禁运与商路袭扰）。" % [
		firm.name, war.pretext_label, world.flag_name(target_flag)
	])
	return {"ok": true, "war": war}

## Player and agent commands share the same signing authority and peace terms.
static func director_action(world, action: String, firm_id: int, target_flag: int, kind: String = "tariff_dispute") -> Dictionary:
	if world.firms.get(firm_id,{}).get("director",-1) != world.player:
		return {"ok":false,"reason":"只有现任董事长可以代表公司办理私掠外交。"}
	match action:
		"start_pretext":
			return start_pretext(world,firm_id,target_flag,kind)
		"declare_company_war":
			return declare_war(world,firm_id,target_flag)
		"sign_company_peace":
			var war: Dictionary = world.campaign.get("company_wars",{}).get(_key(firm_id,target_flag),{})
			var ahead := float(war.get("firm_score",0)) >= float(war.get("target_score",0)) + 4.0
			return sign_peace(world,firm_id,target_flag,"firm" if ahead else "white")
	return {"ok":false,"reason":"未知的公司外交指令。"}

## Conclude a company war with commercial reparations and a truce.
static func sign_peace(world, firm_id: int, target_flag: int, winner: String = "firm") -> Dictionary:
	ensure_state(world)
	var k := _key(firm_id, target_flag)
	if not world.campaign.company_wars.has(k):
		return {"ok": false, "reason": "双方未处于公司交战状态。"}
	var war: Dictionary = world.campaign.company_wars[k]
	world.campaign.company_wars.erase(k)
	world.campaign.company_truces[k] = int(world.day) + TRUCE_DAYS
	var firm: Dictionary = world.firms.get(firm_id, {})
	var faction: Dictionary = world.factions.get(target_flag, {})
	# Earlier saves stored the wartime ban in the company's discretionary embargo field.
	if not war.has("embargo") and int(firm.get("embargo", world.NEUTRAL)) == target_flag:
		firm.embargo = world.NEUTRAL
	var rep := 0
	if winner == "firm" and not firm.is_empty() and not faction.is_empty():
		var f_treasury := int(faction.get("treasury", 0))
		rep = clampi(roundi(float(f_treasury) * 0.15), 0, mini(f_treasury, 12000))
		if rep > 0:
			faction.treasury = f_treasury - rep
			firm.treasury = int(firm.get("treasury", 0)) + rep
	elif winner == "target" and not firm.is_empty() and not faction.is_empty():
		var c_treasury := int(firm.get("treasury", 0))
		rep = clampi(roundi(float(c_treasury) * 0.15), 0, mini(c_treasury, 8000))
		if rep > 0:
			firm.treasury = c_treasury - rep
			faction.treasury = int(faction.get("treasury", 0)) + rep
	for ship in world.ships.values():
		if int(ship.get("privateer_firm", 0)) == firm_id and int(ship.job.get("target_flag", -1)) == target_flag:
			ship.job = {"kind": "护航", "system": ship.system}
	var outcome := "白和平"
	if rep > 0:
		outcome = "%s 赔款 ¢%d 并签订商约" % [
			world.flag_name(target_flag) if winner == "firm" else firm.get("name", "公司"), rep
		]
	world.event("【商业和约】%s 与 %s 结束私掠冲突（%s，休战 %d 日）。" % [
		firm.get("name", "公司"), world.flag_name(target_flag), outcome, TRUCE_DAYS
	])
	return {"ok": true, "reparations": rep, "war": war}

## Check whether two combatant/ship dictionaries are hostile due to a company privateer war.
static func ships_hostile(world, source: Dictionary, target: Dictionary) -> bool:
	if world.campaign.get("company_wars", {}).is_empty():
		return false
	var t_flag := int(target.get("flag", world.NEUTRAL))
	var s_flag := int(source.get("flag", world.NEUTRAL))
	var s_firm := int(source.get("firm",source.get("privateer_firm",0)))
	var t_firm := int(target.get("firm",target.get("privateer_firm",0)))
	return (t_flag >= 0 and s_firm > 0 and at_war(world,s_firm,t_flag)) or (s_flag >= 0 and t_firm > 0 and at_war(world,t_firm,s_flag))

static func _pick_raider_target(world, target_flag: int, hq_system: int) -> Dictionary:
	var best_score := INF
	var best_port := {}
	for port_data in world.ports.values():
		if int(port_data.get("flag", -1)) != target_flag or int(port_data.get("build", 0)) != 0:
			continue
		var score := float(world.distance(hq_system, int(port_data.system))) + float(port_data.get("defense", 10)) * 2.0
		if score < best_score:
			best_score = score
			best_port = port_data
	return best_port

static func _commission_privateer(world, firm_id: int, firm: Dictionary) -> int:
	var hq_id := int(firm.get("hq", 0))
	var hq: Dictionary = world.ports.get(hq_id, {})
	if hq.is_empty() or at_war(world, firm_id, int(hq.get("flag", world.NEUTRAL))):
		return 0
	var chosen := -1
	var best_val := -INF
	for kind in range(hq.hulls.size()):
		if hq.hulls[kind] <= 0 or not Hulls.model_limit(hq, kind):
			continue
		var hull: Dictionary = Hulls.MODELS[kind]
		var price := int(Economy.ship_quote(hq, kind).price)
		if price <= 0 or price > int(firm.get("treasury", 0)) - 200:
			continue
		var score := (float(hull.power) * 1.4 + float(hull.hp) * 0.05) / float(price)
		if score > best_val:
			best_val = score
			chosen = kind
	if chosen < 0:
		return 0
	var cost := Economy.withdraw_priced_hull(hq, chosen, int(firm.treasury))
	if cost <= 0:
		return 0
	firm.treasury = int(firm.treasury) - cost
	world.Treasury.post(world, hq, cost, "公司私掠购舰")
	var captain: int = world.random_person(world.NEUTRAL, hq.id)
	var sid: int = world.ship(chosen, 0, captain, world.NEUTRAL, hq.system, hq.pos)
	world.ships[sid].firm = firm_id
	world.ships[sid]["privateer_firm"] = firm_id
	world.ships[sid]["job"] = {"kind": "护航", "system": hq.system}
	return sid

static func _advance_pretexts(world) -> void:
	var expired: Array[String] = []
	for k in world.campaign.casus_belli:
		var cb: Dictionary = world.campaign.casus_belli[k]
		var fid := int(cb.get("firm_id", 0))
		var tflag := int(cb.get("target_flag", -1))
		if not is_pure_company(world, fid) or not world.factions.get(tflag, {}).get("alive", false):
			expired.append(k)
			continue
		if not bool(cb.get("ready", false)):
			cb.progress = clampi(world.day - int(cb.started), 0, int(cb.required))
			if cb.progress >= int(cb.get("required", 10)):
				var spec: Dictionary = PRETEXT_KINDS.get(cb.get("kind", "tariff_dispute"), PRETEXT_KINDS["tariff_dispute"])
				cb.ready = true
				cb.expires = int(world.day) + int(spec.duration)
				world.event("【战争借口】%s 已完成对 %s 的「%s」借口制造，可随时发起私掠宣战。" % [
					world.firms[fid].name, world.flag_name(tflag), cb.get("label", "商业纠纷")
				])
		elif int(world.day) > int(cb.get("expires", 0)):
			expired.append(k)
	for k in expired:
		world.campaign.casus_belli.erase(k)

static func _advance_wars(world) -> void:
	var to_close: Array[Array] = []
	var acted := {}
	for k in world.campaign.company_wars.keys():
		var war: Dictionary = world.campaign.company_wars[k]
		var fid := int(war.get("firm_id", 0))
		var tflag := int(war.get("target_flag", -1))
		if not is_pure_company(world, fid) or not world.factions.get(tflag, {}).get("alive", false):
			to_close.append([fid, tflag, "white"])
			continue
		var firm: Dictionary = world.firms[fid]
		var hq: Dictionary = world.ports.get(int(firm.get("hq", 0)), {})
		if hq.is_empty():
			continue
		var raiders: Array[int] = []
		var reserve: Array[int] = []
		var fleet_count := 0
		for ship in world.ships.values():
			if int(ship.get("privateer_firm", 0)) != fid:
				continue
			fleet_count += 1
			if ship.locked or ship.captain == world.player or acted.has(ship.id):
				continue
			if ship.job.get("kind","") != "私掠":
				reserve.append(int(ship.id))
			elif ship.job.get("target_flag",-1) == tflag:
				raiders.append(int(ship.id))
		var front_limit := 2 if active_wars_for_firm(world,fid).size() == 1 else 1
		raiders.append_array(reserve.slice(0,maxi(0,front_limit-raiders.size())))
		if raiders.size() < front_limit and fleet_count < 2 and int(firm.get("treasury", 0)) >= MIN_WAR_TREASURY:
			var bought := _commission_privateer(world, fid, firm)
			if bought > 0:
				raiders.append(bought)
		var target_port := _pick_raider_target(world, tflag, int(hq.system))
		for sid in raiders:
			var vessel: Dictionary = world.ships[sid]
			acted[sid] = true
			if vessel.job.get("kind", "") != "私掠":
				if target_port.is_empty():
					continue
				var transit := clampi(int(world.distance(vessel.system, target_port.system) / 90.0), 5, 16)
				if vessel.dock != 0:
					world.depart(vessel)
				vessel.job = {
					"kind": "私掠", "target": target_port.id, "target_flag": tflag,
					"origin_system": vessel.system, "started": int(world.day), "eta": int(world.day) + transit,
				}
				continue
			var st: Dictionary = world.ports.get(int(vessel.job.get("target", 0)), {})
			if st.is_empty() or int(st.flag) != tflag:
				vessel.job = {"kind": "护航", "system": vessel.system}
				continue
			if int(world.day) < int(vessel.job.get("eta", 0)):
				var origin_sys := int(vessel.job.get("origin_system", vessel.system))
				if origin_sys >= 0 and origin_sys < world.systems.size() and int(st.system) != origin_sys:
					vessel.layer = true
					var total_days := maxi(1, int(vessel.job.eta) - int(vessel.job.get("started", world.day - 1)))
					var progress := clampf(float(world.day - int(vessel.job.get("started", world.day - 1))) / float(total_days), 0.0, 1.0)
					vessel.galpos = Vector2(world.systems[origin_sys].pos).lerp(Vector2(world.systems[st.system].pos), progress)
				continue
			vessel.layer = false
			vessel.system = st.system
			if not vessel.job.get("arrived", false):
				vessel.pos = st.pos + Vector2(-240, 120)
				vessel.job.arrived = true
				continue
			var home_guard := false
			for defender in world.ships.values():
				if int(defender.flag) == tflag and int(defender.system) == int(st.system) and defender.job.get("kind", "") == "护航":
					home_guard = true
					break
			st.defense -= 10 if home_guard else 18
			vessel.hp -= 10 if home_guard else 3
			if vessel.hp <= 0:
				war.target_score = float(war.target_score) + 6.0
				world.destruction(vessel.id)
			elif st.defense <= 0:
				var available: int = world.Treasury.available(st)
				var loot := mini(available, clampi(roundi(available * 0.15), 600, 1800))
				if loot > 0 and world.Treasury.post(world, st, -loot, "私掠劫掠"):
					firm.treasury = int(firm.treasury) + loot
				else:
					loot = 0
				war.raids = int(war.get("raids", 0)) + 1
				war.looted = int(war.get("looted", 0)) + loot
				war.firm_score = float(war.firm_score) + 10.0
				st.defense = 12
				world.event("【私掠袭扰】%s 的私掠船队洗劫了 %s 商路（截获 ¢%d），未占领主权。" % [firm.name, st.name, loot])
				vessel.job = {"kind": "护航", "system": vessel.system}
		var age_days := int(world.day) - int(war.get("started", world.day))
		if float(war.firm_score) >= 20.0 or (age_days >= 60 and float(war.firm_score) >= float(war.target_score) + 8.0):
			to_close.append([fid, tflag, "firm"])
		elif float(war.target_score) >= float(war.firm_score) + 18.0:
			to_close.append([fid, tflag, "target"])
		elif age_days >= 120:
			to_close.append([fid, tflag, "white"])
	for item in to_close:
		sign_peace(world, int(item[0]), int(item[1]), String(item[2]))

static func _npc_company_ai(world) -> void:
	for fid_raw in world.firms.keys():
		var fid := int(fid_raw)
		if not is_pure_company(world, fid):
			continue
		var firm: Dictionary = world.firms[fid]
		if int(firm.get("director", 0)) == int(world.player):
			continue
		if int(firm.get("treasury", 0)) < NPC_MIN_TREASURY:
			continue
		if operated_stations(world, fid) < NPC_MIN_STATIONS and int(firm.get("revenue", 0)) < NPC_MIN_REVENUE:
			continue
		if not active_wars_for_firm(world, fid).is_empty():
			continue
		if int(world.day) - int(firm.get("last_company_war", -NPC_WAR_COOLDOWN)) < NPC_WAR_COOLDOWN:
			continue
		var hq: Dictionary = world.ports.get(int(firm.get("hq", 0)), {})
		if hq.is_empty():
			continue
		var host_flag := int(hq.get("flag", world.NEUTRAL))
		for k in world.campaign.casus_belli.keys():
			var cb: Dictionary = world.campaign.casus_belli[k]
			if int(cb.get("firm_id", 0)) == fid and bool(cb.get("ready", false)):
				declare_war(world, fid, int(cb.target_flag))
				break
		if not active_wars_for_firm(world, fid).is_empty():
			continue
		var has_pending := false
		for cb in world.campaign.casus_belli.values():
			if int(cb.get("firm_id", 0)) == fid:
				has_pending = true
				break
		if has_pending:
			continue
		var best_target := -1
		var best_dist := INF
		for flag_raw in world.factions.keys():
			var tflag := int(flag_raw)
			if tflag == host_flag or not world.factions[tflag].get("alive", false):
				continue
			if in_truce(world, fid, tflag):
				continue
			for port_data in world.ports.values():
				if int(port_data.get("flag", -1)) == tflag and int(port_data.get("build", 0)) == 0:
					var d := float(world.distance(int(hq.system), int(port_data.system)))
					if d < best_dist:
						best_dist = d
						best_target = tflag
		if best_target >= 0:
			var director: Dictionary = world.people.get(int(firm.get("director", 0)), {})
			if director.is_empty() or world.Politics._npc_roll(world, director, 0.35, "company_war"):
				var traits: Array = director.get("ck_traits", [])
				var kind := "privateer_incident" if ("狡诈" in traits or "残忍" in traits) else ("asset_seizure" if "贪婪" in traits else "tariff_dispute")
				start_pretext(world, fid, best_target, kind)

## Daily tick for company war pretexts, privateer raids, and large NPC company AI.
static func daily(world) -> void:
	ensure_state(world)
	_advance_pretexts(world)
	if world.day % 6 == 0:
		_advance_wars(world)
		_npc_company_ai(world)
