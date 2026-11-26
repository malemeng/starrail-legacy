extends SceneTree

const Game = preload("res://game.tscn")
var game
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func button(body: Node, prefix: String) -> Button:
	for control: Button in body.find_children("*","Button",true,false):
		if control.text.begins_with(prefix):
			return control
	return null

func rejected(port_id: int, mercenary: bool, message: String) -> void:
	var before := var_to_bytes(game.world.snapshot())
	game.hud.attack(port_id,mercenary)
	check(before == var_to_bytes(game.world.snapshot()),message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	var world = game.world
	world.new_game({"seed":"remote-orders","systems":12,"factions":3})
	game.run_bridge()
	game.set_physics_process(false)
	var flagship: Dictionary = world.ride()
	var actor: Dictionary = world.active()
	var remote_id: int = world.port(4,"远港",Vector2(81000,41000),0,0,0)
	var site: Dictionary = world.ports[remote_id]
	var scout: int = world.ship(flagship.kind,actor.id,0,world.NEUTRAL,site.system,site.pos,remote_id)
	world.depart(flagship)
	flagship.pos = site.pos
	game.refresh()
	button(game.tabs,"资产").pressed.emit()
	button(game.body,"观察视角").pressed.emit()
	button(game.tabs,"港口").pressed.emit()
	check(game.watch_ship_id == scout and game.current_system() == 4 and flagship.system == 0,"the port panel actually observes another owned ship in system four while the flagship stays in system zero")
	check(button(game.body,"远港") != null and button(game.body,"宣战 / 强占") == null and button(game.body,"替雇主夺站") == null,"a neutral observer can see the remote harbour but neither capture action")
	world.set_treaty(1,0,-1)
	rejected(remote_id,true,"an old mercenary action cannot pay a bounty, consume hull, or transfer a remote port")
	actor.flag = 1
	flagship.flag = 1
	world.set_treaty(1,0,0)
	rejected(remote_id,false,"remote observation cannot declare war even when local coordinates coincide")
	game.watch_button.pressed.emit()
	rejected(remote_id,false,"an unseen remote station remains unreachable from the flagship view")
	flagship.system = site.system
	flagship.layer = true
	rejected(remote_id,false,"matching star system in hyperspace cannot attack a local station")
	flagship.layer = false
	flagship.dock = remote_id
	rejected(remote_id,false,"a docked flagship cannot assault")
	flagship.dock = 0
	flagship.pos = site.pos + Vector2(1801,0)
	rejected(remote_id,false,"a ship outside the assault perimeter cannot start the attack")
	flagship.pos = site.pos + Vector2(1450,0)
	game.refresh()
	var marker := button(game.body,"远港")
	var actions := marker.get_parent().get_child(marker.get_index()+1) if marker != null else null
	var declare: Button = button(actions,"宣战 / 强占") if actions != null else null
	check(declare != null and not declare.disabled,"the normal port controls expose a genuinely local target")
	if declare != null: declare.pressed.emit()
	check(world.hostile(1,0) and site.owner == 0,"the first local action declares war without granting ownership")
	game.hud.attack(remote_id)
	check(site.flag == 0 and not site.assault.nodes.is_empty(),"repeat clicks cannot take a defended station")
	for sid in site.assault.nodes.duplicate():
		world.destruction(sid,actor.id)
	rejected(remote_id,false,"even a defeated garrison cannot be annexed remotely")
	flagship.pos = site.pos + Vector2(140,0)
	game.hud.attack(remote_id)
	check(site.flag == 1 and site.owner == 0 and site.occupied_from == 0 and world.treaty(1,0).occupied.has(remote_id),"war ledger records the occupation before title changes")
	rejected(remote_id,false,"a stale action on an already captured target has no side effects")
	rejected(0,false,"a missing station cannot be targeted")
	var contract_id: int = world.port(4,"合同港",site.pos+Vector2(10000,0),0,0,0)
	var contract: Dictionary = world.ports[contract_id]
	actor.flag = world.NEUTRAL
	flagship.flag = world.NEUTRAL
	flagship.pos = contract.pos
	var blocker: int = world.ship(flagship.kind,0,0,0,4,contract.pos)
	world.ships[blocker].job = {"kind":"护航","system":4}
	var guard_cap: int = world.random_person(0,contract_id)
	world.ships[blocker].captain = guard_cap
	world.people[guard_cap].ship = blocker
	game.hud.attack(contract_id,true)
	check(contract.flag == 0 and world.enemy(flagship,world.ships[blocker]) and not contract.assault.nodes.is_empty(),"a neutral mercenary faces station weapons and the local guard")
	for sid in contract.assault.nodes.duplicate():
		world.destruction(sid,actor.id)
	game.hud.attack(contract_id,true)
	check(contract.flag == 0,"a remaining guard prevents surrender")
	world.ships[blocker].layer = true
	var credits: int = actor.wallet
	game.hud.attack(contract_id,true)
	check(contract.flag == 1 and contract.occupied_from == 0 and actor.wallet == credits + 280,"a mercenary occupies for the employer and earns one bounty")
	game.hud.attack(contract_id,true)
	check(actor.wallet == credits + 280,"a repeated claim pays no second bounty")
	game.free()
	print("Local and remote station assault %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
