# 用 Agent 玩《星轨遗产》

游戏新增可选的本地 JSON 操控接口。**Agent 自己选择目标、路线和打法**；接口只负责观察与执行，不内置代玩策略。游戏进程默认无窗口，可用 `-Watch` 打开旁观窗口。普通双击启动不监听命令。代理模式不读写普通存档，退出后该局不保留。

平民旗舰的 `ship.charter` 含买断价、登记港及当前可否成交。到港后用 `buyout_charter` 传入 `ship`（舰船 ID）购买产权。`organizations` 给出海盗及教团的星系和据点坐标，敌舰观测中的 `organization` 标明所属组织。`system.planets` 为当前星系实际生成的天体及其勘测状态。

靠港时 `ship_quote` 接受 `hull_id`，返回本站配方、物料总价、工时与最终售价。`ship_catalog[].price` 为目录参考价，`ports[].hull_prices` 为本站在售库存的实际价格。`buy_ship` 和 `buyout_charter` 支持传入 `expected_price`，报价改变时交易会退回。飞行中可调用 `sensor_ping` 扩大接触范围，自舰也更容易暴露。

## 安卓模型托管

安卓模型可从 `state.fleet` 按船号查询舰型、船长、任务、所在港和调度权，从 `state.contacts` 查看同港人员。舰长靠港后用 `disembark` 离舰，然后按 `passenger_liners` 报价购票。途中 `state.passenger_trip` 显示客船、目的港和当前停靠港；`wait` 会在下船时返回。站长可将站属船派作客运，具备建站能力的船可承接工程。自有或站属船缺船长时，`hire_captain` 传 `ship` 可花 ¢85 招募。

单人托管配置和观战面板都有「允许 Agent 作弊」。玩家打开后模型可调用 `cheat`，例如 `{"kind":"credits","amount":1000}`，关闭后立即停止接受作弊指令。玩家自己使用时间控制栏的「作弊」按钮。

在安卓横屏版进入航程，点顶栏「托管」，填写支持工具调用的 Chat Completions 服务地址、模型名称和 API Key。填入经营目标后点「启动全流程托管」。手机会把目标、游戏观测和指令结果发送到你配置的服务。完成目标或达到轮数上限后会恢复手动操作，你也可以点「托管: 开」随时接手。

本地模型运行在电脑上时，手机应填电脑的局域网地址，例如 `http://192.168.1.20:11434/v1`，并确认手机能访问该端口。模型运行在手机本机时才使用 `localhost`。多 Agent 竞技场通过顶栏「竞技场」启动，每个槽位可以选用已保存的模型预设。

## Windows 启动

单人托管可用 `assault_station` 传入 `port` 发起攻站。旗舰须离港并进入同星系目标站的 1,800 距离内。回执的 `defense_targets` 是武装模块 ID，可用 `attack_target`、`order` 和 `step` 指挥实战。守方机库按联队作战半径派出战机。击退模块武备和守舰后，在泊位 150 距离内再次调用同一操作接收投降。中立身份进攻独立企业会以实际交战方登记企业资产战争。

靠港用 `station_armament` 查看每个模块的独立护盾和挂点。传 `module`（0 为指挥核心）查看挂点的类型、尺寸和现装武器，再传 `slot` 查看当地可装的舰船武器 ID。管理者用 `refit_station_module` 传 `port`、`module`、`slot`、`weapon` 执行换装，空武器 ID 表示拆卸；可传 `expected_current` 核对旧武器。换装费用由当前角色支付。

要让游戏自带的 Agent 接管当前航程，完整解压 Windows 发行包，进入游戏后点顶栏「托管」，填入支持工具调用的模型服务地址、模型名及该服务需要的 API Key。单人托管和多 Agent 竞技场共用 `tools/agent-runtime` 内的 Python 和 smolagents，无需另装 Python。使用本地模型时，请先启动模型服务。

```powershell
$session = Join-Path $env:TEMP ('starrail-agent-' + [Guid]::NewGuid().ToString('N'))
.\agent_client.ps1 -Start -Session $session
.\agent_client.ps1 -Session $session -Action new_game -Json '{"seed":"巡航-01","name":"航务代理"}'
.\agent_client.ps1 -Session $session -Action observe
```

