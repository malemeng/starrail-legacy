extends RefCounted

const TARGET_ACTIVE := 3

static func active(world) -> Array:
	var list: Array = world.campaign.get("bounties", [])
	var result := []
	for row: Dictionary in list:
		if int(row.get("expires", -1)) >= world.day:
			result.append(row)
	return result

static func reward_for(bounty: Dictionary, hull: Dictionary) -> int:
	return int(bounty.get("base_reward", 140)) + int(hull.get("power", 10)) * int(bounty.get("per_power", 6))

static func advance(world) -> void:
	var kept := active(world)
	var used_issuers := {}
	for row: Dictionary in kept:
		used_issuers[int(row.issuer_flag)] = true
	var alive_flags: Array = []
	for flag: int in world.factions:
		if world.factions[flag].alive:
			alive_flags.append(flag)
	if alive_flags.is_empty():
		world.campaign.bounties = kept
		return
	var attempts := 0
	while kept.size() < TARGET_ACTIVE and attempts < alive_flags.size() * 2:
		attempts += 1
		var roll: int = absi(hash([world.settings.seed, world.day, kept.size(), attempts]))
		var issuer: int = alive_flags[roll % alive_flags.size()]
		if used_issuers.has(issuer):
			continue
		var enemies: Array = [world.RAIDERS]
		for other: int in alive_flags:
			if other != issuer and world.hostile(issuer, other):
				enemies.append(other)
		var target: int = enemies[(roll / 7) % enemies.size()]
		var owned_ports: Array = world.systems_owned(issuer)
		var designated_system := -1
		if (roll / 13) % 3 != 0 and not owned_ports.is_empty():
			var pid: int = owned_ports[(roll / 17) % owned_ports.size()]
			designated_system = int(world.ports[pid].system)
		var duration := 300 + (roll % 181)
		var base_reward := 180 if designated_system >= 0 else 130
		kept.append({
			"id": world.uid(),
			"issuer_flag": issuer,
			"target_flag": target,
			"system": designated_system,
			"base_reward": base_reward,
			"per_power": 6,
			"started": world.day,
			"expires": world.day + duration,
			"paid_count": 0
		})
		used_issuers[issuer] = true
	world.campaign.bounties = kept

static func on_kill(world, victim: Dictionary, killer: int) -> int:
	if killer == 0 or not world.people.has(killer) or not world.people[killer].alive:
		return 0
	var recipient: int = world.player if world.oversees(killer) else killer
	var recipient_flag: int = int(world.people[recipient].flag)
	var victor: Dictionary = world.ships.get(world.people[recipient].ship, {})
	var hull: Dictionary = world.Hulls.MODELS[victim.kind]
	var total := 0
	for bounty: Dictionary in active(world):
		var issuer := int(bounty.issuer_flag)
		if not world.factions.get(issuer, {}).get("alive", false):
			continue
		if world.hostile(recipient_flag, issuer):
			continue
		var sys := int(bounty.system)
		if sys >= 0 and int(victim.system) != sys:
			continue
		var target := int(bounty.target_flag)
		var matches_target: bool = int(victim.flag) == target or world.hostile(issuer, int(victim.flag)) and target == world.NEUTRAL
		if not matches_target:
			continue
		var reward := reward_for(bounty, hull)
		world.credit(recipient, reward, victor, "星区悬赏")
		world.change_faction_trust(issuer,killer,5,"完成星区悬赏")
		bounty.paid_count = int(bounty.get("paid_count", 0)) + 1
		total += reward
		if recipient == world.player:
			world.event("【自动赏金】%s 发放 ¢%d 悬赏（在%s击毁%s）。" % [world.flag_name(issuer), reward, world.systems[victim.system].name, world.HULLS[victim.kind]])
	return total
