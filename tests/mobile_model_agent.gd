extends SceneTree

const Game = preload("res://game.tscn")
const Bridge = preload("res://agent_bridge.gd")
const Agent = preload("res://scripts/services/mobile_model_agent.gd")
var passed := 0
var failed := 0

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL ",message)

func model_reply(agent, message: Dictionary, code := 200) -> void:
	var body := JSON.stringify({"choices":[{"message":message}]}).to_utf8_buffer()
	agent._on_model_reply(HTTPRequest.RESULT_SUCCESS,code,PackedStringArray(),body)

func call_tool(name_: String, id: String, args: Dictionary) -> Dictionary:
	return {"id":id,"type":"function","function":{"name":name_,"arguments":JSON.stringify(args)}}

func run() -> void:
	var game = Game.instantiate()
	game.mobile_play = true
	game.test_profile = true
	root.add_child(game)
	game.world.new_game({"seed":"model-command-receipts","systems":12,"factions":3})
	game.run_bridge()
	game.set_physics_process(false)
	var human := int(game.world.player)
	var home := int(game.world.active().loc)
	var agent_port: int = game.world.systems[1].ports[0]
	var actor: int = game.world.random_person(game.world.NEUTRAL,agent_port)
	var port: Dictionary = game.world.ports[agent_port]
	var id: int = game.world.ship(0,actor,actor,game.world.NEUTRAL,port.system,port.pos,agent_port)
	game.world.people[actor].wallet = 2400
	var bridge := Bridge.new()
	bridge.game = game
	bridge.bound_actor_id = actor
	var temp := OS.get_temp_dir().path_join("starrail-mobile-model-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(temp)
	check(bridge.start(temp),"open isolated bridge")
	var cfg := {"api_base":"http://127.0.0.1:1/v1","model":"fixture","max_steps":1}
	check(Agent.config_issue(cfg).is_empty() and not Agent.config_issue({"api_base":"", "model":""}).is_empty(),"validate endpoint and model")
	var agent = game.start_mobile_runner(bridge,cfg)
	agent.set_process(false)
	var cash: int = game.world.people[actor].wallet
	var personal: int = game.world.active().wallet
	var calls := [call_tool("observe","one",{}),call_tool("game_action","two",{"action":"trade","args_json":JSON.stringify({"ware":0,"amount":1})})]
	model_reply(agent,{"content":null,"tool_calls":calls})
	agent.suspended = true
	agent._process(0)
	check(not FileAccess.file_exists(temp.path_join("request.json")),"background model completion cannot dispatch an action")
	agent.suspended = false
	for expected in ["one","two"]:
		agent._process(0)
		bridge.poll(1.0)
		agent._process(0)
		var result: Dictionary = JSON.parse_string(agent.turn.back().content)
		check(agent.turn.back().tool_call_id == expected and result.ok and result.state.actor.id == actor,"each model tool receives its own actor's actual receipt")
	agent._process(0)
	check(not agent.running and game.world.ships[id].cargo[0] > 0 and game.world.people[actor].wallet < cash,"buy settles before round limit stops the model")
	check(game.world.player == human and game.world.active().wallet == personal and game.dock_view.station_id == home,"arena transactions preserve the human account and port screen")
	agent.free()

	agent = game.start_mobile_runner(bridge,cfg)
	agent.set_process(false)
	model_reply(agent,{},401)
	agent._process(0)
	check(not agent.running and "401" in agent.final_message,"authentication errors stop with an actionable reason")
	agent.free()

	var multi_cfg := {"api_base":"http://127.0.0.1:1/v1","model":"fixture","max_steps":0}
	agent = game.start_mobile_runner(bridge,multi_cfg)
	agent.set_process(false)
	model_reply(agent,{"content":"先规划一下下一步操作。","tool_calls":[]})
	check(agent.final_message.is_empty() and agent.text_retries == 1 and agent.turn.size() == 2,"first text-only reply nudges the model instead of stopping")
	model_reply(agent,{"content":null,"tool_calls":[{"id":"dict_arg","type":"function","function":{"name":"observe","arguments":{}}}]})
	check(agent.text_retries == 0 and agent.pending.size() == 1 and agent.turn[0].content == "","tool call resets text retries and normalizes null content")
	agent._process(0)
	bridge.poll(1.0)
	agent._process(0)
	var dict_res: Dictionary = JSON.parse_string(agent.turn.back().content)
	check(dict_res.ok,"empty dictionary arguments execute cleanly")
	for _i in range(Agent.MAX_TEXT_RETRIES + 1):
		model_reply(agent,{"content":"任务已完成。","tool_calls":[]})
	agent._process(0)
	check(not agent.running and agent.final_message == "任务已完成。","repeated text-only replies finish cleanly")
	agent.free()

	agent = game.start_mobile_runner(bridge,cfg)
	agent.set_process(false)
	var err_body := JSON.stringify({"error":{"message":"invalid model name"}}).to_utf8_buffer()
	agent._on_model_reply(HTTPRequest.RESULT_SUCCESS,400,PackedStringArray(),err_body)
	agent._process(0)
	check(not agent.running and "400" in agent.final_message and "invalid model name" in agent.final_message,"HTTP errors surface server error message")
	agent.free()
	agent = game.start_mobile_runner(bridge,cfg)
	agent.stop()
	model_reply(agent,{"tool_calls":calls})
	check(not agent.running and agent.pending.is_empty(),"stopped agent ignores late completions")
	agent.free()
	for file in DirAccess.get_files_at(temp):
		DirAccess.remove_absolute(temp.path_join(file))
	DirAccess.remove_absolute(temp)
	game.free()
	print("Mobile model control %d/%d" % [passed,passed+failed])
	quit(1 if failed else 0)

func _initialize() -> void:
	run.call_deferred()