在启动命令加 `-Watch` 即可实时旁观。每条 `step` 按 60 Hz 分帧执行，画面跟随飞船，抵达航点、遇敌或达到指定帧数时返回回执。两条命令之间游戏暂停。观战时最长的一条 1800 帧命令约需 30 秒，客户端默认等候 90 秒。可用 `-Game` 指定其他 EXE。从试玩 ZIP 解压运行时，客户端会自动使用同目录的 EXE。

## 让 Agent 飞一趟

把命令表和玩家任务交给具备终端工具的 Agent。例如：「用观察结果决定下一步。接首航委托，按引力点规则飞到第 02 星系，买 8 矿石送到炉心转运站，交付后报余额。」无须截图或联网。

| 命令 | `args` / 行为 |
|---|---|
| `observe` | 不推进时间；返回人物、任务、舰船/舰队、港口、可见敌舰、航点、引力点或附近信标 |
| `set_intent` | 传 `text` 写下眼下的操作目的（1–120 字），可传 `target` 指明目标（最多 64 字）。在换目标时更新。观战窗口会把这段说明和游戏返回的实际操作结果分别显示。 |
| `market_quote` | 靠港后传 `ware,amount` 查询整批可成交量、货款、税额及实际收付总额。正数买入，负数卖出，可选 `black`。 |
| `freight_offer`、`accept_freight`、`deliver_freight` | 在起运港查询采购委托，返回 `offer`、目的港和安全航路的星系编号。将原报价作为 `{"offer":...}` 传回签单，自行采购并实际运到收货港后交付。`paid` 是含运费的实际到账金额。 |
| `watch_frame` | 在可见观战会话中截取当前游戏画面，保存到本次会话目录的 `watch.png`。下次截图会替换同一文件。 |
| `new_game` | `seed`、`name`、`noble` 可选；也可传 `systems`、`factions` 和 `role`（`captain` / `independent_manager` / `employed_manager`） |
| `waypoint` | `kind` 可选 `gravity`、`mine`、`port`、`system`、`point`、`planet`（登陆）、`survey`（勘测）或 `construction_orbit`（建站轨道）。港口和星系使用 `target` ID，后三种使用 `system.planets[].index` 作为 `target`，坐标航点使用 `pos:[x,y]`。港口和行星航点会随天体移动。 |
| `hire_builder`、`cancel_builder` | 到港后从该港的 `builder_offer` 读取现货和项目服务费。签约可传 `expected_fee` 锁定报价，通过 `state.construction_contract` 跟踪工程舰。 |
| `board_liner`、`disembark_liner` | 离开自己驾驶的船后，从 `state.passenger_liners` 选择靠港客船和目的港。登船时传 `ship`、`dest` 和该站报价 `fare`。报价变化时会退回请求。抵达目的港会自动下船，也可在停靠期间提前下船。 |
| `assign_passenger_liner`、`assign_contractor` | 用 `ship` 指定由 NPC 船长执掌的自有或公司舰船。客运可传经停港 ID 数组 `route`，工程舰可传母港 `home_port`。 |
| `deploy_station`、`donate_materials` | 在行星施工轨道发送 `deploy_station`，传产业编号 `module`。自驾或雇来的工程巡洋舰须已到场。得到工地的 `port` 后靠泊，发送 `donate_materials` 从旗舰货舱卸入所需材料。 |
| `found_planet_port` | 在已勘测的未开发行星着陆点提交 `module`，建立地表或浮空港口项目。 |
| `financial_report` | 可传 `days`（1–90，默认 30）。返回舰队与空间站的实际收入、支出和净额，以及各项资产明细。空间站另列公开市场售货、收货成交额。 |
| `trade_partners`、`trade_catalog` | 查询联系人，以及所选 `kind`（person、station、company、faction）和 `id` 两侧可用资产。本港黑市传 `black:true`。 |
| `preview_deal`、`propose_deal` | 参数包括 `kind,id,black,give,want`。两侧都是形如 `{"kind":"ware","id":0,"quantity":2}` 的数组，现金用 `cash` 且编号为 0。预览返回双方估值、差价和同意度。签署成功会返回 `deal_id`。 |
| `confirm_deal`、`cancel_deal` | 传 `deal_id` 确认交割或撤回整份提案。 |
| `set_operating_area` | 给自有舰传 `ship`、母港 `port` 和 `jumps`（0–5）。0 只在本星系自动贸易或采矿。已接单的船完成本单后启用新范围，分别见 `operating_area` 和 `next_operating_area`。 |
| `station_finance`、`transfer_station_funds` | 传所管港口 `port` 查余额、可用资金、累计未分配收益。划拨传整数 `amount`，正数从玩家钱包注资，负数提款。 |
| `set_dividend_policy`、`pay_dividend` | 给 `port` 设 `percent`（0–100）和最低周转金 `reserve`。周期为 30 日，手动派发遵守同一支付间隔，到账金额见收支简报。 |
| `equity_catalog`、`equity` | 查公司及单站清单。以 `kind=company` 或 `station` 和 `id` 查询股东、当前买卖报价与可分配收益。 |
| `share_capital`、`securities_law` | 使用同一组 `kind,id`，读取已发行股数、在外股份、库存股、各股东比例、公开发行条款，或查询注册地适用的证券法、许可门槛与持股上限。 |
| `request_share_permit` | 以当前人物向监管者请求该公司或站点的持股许可，查看 `allowed` 和 `reason`。 |
| `enact_securities_law` | 在位统治者或摄政可用 `flag,code` 颁布本国证券法。`code` 可取 `open`、`licensed`、`restricted`。 |
| `marriage_terms`、`diplomacy_action` | 用 `target` 查询婚配条件、对方意愿与原因，也可从港口 `contacts[].marriage` 读取。使用 `diplomacy_action`、`kind=marry`、`target_person` 求婚。婚后双方 `spouse` 指向彼此，子女与父母的编号可在角色状态查询。 |
| `stock_quote`、`post_share_listing` | 使用 `kind,id` 查询净值、上笔与最近成交、涨跌及逐日价量。公开卖单另传 `quantity,unit_price`，实际买家按自己的有效出价撮合。 |
| `my_share_listings`、`cancel_share_listing` | 查看自己的挂单、已售数量和实收金额，或按 `listing_id` 撤回余量。 |
| `quote_share_order`、`sign_share_order` | 传入 `order_id,quantity` 核对指定已签报价。签约再传 `unit_price`，以返回的 `deal_id` 调用 `confirm_deal` 交割。 |
| `issue_shares`、`solicit_issue`、`subscribe_shares`、`withdraw_issue` | 前三项还需 `quantity,unit_price`。授权人可公开发行，其他人可提出融资方案。已有发行必须携带 `offer_id` 认购。撤回只关闭尚未认购的部分。 |
| `equity_person` | 传人物编号 `person` 查询性格、对玩家的好感、职务、持股和可代表的账户。`equity` 的 `contacts` 列出每个账户的 `person` 和签字人 `decider`。 |
| `equity_preview` | 与 `equity_inquiry` 参数相同。返回同意度 `score`（0–100）、当前条件能否签字 `accepted`、`reason` 和影响因素 `factors`。预览可重复调用，资金和委托簿均保持原值。 |
| `equity_inquiry` | 传 `kind`、`id`、`counterparty`（账户的 `person`）、`quantity`、`buying` 与每股限价 `limit`。结果的 `accepted` 表示签字意愿，`reason` 给出理由。同意后返回可确认的 `order_id`、单价和到期日。 |
| `trade_equity`、`cancel_equity_inquiry` | 确认交易须传同一标的、账户、方向、数量、原 `order_id` 和 `expected_price`。放弃专门为你签署的委托可传 `order_id` 撤销。 |
| `board_support` | 传 `company`、成年股东 `person`，请求对方支持当前角色出任董事长。返回签字人、答复、票数与理由。 |
| `board_vote`、`company_dividend_policy`、`pay_company_dividend` | 以 `company` 选择公司。股东用 `candidate` 投董事长票。董事长可用 `percent` 与 `reserve` 设置公司派息政策，或发起本期派息。 |
| `step`、`wait` | `step` 按 60Hz 推进 1–1800 个 `ticks`，返回 `days_elapsed`、`distance_moved`、`fuel_spent` 及空转诊断 `idle_reason`；`wait` 传 `days`（1–180）可在非交战状态下直接安全跳过指定天数（无需移动飞船） |
| `depart`、`dock`、`jump` | 走正常规则；`jump` 只在引力点或目的星系信标附近成功 |
| `mine_or_salvage`、`repair`、`field_repair`、`refuel` | 相当于采掘/勘测/打捞残骸、靠港或野外抢修，及港口补给燃料；太空中脱离交火后调用 `repair` 或 `field_repair` 可消耗船体部件/合金/废料抢修舰队（无材料也可应急恢复至 45% 船体） |
| `trade` | `ware` 由 `state.wares` 的 0 基下标确定；`amount` 正买负卖；`black:true` 走黑市规则 |
| `accept_first_job`、`deliver_first_job`、`claim_return_bonus` | 首航委托接单、交矿、返程津贴 |
| `buy_ship`、`assign_escort` | `model` 为 `state.ship_catalog` 的 0 基下标；任命时传 `ship` 和同港 `captain` ID |
| `group`、`system`、`vent` | 编组接受 `group:1–3` 和 `toggle_auto:true`。`system` 启动舰载系统，可传瞄准点 `aim:[x,y]`、可见舰船的 `target` ID 和推进方向 `move:[x,y]`。`vent` 主动排散。 |
| `order`、`autopilot` | `order:0/1/2/3` 对应自由交战/护卫/集火/撤退，集火须带敌舰 `target`；`autopilot` 可传 `enabled:true/false`（不传则切换）开启或关闭旗舰实时战斗托管，开启后 `step` 期间由内置战斗 AI 自动接管走位、护盾、技能与开火 |
| `war_status`、`propose_peace` | `war_status` 查询本国活跃战争的战分、厌战度、可用预算与占领空间站；统治者/摄政可用 `propose_peace` 传 `enemy`、`annex_ports`（割让占领站数组）、`release_ports`（释放为自由港数组）、`reparations:true/false`、`open_trade:true/false`（或 `preview:true` 试算）发起和平谈判并签署休战和约 |
| `join_faction`、`apply_manager`、`disembark`、`buy_station_ship` | `join_faction` 传 `flag` 加入已有阵营；`apply_manager` 传可选 `port`（默认当前停靠站）受雇成为该阵营空间站站长并自动离舰；`disembark` 离舰驻站（不驾驶飞船）；`buy_station_ship` 传 `hull_id`/`model`、`duty`（`站属贸易`/`站属采矿`/`巡逻`）和可选 `port` 一键购舰并直派本站工作。无旗舰时名下与管辖船只见 `state.fleet`，管辖站点见 `state.managed_ports` |

