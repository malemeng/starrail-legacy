extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")

const TRUCE_DAYS := 180

## Ensure war tracking fields exist on a hostile relation entry.
static func _ensure_pact(pact: Dictionary) -> void:
	if not pact.has("score_x"):
		pact.score_x = 0.0
	if not pact.has("score_y"):
		pact.score_y = 0.0
	if not pact.has("occupied"):
		pact.occupied = {}

## Check whether two factions are currently protected by a peace truce.
static func in_truce(world, first: int, second: int) -> bool:
	var pact: Dictionary = world.relations.get(world.pair(first, second), {})
	return int(pact.get("truce_until", 0)) > world.day

## Trigger defensive alliance call-to-arms when war is declared between two factions.
static func on_war_declared(world, attacker: int, defender: int) -> void:
	var pflag := int(world.active().get("flag", -1))
	if pflag == attacker and defender >= 0:
		world.change_faction_trust(defender, world.player, -15, "所属阵营 %s 对其宣战" % world.flag_name(attacker))
	elif pflag == defender and attacker >= 0:
		world.change_faction_trust(attacker, world.player, -15, "向玩家所属阵营 %s 宣战" % world.flag_name(defender))
	for ally_flag in world.factions:
		var ally: int = int(ally_flag)
		if ally == attacker or ally == defender or not world.factions[ally].get("alive", false):
			continue
		if int(world.treaty(defender, ally).get("state", 0)) != 1:
			continue
		if world.hostile(attacker, ally) or in_truce(world, attacker, ally) or int(world.treaty(attacker, ally).get("state", 0)) == 1:
			continue
		world.set_treaty(ally, attacker, -1)
		if pflag == attacker:
			world.change_faction_trust(ally, world.player, -12, "同盟协防 %s 对玩家阵营宣战" % world.flag_name(defender))
		elif pflag == ally:
			world.change_faction_trust(attacker, world.player, -12, "所属阵营履行同盟协防参战")
		world.event("【同盟协防】%s 履行对 %s 的同盟条约，向 %s 宣战！" % [world.flag_name(ally), world.flag_name(defender), world.flag_name(attacker)])

## Return war score pair [my_score, enemy_score] from a faction's perspective.
static func scores_for(world, flag: int, enemy: int) -> Vector2:
	var key: Vector2i = world.pair(flag, enemy)
	var pact: Dictionary = world.relations.get(key, {})
	if pact.is_empty():
		return Vector2.ZERO
	_ensure_pact(pact)
	var sx := float(pact.score_x)
	var sy := float(pact.score_y)
	return Vector2(sx, sy) if flag == key.x else Vector2(sy, sx)

## Add war score to a faction against an enemy if they are at war.
static func add_score(world, scorer: int, loser: int, amount: float) -> void:
	if scorer < 0 or loser < 0 or scorer == loser or amount <= 0.0:
		return
	var key: Vector2i = world.pair(scorer, loser)
	var pact: Dictionary = world.relations.get(key, {})
	if int(pact.get("state", 0)) != -1:
		return
	_ensure_pact(pact)
	if scorer == key.x:
		pact.score_x = float(pact.score_x) + amount
	else:
		pact.score_y = float(pact.score_y) + amount

## Record naval battle war score when a warship is destroyed.
static func record_kill(world, victim: Dictionary, killer_flag: int) -> void:
	var victim_flag := int(victim.get("flag", -1))
	if killer_flag < 0 or victim_flag < 0 or not world.hostile(killer_flag, victim_flag):
		return
	var power := float(Hulls.MODELS[victim.kind].get("power", 1.0))
	add_score(world, killer_flag, victim_flag, 4.0 + power * 3.0)
	var pflag := int(world.active().get("flag", -1))
	if pflag == killer_flag:
		world.change_faction_trust(victim_flag, world.player, -4, "所属阵营击毁其 %s" % Hulls.MODELS[victim.kind].name)

## Temporarily occupy an enemy station during war instead of annexing immediately.
static func occupy(world, port_id: int, attacker: int) -> void:
	if not world.ports.has(port_id) or attacker < 0:
		return
	var station: Dictionary = world.ports[port_id]
	var defender := int(station.flag)
	if defender < 0 or defender == attacker:
		return
	if world.factions.get(attacker, {}).get("civil_enemy", world.NEUTRAL) == defender:
		world.Politics.conquer(world, port_id, attacker)
		return
	var key: Vector2i = world.pair(attacker, defender)
	var pact: Dictionary = world.relations.get(key, {})
	if int(pact.get("state", 0)) != -1:
		world.Politics.conquer(world, port_id, attacker)
		return
	_ensure_pact(pact)
	if not station.has("occupied_from"):
		station.occupied_from = defender
	station.flag = attacker
	station.defense = 25
	station.since = world.day
	world.refresh_tariffs(station.system)
	pact.occupied[port_id] = attacker
	var is_capital: bool = world.factions.get(defender, {}).get("capital", 0) == port_id
	add_score(world, attacker, defender, 55.0 if is_capital else 35.0)
	var pflag := int(world.active().get("flag", -1))
	if pflag == attacker:
		world.change_faction_trust(defender, world.player, -10, "所属阵营占领 %s" % station.name)
		world.change_faction_trust(attacker, world.player, 4, "阵营战果：占领 %s" % station.name)
	elif pflag == defender:
		world.change_faction_trust(attacker, world.player, -10, "占领玩家阵营港口 %s" % station.name)
	world.event("%s 被 %s 战时占领。" % [station.name, world.flag_name(attacker)])

