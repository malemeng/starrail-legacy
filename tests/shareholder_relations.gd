extends SceneTree

const World = preload("res://world.gd")
const Story = preload("res://frontier.gd")
const Relations = preload("res://scripts/campaign/shareholder_relations.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	var world := World.new()
	world.new_game({"seed":"shareholder-relations","systems":12,"factions":3,"overrides":[{"regime":4}]})
	var actor := world.active()
	var chair_id: int = world.firms[world.factions[0].firm].director
	var chair := Relations.profile(world,chair_id)
	check(chair.roles.size() >= 2,"the same public officer is the registered chair and head of government")
	var group: Dictionary = world.factions[0]
	var company: int = group.firm
	check(chair.interests.any(func(x): return x.kind == "company" and x.id == company and x.counterparty == chair_id),"dossier identifies the chair's own stock")
	check(chair.interests.any(func(x): return x.kind == "station" and x.counterparty == -company),"the same person can sign for a subsidiary's corporate shareholder")
	var voter: int = world.ports[Story.origin(world)].manager
	var refusal := Relations.request_support(world,company,voter)
	check(not refusal.accepted and refusal.decider == voter,"a non-shareholder cannot run for chair")
	# Split the issued shares 45/35/20 percent and assign any remainder to the incumbent.
	for npc: Dictionary in world.people.values():
		npc.shares.erase(company)
	var firm: Dictionary = world.firms[company]
	firm.treasury_shares = 0
	firm.ballots.clear()
	var player_votes := int(firm.issued)*35/100
	var proxy_votes := int(firm.issued)*20/100
	actor.shares[company] = player_votes
	world.people[chair_id].shares[company] = int(firm.issued)-player_votes-proxy_votes
	var contact: Dictionary = world.people[voter]
	contact.shares[company] = proxy_votes
	contact.opinions[actor.id] = -55
	var original_opinion: int = world.Politics.opinion(world,voter,actor.id)
	check(not Relations.request_support(world,company,voter).accepted and not firm.ballots.has(voter) and firm.director == chair_id,"untrusted candidate gets no votes and changes no office")
	actor.wallet = 400
	check(Story.accept(world),"the contact commissions the normal starter delivery")
	var ship := world.ride()
	ship.dock = Story.foundry(world)
	ship.system = world.ports[ship.dock].system
	actor.loc = ship.dock
	ship.cargo[0] = 8
	check(Story.deliver(world) and world.Politics.opinion(world,voter,actor.id) == original_opinion+16,"fulfilling the freight contract improves the actual shareholder's opinion")
	check(not world.Politics.influence(world,voter),"meeting a contact in person requires returning to their port")
	ship.dock = Story.origin(world)
	ship.system = world.ports[ship.dock].system
	actor.loc = ship.dock
	for i in 6:
		check(world.Politics.influence(world,voter),"face-to-face gift reaches the named contact")
		var cash: int = actor.wallet
		var opinion: int = world.Politics.opinion(world,voter,actor.id)
		check(not world.Politics.influence(world,voter) and actor.wallet == cash and world.Politics.opinion(world,voter,actor.id) == opinion,"repeated gifts do not buy unlimited trust during the same visit")
		world.day += int(world.Society.rules.personal_gift.interval_days)
	var estate: int = contact.wallet
	var personal_cash: int = actor.wallet
	var treasury: int = firm.treasury
	var vote := Relations.request_support(world,company,voter)
	check(vote.accepted and vote.votes == proxy_votes and vote.decider == voter,"the trusted contact offers only the votes on their shares")
	check(firm.director == world.player and group.leader == world.player and actor.shares[company] == player_votes,"the player wins the board and political office with a minority stake")
	check(contact.shares[company] == proxy_votes and contact.wallet == estate and actor.wallet == personal_cash and firm.treasury == treasury,"support changes neither private property nor company funds")
	check(Relations.request_support(world,company,voter).accepted and world.Equity.supporters(world,company).get(world.player,0) == player_votes+proxy_votes,"repeat discussions never duplicate the proxy ballot")
	var saved := World.new()
	check(saved.load_state(world.snapshot()) and saved.firms[company].ballots[voter] == saved.player,"the consenting shareholder's vote survives reloading")
	print("Shareholder relations %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