### 自动开火与编队 AI 行为

`step` 指定 `target` 并传 `fire:true` 可主动攻击传感器范围内的本地舰船，`order:2` 可让护航舰集火选定对象。`faction_trust` 传可选的 `person` 返回各阵营对该角色的信任和最近一次变化。

用 `debug_ship` 传 `ship` 可读取可管理舰船的产权、上级、结算账户、余额、燃料、在途航段、订舱和近期收付款。游戏内入口在「资产 → 舰船运行诊断」，也可按 F12 打开。逐笔事件从新版开始积累。

用 `incorporate_ship` 传 `ship` 和 `name`，可以用自有舰船出资成立公司，成功后返回 `firm`。用 `contribute_ship` 传 `ship` 和 `firm`，可以将自有舰船无偿转入自己担任董事长的现有公司。

- **武器自动开火（`group` 开启 `toggle_auto` 或护航/NPC 自动射击）**：按各武器槽位弹速分别计算提前量，不对处于相位潜航的目标开火；护航/NPC 会在接近辐能上限时自动停火防过载，并在敌舰低辐能开盾且自身仍有常规武器时暂留限弹高爆导弹。
- **护航与 NPC 机动决策**：按船长性格与 `preferred_range` 维持交战距离并保持友舰防撞间距；护盾会优先朝向最近来袭敌方投射物方向；进入「降盾散热」时仅在无贴脸来袭威胁下主动排散；防御/保命/位移类舰载系统在高辐能或撤退时仍可触发，目标选择优先集火过载、排散或残血敌舰。
| `choose_successor`、`quit` | 继任人选择时传 `id`；退出该代理会话 |

