extends RefCounted

const Portrait = preload("res://portrait.gd")
const Relations = preload("res://scripts/campaign/shareholder_relations.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")
var person_id := 0
var return_tab := ""

func open(game, id: int) -> void:
	return_tab = game.tab
	person_id = id
	game.tab = "人物"
	game.refresh()

func paint(game, body: Node) -> void:
	var world = game.world
	var info := Relations.profile(world,person_id)
	game.button(body,"返回" + ("人物列表" if return_tab == "人物" else return_tab),func():
		person_id = 0
		game.tab = return_tab
		game.refresh())
	if info.is_empty():
		return
	var person: Dictionary = world.people[person_id]
	var actor: Dictionary = world.active()
	var card := PanelContainer.new()
	body.add_child(card)
	var card_box: VBoxContainer = game.vbox(card)
	var header: HBoxContainer = game.hbox(card_box)
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(92, 104)
	portrait.look = Portrait.for_actor(world, person)
	header.add_child(portrait)
	var bio: VBoxContainer = game.vbox(header)
	bio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gender_text := "女" if int(person.get("gender", 0)) == 1 else "男"
	var age_years: int = world.Politics.age(world, person)
	game.hud.bind_character_menu(game.hud.heading(bio, "%s  (%d 岁 · %s)" % [info.name, age_years, gender_text]),person_id)
	game.hud.hint(bio, "%s · %s · %s" % [info.house + "家族" if person.noble else "平民", info.trait, info.faction])
	var rel_tags := []
	var rel: String = actor.get("relations", {}).get(person_id, "")
	if rel == "friend":
		rel_tags.append("挚友")
	elif rel == "rival":
		rel_tags.append("宿敌")
	elif rel == "lover":
		rel_tags.append("情人")
	if actor.get("hooks", {}).has(person_id):
		rel_tags.append("持有把柄")
	var rel_str := (" · [" + " / ".join(rel_tags) + "]") if not rel_tags.is_empty() else ""
	game.hud.hint(bio, ("对你的好感 %+d%s" % [info.opinion, rel_str]) if person_id != world.player else "你本人")
	var traits_list: Array = world.Society.trait_labels(person)
	if not traits_list.is_empty():
		var t_row := HFlowContainer.new()
		t_row.add_theme_constant_override("h_separation", 4)
		card_box.add_child(t_row)
		for tl in traits_list:
			UIKit.badge(t_row, str(tl), "gold")
	UIKit.kv_grid(card_box, [
		["外交", person.stats.diplomacy], ["军事", person.stats.martial],
		["管理", person.stats.stewardship], ["谋略", person.stats.intrigue],
		["学识", person.stats.learning], ["勇武", person.stats.prowess],
	], 3)
	UIKit.meter(card_box, "压力", float(person.get("stress", 0)), 400.0, "warn" if int(person.get("stress", 0)) >= 200 else "info")
	for role in info.roles:
		game.hud.hint(card_box, role)
	game.hud.heading(card_box,"职务与隶属")
	var superior: int = world.reports_to(person)
	if superior and superior != person_id:
		game.button(card_box,"直属上级　%s #%d" % [world.name_of(superior),superior],func(): person_id = superior; game.refresh())
	else:
		game.hud.hint(card_box,"直属上级　无")
	var leader: int = world.factions.get(person.flag,{}).get("leader",0)
	if leader and leader != person_id and world.people.has(leader):
		game.button(card_box,"势力领袖　%s #%d" % [world.name_of(leader),leader],func(): person_id = leader; game.refresh())
	var staff := []
	var roster := []
	for subordinate: Dictionary in world.people.values():
		if subordinate.alive and subordinate.id != person_id and world.reports_to(subordinate) == person_id:
			staff.append(subordinate.id)
			roster.append("%s #%d" % [subordinate.name,subordinate.id])
	game.hud.hint(card_box,"直接下属　%d 人" % staff.size())
	if not staff.is_empty():
		var list = game.choice(card_box,roster)
		game.button(card_box,"查看所选下属",func(): person_id = staff[list.selected]; game.refresh())
	game.hud.heading(card_box,"阵营对%s的信任" % ("你" if person_id == world.player else person.name))
	for flag: int in world.factions:
		if not world.factions[flag].alive:
			continue
		var history: Dictionary = person.get("faction_trust",{}).get(flag,{})
		var entry := "%s　%+d" % [world.flag_name(flag),world.faction_trust(flag,person_id)]
		if not history.is_empty():
			entry += "　·　第 %d 天 %s（%+d）" % [history.day,history.reason,history.change]
		game.hud.hint(card_box,entry)
	var location: Dictionary = world.ports.get(person.loc, {})
	if not location.is_empty() and (location.scan or person.loc == actor.loc):
		var loc_lbl: Label = game.hud.hint(card_box, "所在地：%s · %s" % [world.systems[location.system].name, location.name])
		game.hud.bind_location_menu(loc_lbl, int(location.id), int(location.system))
	if person.spouse != 0:
		var sp_btn: Button = game.button(card_box, "配偶：%s" % world.name_of(person.spouse), func(): open(game, person.spouse))
		game.hud.bind_character_menu(sp_btn, person.spouse)

	if person_id != world.player and info.alive:
		var watched: bool = world.is_watched(person_id)
		UIKit.action_button(card_box, "★ 已特别关注（点击取消）" if watched else "☆ 加入特别关注（动态追踪）", func():
			var on: bool = world.toggle_watch(person_id)
			game.hud.result(true, ("已特别关注 %s，后续其买船/建站/创业/宣战动态将实时播报。" % info.name) if on else ("已取消关注 %s。" % info.name)),
			"primary" if watched else "ghost")
		var same_port: bool = person.loc > 0 and person.loc == actor.loc
		game.hud.heading(body,"外交与社交" if same_port else "远程外交")
		if actor.flag >= 0 and person.flag >= 0 and world.factions[person.flag].leader == person_id and world.hostile(actor.flag,person.flag) and world.Society.player_governs(world,actor.flag):
			game.button(body,"商谈两国停战条款",func(): game.open_strategic_map("peace",person.flag))
		var dip_row: HBoxContainer = game.hbox(body)
		var wait_days: int = world.Politics.gift_wait(world, person_id)
		var gift := ("赠礼 ¢%d" if same_port else "汇赠信用点 ¢%d") % int(world.Society.rules.personal_gift.cost)
		if wait_days > 0:
			gift += " (%d日)" % wait_days
		game.button(dip_row, gift, func(): game.hud.result(world.Politics.influence(world, person_id,true), "对方收下了礼物。"), world.Politics.can_gift(world, person_id,true))
		if person.spouse == 0 and actor.spouse == 0:
			var terms: Dictionary = world.Politics.marriage_terms(world, world.player, person_id,true)
			if terms.eligible:
				game.button(dip_row, "提议联姻" if terms.dynastic else "求婚", func():
					var current: Dictionary = world.Politics.marriage_terms(world, world.player, person_id,true)
					game.hud.result(world.Politics.marry(world, world.player, person_id,true), "你与%s结为配偶。" % person.name, current.reason))

		game.hud.heading(body, "密谋与把柄")
		var scheme: Dictionary = world.campaign.schemes.get(world.player, {})
		if scheme.is_empty():
			var sch_row: HBoxContainer = game.hbox(body)
			game.button(sch_row, "展开拉拢 (好感/挚友)", func(): game.hud.result(world.Society.scheme(world, person_id, "sway"), "已对 %s 展开拉拢。" % person.name))
			if same_port:
				game.button(sch_row, "刺探秘密 (获取把柄)", func(): game.hud.result(world.Society.scheme(world, person_id, "find_secrets"), "已开始刺探 %s 的秘密。" % person.name))
		elif scheme.target == person_id:
			var sname := "拉拢" if scheme.kind == "sway" else "刺探秘密"
			game.hud.hint(body, "进行中：%s（阶段 %d / 3）" % [sname, scheme.stage])
			var act_row: HBoxContainer = game.hbox(body)
			game.button(act_row, "资助特工 ¢25", func(): game.hud.result(world.Society.fund_scheme(world), "已资助计谋。"), scheme.funded < 3 and actor.wallet >= 25)
			game.button(act_row, "收网结算", func(): game.hud.result(world.Society.resolve_scheme(world), "计谋已结算。"), scheme.stage >= 3)
		else:
			game.hud.hint(body, "当前正在对 %s 执行计谋。" % world.name_of(scheme.target))

		if world.Equity.at_market(world):
			game.hud.heading(body, "商业贸易")
			game.button(body, "与 %s 进行大宗交易" % person.name, func(): game.open_trade_table("person", person_id))
	if info.interests.is_empty():
		game.hud.hint(body,"当前股东名册里查不到此人持有或能经手的股份。")
		return
	game.hud.heading(body,"持股与受托账户")
	var names := []
	for entry: Dictionary in info.interests:
		var role := "私人" if entry.counterparty == person_id else str(entry.account)
		names.append("%s · %s · %s" % [entry.name,role,("%d 股" % entry.units) if entry.units else "潜在买家"])
	var list = game.choice(body,names)
	list.fit_to_longest_item = false
	list.clip_contents = true
	var action = game.button(body,"洽谈股份",func():
		var entry: Dictionary = info.interests[list.selected]
		if entry.can_negotiate and world.Equity.at_market(world):
			game.open_equity_trade(entry.kind,entry.id,entry.counterparty)
		else:
			game.hud.equity.open(game,entry.kind,entry.id))
	var update_action := func(index: int):
		action.text = "洽谈股份" if info.interests[index].can_negotiate and world.Equity.at_market(world) else "查看股权名册"
	list.item_selected.connect(update_action)
	update_action.call(list.selected)
	if not world.Equity.at_market(world):
		game.hud.hint(body,"停靠营业港后可以通过港口通信洽谈。")
