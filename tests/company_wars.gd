extends SceneTree

const WorldScript = preload("res://world.gd")
const CompanyWars = preload("res://scripts/campaign/company_wars.gd")

var passed := 0
var failed := 0

func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var w = WorldScript.new()
	w.new_game({"seed": "company-wars-test", "systems": 16, "factions": 4, "avatar": {"name": "Test Director"}})

	var firm_id := 0
	for fid in w.firms:
		if CompanyWars.is_pure_company(w, int(fid)):
			firm_id = int(fid)
			break
	check(firm_id != 0, "found pure commercial company")

	var firm: Dictionary = w.firms[firm_id]
	var target_flag := 0
	for f in w.factions:
		if w.factions[f].alive:
			target_flag = int(f)
			break
	w.factions[target_flag].treasury = 2000

	# 1. Cannot declare war without casus belli
	firm.treasury = 10000
	var no_cb: Dictionary = CompanyWars.declare_war(w, firm_id, target_flag)
	check(not bool(no_cb.get("ok", false)), "declare_war blocked without casus belli")

	# 2. Fabricate pretext
	var start_res: Dictionary = CompanyWars.start_pretext(w, firm_id, target_flag, "tariff_dispute")
	check(bool(start_res.get("ok", false)), "start_pretext succeeds")
	check(int(firm.treasury) == 8800, "start_pretext deducts 1200 cost")
	check(not CompanyWars.has_ready_pretext(w, firm_id, target_flag), "pretext not ready on day 0")

	for _i in range(45):
		w.day += 1
		CompanyWars.daily(w)
	check(CompanyWars.has_ready_pretext(w, firm_id, target_flag), "pretext ready after 45 days")

	# 3. Declare war using pretext
	var war_res: Dictionary = CompanyWars.declare_war(w, firm_id, target_flag)
	check(bool(war_res.get("ok", false)), "declare_war succeeds with ready pretext")
	check(CompanyWars.at_war(w, firm_id, target_flag), "at_war is true")
	check(int(firm.embargo) == target_flag, "embargo set to target faction")
	check(int(firm.treasury) == 7300, "charter fee 1500 deducted")

	# 4. Ship hostility check without sovereign statehood
	var dir_id := int(firm.director)
	var hq: Dictionary = w.ports[int(firm.hq)]
	var priv_id: int = w.ship(0, dir_id, dir_id, w.NEUTRAL, hq.system, hq.pos)
	w.ships[priv_id]["privateer_firm"] = firm_id
	var foe_cap := w.random_person(target_flag, w.factions[target_flag].capital)
	var foe_id: int = w.ship(0, 0, foe_cap, target_flag, hq.system, hq.pos + Vector2(50, 0))
	check(w.enemy(w.ships[priv_id], w.ships[foe_id]), "privateer ship is hostile to target faction ship")
	check(w.enemy(w.ships[foe_id], w.ships[priv_id]), "target faction ship is hostile to privateer ship")

	# 5. Peace settlement & truce
	var pre_firm_t := int(firm.treasury)
	var peace_res: Dictionary = CompanyWars.sign_peace(w, firm_id, target_flag, "firm")
	check(bool(peace_res.get("ok", false)), "sign_peace succeeds")
	check(not CompanyWars.at_war(w, firm_id, target_flag), "at_war cleared after peace")
	check(CompanyWars.in_truce(w, firm_id, target_flag), "truce active after peace")
	check(int(firm.treasury) > pre_firm_t, "reparations paid to winning company")
	check(int(firm.embargo) == w.NEUTRAL, "embargo cleared on peace")
	check(not w.enemy(w.ships[priv_id], w.ships[foe_id]), "ships no longer hostile after peace")

	# 6. Large NPC company AI fabricates pretext automatically
	var npc_w = WorldScript.new()
	npc_w.new_game({"seed": "company-wars-npc-test", "systems": 16, "factions": 4, "avatar": {"name": "Test Observer"}})
	var npc_fid := 0
	for fid in npc_w.firms:
		if CompanyWars.is_pure_company(npc_w, int(fid)) and int(npc_w.firms[fid].director) != npc_w.player:
			npc_fid = int(fid)
			break
	check(npc_fid != 0, "found NPC pure company")
	var npc_firm: Dictionary = npc_w.firms[npc_fid]
	npc_firm.treasury = 20000
	npc_firm.revenue = 8000
	var has_cb := false
	for _d in range(30):
		npc_w.day += 1
		CompanyWars.daily(npc_w)
		for cb in npc_w.campaign.get("casus_belli", {}).values():
			if int(cb.get("firm_id", 0)) == npc_fid:
				has_cb = true
				break
		if has_cb:
			break
	check(has_cb, "qualifying large NPC company starts fabricating casus belli")

	print("CompanyWars checks %d/%d" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)