自动航行示例（先设航点，再推进）；不能把 `waypoint` 当成瞬移：

```powershell
.\agent_client.ps1 -Session $session -Action depart
.\agent_client.ps1 -Session $session -Action waypoint -Json '{"kind":"gravity"}'
.\agent_client.ps1 -Session $session -Action step -Json '{"ticks":1200,"speed":3,"stop":"arrival"}'
.\agent_client.ps1 -Session $session -Action jump
```

有交火或重大事件时，先观察状态再决定是否继续步进；不能盲发同一个买卖/交付指令。协议没有任意执行脚本、文件访问或存档编辑接口。

## 协议 2

观察结果提供当前角色的属性、压力、待办、港务项目和危机状态。原版的走私查缉和缴获舰员安置进入 `state.events`，`state.event` 提供首项。动作可继续执行，也可在 `step` 传入 `stop: "event"` 主动停在待办处。查看任一项的 `options` 后，用 `event_choice` 提交它的 `event_id` 和从 0 开始的 `option_index`。`enabled` 表示选项可用，`reason` 给出禁用原因。使用 `set_focus` 或 `train` 发展人物，`diplomacy_action` 接受 `kind` 和 `target_person`。

用 `refit_offers` 指定 `slot` 和可选的 `black`，可取得该渠道的兼容武器 ID。武器成交前可以调用 `refit_quote`，参数与 `refit_slot` 相同。检查 `result.ok` 和 `reason` 判断此刻能否换装，`net` 为折价后的净支出，`used_op`、`free_op` 为换装后的整舰装配点。`before`、`after` 返回齐射伤害、两种 DPS、幅能消耗比、射程和 OP。提交 `refit_slot` 时重新检查库存和余额。

