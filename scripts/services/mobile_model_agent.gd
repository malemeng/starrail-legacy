extends Node

signal finished(message: String)

const ACTIONS := ["market_quote","trade","navigate_to_station","step","wait","supply_fleet","ship_quote","buy_ship","set_default_behavior","assign_ship","debug_ship","incorporate_station","incorporate_ship","contribute_ship","freight_offer","accept_freight","deliver_freight","accept_first_job","deliver_first_job","claim_return_bonus","buyout_charter","set_intent","start_pretext","declare_company_war","sign_company_peace","board_liner","disembark_liner","assign_passenger_liner","assign_contractor"]
const FLIGHT_ACTIONS := ["depart","dock","waypoint","jump","mine_or_salvage","repair","refuel","sensor_ping","attack_target","assault_station","autopilot","order","group","system","field_repair","hire_builder","cancel_builder","deploy_station","donate_materials","found_planet_port"]
const PROMPT := "你正在操控《星轨遗产》的一名船长。根据目标和最新游戏状态选择工具。货物编号按 wares 的下标，舰船和港口编号从观测读取。通过 market_quote 和 trade 使用 ware、amount（正买负卖）。navigate_to_station 使用 port_id、auto_dock；step 使用 ticks(1-1800)、speed(1-5)、stop(arrival)。wait 使用 days(1-180)。先核实成交和靠港结果，再作下一步。可以连续调用工具；目标达成时用简短中文总结结束托管。"

const MAX_TEXT_RETRIES := 2
const PORT_ACTIONS := ["disembark","pilot_ship","hire_captain","buy_station_ship","station_armament","refit_station_module"]

var bridge
var http := HTTPRequest.new()
var endpoint := ""
var api_key := ""
var model := ""
var objective := ""
var tools: Array = []
var history: Array = []
var turn: Array = []
var pending: Array = []
var request_id := ""
var call_id := ""
var round_limit := 0
var rounds := 0
var text_retries := 0
var busy := false
var running := false
var suspended := false
var final_message := ""
var request_time := 0

static func config_issue(cfg: Dictionary) -> String:
	var url := str(cfg.get("api_base","")).strip_edges()
	if not (url.begins_with("https://") or url.begins_with("http://")) or url.get_slice("://",1).get_slice("/",0).is_empty():
		return "请输入模型服务的 HTTP 或 HTTPS 地址。"
	if str(cfg.get("model","")).strip_edges().is_empty():
		return "请输入模型名称。"
	return ""

static func tool_spec(name_: String, description: String, props: Dictionary = {}, required: Array = []) -> Dictionary:
	return {"type":"function","function":{"name":name_,"description":description,"parameters":{"type":"object","properties":props,"required":required}}}

func start(session, cfg: Dictionary, rivals: String = "") -> void:
	bridge = session
	endpoint = str(cfg.api_base).strip_edges().trim_suffix("/")
	if not endpoint.ends_with("/chat/completions"):
		endpoint += "/chat/completions"
	model = str(cfg.model).strip_edges()
	api_key = str(cfg.get("api_key","")).strip_edges()
	round_limit = maxi(0,int(cfg.get("max_steps",0)))
	rounds = maxi(0,int(cfg.get("rounds_used",0)))
	objective = str(cfg.get("goal","")).strip_edges()
	if objective.is_empty():
		objective = "观察当前局势，自主经营舰队。"
	if not rivals.is_empty():
		objective += "\n"+rivals
	objective += "\n先调用 observe 读取当前角色的实际状态。"
	objective += "\n靠港离开旗舰用 disembark。按 passenger_liners 的报价用 board_liner（ship、dest、fare）购票；passenger_trip 显示在途状态，wait 可等到下船。fleet 是舰队，contacts 是同港人员。debug_ship 查 ship；若自有船缺船长，可用 hire_captain（ship）。assign_passenger_liner（ship，可选 route 港口 ID 数组）和 assign_contractor（ship，可选 home_port）分别经营客运和派工程舰。玩家允许作弊时可用 cheat（kind 和可选 amount），例如 credits 加信用点。"
	if bridge.bound_actor_id != 0:
		objective += "\n你是竞技场角色。跨港请用 navigate_to_station，再用 wait 推进所需天数及 step 确认抵达。"
	tools = [tool_spec("observe","查看当前船长、账户、舰船、港口和任务。"),
		tool_spec("trade_opportunities","查看当前已发现航线的贸易机会。"),
		tool_spec("game_action","执行一个游戏指令。args_json 是 JSON 对象字符串，例如 {\"ware\":0,\"amount\":1}。",{"action":{"type":"string","enum":allowed_actions()},"args_json":{"type":"string"}},["action","args_json"])]
	http.timeout = 120.0
	http.body_size_limit = 1048576
	http.max_redirects = 3
	add_child(http)
	http.request_completed.connect(_on_model_reply)
	running = true
	status("正在连接模型 "+model)

