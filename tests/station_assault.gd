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
	flagship.pos = site.pos + Vector2(151,0)
	rejected(remote_id,false,"the 150-unit local range still applies")
	flagship.pos = site.pos + Vector2(150,0)
	game.refresh()
	var marker := button(game.body,"远港")
	var actions := marker.get_parent().get_child(marker.get_index()+1) if marker != null else null
	var declare: Button = button(actions,"宣战 / 强占") if actions != null else null
	check(declare != null and not declare.disabled,"the normal port controls expose a genuinely local target")
	if declare != null: declare.pressed.emit()
	check(world.hostile(1,0) and site.owner == 0,"the first local action declares war without granting ownership")
	game.hud.attack(remote_id)
	check(site.owner == actor.id and site.flag == 1,"the local flagship takes the hostile station on the next action")
	rejected(remote_id,false,"a stale action on an already captured target has no side effects")
	game.hud.attack(remote_id,false,true)
	check(site.defense == 0 and site.owner == actor.id,"an explicit attack on the owner's station damages its defenses and preserves title")
	rejected(0,false,"a missing station cannot be targeted")
	var contract_id: int = world.port(4,"合同港",site.pos+Vector2(10000,0),0,0,0)
	var contract: Dictionary = world.ports[contract_id]
	actor.flag = world.NEUTRAL
	flagship.flag = world.NEUTRAL
	flagship.pos = contract.pos
	var blocker: int = world.ship(flagship.kind,0,0,0,4,contract.pos)
	game.hud.attack(contract_id,true)
	check(contract.flag == 0 and flagship.raid == 0,"a neutral raid still draws a real local defender before conquest")
	world.ships[blocker].layer = true
	var credits: int = actor.wallet
	game.hud.attack(contract_id,true)
	check(contract.flag == 1 and actor.wallet == credits + 280,"a local mercenary takes the station for its employer, while a defender in hyperspace cannot block the assault")
	game.free()
	print("Local and remote station assault %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
