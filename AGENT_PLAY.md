# 用 Agent 玩《星轨遗产》

游戏新增可选的本地 JSON 操控接口。**Agent 自己选择目标、路线和打法**；接口只负责观察与执行，不内置代玩策略。游戏进程默认无窗口，可用 `-Watch` 打开旁观窗口。普通双击启动不监听命令。代理模式不读写普通存档，退出后该局不保留。

## Windows 启动

```powershell
$session = Join-Path $env:TEMP ('starrail-agent-' + [Guid]::NewGuid().ToString('N'))
.\agent_client.ps1 -Start -Session $session
.\agent_client.ps1 -Session $session -Action new_game -Json '{"seed":"巡航-01","name":"航务代理"}'
.\agent_client.ps1 -Session $session -Action observe
```

若使用旁观窗口，在第一条客户端命令加 `-Watch`；想用其他路径的 EXE 则传 `-Game`。请从工程目录运行；如果从试玩 ZIP 解压运行，客户端会自动使用同目录的 EXE。

## 让 Agent 飞一趟

把命令表和玩家任务交给具备终端工具的 Agent。例如：「用观察结果决定下一步。接首航委托，按引力点规则飞到第 02 星系，买 8 矿石送到炉心转运站，交付后报余额。」无须截图或联网。

| 命令 | `args` / 行为 |
|---|---|
| `observe` | 不推进时间；返回人物、任务、舰船/舰队、港口、可见敌舰、航点、引力点或附近信标 |
| `new_game` | `seed`、`name`、`noble` 可选；也可传 `systems` 和 `factions` |
| `waypoint` | `kind` 为 `gravity` / `mine` / `port` / `system` / `point`；港口和星系要带观察所得 `target` ID，坐标航点带 `pos:[x,y]` |
| `step` | 按 60Hz 推进 1–1800 个 `ticks`，结束自动暂停；可传 `move:[x,y]`、`aim:[x,y]`、`target`（可见敌舰）、`fire:true`、`shield:true`；`stop` 为 `encounter`（默认）、`arrival` 或 `never`；自动驾驶和停泊可传 `speed:1–5` |
| `depart`、`dock`、`jump` | 走正常规则；`jump` 只在引力点或目的星系信标附近成功 |
| `mine_or_salvage`、`repair`、`refuel` | 相当于采掘/勘测及港口服务 |
| `trade` | `ware` 由 `state.wares` 的 0 基下标确定；`amount` 正买负卖；`black:true` 走黑市规则 |
| `accept_first_job`、`deliver_first_job`、`claim_return_bonus` | 首航委托接单、交矿、返程津贴 |
| `buy_ship`、`assign_escort` | `model` 为 `state.ship_catalog` 的 0 基下标；任命时传 `ship` 和同港 `captain` ID |
| `group`、`system`、`vent` | 编组 `group:1–3`，可带 `toggle_auto:true`；其余对应主动系统、排散 |
| `order`、`auto_battle` | `order:0/1/2/3` 对应自由交战/护卫/集火/撤退，集火须带敌舰 `target`；自动结算仍有原有限制 |
| `choose_successor`、`quit` | 继任人选择时传 `id`；退出该代理会话 |

自动航行示例（先设航点，再推进）；不能把 `waypoint` 当成瞬移：

```powershell
.\agent_client.ps1 -Session $session -Action depart
.\agent_client.ps1 -Session $session -Action waypoint -Json '{"kind":"gravity"}'
.\agent_client.ps1 -Session $session -Action step -Json '{"ticks":1200,"speed":3,"stop":"arrival"}'
.\agent_client.ps1 -Session $session -Action jump
```

有交火或重大事件时，先观察状态再决定是否继续步进；不能盲发同一个买卖/交付指令。协议没有任意执行脚本、文件访问或存档编辑接口。

## 给其他语言接入

传空的私有绝对目录，启动参数为 `--headless -- --agent-dir=<绝对路径>`（旁观时去掉 `--headless`）。等待 `ready.json`。将 UTF-8 JSON `{"id":"唯一请求ID","action":"observe","args":{}}` 写到临时文件，再在同目录原子更名为 `request.json`；读取 `response.json`，核对 `id` 后删除响应，才发下一条。一次一个请求；不提供网络监听。**不要把该目录共享给不可信程序。** 超时不代表动作未执行；检查是否已有回执，不要盲目重试。

## 验证

在工程目录执行 `verify_agent.ps1`，它启动导出的 EXE，用实际桥接指令跑两次同种子跨星系交付和一次实时舰战。回归不读写真实玩家存档。