func status(message: String) -> void:
	if bridge != null:
		bridge.publish("thought.json",{"thought":message.left(260)})

func stop() -> void:
	running = false
	if http.is_inside_tree():
		http.cancel_request()
	api_key = ""
	set_process(false)

func finish(message: String) -> void:
	status(message)
	stop()
	finished.emit(message)

func _process(_delta: float) -> void:
	if not running or suspended or busy:
		return
	if bridge.game.world.succession or (bridge.bound_actor_id != 0 and not bridge.game.world.people.get(bridge.bound_actor_id,{}).get("alive",false)):
		finish("角色交接，托管已结束。")
	elif not request_id.is_empty():
		read_receipt()
	elif not pending.is_empty():
		run_tool(pending.pop_front())
	elif not final_message.is_empty():
		finish(final_message)
	elif round_limit > 0 and rounds >= round_limit:
		finish("已完成 %d 轮模型决策。" % rounds)
	else:
		ask_model()

func allowed_actions() -> Array:
	var allowed := ACTIONS.duplicate()
	allowed.append_array(PORT_ACTIONS)
	if bridge.bound_actor_id == 0:
		allowed.append_array(FLIGHT_ACTIONS)
	if bridge.allow_cheats:
		allowed.append("cheat")
	return allowed

func ask_model() -> void:
	tools[2].function.parameters.properties.action.enum = allowed_actions()
	if not turn.is_empty():
		history.append(turn)
		turn = []
		while history.size() > 1 and (history.size() > 4 or JSON.stringify(history).length() > 26000):
			history.pop_front()
	var messages := [{"role":"system","content":PROMPT},{"role":"user","content":objective}]
	for prior in history:
		messages.append_array(prior)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not api_key.is_empty():
		headers.append("Authorization: Bearer "+api_key)
	var data := {"model":model,"messages":messages,"tools":tools,"stream":false}
	busy = true
	var err := http.request(endpoint,headers,HTTPClient.METHOD_POST,JSON.stringify(data))
	if err != OK:
		finish("连接模型失败，请检查服务地址。")

static func _extract_error_detail(body: PackedByteArray) -> String:
	var text := body.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var err: Variant = parsed.get("error")
		if err is Dictionary and err.get("message") is String:
			return str(err.message).strip_edges().left(140)
		if parsed.get("message") is String:
			return str(parsed.message).strip_edges().left(140)
	return text.left(140)

static func _parse_args_dict(raw: Variant) -> Variant:
	if raw is Dictionary:
		return raw
	if raw is String:
		var trimmed := str(raw).strip_edges()
		if trimmed.is_empty():
			return {}
		return JSON.parse_string(trimmed)
	return null