## Compute war exhaustion (0..100) for a faction in a specific war.
static func exhaustion(world, flag: int, enemy: int) -> float:
	var key: Vector2i = world.pair(flag, enemy)
	var pact: Dictionary = world.relations.get(key, {})
	if int(pact.get("state", 0)) != -1:
		return 0.0
	_ensure_pact(pact)
	var duration := float(maxi(0, world.day - int(pact.get("since", world.day))))
	var total := minf(45.0, duration * 0.14)
	var group: Dictionary = world.factions.get(flag, {})
	if int(group.get("treasury", 0)) < 150:
		total += 20.0
	var owned: int = world.systems_owned(flag).size()
	var lost_count := 0
	for pid in pact.occupied:
		var st: Dictionary = world.ports.get(pid, {})
		if int(st.get("occupied_from", -1)) == flag:
			lost_count += 1
	var base_count := maxi(1, owned + lost_count)
	total += minf(45.0, 45.0 * float(lost_count) / float(base_count))
	var sc := scores_for(world, flag, enemy)
	if sc.y > sc.x:
		total += minf(35.0, (sc.y - sc.x) * 0.4)
	return clampf(total, 0.0, 100.0)

## Cost in war score to permanently annex a station in a peace treaty.
static func station_peace_cost(world, port_id: int, defender: int) -> int:
	var st: Dictionary = world.ports.get(port_id, {})
	if st.is_empty():
		return 999
	var base := 28 + int(roundf(float(st.get("pop", 100)) / 120.0))
	if int(world.factions.get(defender, {}).get("capital", 0)) == port_id:
		base += 20
	return mini(75, base)

## Available negotiation budget for proposer against defender.
static func peace_budget(world, proposer: int, defender: int) -> int:
	var sc := scores_for(world, proposer, defender)
	var enemy_ex := exhaustion(world, defender, proposer)
	return maxi(0, roundi(sc.x - sc.y + enemy_ex * 0.35))

