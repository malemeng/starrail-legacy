extends SceneTree

const World = preload("res://world.gd")
var checks := 0
var errors := 0

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		errors+=1
		printerr("FAIL ",label)
	return ok

func new_family(seed_name: String, noble_partner: bool = false) -> Dictionary:
	var w:=World.new()
	w.new_game({"seed":seed_name,"systems":12,"factions":3,"avatar":{"noble":false,"age":26,"gender":0}})
	var actor:=w.active()
	var spouse:=w.random_person(w.NEUTRAL,actor.loc,"月汀",1)
	var resident: Dictionary=w.people[spouse]
	resident.noble=noble_partner
	resident.birth=w.day-25*360
	resident.opinions[actor.id]=90
	actor.opinions[spouse]=90
	return {"w":w,"actor":actor,"other":resident}

func inheritance(w, actor: Dictionary, spouse: Dictionary, child_id: int = 0) -> void:
	var dock: Dictionary=w.ports[actor.loc]
	actor.wallet=100000
	var kind: int=w.Hulls.kind_for_reference(w.deployment.home_miner)
	var own: int=w.Economy.buy_ship(w,dock.id,kind)
	var charter: int=actor.ship
	var issuer: int=w.incorporate("青禾储运",actor.id,dock.id,false)
	var neighbour: int=w.random_person(w.NEUTRAL,dock.id)
	var site: Dictionary=w.ports[w.port(dock.system,"栖湾工坊",dock.pos+Vector2(800,100),w.NEUTRAL,neighbour,0)]
	w.StationEquity.freeze(w,site)
	w.StationEquity.add_units(site.equity.people,neighbour,-7)
	w.StationEquity.add_units(site.equity.people,actor.id,7)
	var heir: int=child_id if child_id!=0 else spouse.id
	var person: Dictionary=w.people[heir]
	var shares: int=actor.shares[issuer]
	var cash: int=actor.wallet
	var original: int=person.wallet
	var spouse_cash: int=spouse.wallet
	check(own>0 and w.ships[own].owner==actor.id and w.ships[charter].owner==0 and w.Politics.heirs(w,actor.id).front()==heir,"the actual household's eligible beneficiary is identified before the owner dies")
	w.Politics.die(w,actor.id,false)
	check(person.wallet==original+cash and actor.wallet==0 and person.shares.get(issuer,0)==shares and actor.shares.is_empty(),"cash and all corporate votes transfer to the beneficiary's real accounts")
	check(w.StationEquity.cap_table(w,site).people.get(heir,0)==7 and not site.equity.people.has(actor.id) and site.owner==neighbour and w.ships[own].owner==heir and w.ships[charter].owner==0,"the private station stake and personally purchased ship pass along, preserving unrelated station and charter property")
	check(w.active().ship==own and w.ride().get("id",0)==own,"the successor boards the inherited owned ship as flagship")
	if child_id==0:
		check(w.player==spouse.id and spouse.spouse==0 and not spouse.noble,"the widowed ordinary spouse continues as the active character")
	else:
		check(spouse.wallet==spouse_cash and not spouse.shares.has(issuer) and (w.player==child_id or w.regency==child_id) and not person.noble,"the child's estate takes precedence over the surviving spouse's personal holdings and status")
	var restored:=World.new()
	check(restored.load_state(w.snapshot()) and restored.ports[site.id].equity.people.get(heir,0)==7 and restored.people[heir].shares.get(issuer,0)==shares and restored.ships[own].owner==heir,"family and property succession are preserved by an actual save and load")

func _initialize() -> void:
	var household:=new_family("civil-household")
	var w=household.w
	var actor: Dictionary=household.actor
	var spouse: Dictionary=household.other
	var rival: int=w.random_person(w.NEUTRAL,actor.loc,"烟池",1)
	var home: int=spouse.loc
	spouse.birth=w.day-17*360
	check(not w.Politics.marriage_terms(w,actor.id,spouse.id).eligible and not w.Politics.marry(w,actor.id,spouse.id),"a minor cannot consent to marriage")
	spouse.birth=w.day-25*360
	spouse.loc=w.factions[0].capital
	check(not w.Politics.marriage_terms(w,actor.id,spouse.id).eligible and not w.Politics.marry(w,actor.id,spouse.id),"the ordinary couple must actually meet in the same port")
	spouse.loc=home
	var common_parent: int=w.random_person(w.NEUTRAL,home)
	actor.parents.append(common_parent)
	spouse.parents.append(common_parent)
	check(not w.Politics.marriage_terms(w,actor.id,spouse.id).eligible and not w.Politics.marry(w,spouse.id,actor.id),"a sibling relationship rules out both proposal directions")
	actor.parents.clear()
	spouse.parents.clear()
	spouse.opinions[actor.id]=-100
	var direct: Dictionary=w.Politics.marriage_terms(w,actor.id,spouse.id)
	var reversed: Dictionary=w.Politics.marriage_terms(w,spouse.id,actor.id)
	check(direct.eligible and not direct.accepted and not reversed.accepted and not reversed.reason.is_empty() and not w.Politics.marry(w,spouse.id,actor.id) and actor.spouse==0,"reversing the people never substitutes the player's approval for a rejecting partner's decision")
	actor.opinions[spouse.id]=-100
	spouse.opinions[actor.id]=90
	reversed=w.Politics.marriage_terms(w,spouse.id,actor.id)
	if check(reversed.eligible and reversed.accepted and not reversed.dynastic and w.Politics.marry(w,spouse.id,actor.id) and actor.spouse==spouse.id and spouse.spouse==actor.id and not actor.noble and not spouse.noble,"two ordinary residents can consent at the same port, with the true recipient deciding in either API order"):
		check(not w.Politics.marriage_terms(w,actor.id,rival).eligible and not w.Politics.marry(w,actor.id,rival),"an existing marriage prevents a second wedding")
		inheritance(w,actor,spouse)
	var mixed:=new_family("mixed-household",true)
	var pre_relations: Dictionary=mixed.w.relations.duplicate(true)
	var mixed_terms: Dictionary=mixed.w.Politics.marriage_terms(mixed.w,mixed.actor.id,mixed.other.id)
	check(mixed_terms.eligible and mixed_terms.accepted and not mixed_terms.dynastic and mixed.w.Politics.marry(mixed.w,mixed.actor.id,mixed.other.id) and not mixed.actor.noble and mixed.other.noble and mixed.w.relations==pre_relations,"a noble and a commoner can voluntarily marry without promoting the commoner or creating a diplomatic alliance")
	var family:=new_family("ordinary-birth")
	w=family.w
	actor=family.actor
	spouse=family.other
	if check(w.Politics.marry(w,actor.id,spouse.id),"the second ordinary household is registered at the public port"):
		spouse.employer=actor.id
		for month in 144:
			w.day+=29-(int(w.day)%30)
			w.tick()
			if not actor.children.is_empty():
				break
		if check(not actor.children.is_empty(),"the normal monthly simulation produces an ordinary player's child"):
			var child_id:int=actor.children.front()
			var child: Dictionary=w.people[child_id]
			check(child_id in spouse.children and actor.id in child.parents and spouse.id in child.parents and not child.noble and child.alive,"birth records both parents and keeps a two-commoner household's child a commoner")
			inheritance(w,actor,spouse,child_id)
	print("Ordinary households and inheritance %d/%d" % [checks-errors,checks])
	quit(1 if errors else 0)