func _on_model_reply(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not running:
		return
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var detail := _extract_error_detail(body)
		match code:
			401,403: final_message = "模型服务拒绝访问（HTTP %d），请检查 API Key 和模型权限。" % code
			404: final_message = "模型接口不存在（HTTP 404），请检查地址和模型名。"
			429: final_message = "模型服务限流或额度不足（HTTP 429）。"
			_: final_message = "模型请求失败（HTTP %d，网络状态 %d）。请检查网络和服务地址。" % [code,result]
		if not detail.is_empty():
			final_message += " " + detail
		return
	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not payload is Dictionary or not payload.get("choices") is Array or payload.choices.is_empty() or not payload.choices[0] is Dictionary or not payload.choices[0].get("message") is Dictionary:
		final_message = "模型返回了无法识别的 Chat Completions 响应。"
		return
	rounds += 1
	var message: Dictionary = payload.choices[0].message
	var content := str(message.content) if message.get("content") is String else ""
	var calls: Variant = message.get("tool_calls",[])
	if calls == null or (calls is Array and calls.is_empty()):
		if text_retries < MAX_TEXT_RETRIES and (round_limit <= 0 or rounds < round_limit):
			text_retries += 1
			if not content.is_empty():
				status(content)
			turn = [
				{"role":"assistant","content":content},
				{"role":"user","content":"请直接调用工具执行下一步操作，不要只输出文字计划；如果目标已全部完成，请再次总结结束。"}
			]
			return
		final_message = content.left(260) if not content.is_empty() else "模型结束了本次托管。"
		return
	if not calls is Array or calls.size() > 16:
		final_message = "模型返回了无效的工具调用列表。"
		return
	var ids := {}
	for item in calls:
		if not item is Dictionary or not item.get("id") is String or item.id.is_empty() or ids.has(item.id) or not item.get("function") is Dictionary or not item.function.get("name") is String:
			final_message = "模型返回了无效的工具调用。"
			return
		var raw_args: Variant = item.function.get("arguments","")
		if not (raw_args is String or raw_args is Dictionary or raw_args == null):
			final_message = "模型返回了无效的工具调用。"
			return
		ids[item.id] = true
	text_retries = 0
	turn = [{"role":"assistant","content":content,"tool_calls":calls}]
	if message.get("reasoning_content") is String:
		turn[0].reasoning_content = message.reasoning_content
	pending = calls.duplicate()
	if not content.is_empty():
		status(content)

func run_tool(item: Dictionary) -> void:
	call_id = item.id
	var action: String = item.function.name
	var args: Variant = _parse_args_dict(item.function.get("arguments",""))
	if action == "game_action" and args is Dictionary:
		action = str(args.get("action",""))
		args = _parse_args_dict(args.get("args_json","{}"))
		if action == "cheat" and not bridge.allow_cheats:
			append_result({"ok":false,"error":"cheats_disabled_by_player"})
			return
		if action not in allowed_actions():
			append_result({"ok":false,"error":"unknown_action"})
			return
	elif action not in ["observe","trade_opportunities"]:
		append_result({"ok":false,"error":"unknown_tool"})
		return
	if not args is Dictionary:
		append_result({"ok":false,"error":"invalid_arguments"})
		return
	request_id = "%d-%d-%d" % [get_instance_id(),rounds,turn.size()]
	var request := {"id":request_id,"action":action,"args":args}
	if JSON.stringify(request).to_utf8_buffer().size() > bridge.MAX_BYTES:
		request_id = ""
		append_result({"ok":false,"error":"arguments_too_large"})
		return
	request_time = Time.get_ticks_msec()
	status("第 %d 轮 · %s" % [rounds,action])
	if not bridge.publish("request.json",request):
		finish("游戏指令写入失败。")

func read_receipt() -> void:
	var path: String = bridge.directory.path_join("response.json")
	if not FileAccess.file_exists(path):
		if Time.get_ticks_msec()-request_time > 120000 and bridge.active_step.is_empty():
			finish("等待游戏回执超时。")
		return
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(path)
	if not receipt is Dictionary or receipt.get("id","") != request_id:
		finish("游戏回执与当前指令不匹配。")
		return
	request_id = ""
	append_result(compact_receipt(receipt))

func append_result(result: Dictionary) -> void:
	turn.append({"role":"tool","tool_call_id":call_id,"content":JSON.stringify(result)})

static func compact_receipt(receipt: Dictionary) -> Dictionary:
	var compact := {"ok":receipt.get("ok",false)}
	for key in ["error","detail","result"]:
		if receipt.has(key):
			compact[key] = receipt[key]
	var state: Dictionary = receipt.get("state",{})
	var view := {}
	for key in ["day","screen","actor","system","targets","objective","notice","wares","waypoint","beacons","jump_allowed","contract","passenger_liners","passenger_trip","managed_ports","allow_cheats"]:
		if state.has(key):
			view[key] = state[key]
	if view.has("system"):
		view.system = {"id":view.system.id,"name":view.system.name}
	view.ship = fields(state.get("ship",{}),["id","hull_id","model","owner","firm","pos","dock","hp","fuel","crew","cargo","free_cargo","locked","shield","group","autopilot"])
	view.fleet = []
	for ship: Dictionary in state.get("fleet",[]):
		var item := fields(ship,["id","hull_id","model","captain","captain_name","owner","firm","station_owner","dock","system","engineering","can_dispatch","charter"])
		item.job = fields(ship.get("job",{}),["kind","home_port","route","site","fee"])
		view.fleet.append(item)
	view.contacts = []
	for person: Dictionary in state.get("contacts",[]):
		view.contacts.append(fields(person,["id","name","roles","age","ship","employer"]))
	view.ports = []
	for port in state.get("ports",[]).slice(0,12):
		view.ports.append(fields(port,["id","name","pos","hostile","construction_days","stock","buy","sell","operator","occupied_from","defense_targets"]))
	for key in ["targets","beacons"]:
		if view.has(key):
			view[key] = view[key].slice(0,12)
	compact.state = view
	if JSON.stringify(compact.get("result",{})).length() > 7000:
		compact.result = {"summary":JSON.stringify(compact.result).left(6900),"truncated":true}
	return compact

static func fields(row: Dictionary, keys: Array) -> Dictionary:
	var out := {}
	for key in keys:
		if row.has(key):
			out[key] = row[key]
	return out