## Return summary of all active wars involving a faction.
static func active_wars(world, flag: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for key: Vector2i in world.relations:
		var pact: Dictionary = world.relations[key]
		if int(pact.get("state", 0)) != -1 or (key.x != flag and key.y != flag):
			continue
		var enemy: int = key.y if key.x == flag else key.x
		if not world.factions.get(enemy, {}).get("alive", false):
			continue
		_ensure_pact(pact)
		var sc := scores_for(world, flag, enemy)
		var occupied_by_me: Array[int] = []
		var occupied_by_enemy: Array[int] = []
		for pid in pact.occupied:
			var occ: int = int(pact.occupied[pid])
			if occ == flag:
				occupied_by_me.append(int(pid))
			elif occ == enemy:
				occupied_by_enemy.append(int(pid))
		list.append({
			"enemy": enemy,
			"days": world.day - int(pact.get("since", world.day)),
			"my_score": sc.x,
			"enemy_score": sc.y,
			"my_exhaustion": exhaustion(world, flag, enemy),
			"enemy_exhaustion": exhaustion(world, enemy, flag),
			"budget": peace_budget(world, flag, enemy),
			"occupied_by_me": occupied_by_me,
			"occupied_by_enemy": occupied_by_enemy,
			"civil": world.factions.get(flag, {}).get("civil_enemy", world.NEUTRAL) == enemy,
		})
	return list

## Cost in war score to release an occupied station as an independent neutral port.
static func release_peace_cost(world, port_id: int, defender: int) -> int:
	return maxi(14, int(roundf(float(station_peace_cost(world, port_id, defender)) * 0.55)))

## Preview whether a peace proposal would be accepted and its score cost.
static func preview_peace(world, proposer: int, defender: int, annex_ports: Array = [], demand_reparations: bool = false, release_ports: Array = [], open_trade: bool = false) -> Dictionary:
	var key: Vector2i = world.pair(proposer, defender)
	var pact: Dictionary = world.relations.get(key, {})
	if int(pact.get("state", 0)) != -1:
		return {"valid": false, "accepted": false, "cost": 0, "budget": 0, "reason": "双方未处于交战状态"}
	_ensure_pact(pact)
	var cost := 0
	for pid in annex_ports:
		if int(pact.occupied.get(pid, -1)) != proposer:
			return {"valid": false, "accepted": false, "cost": 999, "budget": 0, "reason": "只能割让已占领的空间站"}
		cost += station_peace_cost(world, int(pid), defender)
	for pid in release_ports:
		if int(pid) in annex_ports:
			return {"valid": false, "accepted": false, "cost": 999, "budget": 0, "reason": "同一空间站不能同时割让与释放"}
		if int(pact.occupied.get(pid, -1)) != proposer:
			return {"valid": false, "accepted": false, "cost": 999, "budget": 0, "reason": "只能释放已占领的空间站"}
		cost += release_peace_cost(world, int(pid), defender)
	if demand_reparations:
		cost += 18
	if open_trade:
		cost += 12
	var budget := peace_budget(world, proposer, defender)
	var my_ex := exhaustion(world, proposer, defender)
	var their_ex := exhaustion(world, defender, proposer)
	var white_peace := annex_ports.is_empty() and release_ports.is_empty() and not demand_reparations and not open_trade
	var accepted := (budget >= cost) if not white_peace else (their_ex >= 45.0 or (my_ex >= 50.0 and scores_for(world, proposer, defender).x >= scores_for(world, proposer, defender).y - 15.0))
	var reason := "可达成协议" if accepted else ("战争分数不足（需 %d / 可用 %d）" % [cost, budget] if not white_peace else "对方厌战度不足，暂不愿白和平")
	return {"valid": true, "accepted": accepted, "cost": cost, "budget": budget, "reason": reason}

static func _reward_war_merit(world, winner: int, port_id: int) -> void:
	var st: Dictionary = world.ports.get(port_id, {})
	if st.is_empty() or int(st.flag) != winner:
		return
	var best_person := 0
	var best_merit := 14
	var leader := int(world.factions.get(winner, {}).get("leader", 0))
	for pid in world.people:
		var cand: Dictionary = world.people[pid]
		if not cand.alive or int(cand.flag) != winner or pid == leader:
			continue
		var m := int(cand.get("merit", 0))
		if m > best_merit:
			best_merit = m
			best_person = pid
	if best_person != 0:
		st.manager = best_person
		world.people[best_person].employer = leader
		if best_person == world.player:
			world.event("战功封赏：因战功卓著，%s 将新占领的 %s 交由你掌管！" % [world.name_of(leader), st.name])

## Execute a peace treaty: annex/release chosen stations, restore others, pay reparations, open trade, start truce.
static func sign_peace(world, proposer: int, defender: int, annex_ports: Array = [], demand_reparations: bool = false, release_ports: Array = [], open_trade: bool = false) -> bool:
	var check := preview_peace(world, proposer, defender, annex_ports, demand_reparations, release_ports, open_trade)
	if not check.valid or not check.accepted:
		return false
	var key: Vector2i = world.pair(proposer, defender)
	var pact: Dictionary = world.relations[key]
	var occupied: Dictionary = pact.get("occupied", {}).duplicate()
	var annexed_names: Array[String] = []
	var released_names: Array[String] = []
	for pid in annex_ports:
		var port_id := int(pid)
		var st: Dictionary = world.ports.get(port_id, {})
		if not st.is_empty():
			st.erase("occupied_from")
			world.Politics.conquer(world, port_id, proposer)
			_reward_war_merit(world, proposer, port_id)
			annexed_names.append(st.name)
		occupied.erase(port_id)
	for pid in release_ports:
		var port_id := int(pid)
		var st: Dictionary = world.ports.get(port_id, {})
		if not st.is_empty():
			st.erase("occupied_from")
			st.flag = world.NEUTRAL
			st.owner = 0
			st.manager = 0
			st.defense = maxi(18, int(st.defense))
			world.refresh_tariffs(st.system)
			world.Equity.update_operator(world, st)
			released_names.append(st.name)
		occupied.erase(port_id)
	for pid in occupied:
		var port_id := int(pid)
		var st: Dictionary = world.ports.get(port_id, {})
		if st.is_empty():
			continue
		var original_owner := int(st.get("occupied_from", -1))
		st.erase("occupied_from")
		if original_owner >= 0 and world.factions.get(original_owner, {}).get("alive", false):
			st.flag = original_owner
			st.defense = maxi(18, int(st.defense))
			world.refresh_tariffs(st.system)
	var rep_paid := 0
	if demand_reparations and world.factions.has(defender) and world.factions.has(proposer):
		var loser_treasury := int(world.factions[defender].get("treasury", 0))
		rep_paid = mini(loser_treasury, maxi(40, roundi(float(loser_treasury) * 0.25)))
		if rep_paid > 0:
			world.factions[defender].treasury -= rep_paid
			world.factions[proposer].treasury += rep_paid
	if open_trade:
		for firm in world.firms.values():
			if int(firm.get("embargo", -1)) in [proposer, defender]:
				firm.embargo = world.NEUTRAL
		for st in world.ports.values():
			if int(st.flag) in [proposer, defender]:
				st.stability = clampf(float(st.stability) + 4.0, 0.0, 100.0)
	world.set_treaty(proposer, defender, 0)
	world.relations[key].truce_until = world.day + TRUCE_DAYS
	var pflag := int(world.active().get("flag", -1))
	if pflag == proposer:
		world.change_faction_trust(defender, world.player, 8, "与 %s 签订停战和约" % world.flag_name(proposer))
	elif pflag == defender:
		world.change_faction_trust(proposer, world.player, 8, "与 %s 签订停战和约" % world.flag_name(defender))
	var parts: Array[String] = []
	if not annexed_names.is_empty():
		parts.append("割让 " + "、".join(annexed_names))
	if not released_names.is_empty():
		parts.append("释放自由港 " + "、".join(released_names))
	if rep_paid > 0:
		parts.append("赔款 %d 信用点" % rep_paid)
	if open_trade:
		parts.append("解除商业禁运")
	var summary := "白和平" if parts.is_empty() else "，".join(parts)
	world.event("【和约】%s 与 %s 停战（%s，休战 %d 日）。" % [world.flag_name(proposer), world.flag_name(defender), summary, TRUCE_DAYS])
	return true

## Daily war score accumulation from occupied/blockaded stations and AI peace checks.
static func daily(world) -> void:
	var pending_peace: Array[Array] = []
	for key: Vector2i in world.relations:
		var pact: Dictionary = world.relations[key]
		if int(pact.get("state", 0)) != -1:
			continue
		_ensure_pact(pact)
		for pid in pact.occupied:
			var occ := int(pact.occupied[pid])
			var other: int = key.y if occ == key.x else key.x
			add_score(world, occ, other, 1.0)
		var fa: Dictionary = world.factions.get(key.x, {})
		var fb: Dictionary = world.factions.get(key.y, {})
		if not fa.get("alive", false) or not fb.get("alive", false):
			continue
		if int(fa.get("civil_enemy", world.NEUTRAL)) == key.y:
			continue
		var days: int = world.day - int(pact.get("since", world.day))
		var ex_a := exhaustion(world, key.x, key.y)
		var ex_b := exhaustion(world, key.y, key.x)
		var diff := absf(float(pact.score_x) - float(pact.score_y))
		var ready: bool = (ex_a >= 75.0 or ex_b >= 75.0) or (diff >= 70.0 and days >= 60) or (days >= 260 and ex_a >= 45.0 and ex_b >= 45.0)
		if ready:
			pending_peace.append([key.x, key.y])
	for pair in pending_peace:
		_resolve_ai_peace(world, int(pair[0]), int(pair[1]))

static func _resolve_ai_peace(world, a: int, b: int) -> void:
	var fa: Dictionary = world.factions.get(a, {})
	var fb: Dictionary = world.factions.get(b, {})
	# If player governs either side, let player negotiate unless total collapse (exhaustion >= 95).
	var player_a: bool = world.Society.player_governs(world, a)
	var player_b: bool = world.Society.player_governs(world, b)
	if (player_a and exhaustion(world, a, b) < 95.0) or (player_b and exhaustion(world, b, a) < 95.0):
		return
	var sc := scores_for(world, a, b)
	var winner := a if sc.x >= sc.y else b
	var loser := b if winner == a else a
	var budget := peace_budget(world, winner, loser)
	var key: Vector2i = world.pair(winner, loser)
	var pact: Dictionary = world.relations.get(key, {})
	var occupied: Dictionary = pact.get("occupied", {})
	var annex: Array[int] = []
	var loser_owned: int = world.systems_owned(loser).size()
	var remaining_budget := budget
	for pid in occupied:
		if int(occupied[pid]) != winner:
			continue
		if loser_owned <= 0 and annex.is_empty() and remaining_budget < 80:
			continue
		var cost := station_peace_cost(world, int(pid), loser)
		if cost <= remaining_budget:
			annex.append(int(pid))
			remaining_budget -= cost
	var rep := remaining_budget >= 18 and int(world.factions.get(loser, {}).get("treasury", 0)) >= 80
	if not sign_peace(world, winner, loser, annex, rep):
		sign_peace(world, winner, loser, [], false)