在港口用 `refit_slot` 指定 `slot`、`weapon`，用 `refit_tuning` 的 `caps_delta` 和 `vents_delta` 调整电容或散热；`refit_preset` 接受整套 `preset` ID。用 `order_hull` 提交稳定的 `hull_id`。`station_expand`、`queue_dock`、`supply_construction`、`assign_role` 可操作工业与舰队。`crisis` 的 `kind` 可选 `investigate`、`swarm`、`negotiate` 或 `challenge`。

购买航母后，用 `pilot_ship` 的 `ship` 参数登舰。在靠港观测的 `ports[].wing_catalog` 可读 31 种联队及各自材料。提交 `refit_wing`，例如 `{"bay":0,"wing_id":"cobra_wing"}`，以从零开始的机库号换装。已装编成见 `ship.fit.wings`，固定机库见 `ship.builtin_wings`，实际出击与返航见 `ship.fighter_wings`。

用 `queue_fleet_order` 给已有船长的下属追加一次性指令。参数 `ship`、`port` 和 `kind` 为必填。种类有 `dock`、`escort_to`（护送当前旗舰到港）、`buy`、`sell`、`load` 和 `unload`。后四种还需货物编号 `ware` 和正整数 `quantity`，其中装卸限自有或摄政代管的仓库。每条指令至多成交指定数量。用 `ship.fleet[].order_queue` 查看顺序，`last_order` 查看实绩。用 `cancel_fleet_order` 的 `ship` 和从零开始的 `index` 撤单。

用 `set_default_behavior` 设置清空队列后接替的常驻任务。`kind` 可设为「自动贸易」「自动采矿」「护航」，也可设为需要指定 `source` 港的「停泊待命」「巡逻」，或需要指定 `source` 与 `target` 两港的「贸易」「采矿」。已排入队列的指令会照常执行。

商船会绕开敌对政权、海盗和教团控制的航道。可在 `ship.fleet` 各舰的 `route_hold` 查看停航原因。安全航道恢复后，船长会重新预订舱位并继续航行。玩家相关货船遭到实际攻击时，`notice` 会给出船只和星系，同一地点的近期遇袭会合并进「纪事」。

## 给其他语言接入

传入一个仅供本机可信程序访问的空目录，使用绝对路径。无窗口启动参数为 `--headless -- --agent-dir=<绝对路径>`，可见观战为 `-- --agent-dir=<绝对路径> --agent-watch`。`ready.json` 的 `watch` 字段表明是否启用了实时旁观。将 UTF-8 JSON `{"id":"唯一请求ID","action":"observe","args":{}}` 写到临时文件，再在同目录原子更名为 `request.json`。读取 `response.json`，核对 `id` 并删除响应后，再发下一条。一条观战命令执行期间 `request.json` 会持续存在。客户端超时后先检查该请求及回执，再决定下一步。

## 验证

在工程目录执行 `verify_agent.ps1`，它启动导出的 EXE，用实际桥接指令跑两次同种子跨星系交付和一次实时舰战。回归不读写真实玩家存档。
