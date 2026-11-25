# 《星轨遗产 (StarrailLegacy)》深度架构重构与美术技术升级意见书
> **面向执行主体**: AI Coding/Art Agent 与工程研发团队  
> **代码事实基准**: `f:\dev\1\` 当前仓库（Godot `4.6.3` / `GL Compatibility` 渲染器，19 个 `.gd` 脚本共 6,271 行，存档版本 `World.VERSION := 6`）  
> **核心对标基准**: 《远行星号 (Starsector)》`0.97a/0.98a`、《X4：基石 (X4: Foundations)》`7.50/8.00`、《十字军之王3 (Crusader Kings III)》`Chapter IV`

---

## 执行摘要

《星轨遗产 (StarrailLegacy)》当前的 Windows 试玩版已经成功验证了一个极具潜力的**“太空战术海战 + 沙盒实体经济 + 家族传承政治”三核原型**。在仅约 6,271 行 GDScript 代码的体量下，团队实现了从角色捏脸与八项基因遗传（`portrait.gd`）、四级舰体与 53 船/84 武器目录（`hull_catalog.gd`）、双轨软硬幅能战斗（`combat.gd`）、7 类货品供需与跨星系企业（`economy.gd`）、5 种政体继承与摄政（`politics.gd`），到程序化 PCM 音效（`audio.gd`）、本地 Agent 操控桥接（`agent_bridge.gd`）以及 12 组自动化回归测试（`verify.gd`）的完整闭环。

然而，若以商业级硬核太空沙盒为目标，当前 Demo 正面临严重的**“原型债集中爆发”**与**“三核浅层耦合”**瓶颈：
1. **工程层面**：全项目依赖无类型 `Dictionary` 字典传递核心实体状态（船只、人物、空间站、星系），UI 完全由 `game.gd`、`panels.gd` 与 `dock_view.gd` 在运行时通过代码循环动态销毁并重建 `Control` 节点树，极易引发性能抖动与键名拼写静默 Bug。
2. **美术与视听层面**：`art/pixel_art.gd` 使用 CPU 逐像素绘制 `64×40` 静态船体底图，`sector_view.gd` 在单次 `_draw()` 中直接绘制贴图与简单几何圆弧，缺少独立炮塔旋转与后坐力图层、离散装甲损伤遮罩、Additive 发光混合与前置弹道预测环；`64×72` 角色肖像缺乏 2.5D 光影层次与派系制服符号学。
3. **玩法深度层面**：战斗缺乏局部装甲网格与方向性护盾弧度博弈；经济缺乏跨层级工业依赖链、订单预留锁与 IS/OOS 双层模拟；政治缺乏角色特质冲突、压力（Stress）约束、把柄/秘密/计谋（Hooks/Secrets/Schemes）与内部派系叛乱状态机。

本意见书旨在为 AI Agent 与工程团队提供一份**可直接拆解为工单（Ticket）与代码 PR 的零歧义重构蓝图**，涵盖现状审计、架构与渲染管线设计、数据结构与数学公式、以及 P0–P3 分阶段实施与回归验收标准。

---

## 第 1 章：Demo 现状全景审计与“三核耦合”核心瓶颈诊断

### 1.1 现有 19 个 `.gd` 脚本职责分布与技术债全景盘点

通过对仓库全部 19 个脚本（总计 6,271 行）进行逐文件审计，当前代码库呈现出明显的“核心逻辑集中于少数 `RefCounted` 静态工具类 + UI 与视图高度耦合于根节点”的特征。各脚本的真实职责、规模与核心技术债如下表所示：

| 脚本路径 | 行数 | 当前核心职责与已实现符号 | 关键技术债与架构风险 |
| :--- | :---: | :--- | :--- |
| `game.gd` | 638 | 主场景根 `Control`，负责 `Theme` 构建、捏脸界面 `show_creator()`、主界面 `run_bridge()`、输入 `_input()`、物理帧 `_physics_process()` 与存档 `save_game()`/`load_game()` | **God Class 化**：同时承担主题构建、UI 控件工厂（`vbox`/`button`/`clear`）、输入分发、音频调度与存档 I/O；每次 `refresh()` 调用 `clear(body)` 销毁重建全量节点 |
| `world.gd` | 635 | 核心状态容器 `World`（`VERSION := 6`），管理 `systems`/`ports`/`people`/`factions`/`ships`/`wrecks`/`firms`，含外域分块 `ensure_chunks_around()` 与存档迁移 `migrate()` | **无类型字典地狱**：所有实体均为裸 `Dictionary`，依赖字符串键访问（如 `vessel.battle.hard_flux`）；`HULLS`/`HULL_HP` 等数组与 `Hulls.MODELS` 存在冗余映射 |
| `verify.gd` | 607 | `SceneTree` 自动化回归测试，覆盖 `generation()`、`logistics()`、`inheritance()`、`combat_edges()`、`ui_flow()` 等 12 个测试集 | **缺口明显**：偏重状态字段断言与单帧模拟，缺少千帧级战斗物理稳定性压测、经济死锁/通缩监控、渲染节点泄漏检测 |
| `politics.gd` | 590 | 静态政体与角色系统，含 `opinion()`、`marry()`、`child()`、`heirs()`、`estate()`、`select_leader()`、`die()`、`military()`、`appointments()` | **规则单薄**：`TRAITS` 仅 4 项枚举且无互斥/性格向量；`military()` 攻城仅按天数扣减 `station.defense`；无内部派系（Faction）、把柄与压力系统 |
| `economy.gd` | 565 | 静态经济与物流系统，含 `population_day()`、`price()`、`trade()`、`deploy()`、`expand()`、`produce()`、`run_module()`、`trade_plan()`、`step_ship()`、`refit_slot()` | **无预留锁与供应链断裂**：`trade_plan()` 未锁定目标库存，多船易抢单；`step_ship()` 靠 `travel.eta` 瞬移跳过星系物理空间；仅 7 类货品且无建筑仓储分离 |
| `art/pixel_art.gd` | 512 | CPU 程序化像素画生成器，生成 `64×40` 船体 `hull()`/`specialist()`、`80×72` 空间站 `station()`、`64×72` 肖像 `portrait()`、`320×180` 背景 `orbit()`/`bay()` | **纯 CPU 软光栅瓶颈与资产平面化**：每次冷启动在主线程通过双重循环 `is_point_in_polygon` 绘制；舰船为单层静态图，无独立炮塔、发光槽与损毁遮罩 |
| `flight.gd` | 450 | 实时飞行、跃迁 `change_layer()`、停靠 `dock()`、打捞 `salvage()`、护航指令 `issue()`、AI 驾驶 `drive_ai()` 与物理帧 `step()` | **物理与 AI 简化**：`maneuver()` 使用线性 `move_toward` 缺乏质量惯性与助推池；`drive_ai()` 无性格分化、无目标滞回（Target Stickiness） |
| `panels.gd` | 387 | 侧边栏动态 UI 生成器，渲染 `port()`、`market()`、`person()`、`assets()`、`powers()`、`history()`、`successor()` | **视图与业务强耦合**：UI 布局逻辑与经济/政治校验条件混杂，缺少 Tooltip 解释层与数据筛选/排序能力 |
| `agent_bridge.gd` | 364 | 本地文件 IPC 桥接（`PROTOCOL := 1`），通过 `request.json`/`response.json` 提供 `observe()` 与 `dispatch()` | **协议覆盖不全**：尚未暴露 `refit_slot`、外交条约、空间站扩建、人物互动（送礼/联姻）与高阶战术编队指令 |
| `sector_view.gd` | 343 | 主战与星图渲染器，通过 `_draw()` 绘制背景、天体、空间站、舰船 `draw_ship()`、弹丸、粒子 `effects()` 与 `tactical_overlay()` | **单画布硬绘制**：所有元素在同一 `_draw()` 中顺序绘制，无法利用 GPU Shader、Additive 混合材质、硬件实例化或独立粒子节点 |
| `dock_view.gd` | 322 | 停靠状态下的左侧主舞台与侧边栏控制器，包含 `show_refit()`、`show_hull()`、`conversation()`、`refit_sidebar()` | **整备可视化不足**：`show_refit()` 仅用文本列表按钮展示武器槽位，未能将槽位位置、射界弧度（`arc`）直接叠加渲染在舰船蓝图上 |
| `combat.gd` | 234 | 战斗数值与状态机：`tick()`、`add_flux()`、`hull_impact()`、`hit()`、`system()`、`fire_slot()`、`point_defense()`、`project()`、`ai_mode()` | **数值模型过于扁平**：`state.armor` 为单一标量；`shield` 为 360° 全向无死角；`project()` 仅做线段-圆心距离判定，无真实多边形碰撞与光束武器 |
| `hull_catalog.gd` | 190 | 舰船与武器静态数据表：`BASE_WEAPONS`、`WEAPON_SERIES`、`BASE_MODELS`、`DESIGN_LINES`、`SLOTS`、`fitting_cost()` | **程序化缩放同质化**：53 船与 84 武器通过数组倍率相乘生成，缺乏独特机制插件（Built-in Mods）、弹药/备弹量与武器手感差异 |
| `audio.gd` | 155 | 程序化 16-bit PCM WAV 合成器，预生成 14 种音效与 12 通道 `AudioStreamPlayer` 池 | **缺少空间化与动态音景**：非 `AudioStreamPlayer2D`，无距离衰减；缺少战斗强度动态混音与过载/低甲警报分层 |
| `presentation.gd` | 80 | 静态环境/舰船/港口文本描述与 `TextureRect` 渐变辅助工具 | **内容量极少**：仅覆盖前 9 艘基础船的文本，第 9–52 号量产船仅拼接数值模板 |
| `frontier.gd` | 79 | 开局引导委托「熄火之前」（沈照与罗启山，运送 8 单位矿石赚取 `PAYOUT := 210` + `BONUS := 40`） | **叙事孤岛**：全游戏唯一具备命名角色与多阶段对话的剧情链，完成后即进入纯机制沙盒 |
| `celestial.gd` | 64 | 恒星（6 类）与行星（24 类）生成、勘测 `survey()`、轨道检测 `orbit_at()` 与引力点 `gravity_point()` | **天体无物理交互**：行星仅作为背景坐标与建站圆环判定，缺乏行星环/小行星带地形遮挡与传感器隐匿交互 |
| `portrait.gd` | 51 | 肖像基因编码 `GENES`（8 项可遗传）与非遗传项（`wear`、`mark`）的随机/遗传计算 | **表现维度单一**：无年龄老化、伤病/压力外显、家族徽章与派系制服映射 |
| `art/export_pixels.gd` | 52 | 离线导出工具，将 `pixel_art.gd` 图集导出为 `art/*.png` 预览文件 | 工具脚本，无运行时问题，但需同步适配升级后的多层资产管线 |

#### 1.1.1 核心工程反模式剖析
1. **全局无类型字典传递（Untyped Dictionary Coupling）**：`world.gd` 中的 `ships`、`ports`、`people`、`factions` 均以裸 `Dictionary` 存储。例如 `combat.gd` 中直接读写 `vessel.battle.soft_flux`、`vessel.fit.weapons`，`economy.gd` 中直接读写 `station.stock[1]`、`station.build`。这种模式导致 IDE 无法进行静态类型检查、重构极易遗漏字段、且难以在运行时拦截非法状态写入。
2. **全量销毁重建式 UI（Immediate-Mode Node Churn）**：`game.gd` 的 `refresh()` 每次被调用时直接执行 `clear(body)`（遍历 `queue_free()` 所有子节点），再由 `panels.gd` / `dock_view.gd` 重新实例化数十个 `HBoxContainer`、`Button` 与 `Label`。在停靠市场高频点击买卖或切换页签时，不仅造成主线程 GC 与布局重算卡顿，还导致滚动条位置丢失、Tooltip 状态中断。
3. **单一场景树与逻辑-渲染紧耦合**：整个游戏仅有一个 `game.tscn`（12 行，仅含一个挂载 `game.gd` 的 `Control` 节点）。太空战斗画布 `Sector` 直接继承 `Control` 并通过 `_draw()` 轮询 `world.ships` 和 `world.projectiles`，使渲染层无法独立使用 Godot 的 2D 节点层级（`Node2D`、`GPUParticles2D`、`CanvasItem` 材质与 Shader、独立 `Camera2D` 震动与缩放插值）。

---

### 1.2 “三核耦合”闭环断裂点诊断

《星轨遗产》的核心设计野心是将**星际战术海战（Starsector）**、**实体化沙盒经济（X4）**与**角色家族政治（CK3）**融为一体。但在当前 Demo 中，三大系统仅在“数据表共享 ID”的浅层发生接触，真正的机制反馈环存在多处断裂：

```
[当前 Demo 的三核浅层耦合与断裂点]
   +-------------------+      (断裂1: 战损不消耗船坞合金/组件)      +-------------------+
   |   战术海战核      | -----------------------------------------> |   沙盒经济核      |
   | combat / flight   | <----------------------------------------- | economy / world   |
   +-------------------+      (断裂2: AI商船/矿船不进入物理太空)     +-------------------+
             |                                                                |
   (断裂3: 船长仅提供0.25~1.0人数比例效率，                         (断裂4: 站长仅看origin==2，
    性格/压力/技能不介入战斗与AI)                                    公司/市场危机不触发政治事件)
             v                                                                v
   +------------------------------------------------------------------------------------+
   |                        角色与政治核 (politics / frontier)                          |
   |  * 仅靠 opinion / loyalty / 4选1 trait 维系；无把柄/秘密/派系叛乱/动态叙事事件 *      |
   +------------------------------------------------------------------------------------+
```

1. **断裂点 1（战斗 -> 经济的战损消耗黑洞）**：在 `world.gd` 的 `destruction()` 中，舰船被击毁后直接 `ships.erase(ship_id)` 并生成残骸 `wreck()`；但 AI 派系在 `politics.gd` 的 `military()` 中补充兵力时，仅当 `capital.hulls[2] > 0 and group.treasury >= 180` 才消耗 1 艘库存巡洋舰，而普通护航舰/海盗的损失不会按真实部件（武器、装甲板、引擎、电子元件）倒逼船坞订单，导致战争无法真正拉动上游采矿与精炼需求。
2. **断裂点 2（经济 -> 战斗的 OOS 幽灵航行）**：在 `economy.gd` 的 `step_ship()` 中，AI 商船与矿船通过 `begin_trip()` 设置 `vessel.travel = {"port": target.id, "eta": world.day + ...}`，期间直接 `vessel.dock = 0` 但**并不在超空间或星系坐标中真实移动**，也不会被海盗截杀、被玩家伏击或受封锁影响。一旦 `world.day >= vessel.travel.eta`，船只直接瞬移停靠目标港，彻底剥离了“护航商路”与“破交封锁”的沙盒玩法。
3. **断裂点 3（政治 -> 战斗的军官与士气脱节）**：`hull_catalog.gd` 的 `crew_efficiency()` 仅计算 `vessel.crew / minimum`，与船长（`vessel.captain`）的个人属性、性格（`trait`）及压力毫无关系；`combat.gd` 与 `flight.gd` 的 AI 对所有船长一视同仁，无法涌现出“鲁莽军官驾船孤军深入”或“怯懦船长高幅能逃跑”的戏剧性。
4. **断裂点 4（经济/战争 -> 政治的叙事与危机真空）**：空间站断供暴动仅在 `economy.gd` 的 `population_day()` 中写死一行日志（`station.shortage == 30`）；家族继承、企业禁运、领土易主均无后续的秘密泄露、封臣结派讨伐或动态叙事事件链，导致中后期陷入“无事发生”的纯数值挂机。

---

### 1.3 “当前 Demo 成熟度 vs 目标基准”三维差距矩阵

下表以《远行星号》《X4：基石》《十字军之王3》三份基准报告为标尺，量化评估当前 Demo 在各子系统上的成熟度与核心差距：

| 评估维度 | 对标作品 | 当前 Demo 已实现基线 | 目标基准核心要求 | 成熟度评分 (1-5) | 核心重构优先级 |
| :--- | :---: | :--- | :--- | :---: | :---: |
| **舰船与炮塔视觉管线** | 远行星号 | `64×40` 单层静态 PNG；无炮塔独立贴图；无后坐力与发光层 | 7 层独立节点装配（底图/损伤遮罩/炮塔底座与炮管/发光槽/尾焰/弧盾）；Greebling 与派系涂装分化 | **1.5 / 5** | **P1 (高)** |
| **战斗特效与打击感** | 远行星号 | 简单 `draw_arc`/`draw_line`；4 帧 `24×24` 粒子；简单 `impulse` 震动 | Additive 混合光束/电弧/枪口焰；局部装甲击穿闪白与焦痕；幅散蒸汽流；相位残影；断舰碎裂 | **1.5 / 5** | **P1 (高)** |
| **护甲、护盾与武器深度** | 远行星号 | 单一标量 `armor`；360° 全向 `shield`；数组缩放 53 船/84 武器；无光束/航母 | 二维离散装甲网格 + $\frac{D}{A+D}$ 公式；`FRONT`/`OMNI` 角度护盾；光束/EMP/航母战机联队；数据驱动 `.tres` | **2.0 / 5** | **P1 (高)** |
| **飞行手感与战术 AI** | 远行星号 + X4 | 线性 `move_toward`；`drive_ai` 3 模式；4 项基础僚舰指令 | X4 7.50 独立助推池 + 质量惯性漂移；5 档性格驱动 AI + 目标滞回；Tab 矢量战术全局视图 | **2.0 / 5** | **P1 (高)** |
| **工业链与空间站模拟** | X4：基石 | 7 类货品；5 类单模块+1 扩建；`20 合金+30 日` 建站；无库存预留 | Tier 0–3 工业有向无环图；3 类物理仓储；建筑仓储；劳动力效率曲线；交易预留锁与黑名单 | **2.0 / 5** | **P2 (中)** |
| **双层模拟与舰队自动化** | X4：基石 | AI 商船靠 `eta` 瞬移；舰船仅单一 `job` 字典；无指挥链 | IS/OOS 双层模拟气泡与状态重对齐；`OrderQueue + DefaultBehavior`；6 大下属职责过滤器（含 `Mimic`） | **1.5 / 5** | **P2 (中)** |
| **角色、阴谋与政体博弈** | CK3 | 4 项 `trait`；简单 `opinion` 与联姻继承；2 种继承法；摄政 | 多维属性 + 性格互斥组；`0–400` 压力与精神崩溃；秘密/把柄/阶段化计谋；封臣契约与派系内战 | **2.0 / 5** | **P2 (中)** |
| **动态叙事与 UI 可解释性** | CK3 + 远行星号 | 仅开局「熄火之前」短任务；单层原生 `tooltip_text` | `on_action + trigger + weight_multiplier` 事件引擎；行旅危险事件；CK3 式嵌套工具提示 | **1.0 / 5** | **P2 (中)** |
| **软件工程与 Agent 生态** | 工程基准 | 裸 `Dictionary`；全量销毁 UI；`agent_bridge` 协议 v1；12 组测试 | 强类型 `Resource`/`class_name`；增量更新 UI 与主题资源；协议 v2；长周期经济/战斗压测 | **2.5 / 5** | **P0 (极高)** |

---

## 第 2 章：美术与视觉管线全面升级方案（对标《远行星号》）

### 2.1 现有 `art/pixel_art.gd` 与 `sector_view.gd` 局限深度审计

当前 Demo 的视觉管线虽然验证了“零外部美术依赖、纯代码生成统一像素风资产”的可行性，但在画面表现力、战斗信息可读性与扩展性上存在五项结构性缺陷：

1. **单层静态船体与固定小尺寸瓶颈 (`art/pixel_art.gd:66-214`)**：
   - 无论是 `hull()`（基础 0–2 号船）、`specialist()`（3–8 号船）还是 `production_hull()`（9–52 号量产船），最终都光栅化为一张 `64×40` 的单层 `Image`（`RGBA8`）。
   - `production_hull()` 仅通过 `line_id`（0–10）和 `role`（0–3）在 4 个基础底盘 `[0, 1, 3, 7]` 上叠加对称矩形条或小三角翼片（第 126–145 行），导致 44 艘量产船在中等视距下剪影高度趋同，违背了《远行星号》的**剪影优先（Silhouette First）**原则。
2. **武器挂点与船体完全分离失效 (`sector_view.gd:218-237`)**：
   - `hull_catalog.gd` 明明在 `SLOTS` 中定义了 `nose`/`port`/`starboard`/`dorsal`/`aft` 的精确偏移坐标（`offset`）、默认朝向（`facing`）和炮塔类型（`"固定"` vs `"炮塔"`），但 `sector_view.gd` 的 `draw_ship()` 完全没有渲染任何武器模型！玩家既看不到炮塔随鼠标或敌舰旋转，也无法在开火时看到炮管后坐力与枪口焰位置对齐。
3. **缺少局部损伤可视化与光效叠加混合 (`sector_view.gd:156-168, 255-276`)**：
   - 护盾开启时仅画一个全向 `draw_arc`（第 164 行）；装甲受损或过载时仅在船体中心附近贴一张 `24×24` 的 4 帧 `effect_texture(1, phase, ...)`，无法反映“左舷装甲被打穿、右舷依然完好”的空间信息。
   - 所有粒子、弹丸、尾焰均使用标准 Alpha 混合绘制，缺乏 OpenGL **Additive 加法混合（`CanvasItemMaterial.BLEND_MODE_ADD`）**，导致能量光束与爆炸核心无法产生向纯白过曝的炽热能量感。
4. **肖像平涂与缺失光影/派系语义 (`art/pixel_art.gd:314-379`)**：
   - `portrait()` 在 `64×72` 画布上仅用简单多边形色块平涂五官与 4 种固定配色衣装（`["536b81", "496b62", "6d506b", "8b6048"]`），仅有单侧微弱暗面多边形，缺少硬边厚涂笔触、工业环境冷暖侧逆光、衰老白发/伤病物理映射以及派系专属制服徽记。
5. **HUD 语义色彩混杂与缺失前置弹道预测环 (`sector_view.gd:286-328`)**：
   - 旗舰状态面板中，护盾、系统、主炮青色 `CYAN` 与船体翠绿、装甲琥珀、硬幅能橙红混用，但硬幅能未使用《远行星号》高对比度的**纯白/亮灰**与青色软幅能形成阶梯对比；世界空间中鼠标瞄准敌舰时缺乏**前置弹道预测环（Lead Indicator）**。

---

### 2.2 Godot 4.6.3 Compatibility 渲染器下的分层舰船渲染管线

考虑到项目锁定 `renderer/rendering_method="gl_compatibility"`（见 `project.godot:15`），且需要保持程序化像素/硬科幻风格的低包体优势与高刷新率性能，**不应继续在单个 `Control._draw()` 中硬画全战场**，而应重构为基于 `Node2D` + `SubViewport`（或独立战场 `Node2D` 世界层 + 顶层 `CanvasLayer` HUD）的硬件加速分层场景树。

#### 2.2.1 `ShipVisual2D` 七层节点树结构规范
每艘在场（High Attention / IS）的舰船对应一个独立的 `ShipVisual2D (Node2D)` 预制体实例，从下到上严格按 7 个渲染层级（`z_index` 递增）装配：

```
ShipVisual2D (Node2D)
 ├── [Z=0] ThrustersGroup (Node2D)         # 尾焰与烟迹：按 HullResource.engine_slots 生成 Sprite2D + GPUParticles2D (Additive)
 ├── [Z=1] BaseHullSprite (Sprite2D)       # 基础舰体底图 (建议升级至 128×80 或按舰级 96×64 ~ 256×160)，挂载局部损毁 Shader
 ├── [Z=2] HardpointMounts (Node2D)        # 固定武器 (HARDPOINT)：嵌入舰体凹槽，随开火沿局部 -X/-Y 后坐力位移
 ├── [Z=3] DecorativeParts (Node2D)        # 内置动画部件：旋转雷达、航母甲板灯、可动装甲翼片
 ├── [Z=4] TurretMounts (Node2D)           # 旋转炮塔 (TURRET)：每门含 TurretBase (Sprite2D) + Barrel (Sprite2D) + Glow (Additive)
 ├── [Z=5] HullEmissiveGlow (Sprite2D)     # 舰体导能槽、系统激活高光、过载故障电弧 (CanvasItemMaterial: BLEND_MODE_ADD)
 └── [Z=6] ShieldBubble (Sprite2D/Mesh)    # 方向性护盾气泡：挂载自定义 GLSL 护盾着色器 (支持展开角、旋转与受击波纹)
```

> **坐标系对齐铁律（修复当前 `hull_catalog.gd` 与 `pixel_art.gd` 的隐性对齐）**：  
> 当前 `combat.gd` 中 `vessel.heading = 0.0` 指向正右方（`+X`），而 `pixel_art.gd` 绘制的船体也是舰首朝右（`x = 63` 为舰首，`x = 0` 为舰尾）。升级后的 `HullResource` 必须显式记录 `sprite_center: Vector2`（像素中心点），所有 `weapon_slots`、`engine_slots` 与 `shield_center` 均以 `sprite_center` 为 `(0, 0)` 原点，在本地坐标系下 `+X` 为舰首方向、`+Y` 为右舷、`-Y` 为左舷，彻底消除手算偏移误差。

---

### 2.3 核心 GLSL 片段着色器方案（适配 `GL Compatibility`）

在 Godot 4.6.3 的 `gl_compatibility`（OpenGL ES 3.0 / OpenGL 3.3）后端中，以下三个轻量级 `canvas_item` 着色器可直接提供接近《远行星号》的战斗视觉质感，且单帧 GPU 开销极低：

#### 2.3.1 局部装甲网格损伤与命中闪白着色器（挂载于 `BaseHullSprite`）
通过将舰船的二维离散装甲网格（例如 `8×5` 归一化损伤数据）编码进一张极小的 `ImageTexture`（`FORMAT_R8`，`FILTER_LINEAR` 插值采样）作为 `uniform sampler2D armor_mask`，即可在 GPU 上实时混合焦黑弹坑、炽热熔融边缘与命中瞬间的亮白 `hit_flash`：

```glsl
shader_type canvas_item;

uniform sampler2D armor_mask : filter_linear; // R通道: 1.0=装甲完好, 0.0=完全剥离
uniform sampler2D scorch_noise : repeat_enable; // 预生成程序化噪点纹理
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0; // 受击瞬时闪白衰减值
uniform float overload_intensity : hint_range(0.0, 1.0) = 0.0; // 过载电弧闪烁

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    if (base.a < 0.05) {
        discard;
    }
    float integrity = texture(armor_mask, UV).r;
    float noise = texture(scorch_noise, UV * 3.5).r;

    // 装甲剥离区（integrity < 0.45）：边缘呈炽热暗红，中心呈焦黑碳化
    float damage_factor = smoothstep(0.55, 0.10, integrity + (noise - 0.5) * 0.25);
    vec3 scorch_color = mix(vec3(0.06, 0.07, 0.09), vec3(0.75, 0.22, 0.08), smoothstep(0.3, 0.7, noise) * (1.0 - integrity));
    vec3 damaged_rgb = mix(base.rgb, scorch_color, damage_factor * 0.85);

    // 过载时表面随机电弧噪点高光
    float arc = step(0.92, fract(noise * 7.0 + TIME * 4.3)) * overload_intensity;
    damaged_rgb += vec3(0.55, 0.25, 0.95) * arc;

    // 命中闪白（Hit-Flash）
    vec3 final_rgb = mix(damaged_rgb, vec3(1.0, 0.96, 0.88), hit_flash * 0.8);
    COLOR = vec4(final_rgb, base.a);
}
```

#### 2.3.2 方向性护盾弧展开与受击波纹着色器（挂载于 `ShieldBubble`）
用一张覆盖舰船的矩形 `ColorRect` 或 `Sprite2D` 承载护盾，通过 `shield_facing`（当前护盾中心角）、`shield_arc`（当前展开弧度，从 `0` 动态插值到最大弧度 `max_arc`）与 `impact_dir`（最近受击方向角）在片段着色器内精确裁剪出带六边形/能量涟漪边缘的护盾弧：

```glsl
shader_type canvas_item;
render_mode blend_add; // 强制使用 Additive 加法混合

uniform vec4 shield_color : source_color = vec4(0.38, 0.85, 0.92, 1.0);
uniform float shield_facing = 0.0;       // 护盾中心角（弧度，相对局部坐标系）
uniform float shield_half_arc = 1.57;    // 当前展开半角（0.0 ~ PI）
uniform float impact_angle = 0.0;        // 最近一次受击角度
uniform float impact_pulse = 0.0;        // 受击涟漪强度 (1.0 -> 0.0)
uniform float flux_ratio = 0.0;          // 当前幅能占比，高幅能时护盾边缘高频抖动

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float r = length(p);
    if (r > 1.0 || r < 0.72 || shield_half_arc <= 0.01) {
        discard;
    }
    float ang = atan(p.y, p.x);
    float diff = abs(atan(sin(ang - shield_facing), cos(ang - shield_facing)));
    if (diff > shield_half_arc) {
        discard;
    }

    // 护盾边缘高光 + 内部半透明渐隐 + 弧度边界柔和衰减
    float rim = smoothstep(0.72, 0.96, r) * (1.0 - smoothstep(0.96, 1.0, r));
    float arc_fade = smoothstep(shield_half_arc, shield_half_arc - 0.14, diff);
    float jitter = 1.0 + sin(ang * 18.0 + TIME * 20.0) * 0.12 * flux_ratio;

    // 受击位置高亮波纹
    float hit_diff = abs(atan(sin(ang - impact_angle), cos(ang - impact_angle)));
    float ripple = exp(-hit_diff * 4.5) * impact_pulse;

    float alpha = (rim * 0.65 + 0.12 + ripple * 0.85) * arc_fade * jitter;
    vec3 col = mix(shield_color.rgb, vec3(0.95, 0.99, 1.0), ripple * 0.75);
    COLOR = vec4(col * alpha, alpha);
}
```

#### 2.3.3 相位残影（Afterimages）与主动幅散蒸汽（Venting）
- **相位残影**：在 `flight.gd` 激活 `phase` 系统期间，每隔 `0.06s` 在主战场景中生成一个轻量级 `Sprite2D` 残影节点（复用当前舰体纹理，叠加 `modulate = Color("8a5cf6", 0.55)` 与 `BLEND_MODE_ADD`），通过 `Tween` 在 `0.35s` 内将透明度线性降至 `0.0` 并 `queue_free()`。
- **主动幅散蒸汽**：当 `vessel.battle.vent == true` 时，激活挂载于舰船散热口坐标的 `GPUParticles2D`（青白色条状粒子向舰体两侧高速喷射），直观向敌我双方暴露“护盾与武器已下线、正在双倍散热”的战术窗口。

---

### 2.4 Greebling 尺度法则与八大派系视觉语法矩阵

为了解决当前 `Hull` 缩放同质化问题，需将舰船底图生成分辨率从统一的 `64×40` 提升为**按舰级分档**：
- `FRIGATE`（护卫舰）：`80×56` 像素
- `DESTROYER`（驱逐舰）：`112×80` 像素
- `CRUISER`（巡洋舰）：`152×108` 像素
- `CAPITAL`（主力舰）：`208×144` 像素

遵循《远行星号》的 **H-ART-02（体量与微细节反比律）**，舰船像素尺寸放大后，单个装甲分块（Panel）的像素宽度保持在 `4–8px` 不变，从而在巡洋舰与主力舰上自然呈现出数倍密度的接缝、散热格栅、舰桥视窗与警告条纹（Greebling），建立无需文字标注的直观体量压迫感。

同时，将 `world.gd` 中已定义的 `CANON` 8 大势力与 `RAIDERS` 映射到统一的**派系视觉语法表**，指导 `pixel_art.gd` 涂装生成与武器/引擎光效着色：

| 势力 / 标识 (`world.gd:CANON`) | 识别色 (`color`) | 主导风格 (`style`) | 舰体轮廓与表面结构特征 | 引擎尾焰与武器光效 |
| :--- | :---: | :---: | :--- | :--- |
| **赤矛边防军** (`#e39461`) | 赭橙 / 暗钢灰 | 军武 (`0`) | 厚重前部楔形装甲、外露铆接缝与黄黑警示条纹 | 粗壮橙红化学能尾焰；实弹炮口焰与烟尘 |
| **曙铁共和国** (`#65c4c9`) | 冰青 / 珍珠灰 | 商业 (`1`) | 对称流线型海军舰体、洁净标准化装甲分块 | 亮青白离子尾焰；实弹与脉冲能量混编 |
| **长辉诸侯领** (`#a895e2`) | 晶紫 / 皇室金 | 军武 (`0`) | 仪仗感双翼对称构型、金色镶边与家族徽记 | 暖金/淡紫高能尾焰；重型长弧主炮光束 |
| **九环商会** (`#96bb73`) | 军绿 / 工业黄 | 商业 (`1`) | 不对称侧置舰桥、外露集装箱与球形燃料罐 | 稳定琥珀色商用推进焰；偏重防空与导弹 |
| **赫弧企业领** (`#edc176`) | 金黄 / 钛银白 | 商业 (`1`) | 镂空环形/双体结构、光滑复合材料表面、导能发光槽 | 高亮电青/白金冷光尾焰；高频能量弹幕 |
| **新岸公社** (`#db7f9d`) | 玫红 / 炭灰 | 打捞 (`2`) | 民用船体加焊额外防撞框与外挂机械臂、补丁涂装 | 混杂蓝白/橙色废料推进焰；高爆榴弹 |
| **白鲸舰团** (`#7899db`) | 海蓝 / 冰白 | 打捞 (`2`) | 宽体深空补给/破冰船型、重型前伸式破岩钳 | 粗大深蓝离子尾焰；鱼雷与重型实弹 |
| **灯塔守护领** (`#bea798`) | 岩灰 / 暗铜 | 打捞 (`2`) | 古老领域时代对称构型、厚重雷达天线与宗教/灯塔徽记 | 苍白/淡青冷光尾焰；点防与激光阵 |
| **裂缝掠夺者** (`RAIDERS: #e57873`) | 铁锈红 / 焦黑 | 劫掠 | 在标准船体上强行焊接不对称锯齿冲角与杂乱红漆条纹 | 不稳定喷溅橙红尾焰带黑烟；廉价导弹 |

---

### 2.5 2.5D 光影肖像与派系制服图层扩展

将 `art/pixel_art.gd` 的 `portrait()` 从当前 `64×72` 升级为 `128×144` 多图层叠加管线（或运行时 `TextureRect` 叠层缓存），并接入人物的动态状态：
1. **光影重构**：弃用均匀亮度的背景与平涂五官。背景固定为低明度暗色舱壁/金属桁架 + 微弱全息栅格；面部采用**左前冷色主光 + 右后暖橙/青色硬边轮廓光（Rim Light）**，通过 3 阶明暗色阶塑造颧骨、鼻梁与下颌阴影。
2. **年龄与状态物理映射（对标 CK3）**：
   - `Politics.age(world, actor) >= 50` 时，自动将 `hair` 通道向银灰插值，并在眼角/额头叠加像素皱纹；
   - 当角色处于低健康/战伤/重度压力（`stress >= 200`）时，自动叠加上眼睑阴影、凌乱发丝或绷带/义体贴片；
   - 贵族且身为势力领袖时，叠加派系专属高领礼服/肩章勋带与领口识别色指示灯。

---

## 第 3 章：实时战术海战与飞行手感重构（对标《远行星号》+《X4》）

### 3.1 `combat.gd`、`hull_catalog.gd` 与 `flight.gd` 现状审计

当前战斗系统虽然完整实现了软硬幅能分离（`combat.gd:51-55`）、过载 3 秒惩罚（`combat.gd:71`）、主动排散（`combat.gd:27-33`）与点防御拦截导弹（`combat.gd:159-183`），但存在五个核心机制瓶颈：
1. **单一标量装甲 (`combat.gd:77-86`)**：`vessel.battle.armor` 是一个全局浮点数。无论炮弹击中舰首、左舷还是舰尾，均扣除同一个标量。这使得“扭转船身用完好侧翼扛伤（Armor Tanking）”这一《远行星号》最核心的战术微操完全无法成立。
2. **全向无死角护盾 (`combat.gd:93-98`)**：`hit()` 只检查 `if state.shield and ready(vessel)`，没有任何角度与弧度判定。高速护卫舰绕到主力舰菊花后面开火，依然会被主力舰的“全向护盾”完美挡下。
3. **同质化的目录生成 (`hull_catalog.gd:100-163`)**：84 条武器仅仅是用 `WEAPON_SERIES` 的 13 组固定倍率数组（`tuning`、`range`、`cool`、`flux`）乘以 6 个基础武器；53 艘舰船仅仅是用 `DESIGN_LINES` × `DESIGN_ROLES` 的线性公式生成。缺乏**光束武器（Beam）**、**EMP 瘫痪武器**、**航母与战机联队**以及**内置船体插件（Built-in Hullmods）**。
4. **AI 缺乏性格与滞回 (`combat.gd:228-234`, `flight.gd:307-367`)**：`ai_mode()` 仅根据 `flux >= 0.72` 或 `distance > 225.0` 在“降盾散热 / 压进 / 侧翼拉扯”三态间切换；`drive_ai()` 每帧重新调用 `target()` 索敌，容易在两个等距目标间频繁抖动换靶，且所有船长共享同一套 0.72 幅能阈值，毫无性格差异。
5. **飞行手感缺少惯性纵深与打击反馈 (`flight.gd:301-305, 423-426`)**：`step()` 中 `state.motion` 使用 `move_toward(..., 390 * model.speed * delta)` 线性追随目标速度，松开 WASD 后瞬间急刹，缺乏太空质量惯性；`boost` 仅作为一个 10 秒冷却的技能（`combat.gd:6`），未能像 X4 7.50 那样提供可随时点按的独立助推能量池与漂移手感。

---

### 3.2 离散二维装甲网格与非线性减伤公式重构

参考《远行星号》的局部装甲网格机制，为每艘舰船在 `BattleState` 中引入低分辨率二维装甲网格 `armor_grid`（固定逻辑分辨率如 `7×5` 共 35 格，按舰体局部坐标映射到 `[-half_len, +half_len] × [-half_width, +half_width]`）：

1. **命中网格定位与 8 邻域溅射**：
   当弹丸在世界坐标 `contact` 命中舰船时，将其转换至舰船局部坐标系：
   $$P_{\text{local}} = (contact - vessel.pos).\text{rotated}(-vessel.heading)$$
   映射为网格索引 $(gx, gy) \in [0, 6] \times [0, 4]$。除主命中格承受 `100%` 有效伤害外，周围 8 个相邻格按距离衰减承受 `35%` 的溅射剥离，同步更新 `armor_mask` 纹理供第 2 章的 GLSL 着色器渲染。
2. **非线性减伤与 5% 残余装甲保底公式**：
   替换当前 `combat.gd:79-83` 的简单线性减法 `amount - armor_loss / multiplier`，严格实施非线性单发抗性公式：
   $$D_{\text{eff}} = D_{\text{raw}} \times M_{\text{armor}}(\text{damage\_type}) \times (0.5 \text{ if is\_beam else } 1.0)$$
   $$A_{\text{eff}} = \max\left(A_{\text{cell}},\ 0.05 \times A_{\text{base}}\right)$$
   $$\text{DamageMultiplier} = \max\left(\frac{D_{\text{eff}}}{A_{\text{eff}} + D_{\text{eff}}},\ 1.0 - R_{\max}\right)$$
   其中 $R_{\max} = 0.85$（常规装甲最高减伤 85%）。最终穿透至船体的伤害为 $D_{\text{hull}} = D_{\text{eff}} \times \text{DamageMultiplier}$，该格剩余装甲更新为 $A_{\text{cell}} \leftarrow \max(0.0,\ A_{\text{cell}} - D_{\text{hull}})$。
   - **设计收益**：低单发高射速武器（如 `pulse` 脉冲激光，单发 `16` 伤）面对重甲主力舰（$A_{\text{base}} = 240$）时几乎只能造成 15% 保底伤害，必须先由高爆重炮（`howitzer` / `lance`）或鱼雷撕开某一侧的装甲网格后，才能高效收割船体。

---

### 3.3 方向性护盾状态机与光束/EMP/航母联队扩展

#### 3.3.1 方向性护盾状态机 (`FRONT` vs `OMNI`)
在 `HullResource` 中为每艘船新增 `shield_type`（`NONE` / `FRONT` / `OMNI`）、`shield_max_arc`（如 `120°` ~ `270°`）、`shield_unfold_rate`（展开角速度，弧度/秒）与 `shield_efficiency`（伤害转硬辐能系数，`0.6` ~ `1.2`）：
- **展开/收拢状态**：开启护盾时，`shield_current_arc` 从 `0.0` 线性增长至 `shield_max_arc`；关闭或过载时归零。
- **朝向追踪**：`FRONT` 盾的中心角死锁为 `0.0`（舰首正前方）；`OMNI` 盾的中心角在每物理帧以 `shield_turn_rate` 旋转朝向玩家鼠标位置或 AI 判定的最高威胁方向。
- **受击方向校验**：在 `combat.gd:hit()` 中，计算受击向量相对舰体朝向的角度 `hit_angle`，仅当 `abs(angle_difference(hit_angle, shield_facing)) <= shield_current_arc * 0.5` 时才由护盾吸收伤害并产生硬辐能；否则直接绕过护盾命中对应方位的局部装甲网格。

#### 3.3.2 光束武器 (`Beam`)、EMP 电弧与航母战机联队
1. **光束武器 (`is_beam = true`)**：在 `combat.gd` 中为光束武器引入独立射线检测（`Geometry2D.segment_intersects_circle` / 多边形求交），命中护盾时**仅产生软辐能（Soft Flux）**而非硬辐能，但持续对护盾施加维持压力；命中无盾装甲时取 `0.5 * DPS` 计入非线性穿透。
2. **EMP 电弧 (`emp_damage > 0`)**：当电弧穿透护盾（或击中裸露船体）时，直接对目标的武器槽位或引擎施加临时瘫痪计时器（`disabled_timer`），配合程序化中点位移折线闪电特效，赋予电子战舰船战略价值。
3. **航母与战机联队 (`Carrier & Fighter Wings`)**：在 `HullResource` 中新增 `fighter_bays: int`（机库容量），支持搭载 `Interceptor`（截击机，优先拦截敌方导弹与战机）、`Fighter`（狗斗制空）与 `Bomber`（携带鱼雷周期性突防轰炸）。每艘航母维护独立的 `replacement_rate`（初始 `1.0`，战机损毁后消耗补充率并延长整备时间）。

---

### 3.4 数据驱动武器与船体管线（`.tres` + JSON 蓝图）

废除 `hull_catalog.gd` 中通过嵌套循环硬编码生成 53 船与 84 武器的做法，改为 Godot 原生强类型 `Resource` 资产管线：
- **`res://data/hulls/*.tres` (`HullResource`)**：定义 `id`、`display_name`、`hull_size`（`FRIGATE`..`CAPITAL`）、`faction_style`、`hp`、`base_armor`、`flux_capacity`、`flux_dissipation`、`shield_spec`、`ordnance_points`、`weapon_slots: Array[WeaponSlotDef]`、`engine_slots: Array[EngineSlotDef]`、`built_in_mods: Array[String]`、`fighter_bays: int`。
- **`res://data/skins/*.tres` (`HullSkinResource`)**：借鉴《远行星号》`.skin` 变体覆写机制，仅引用 `base_hull_id` 并局部覆写涂装色板、额外挂点或锁死炮塔为固定槽位（例如一键生成“掠夺者改装版”或“边防军重甲版”），以 10% 的配置成本将舰船池扩展至 3 倍以上。
- **`res://data/weapons/*.tres` (`WeaponResource`)**：显式定义伤害类型、单发伤害、弹丸速度、射程、冷却、幅能、备弹与装填速率（`ammo` / `ammo_per_sec`）、炮塔转速（`turn_rate`）、后坐力像素距离（`visual_recoil`）与 AI 提示标签（`PD` / `ANTI_SHIELD` / `STRIKE`）。

---

### 3.5 军官 AI 性格状态机与 X4 v7.50 飞行手感调优

#### 3.5.1 五档军官性格与目标滞回（Target Stickiness）
将 AI 决策从 `combat.gd:ai_mode()` 的单一阈值抽离为受船长性格驱动的效用评分状态机：

| AI 性格 | 退避幅能阈值 | 交战距离偏好 | 护盾/幅散策略 | 适用舰船定位 |
| :--- | :---: | :---: | :--- | :--- |
| **鲁莽 (`RECKLESS`)** | `92%` | 贴脸 (`0.55×` 最短射程) | 极少开盾，优先全武器倾泻，过载边缘才强行后撤 | 高机动突击护卫舰、近战重甲船 |
| **好战 (`AGGRESSIVE`)** | `85%` | 中近 (`0.75×` 平均射程) | 主动压进让点防与副炮进入射程，严格执行集火指令 | 主力巡洋舰、常规护航编队 |
| **稳健 (`STEADY`)** | `62%` | 标准 (`0.95×` 主炮射程) | 平衡开盾接弹与降盾散热，保持战线阵型 | 远程火力支援、标准战列舰 |
| **谨慎 (`CAUTIOUS`)** | `45%` | 远距 (`1.15×` 最长射程) | 高频开盾与提前幅散，倾向风筝拉扯 | 脆皮光束/导弹平台 |
| **胆怯 (`TIMID`)** | `28%` | 脱战边缘 | 一旦受击或己方劣势立即脱离交火圈 | 未受训民用货船/采矿船 |

同时在 `flight.gd:drive_ai()` 中为每艘 AI 舰船维护 `current_target_id` 与 `retarget_cooldown`（至少 `1.5s`），新目标评分必须超过当前目标 `1.35×` 才允许换靶，彻底消除炮塔与舰首在等距双目标间来回抽搐的 Bug。

#### 3.5.2 X4 v7.50 飞行物理与战斗打击感
1. **质量惯性漂移与独立助推能量池**：在 `flight.gd:step()` 中引入舰船总质量 $M = M_{\text{hull}} + \sum \text{cargo}_i$，加速度与制动率反比于 $M$；引入独立的 `boost_energy`（`0.0 ~ 100.0`，不消耗护盾或幅能），按住 `Space`（或侧向双击）消耗助推能量获得 `1.8×` 瞬时推力与高机动侧滑，松开后自动充能。
2. **战斗打击感闭环**：
   - 重炮开火/高爆穿透/主力舰殉爆时，触发随距离衰减的 `Camera2D` 震动与 `2–4` 帧的微顿挫（Hit-Stop，仅在旗舰承受或打出致命重击时触发，避免混战掉帧）；
   - 玩家鼠标悬停或锁定敌舰时，在 `sector_view` 实时绘制基于**当前选中武器组弹速与目标速度矢量**解算的**前置弹道预测环（Lead Indicator）**（求解一元二次追及方程 $|\vec{P}_t + \vec{V}_t t - \vec{P}_0| = v_{\text{proj}} t$ 的最小正实根 $t$）。

---

## 第 4 章：实体化动态经济、空间站建造与舰队自动化重构（对标《X4：基石》）

### 4.1 `economy.gd` 与 `world.gd` 现状深度审计

当前经济系统（`economy.gd` 共 565 行、`world.gd` 共 635 行）虽然跑通了“采矿 -> 精炼 -> 船厂造船 -> 货船跑商”的基础循环，并加入了黑市走私嫌疑（`inspect_departure()`）与跨星系企业禁运（`firms`），但在沙盒尺度扩大或长周期运行时会暴露出五项结构性短板：

1. **货品与工业树过于扁平 (`world.gd:11`, `economy.gd:308-346`)**：
   - `WARES` 仅包含 7 类货品（`矿石、合金、燃料、舰船补给、重工机械、日用消费品、违禁奢侈品`），且 `run_module()` 中非外域空间站每 6 天**无条件凭空生成** `舰船补给`、`日用消费品` 与 `燃料`（第 312–315 行：`station.stock[3] += 5 + efficiency` 等），严重违背了《X4：基石》的**全实体守恒律**——即使全宇宙矿船死绝，核心星区依然源源不断产出补给与燃料。
2. **造船与战损缺乏组件级闭环 (`economy.gd:326-339`)**：
   - 船厂（`module == 2`）每 30 天仅消耗单一物资 `合金`（`station.stock[1] -= recipe`）即可造出整艘舰船（含全套出厂武器 `stock_fit`），导致 `重工机械`（`ware = 4`）与武器市场脱节，战斗中的武器损耗与导弹消耗无法传导至上游制造业。
3. **空间站建造与仓储机制极度简化 (`economy.gd:200-240`)**：
   - 新建空间站只需在轨道带支付 `120` 信用点 + 卸下 `20` 单位合金 + 等待 `30` 日即可完工，且最多只能加建 1 个 `extension` 扩建模块（第 234 行），没有独立**建筑仓储（Build Storage）**、没有固体/液体/集装箱物理仓储分类，也没有居住区劳动力消耗食物/医疗换取额外产出的正向闭环。
4. **AI 航运“瞬移黑箱”与抢单死锁 (`economy.gd:375-451`)**：
   - `step_ship()` 通过 `begin_trip()` 计算 `eta` 后直接将船只置于 `travel` 字典中等待天数倒数，AI 商船既不在超空间与星系中真实航行（无法被玩家护航或海盗劫掠），也不会在 `trade_plan()` 中对目标空间站库存施加**交易预留锁（Reservation Lock）**——多艘商船会同时计算同一座矿站的最高利润并蜂拥而至，导致后到者扑空。
5. **舰队自动化缺少指挥层级与职责过滤 (`economy.gd:242-266`)**：
   - `assign()` 仅支持 `"贸易"、"采矿"、"护航"` 三种平级 `job.kind`，贸易/采矿必须手动指定固定 `source` 与 `target` 港口，缺乏“按站长辐射半径自动撮合”、“黑名单规避战区”、“模仿指挥官行为（Mimic）”以及战斗下的“拦截/轰炸/防御/补给”职责过滤器。

---

### 4.2 全实体化 Tier 0–3 工业有向无环图与经济消耗槽闭环

参考《X4：基石》的通用联邦经济与废料回收闭环，将 `world.gd:WARES` 从 7 类扩展为 **15 类强类型实体货品**，并强制引入**三重物理仓储分类**（`SOLID` 固体、`LIQUID` 液体、`CONTAINER` 集装箱），不同仓储类型不可混装（逼迫货船与矿船按船型分工）：

| 层级 | 货品 ID & 名称 | 仓储类型 | 上游输入配方（每生产周期） | 核心下游去向（Sink / Consumer） |
| :---: | :--- | :---: | :--- | :--- |
| **Tier 0** | `ore` 铁镍矿石 | `SOLID` | 小行星带/矿区物理采集 | 精炼金属、废料熔炉 |
| **Tier 0** | `silicon` 高纯硅砂 | `SOLID` | 小行星带/矿区物理采集 | 硅晶圆、电子芯片 |
| **Tier 0** | `ice` 冰晶水冰 | `SOLID` | 冰环/外域冰带采集 | 生命维持水、燃料合成 |
| **Tier 0** | `gas_h2` 聚变气（氢/氦） | `LIQUID` | 气态巨行星大气抽取（`celestial.gd` type>=20） | 燃料、反物质电池、冷却剂 |
| **Tier 0** | `energy` 能量电池 | `CONTAINER` | 太阳能阵列免费生产（受恒星类型 `STARS` 光照倍率影响） | **全宇宙所有生产与建造模块** |
| **Tier 1** | `alloy` 结构合金 | `CONTAINER` | `ore` + `energy` | 船体部件、空间站骨架 |
| **Tier 1** | `wafer` 硅晶圆 | `CONTAINER` | `silicon` + `energy` | 航电芯片、护盾/传感器组件 |
| **Tier 1** | `water` 净水 | `CONTAINER` | `ice` + `energy` | 居住区人口、食品/医疗 |
| **Tier 1** | `fuel` 跃迁燃料 | `CONTAINER` | `gas_h2` + `water` + `energy` | 舰船超空间跃迁消耗（取消凭空生成） |
| **Tier 2** | `hull_parts` 船体部件 | `CONTAINER` | `alloy` + `energy` | **所有造船订单、空间站模块建造、战后维修** |
| **Tier 2** | `electronics` 航电元件 | `CONTAINER` | `wafer` + `gas_h2` + `energy` | 空间站核心、武器/炮塔组件、船坞升级 |
| **Tier 2** | `food_med` 口粮与医疗 | `CONTAINER` | `water` + `energy`（生态模块产出） | **居住区劳动力不可逆日常消耗** |
| **Tier 3** | `ordnance` 武器与弹药组件 | `CONTAINER` | `alloy` + `electronics` + `energy` | **船坞装配武器、导弹/鱼雷补给、防御平台** |
| **Tier 3** | `engine_parts` 引擎与护盾组件 | `CONTAINER` | `alloy` + `electronics` + `gas_h2` | **造船厂主力舰建造、舰船维修** |
| **逆向** | `scrap` 战舰废料 | `SOLID` | 打捞船/回收船拆解战斗残骸 `wrecks` | 废料回收厂消耗大量 `energy` 逆向转化为 `alloy` 与 `hull_parts` |
| **黑市** | `luxury` 违禁奢侈品/旧帝国遗物 | `CONTAINER` | 遗迹打捞 / 黑市地下作坊 | 高利润走私、触发巡逻队盘查与把柄事件 |

#### 4.2.1 取消“凭空刷货”，打通四层经济消耗槽 (Economic Sinks)
1. **造船与装配真消耗**：AI 势力（`politics.gd:military()`）与玩家在船坞购买/建造舰船或更换武器时，必须真实扣除对应空间站的 `hull_parts`、`engine_parts`、`ordnance` 与 `electronics` 库存。若某派系矿船被玩家或海盗截杀导致船厂断料，其前线战损将无法补充，战局随之逆转。
2. **居住区人口不可逆消耗**：所有空间站的 `pop` 每日消耗 `food_med` 与 `water`，替代当前 `economy.gd:27-30` 中消耗 `燃料` 与 `舰船补给` 的不合理设定。
3. **战场残骸逆向回收循环**：`world.gd:destruction()` 生成的 `wrecks` 不再只是一次性捡 2 样货物，而是携带基于原舰体质量计算的 `scrap` 储量，由 `钩灯级回收船` 等专用船只拖回或拆解送往废料回收模块，打通“战争损毁 -> 废料 -> 船体部件 -> 新舰出坞”的闭环。

---

### 4.3 模块化空间站拓扑、劳动力效率曲线与贸易防死锁

#### 4.3.1 多模块自由扩展与独立建筑仓储 (`Build Storage`)
废除当前 `station.module`（主模块）+ `station.extension`（最多 1 个扩建）的硬编码上限，将空间站重构为**模块槽位数组 `modules: Array[StationModule]`**（例如基础空间站支持 4–8 个模块槽位）：
- 必须区分 **停靠设施（小型泊位 Dock / 大型泊位 Pier）**、**三类物理仓储模块（Solid / Liquid / Container）**、**生产模块**、**居住生态模块（Habitat）** 与 **防御/行政模块**。
- 新建或扩建模块时，物料（`hull_parts`、`electronics`、`energy`）不再混入空间站主贸易库存 `station.stock`，而是进入独立的 **`build_storage: Dictionary`**，由玩家货船或指派为“为建筑仓储运料”的 AI 货船专职配送，避免施工建材与市场商品互相污染。

#### 4.3.2 居住区劳动力（Workforce）效率曲线
参考 X4 的零额外原料消耗加成法则：空间站在零工人时以 `100%` 基础效率运行；当建造居住区并持续供应 `food_med` 与 `water` 后，人口迁入提供劳动力比例 $r = \min(1.0, W_{\text{avail}} / W_{\text{req}})$，使生产模块的实际产出倍率为：
$$M_{\text{output}} = 1.0 + r \cdot B_{\max} \quad (B_{\max} \in [0.25, 0.60])$$
**关键性质**：原材料输入量保持 `100%` 不变，仅成品产出提升最高 `60%`，以此激励玩家投资居住区与食品供应链。

#### 4.3.3 动态定价、交易预留锁 (`TradeReservation`) 与防死锁熔断
1. **库存水位线性定价**：每种货品定义 $[P_{\min}, P_{\text{avg}}, P_{\max}]$。买单（原料输入）随库存比例 $S \in [0, 1]$ 从 $P_{\max}$ 线性降至 $P_{\min}$；卖单（成品输出）随库存比例从 $P_{\max}$ 降至 $P_{\min}$，支持空间站经理自动调价或玩家手动锁定。
2. **物理预留锁与超时熔断**：在 `Economy` 中引入全局 `reservations: Dictionary`。当货船 A 锁定目标空间站 B 购买 40 单位合金时，立即在 B 站的逻辑可售库存中扣除 40 单位并生成一条带 `expire_day`（超时天数，如 `ETA + 10` 天）的预留记录。其他货船在计算 `trade_plan()` 时只能看到扣除预留后的净库存。若货船 A 中途被击毁、被玩家取消指令或超时未达，系统在 `tick()` 中自动熔断释放该预留锁，彻底杜绝幽灵订单锁死空间站。
3. **三维度贸易黑名单**：允许玩家与 AI 势力配置 `星区行进黑名单`（禁止飞越海盗/交战高危星区）、`星区活动黑名单`（禁止在该星区采矿/交易）与 `内部贸易规则`（锁定本势力空间站产出的 `hull_parts` 仅限内部流转，不卖给竞争对手）。

---

### 4.4 IS/OOS 双层模拟调度器与舰队指挥官职责树

为解决“全星区 AI 商船/矿船瞬移脱节”与“多船在场卡顿”的矛盾，引入简化版的 **IS（High Attention / 在场精细）vs OOS（Low Attention / 离场统计）双层模拟架构**：

```
[双层模拟调度器 Dual-Layer Attention Scheduler]
   玩家当前所在星系 (Active System)               其他 23~47+ 星系 (Background Systems)
  +-----------------------------------+          +-----------------------------------+
  |  High Attention (IS / 物理模拟)    |          |  Low Attention (OOS / 统计模拟)    |
  |  * 60Hz 刚体运动与惯性漂移         |  跃迁    |  * 按固定周期 (如每6游戏小时/1天)   |
  |  * 真实弹丸/光束/护盾/装甲网格结算  | <======> |  * 坐标沿航线矢量平滑推进 (无碰撞) |
  |  * 7层 ShipVisual2D 渲染与粒子     | 进出星系 |  * 遭遇战按 DPS*效率*RNG 统计扣血   |
  |  * 矿船/货船真实飞向矿带与泊位停靠  |          |  * 采矿按丰度与效率公式直接入库     |
  +-----------------------------------+          +-----------------------------------+
```

- **真实跨星系航行与拦截可能**：AI 商船与矿船不再瞬移，而是拥有真实的星系坐标 `pos` 与超空间坐标 `galpos`。在 OOS 状态下沿星图路径每日推进，若途经海盗活跃区或敌对势力封锁线，将按遭遇概率触发 OOS 战斗结算（甚至被击毁生成残骸 `wrecks`）；当玩家恰好进入同一星系（切换至 IS）时，可亲眼看到自己的货船正从引力点飞向空间站泊位，或正在被掠夺者追击并及时出手救援。
- **状态重对齐规则**：当实体从 OOS 切入 IS 瞬间，校验其坐标与空间站/其他舰船的最小安全间距，避免首帧重叠碰撞。

#### 4.4.1 `OrderQueue + DefaultBehavior` 与六大下属职责过滤器
重构 `vessel.job` 为双层控制器：
1. **`order_queue: Array[Order]`**：显式一次性指令队列（停靠、交易、转移货物、护航到点），执行完毕自动弹出。
2. **`default_behavior: Dictionary`**：队列为空时的常驻行为（停泊待命、自动采矿 `AutoMine`、自动贸易 `AutoTrade`、星区巡逻 `Patrol`、**模仿指挥官 `Mimic`**）。其中自动贸易/采矿半径由站长/船长管理等级决定（`1–5` 跳星门）。
3. **舰队六大下属职责（替代当前单一的 `"护航"`）**：
   - `ATTACK`（跟随攻击：集火旗舰目标）
   - `INTERCEPT`（拦截：主动索敌敌方护卫/驱逐舰与战机）
   - `BOMBARD`（轰炸：主动索敌敌方巡洋/主力舰）
   - `DEFEND`（防御：仅反击对旗舰开火的敌舰）
   - `SUPPLY`（补给：自动从周边港口采购燃料/弹药并飞向旗舰或母港补给）
   - `MIMIC`（模仿：独立复制指挥官的 `default_behavior`，实现 $O(1)$ 规模化商队/矿队配置）

---

## 第 5 章：角色驱动政治、继承博弈与动态叙事重构（对标《十字军之王3》）

### 5.1 `politics.gd` 与 `frontier.gd` 现状深度审计

当前角色与政治系统（`politics.gd` 共 590 行、`frontier.gd` 共 79 行）在“家族继承、摄政、5 种政体选举规则”方面搭出了极佳的骨架，但角色内核依然停留在“带名字的数值容器”阶段，缺少 CK3 级的戏剧张力与内生博弈：

1. **角色属性与特质极度贫瘠 (`world.gd:16, 176-185`)**：
   - 每个角色仅有一个 `trait: int`（`TRAITS := ["谨慎", "野心勃勃", "重情", "务实"]` 4 选 1），没有任何治理能力属性（外交/军事/管理/谋略），仅凭 `origin == 2` 给站长加 `+1` 效率（`economy.gd:309`），其余场景下船长与站长的能力差异几乎为零。
   - 缺少 **压力（Stress）** 系统。玩家或 AI 可以毫无心理代价地背刺盟友、苛捐杂税或流放亲属，不存在“违背角色性格（In-Character）”的惩罚机制。
2. **缺失秘密、把柄与主动计谋 (`politics.gd:23-35`)**：
   - 角色间互动只有 `influence()`（花 `¢35` 加 `18` 好感与 `8` 忠诚）和 `marry()`（联姻结盟）。没有秘密（走私、贪污、私生子、谋杀前任）、没有把柄（Weak/Strong Hook），也无法发起暗杀、绑架、诽谤或拉拢等阶段化计谋。
3. **内部派系（Factions）与政体契约缺失 (`politics.gd:495-535`)**：
   - `appointments()` 中的叛乱逻辑仅是一条简单掷骰：如果独立站长 `trait == 1`（野心勃勃）且 `opinion < 15`，就有 `22%` 概率直接独立建国；船长忠诚低于 20 就有 `30%` 概率直接卷船跑路。这种“无预警随机暴雷”缺乏先兆积累与玩家反制空间（如联姻安抚、恐怖值威慑、剥夺头衔或契约让步）。
   - 5 种政体（`REGIMES := ["世袭领", "议会共和国", "商团寡头", "军政府", "公司领"]`）仅在 `select_leader()` 选新领袖时有公式差异（`politics.gd:200-234`），在日常治理、税率谈判、舰队调动权限上完全同质化。
4. **叙事系统孤岛化 (`frontier.gd:1-79`)**：
   - 整个宇宙仅有开局晨曦自由港的「熄火之前」一条委托（沈照 -> 罗启山运 8 单位矿石）。一旦完成，全宇宙便不再有任何事件弹窗、道德抉择、行旅危机或角色关系演化。

---

### 5.2 角色实体 Schema 扩展与“压力-特质效用”引擎

将 `world.gd:person()` 中的角色字典升级为强类型 `CharacterData` Schema，注入 CK3 式的核心状态空间：

```gdscript
# 角色核心扩展 Schema（替代 world.gd:178 的扁平字典）
class_name CharacterData extends Resource

@export var id: int
@export var name: String
@export var house: String
@export var birth_day: int
# 1. 四维治理与指挥属性 (0 ~ 25+)
@export var stats := {"diplomacy": 6, "martial": 6, "stewardship": 6, "intrigue": 6}
# 2. 性格特质组 (2~3个互斥性格特质) + 先天遗传特质 + 应对特质
@export var personality_traits: Array[String] = [] # 如 ["brave", "greedy", "just"] vs ["craven", "generous", "arbitrary"]
@export var congenital_traits: Array[String] = []  # 如 ["quick", "robust"] (可遗传，含近亲惩罚)
@export var coping_traits: Array[String] = []      # 如 ["alcoholic", "journaller"]
# 3. 8维 AI 性格向量 (-100 ~ +100)，由特质自动汇总，驱动所有 AI 决策权重
@export var ai_vector := {"boldness": 0, "compassion": 0, "greed": 0, "honor": 0, "rationality": 0, "zeal": 0}
# 4. 压力、恐怖值与正统性状态机
@export var stress: int = 0                        # 0 ~ 400
@export var break_cooldown_day: int = 0
@export var dread: int = 0                         # 0 ~ 100 (恐怖值)
@export var legitimacy: int = 2                    # 0 ~ 5 级 (正统性，影响继承期好感与派系)
# 5. 秘密与把柄
@export var secrets: Array[Dictionary] = []        # [{"type": "smuggling", "target": id, "discovered_by": []}]
@export var hooks_held: Dictionary = {}            # {target_id: {"strength": "weak"|"strong", "reason": "...", "expire": day}}
```

#### 5.2.1 “压力（Stress）”惩罚与性格对齐引擎
- **触发规则**：任何玩家抉择、事件选项或管理动作（如：拥有 `generous` 慷慨特质的角色克扣船员薪水；拥有 `just` 公正特质的角色私吞黑市赃款或暗杀对手；拥有 `compassionate` 同情特质的角色击毁民用逃生舱）均附带 `stress_impact` 字典。
- **0–400 三级精神崩溃状态机**：
  - `100`（轻度崩溃）：强制触发崩溃事件，在“获得应对特质（如 `酗酒` 降属性或 `写航行日志` 缓慢减压）”与“承受永久属性惩罚”间抉择；
  - `200`（中度崩溃）：健康与寿命上限削减，可能获得高危性格突变（如 `偏执`、`专断`）；
  - `300`（重度崩溃）：随时面临突发猝死风险，且在 5 年（`1800` 游戏日）冷却期后若压力未降至 100 以下将再次崩溃。
- **反哺战斗与经济**：将角色的 `martial` 直接映射为旗舰/护航舰的武器冷却与射程微调（以及第 3 章的 AI 性格偏向）；将 `stewardship` 映射为空间站站长的劳动力上限与贸易税收加成；将 `diplomacy` 映射为黑市盘查豁免率与交涉折扣。

---

### 5.3 秘密、把柄与阶段化计谋系统

将 CK3 1.13 重构后的阶段化谍报引擎引入太空沙盒：
1. **秘密（Secrets）与把柄（Hooks）转化环**：
   - 角色在空间站走私违禁品（`suspicion` 过高）、私下资助海盗、篡改企业账本或暗中破坏空间站模块时，自动生成一条 `Secret`。
   - 玩家（或雇佣的驻站情报官）可执行 **“搜寻秘密（Find Secrets）”** 计谋。发现目标秘密后可选择：**公开揭露（Expose）**（重创目标在所属派系的正统性与好感，若涉及叛国/谋杀则赋予合法剥夺其站长/船长职务或宣战的理由）或 **暗中勒索（Blackmail）**（转化为对该角色的 `Weak Hook` 或 `Strong Hook`）。
   - **把柄用途**：强迫高好感门槛的贵族同意联姻、强迫企业董事放弃贸易禁运、强制压低封臣空间站的税收豁免要求、或在派系叛乱中强迫核心成员退群。
2. **阶段化计谋（Phased Schemes）**：
   - 支持 **敌意计谋**（破坏空间站生产、策反敌方船长带船投诚、暗杀敌对势力继承人）与 **个人计谋**（拉拢 `Sway`、结交挚友 `Befriend`、伪造债权把柄）。
   - 计谋不再是“点击后等概率成功”，而是分为 3–5 个离散阶段推进，期间可花费信用点或利用本地特工（如目标船上的轮机长、空间站港务员）提升成功率上限（Potential Cap）与隐蔽度（Secrecy），在阈值满意时手动收网。

---

### 5.4 政体差异化契约与内部派系叛乱状态机

#### 5.4.1 五大政体 (`world.gd:REGIMES`) 差异化契约与博弈机制
1. **世袭领 (`regime == 0`) — 封臣契约系统**：领主与每位拥有空间站或重型舰队的下属贵族维护一份独立契约（税率 3 档、舰队征召比例 3 档、以及“免剥夺权 / 理事会席位保障”等特殊权利）。修改契约需双向对等交换，或消耗 `Hook` 单方面强加。
2. **议会共和国 (`regime == 1`) — 执政官任期与弹劾投票**：每 4 年（`1440` 日）大选不仅比拼 `endorsement`，候选人还可通过消耗把柄与信用点游说议员席位；在任期间若 `tyranny`（暴政值）或战损过高，议会可发起不信任弹劾案提前下台。
3. **商团寡头 (`regime == 2`) & 公司领 (`regime == 4`) — 股权董事会与恶意收购**：势力领袖即为控股母公司董事长。下属站长与股东通过扩建盈利争夺股权（`shares`），玩家或 AI 可通过资本并购或商业禁运直接发起“董事会罢免投票”，实现不流血的政权更迭。
4. **军政府 (`regime == 3`) — 军功威望与兵变威胁**：统治合法性直接挂钩活跃主力舰数量与战功；若长期停战且军饷拖欠，前线舰队司令将积累不满度并发动军事政变。

#### 5.4.2 内部派系（Factions）叛乱状态机（替代当前随机独立）
取消 `politics.gd:505-514` 的突兀掷骰独立，建立透明可对抗的派系状态机：
- **四大派系类型**：`独立派系`（下属空间站要求脱离自立）、`减税/自治派系`（要求降低税率与赋予契约豁免）、`拥立宣称者派系`（推翻当前领袖/继承人）、`股东罢免派系`（公司领专属）。
- **不满度推进公式**：所有好感低于阈值且未被 `dread`（恐怖值）吓阻到 `Terrified`（惊恐）或未与领袖结盟的下属，可加入同一派系。当 `派系总舰队战力 >= 领袖总战力 × 80%` 时，不满度 `discontent` 每月按差值比例推进（`0% -> 100%`）；达到 `100%` 时向玩家发出**最后通牒**，玩家可选择**妥协让步**或爆发**可控的全面内战**。

---

### 5.5 `on_action + trigger + weight_multiplier` 动态叙事事件引擎

将 `frontier.gd` 从单一硬编码任务升级为数据驱动的**符号化动态事件调度器 (`EventEngine`)**，覆盖“熄火之前”之后的漫长星际生涯：

```
[事件调度执行流]
生命周期钩子 (on_action: on_dock / on_jump / on_battle_won / on_monthly_pulse / on_succession)
   │
   ▼
遍历事件模板库 (res://data/events/*.json) ──► 评估硬门控 trigger (如: is_noble, cargo_ore >= 10, stress >= 100)
   │
   ▼ (通过过滤的候选池)
计算动态权重: Final_Weight = base_weight * Π(weight_multiplier)
   │   (例: 若船长拥有 "greedy" 特质, 走私诱惑事件权重 x3.0; 若在荒芜外域, 故障事件权重 x2.5)
   ▼
加权随机抽样 ──► 推送至主界面事件弹窗 (暂停时间 world.attention = true)
   │
   ▼
玩家/AI 抉择 Option ──► 执行 Effects (增减资源/好感/秘密/把柄) + 结算 Stress Impact
```

- **星际旅行危险与航行事件**：在超空间跃迁或长途航行中，触发“跃迁引擎异常”、“船员思乡/哗变前兆”、“发现旧帝国求救信标（真实救援 vs 海盗诱饵陷阱）”、“黑市掮客密电”等事件，彻底填补跑商与探索途中的叙事空白。

---

## 第 6 章：软件工程架构、UI/UX、音频与 Agent 生态重构

### 6.1 类型安全重构与模块解耦

1. **强类型实体类替代裸 `Dictionary`**：
   - 在 `res://scripts/models/` 下建立 `ShipData`、`BattleState`、`FittingData`、`StationData`、`PersonData`、`FactionData`、`SystemData` 等 `RefCounted` 或 `Resource` 子类（带 `class_name` 与明确静态类型注解）。
   - 为每个模型类实现标准 `to_dict() -> Dictionary` 与 `static func from_dict(d: Dictionary)` 序列化接口，确保 `World.snapshot()` 与 `migrate()`（升至 `VERSION := 7`）在保留 v3–v6 向下兼容性的同时，在运行时享有 100% 的静态类型检查与内存布局优化。
2. **解耦 `game.gd` 上帝类与引入 `EventBus`**：
   - 将 `game.gd` 拆分为：`GameRoot`（场景生命周期与顶层状态）、`ThemeManager`（加载独立 `.tres` 主题资源而非运行时拼装 `StyleBoxFlat`）、`SaveManager`（异步安全读写与版本迁移）、`InputController`（键鼠与镜头控制）。
   - 引入全局轻量级信号总线 `EventBus`（如 `ship_damaged`、`flux_overloaded`、`market_updated`、`character_stressed`），各 UI 面板仅订阅自己关心的信号进行**局部增量刷新**，彻底废除 `clear(body)` 全量销毁重建模式。

---

### 6.2 UI/UX 范式升级：场景化 UI、嵌套工具提示与战术视图

1. **`.tscn` 场景化 UI 与增量列表复用**：
   - 将 `show_creator()`、`dock_view.gd`、`panels.gd` 的硬编码布局迁移为独立的 Godot `.tscn` 场景预制体（`CreatorScreen.tscn`、`DockOverlay.tscn`、`SidePanel.tscn`、`RefitBench.tscn`）。
   - 在 `RefitBench.tscn`（整备界面）中，将舰船放大渲染在带像素比例网格的蓝图背景上，**直接在各槽位实际坐标处绘制交互按钮与射界扇形弧（`arc`）**，支持按武器类型颜色编码（实弹琥珀、能量青蓝、导弹翠绿）直观拖拽或点击换装。
2. **CK3 式嵌套工具提示 (`NestedTooltip.gd`)**：
   - 替换当前原生单行 `tooltip_text`（如 `panels.gd:371` 与 `dock_view.gd:322`）。实现一个全局 `TooltipLayer (CanvasLayer)`：
     - 支持 BBCode 高亮下划线概念词（如 `[url=concept:hard_flux]硬辐能[/url]`、`[url=concept:strong_hook]强把柄[/url]`）；
     - 悬停 `0.45s` 或按中键**锁定面板**，鼠标移入面板内任意概念词即可递归弹出子级解释与实时公式拆解（L1 结果 -> L2 红绿加减归因项 -> L3 规则定义 -> L4 行动建议），极大降低三核高复杂度机制的学习门槛。
3. **Starsector 式战术 `Tab` 全局视图与传感器圈层地图**：
   - 当前 `Tab` 键仅在屏幕下方打开一个 4 个按钮的指令条（`game.gd:374-379`）。将其升级为真正的**全屏战术覆盖视图（Tactical Overlay）**：切换为矢量几何图标（三角/菱形/六边形区分舰级）、绘制所有友军与敌军的武器最大射程圈、护盾朝向弧、护航目标连线，并支持鼠标框选多艘僚舰右键下达航路点或集火目标。
   - 在 `sector_view.gd`（星系与超空间视图）中，将 `transponder`（应答器）与 `ping`（主动脉冲）的数值影响**几何可视化**：围绕玩家旗舰绘制两圈同心圆——青色虚线为**自身探测半径（Sensor Range）**，琥珀/红色虚线为**被敌方探测半径（Detected-At Range）**。开启 `T` 应答器或 `R` 主动脉冲时，被探测圈剧烈扩张；关闭应答器并躲入星云/小行星带时，该圈急剧收缩，将隐匿走私转化为直观的空间博弈。

---

### 6.3 `audio.gd` 视听耦合矩阵升级

基于现有纯程序化 PCM 合成器（无需外部版权音频文件，保持零外部依赖优势），进行四项关键升级：
1. **空间化 2D 音频池**：将战斗音效通道从全局 `AudioStreamPlayer` 升级为 `AudioStreamPlayer2D`（或根据事件坐标 `event.pos` 到 `camera` 的距离计算衰减增益 `volume_db` 与左右声道声像 `pan`），确保视野边缘的炮击声远低于旗舰贴脸受击声。
2. **材质与事件音色分化**：严格落实视听耦合矩阵——护盾受击使用高频带通滤波电磁嗡鸣；装甲受击使用低频金属撕裂+噪声爆发；主动幅散 `vent` 增加持续循环的高压泄压嘶鸣声；高爆穿透船体触发低频重击并伴随 `0.15s` 的瞬间环境音闪避（Audio Ducking）。
3. **动态战斗音景层**：在 `ambient_player` 之外增加一层低频脉冲战斗音轨，当旗舰处于 `vessel.locked == true` 且周边敌舰战力比高时平滑淡入，脱战后淡出。

---

### 6.4 `agent_bridge.gd` 与 `verify.gd` 自动化回归扩展

1. **`agent_bridge.gd` 协议升级 (`PROTOCOL := 2`)**：
   - 补充暴露缺失的核心操作接口：`refit_slot`、`refit_tuning`、`assign_role`（分配舰队 6 大职责）、`station_expand`、`diplomacy_action`（送礼/联姻/发现秘密/勒索把柄/启动计谋）、`event_choice`（响应动态叙事事件弹窗）。
   - 在 `observe()` 中增加局部 `armor_grid` 最低格健康度、护盾当前朝向与弧度、`stress` 数值与 `active_factions` 派系不满度摘要，使外部 AI Agent 能够真正以策略深度游玩重构后的游戏。
2. **`verify.gd` 回归测试矩阵扩展**：
   - **战斗物理与装甲网格压测**：新增 `armor_grid_and_shields()`，验证非线性减伤公式、5% 残余装甲保底、侧翼绕后击穿无盾区、光束仅生软辐能与目标滞回稳定性。
   - **长周期经济守恒与防死锁校验**：新增 `economy_conservation_10000d()`，运行 10,000 游戏日无玩家干预模拟，断言全宇宙所有仓储非负、无超时未释放的幽灵 `TradeReservation`、造船消耗真实拉动上游矿产。
   - **CK3 政治状态机校验**：新增 `stress_hooks_factions()`，验证违背性格累计压力触发 1–3 级精神崩溃、秘密->把柄->强迫联姻/退群流转、以及派系不满度 100% 触发内战的完整链路。
   - **场景与渲染泄漏冒烟测试**：断言连续执行 50 次 `dock()`/`depart()` 与 `refresh()` 后，场景树节点总数保持恒定（无孤儿节点泄漏）。

---

## 第 7 章：分阶段实施路线图（P0–P3）与量化验收标准

为确保 AI Agent 与工程团队在不破坏现有可玩 Demo（`verify.gd` 12 组现有测试始终保持绿灯）的前提下平滑演进，建议按 **P0 -> P1 -> P2 -> P3** 四个里程碑推进，总周期约 **10–12 周**：

### 7.1 P0：止血与工程基座阶段（第 1–2 周）
* **核心目标**：在不改变外在玩法表现的前提下，完成数据结构强类型化、UI 增量刷新架构与场景分离，消除重构阻力。
* **可执行任务清单**：
  1. 建立 `res://scripts/models/` 强类型数据类（`ShipData`、`PersonData`、`StationData`、`WorldState`）与 `World.VERSION := 7` 存档迁移器（确保 `verify.gd:old_combat_saves()` 及 v3–v6 存档无缝升级）。
  2. 将 `game.gd` 拆分为 `GameRoot`、`ThemeManager`（导出 `res://assets/main_theme.tres`）、`SaveManager` 与 `EventBus`。
  3. 将 `flight.gd` 战斗与弹道步进锁定在固定物理步长（`Fixed Timestep 60Hz`），防止高刷屏/掉帧下高速动能弹穿透。
  4. 将 `sector_view.gd` 从单 `Control._draw()` 拆分为 `BattleWorld2D (Node2D)` + `Camera2D` + `HudLayer (CanvasLayer)`。
* **阶段验收标准**：`verify.gd` 原有全部检查项 100% 通过；停靠市场连续切换与买卖 100 次无节点数增长泄漏；60Hz 物理帧时间稳定 `< 4ms`。

### 7.2 P1：实时战术海战与视觉飞跃阶段（第 3–5 周）
* **核心目标**：全面兑现《远行星号》级视觉质感与《远行星号+X4》双核战斗手感。
* **可执行任务清单**：
  1. 升级 `art/pixel_art.gd` 按舰级输出 `80×56` ~ `208×144` 高精细度分层贴图（底图、导能发光层、独立炮塔底座与炮管、8 势力涂装语法），实现 `ShipVisual2D` 7 层节点树与炮管开火后坐力动画。
  2. 部署 2.3 节所述两套 `GL Compatibility` GLSL 着色器（局部装甲损伤+闪白 Shader、方向性护盾弧展开+涟漪 Shader），并接入 Additive 混合光束、EMP 电弧、相位残影与幅散蒸汽粒子。
  3. 重构 `combat.gd`：落地 `7×5` 离散 `armor_grid` 与非线性 $\frac{D_{\text{eff}}}{A_{\text{cell}}+D_{\text{eff}}}$ 减伤公式；落地 `FRONT`/`OMNI` 方向性护盾状态机；实现光束武器、EMP 瘫痪与航母战机联队。
  4. 重构 `flight.gd`：落地 X4 v7.50 质量惯性漂移与独立 `boost_energy` 能量池；落地 5 档军官 AI 性格与 `1.5s` 目标滞回；在 HUD 实装前置弹道预测环、双色（青+纯白）幅能条、Hit-Stop 与 `audio.gd` 空间化衰减音效。
  5. 升级 `Tab` 键为全屏矢量战术地图，并在星系/超空间视图中绘制探测圈与被探测圈。
* **阶段验收标准**：同屏 40 艘舰船 + 300 发弹丸/光束混战下，在 GTX 1060 / 核显级设备维持 `>= 60 FPS`（`Draw Calls <= 180`）；新增 `armor_grid_and_shields()` 测试全绿。

### 7.3 P2：实体经济、IS/OOS 与 CK3 角色政治阶段（第 6–9 周）
* **核心目标**：打通“战斗 <-> 经济 <-> 政治”三核深度反馈闭环，消除中后期挂机空虚感。
* **可执行任务清单**：
  1. 扩展 `world.gd:WARES` 至 15 类货品与 3 类物理仓储；取消核心区凭空刷货，打通“战损残骸 -> 废料回收 -> 船体/武器组件 -> 船坞造船”闭环；实装空间站多模块建造、独立 `Build Storage` 与居住区劳动力效率曲线。
  2. 在 `economy.gd` 实装带超时熔断的 `TradeReservation` 预留锁、三维度黑名单、IS/OOS 双层模拟调度器，以及 `OrderQueue + DefaultBehavior` 与舰队 6 大下属职责过滤器（含 `Mimic`）。
  3. 在 `politics.gd` 实装 4 维能力属性、互斥性格特质、8 维 AI 性格向量与 `0–400` 压力/精神崩溃状态机；实装秘密、把柄（Weak/Strong Hook）与阶段化计谋系统；重构 5 大政体差异化契约与派系不满度叛乱状态机。
  4. 升级 `portrait.gd` 至 `128×144` 2.5D 光影肖像与年龄/伤病/派系制服映射；落地 `on_action + trigger + weight_multiplier` 动态叙事事件引擎（首批实装 >= 35 个覆盖贸易/行旅/崩溃/内政的分支事件）。
  5. 实装 CK3 式 `NestedTooltip.gd` 嵌套工具提示与全新 `.tscn` 整备/逻辑概览界面。
* **阶段验收标准**：10,000 游戏日无人干预挂机测试中，全宇宙无负库存、无幽灵预留锁、无政权死锁；`stress_hooks_factions()` 与 `economy_conservation_10000d()` 测试 100% 通过。

### 7.4 P3：终局危机、数据驱动与 Mod 生态阶段（第 10–12 周）
* **核心目标**：完成数据与代码彻底分离，提供高重玩价值的终局挑战与外部生态接口。
* **可执行任务清单**：
  1. 废除 `hull_catalog.gd` 硬编码目录，全面迁移至 `res://data/hulls/*.tres`、`res://data/weapons/*.tres`、`res://data/skins/*.tres` 与外部 JSON 事件包加载器，支持启动时校验与 Mod 覆写加载。
  2. 实装两大动态终局危机：**外域失控自复制 AI 蜂群（对标 `[THREAT]`）** 与 **高资产帝国引发的星区联合封锁/殖民地危机（对标 Starsector `Colony Crises` & X4 `Existential Crisis`）**，以及古代星门遗迹重连任务链。
  3. 升级 `agent_bridge.gd` 至 `PROTOCOL := 2`，补全整备、外交、事件抉择与多舰队职责指派接口，并更新 `AGENT_PLAY.md` 与 `verify_agent.ps1`。
* **阶段验收标准**：支持外挂一个示例 Mod 目录零代码修改新增 1 艘舰船与 2 个动态事件；`agent_bridge` 协议 v2 全流程 AI 通关/跑商/海战/政治联姻脚本验收通过。

---

### 7.5 工程与 QA 量化验收总表

| 验收维度 | 指标项 | 目标阈值 (Pass Criteria) | 验证手段 |
| :--- | :--- | :--- | :--- |
| **性能与渲染** | 40 舰混战帧率 (1440×900) | `>= 60 FPS`，单帧物理 `< 4ms` | 内置性能剖析器 + 压测场景 |
| **性能与渲染** | Draw Calls 与节点泄漏 | 混战 `Draw Calls <= 180`；50 次开关界面孤儿节点增量 `= 0` | `verify.gd` 场景树节点计数断言 |
| **经济模拟** | 10,000 日守恒与防死锁 | 库存全非负；超时预留锁释放率 `100%`；核心航线无永久停摆 | `verify.gd:economy_conservation_10000d()` |
| **战斗机制** | 装甲网格与护盾交互 | 非线性公式误差 `< 0.1%`；护盾绕后未命中率 `100%` 穿透护甲 | `verify.gd:armor_grid_and_shields()` |
| **政治与叙事** | 压力/把柄/派系闭环 | 压力阈值 `100/200/300` 崩溃正常触发；`>= 35` 个动态事件可触发 | `verify.gd:stress_hooks_factions()` |
| **存档与兼容性** | 跨版本迁移 | `v3 / v4 / v5 / v6` 旧存档 100% 无损迁移至 `v7` 并通过校验 | `verify.gd:old_combat_saves()` |
| **Agent 生态** | `agent_bridge` v2 | 覆盖观察、飞行、战斗、整备、贸易、建造、外交、事件 100% 动作集 | `verify_agent.ps1` 端到端闭环 |

---

## 第 8 章：面向 AI Agent 执行的模块契约、算法规范与工单拆解

本章将第 1 至第 7 章的架构设计转化为**可直接交付 AI Coding Agent 执行的零歧义技术规范**，涵盖数据结构与存档迁移映射、核心战斗/经济/政治算法、数据资产 Schema、Agent 协议 v2 契约以及细粒度工程工单列表。

### 8.1 强类型数据模型与 `v6 -> v7` 存档迁移映射表

当前 `world.gd` 中所有实体均采用无类型 `Dictionary` 存储（`ships`、`ports`、`people`、`factions`、`firms`）。在 P0 阶段重构为强类型 `RefCounted` 模型类后，必须保证 `World.load_state()` 能够将 `VERSION := 3..6` 的历史存档无损迁移至 `VERSION := 7`。

| 原 `world.gd` 字典实体与键 | 目标强类型类与属性 | `v6 -> v7` 迁移转换逻辑与默认值策略 |
| :--- | :--- | :--- |
| `ships[id].kind / hp / cargo / fuel` | `ShipData.hull_id: String` / `hp` / `cargo: Dictionary` / `fuel` | 将整型 `kind (0..52)` 映射为语义化 `hull_id`（如 `0 -> "beacon_ff"`、`7 -> "longnight_bb"`）；旧 `cargo` 7 位数组按索引映射至新 15 类货品字典，其余补 `0` |
| `ships[id].battle.armor` | `BattleState.armor_grid: PackedFloat32Array` | 若旧存档仅有标量 `armor`，按均匀分布写入 `7×5` 共 35 个网格单元：$A_{\text{cell}} = \frac{\text{old\_armor}}{A_{\text{base}}} \times A_{\text{cell\_max}}$，确保残甲比例无损继承 |
| `ships[id].battle.shield` | `BattleState.shield_active` / `shield_facing` / `shield_arc` | 旧布尔值 `true` 映射为 `shield_active = true` 且 `shield_arc = hull.shield_max_arc`，`shield_facing = 0.0` |
| `ships[id].job` | `ShipData.order_queue: Array[ShipOrder]` + `default_behavior` | 若旧 `job.kind == "护航"`，转为 `default_behavior = {"role": "DEFEND", "commander_id": owner_flagship}`；若为 `"贸易"`/`"采矿"`，转为对应 `AutoTrade`/`AutoMine` 默认行为 |
| `ports[id].module / extension` | `StationData.modules: Array[StationModule]` + `build_storage` | 主模块 `module` 与扩建 `extension >= 0` 转为 `modules` 数组的前两个节点；自动补充对应的基础 `Dock` 与 `Storage` 节点防止旧存档空间站无法停靠 |
| `people[id].trait / opinions / loyalty` | `PersonData.personality_traits` / `stats` / `stress` / `dread` | 原 `trait (0..3)` 映射为性格特质种子（`0->cautious`, `1->ambitious`, `2->compassionate`, `3->pragmatic`），并基于 `rng` 与 `origin` 补全四维属性与 `stress = 0` |
| `factions[flag].regime / style` | `FactionData.regime_laws` / `diplomacy_matrix` | 保留 `regime` 与 `style` 枚举，初始化政体专属契约默认值（如 `regime == 0` 世袭领为下属贵族空间站生成标准税收/征召契约） |

---

### 8.2 战斗物理与护甲/护盾核心算法参考实现

为了消除 `combat.gd` 中单一标量装甲与全向护盾的失真，Agent 在重构 `CombatResolver` 时应严格实现以下两个核心算法：

#### 8.2.1 二维离散装甲网格命中与溅射算法
```gdscript
# 7x5 离散装甲网格定位与非线性减伤结算（适配 combat.gd 重构）
const GRID_W := 7
const GRID_H := 5
const MIN_RESIDUAL_RATIO := 0.05
const MAX_ARMOR_DR := 0.85

static func resolve_armor_hit(ship: ShipData, world_pos: Vector2, raw_dmg: float, dmg_type: int, is_beam: bool) -> float:
	var hull: HullResource = DataRegistry.get_hull(ship.hull_id)
	# 1. 将世界命中点转换至舰船局部坐标系（+X 为舰首，+Y 为右舷）
	var local: Vector2 = (world_pos - ship.pos).rotated(-ship.heading)
	var half_extents: Vector2 = hull.bounds_half_size
	var nx := clampf((local.x + half_extents.x) / (2.0 * half_extents.x), 0.0, 0.999)
	var ny := clampf((local.y + half_extents.y) / (2.0 * half_extents.y), 0.0, 0.999)
	var gx := int(nx * GRID_W)
	var gy := int(ny * GRID_H)

	# 2. 计算有效单发伤害（光束取 50% 等效穿透）
	var mult: float = Hulls.ARMOR_MULT[dmg_type]
	var eff_hit := (raw_dmg * 0.5 if is_beam else raw_dmg) * mult
	var cell_base := hull.base_armor / float(GRID_W * GRID_H) * 4.0 # 单格额定装甲
	var cell_idx := gy * GRID_W + gx
	var current_cell := ship.battle.armor_grid[cell_idx]

	# 3. 5% 最低残余装甲保底 + 非线性减伤公式 D / (A + D)
	var eff_armor := maxf(current_cell, cell_base * MIN_RESIDUAL_RATIO)
	var raw_ratio := eff_hit / (eff_armor + eff_hit) if (eff_armor + eff_hit) > 0.0 else 1.0
	var dmg_ratio := maxf(raw_ratio, 1.0 - MAX_ARMOR_DR)
	var hull_damage := eff_hit * dmg_ratio

	# 4. 扣减主命中格与 8 邻域 35% 溅射剥离
	ship.battle.armor_grid[cell_idx] = maxf(0.0, current_cell - hull_damage)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var sx := gx + dx
			var sy := gy + dy
			if sx >= 0 and sx < GRID_W and sy >= 0 and sy < GRID_H:
				var s_idx := sy * GRID_W + sx
				ship.battle.armor_grid[s_idx] = maxf(0.0, ship.battle.armor_grid[s_idx] - hull_damage * 0.35)

	ship.hp -= hull_damage
	ship.battle.armor_mask_dirty = true # 通知 ShipVisual2D 刷新 GPU 着色器纹理
	return hull_damage
```

#### 8.2.2 方向性护盾展开、旋转与受击判定
* **步进更新 (`tick_shield`)**：
  - 当 `shield_active == true` 且未过载/未幅散时，`shield_arc = move_toward(shield_arc, hull.shield_max_arc, hull.shield_unfold_rate * delta)`，同时每秒累加 `hull.shield_upkeep * delta` 的**软辐能**。
  - 若护盾类型为 `OMNI`（全向盾），`shield_facing` 每帧以 `hull.shield_turn_rate * delta` 旋转朝向 `desired_shield_angle`（玩家为鼠标相对舰船坐标角，AI 为最高威胁敌舰或最近来袭弹丸方向角）；若为 `FRONT`（前置盾），`shield_facing` 恒定为 `0.0`。
* **受击判定 (`try_shield_absorb`)**：
  - 计算弹丸命中点相对舰船中心的方向角 `hit_local_angle = (world_pos - ship.pos).angle() - ship.heading`。
  - 若 `absf(angle_difference(hit_local_angle, ship.battle.shield_facing)) <= ship.battle.shield_arc * 0.5`，判定为护盾命中！按 `raw_dmg * Hulls.SHIELD_MULT[dmg_type] * hull.shield_efficiency` 转化为**硬辐能**（若为光束武器则转化为**软辐能**），并向渲染层发送 `shield_ripple(hit_local_angle)` 事件；否则直接穿透至 `resolve_armor_hit()`。

---

### 8.3 经济预留锁、IS/OOS 双层模拟与状态重对齐规范

#### 8.3.1 交易预留锁 (`TradeReservation`) 数据结构与防死锁流程
在 `EconomyManager` 中维护 `reservations: Dictionary`（键为 `reservation_id: int`）：
1. **创建预留**：当 AI 货船决定从 `source_port` 购买 `qty` 单位 `ware` 并运往 `target_port` 时，同时注册一条出库预留（锁定 `source_port` 的可售库存）与一条入库预留（锁定 `target_port` 的剩余仓储配额），设置 `expire_day = world.day + max(12, eta_days * 2)`。
2. **可用库存计算公式**：
   $$\text{Available\_Sell}(p, w) = \max\left(0,\ \text{Stock}(p, w) - \sum_{r \in \text{Outbound}(p, w)} r.\text{qty}\right)$$
   $$\text{Available\_Buy\_Space}(p, w) = \max\left(0,\ \text{Cap}(p, w) - \text{Stock}(p, w) - \sum_{r \in \text{Inbound}(p, w)} r.\text{qty}\right)$$
3. **异常释放与超时熔断**：当货船在 `world.destruction()` 中被摧毁、被玩家重新指派任务或被黑名单拦截时，立即调用 `release_reservations_for_ship(ship_id)`；此外，每日 `Economy.tick()` 扫描 `world.day > r.expire_day` 的过期记录并强制释放，同时记录诊断日志以便回归测试监控。

#### 8.3.2 IS/OOS 双层模拟切换与坐标重对齐规则
- **OOS 航行推进**：非玩家所在星系的 AI 舰船在每 `0.25` 游戏日（或每日）执行一次矢量推进：若在星系内，向目标引力点或空间站坐标移动 `speed * oos_step_dist`；若在超空间，向目标星系 `pos` 推进并按距离扣减 `fuel`。
- **OOS 遭遇战统计结算**：当两艘敌对舰船在 OOS 同一星系内距离小于 `240.0` 时，不生成实体弹丸，而是按双方有效战力与巡航速度计算交战概率；触发交火时，直接按 `有效 DPS × 护盾/装甲修正系数 × 炮塔修正(0.35) × Δt` 双方扣血。若一方归零，同样调用 `world.destruction()` 生成残骸 `wrecks` 并触发造船厂补船订单。
- **IS 状态重对齐（Reconciliation）**：当玩家跃迁进入某个星系（该星系从 OOS 切入 IS）的瞬间，系统遍历该星系内所有处于飞行状态的舰船：
  1. 若某艘船坐标与空间站中心距离小于 `90.0`（且非停靠状态），将其沿外法线推离至 `105.0` 半径处；
  2. 若两艘舰船间距小于各自 `CLASS_RADIUS` 之和，沿连线方向微调分离，防止进入 IS 首帧发生物理碰撞弹飞；
  3. 依据舰船当前 `hp / max_hp` 比例同步初始化其 `armor_grid` 与局部损伤着色器状态。

---

### 8.4 动态叙事事件引擎 (`EventEngine`) JSON Schema 与 `on_action` 钩子

为了将 `frontier.gd` 扩展为类似 CK3 的海量动态事件网络，所有事件模板统一存放在 `res://data/events/*.json`，由 `EventEngine` 在启动时加载并建立 `on_action` 索引：

```json
{
  "id": "frontier.smuggler_bribe_01",
  "on_action": "on_dock_regular_port",
  "title": "港务稽查员的暗示",
  "body": "在 {port_name} 卸货时，一名身穿灰领制服的港务稽查员悄悄拦住了你的去路，目光有意无意地扫过你货舱里的异常铅封箱……",
  "base_weight": 100,
  "cooldown_days": 180,
  "trigger": {
    "player_cargo_gte": {"luxury": 2},
    "player_suspicion_gte": 15
  },
  "weight_multipliers": [
    {"factor": 2.5, "condition": {"has_trait": "greedy"}},
    {"factor": 0.4, "condition": {"stat_gte": {"intrigue": 12}}}
  ],
  "options": [
    {
      "label": "塞给他一笔封口费（¢65）",
      "stress_impact": {"honest": 25, "just": 20, "greedy": 15},
      "effects": {"credit": -65, "suspicion": -15, "grant_secret_to_contact": "bribery"}
    },
    {
      "label": "亮出他上个月收受海盗回扣的把柄",
      "require_hook_on_manager": "weak",
      "effects": {"consume_hook": true, "suspicion": -30, "opinion_manager": -15}
    },
    {
      "label": "拒绝妥协，强行配合例行开箱检查",
      "stress_impact": {"arbitrary": 15, "just": -20},
      "effects": {"confiscate_ware": "luxury", "credit": -40, "legitimacy": 1}
    }
  ]
}
```

#### 8.4.1 核心 `on_action` 生命周期钩子全表
* `on_dock_regular_port` / `on_dock_wild_port`：停靠正规港或外域前哨时触发（走私盘查、酒吧招募、派系密使、黑市交易）。
* `on_hyperspace_jump`：每次跃入超空间或到达星系引力点时触发（跃迁引擎故障、未知求救信号、滑流奇遇、海盗伏击抉择）。
* `on_battle_victory` / `on_ship_captured`：战斗胜利或俘获敌舰时触发（俘虏处决/赎金抉择、打捞古代数据核心、船长居功自傲）。
* `on_monthly_pulse`（每 30 日）：低频角色与政治脉冲（家族成员密谋、秘密泄露、压力崩溃预警、企业董事会摩擦）。
* `on_succession`：主角死亡继承或摄政交权时触发（新君即位加冕/宣誓、兄弟分产争端、摄政篡权危机）。

---

### 8.5 `agent_bridge.gd` 协议 v2 扩展规范

为保证本地 AI Agent 能够完整驾驭重构后的三核系统，`agent_bridge.gd` 应从 `PROTOCOL := 1` 升级至 `PROTOCOL := 2`，在保持现有 `observe`、`step`、`trade`、`dock`、`jump` 等动作向后兼容的基础上，新增以下核心动作契约：

| 动作名 (`action`) | 必需参数 (`args`) | 校验规则与执行逻辑 | 返回增量 (`result`) |
| :--- | :--- | :--- | :--- |
| `refit_slot` | `slot: int`, `weapon: String`, `black: bool` | 校验停靠状态、槽位尺寸与 OP 上限，扣款并更新 `FittingData` | `{"used_op": int, "free_op": int}` |
| `refit_tuning` | `caps_delta: int`, `vents_delta: int` | 调整电容与散热点数，校验 OP 与资金 | `{"capacity": float, "dissipation": float}` |
| `assign_role` | `ship: int`, `captain: int`, `role: String`, `commander: int` | 分配 6 大舰队职责（`ATTACK`/`INTERCEPT`/`BOMBARD`/`DEFEND`/`SUPPLY`/`MIMIC`） | `{"ship": int, "role": String}` |
| `diplomacy_action` | `target_person: int`, `kind: String` | 支持 `gift`/`marry`/`find_secrets`/`blackmail`/`scheme_murder`/`sway` | `{"success": bool, "hook_gained": String}` |
| `event_choice` | `event_id: String`, `option_index: int` | 当 `state.pending_event` 非空时响应叙事事件选项并解除 `attention` 暂停 | `{"stress": int, "effects_applied": Array}` |
| `set_blacklist` | `scope: String`, `system_id: int`, `blocked: bool` | 配置贸易/航行黑名单，防止 AI 商船误入交战星区 | `{"blacklisted_systems": Array}` |

---

### 8.6 可执行工程工单（Tickets）拆解与优先级矩阵

以下工单列表可直接作为 AI Agent 或研发团队的 Sprint 任务看板，每条工单均明确了目标文件、前置依赖与验收标准：

| 工单编号 | 阶段 | 目标模块/文件 | 核心改造内容 | 前置依赖 | 验收标准（Definition of Done） |
| :---: | :---: | :--- | :--- | :---: | :--- |
| **T-001** | P0 | `scripts/models/*.gd`, `world.gd` | 定义 `ShipData`/`PersonData`/`StationData` 强类型类与 `v7` 迁移器 | 无 | `verify.gd` 12 组测试全绿；`old_combat_saves()` 支持 v3–v6 迁移至 v7 |
| **T-002** | P0 | `game.gd`, `ThemeManager` | 拆分 `game.gd` 上帝类，导出 `.tres` 主题，引入 `EventBus` 局部刷新 | T-001 | 连续切换页签与交易 100 次无孤儿节点增长 |
| **T-003** | P0 | `flight.gd`, `sector_view.gd` | 锁定 60Hz 固定物理步长；拆分 `BattleWorld2D` 与 `HudLayer` | T-002 | 帧率波动下高速弹丸零穿透；场景树职责清晰 |
| **T-004** | P1 | `art/pixel_art.gd`, `ShipVisual2D` | 升级分档底图（`80×56`~`208×144`）、独立炮塔贴图与 7 层节点装配 | T-003 | 炮塔可随目标旋转，开火触发炮管后坐力与 Additive 枪口焰 |
| **T-005** | P1 | `shaders/hull_damage.gdshader`, `shield_arc.gdshader` | 实装局部装甲损伤+闪白着色器、方向性护盾展开与涟漪着色器 | T-004 | 受击处实时显现焦痕与护盾局部涟漪，无明显帧率下降 |
| **T-006** | P1 | `combat.gd`, `flight.gd` | 实装 `7×5` 装甲网格、非线性公式、`FRONT`/`OMNI` 护盾、光束与 EMP | T-001, T-005 | `armor_grid_and_shields()` 测试全绿；绕后攻击可击穿无盾装甲 |
| **T-007** | P1 | `flight.gd`, `HudLayer`, `audio.gd` | 实装 X4 惯性漂移与助推池、5 档 AI 性格与滞回、前置弹道环、Tab 战术图、2D 空间音频 | T-006 | 40 舰混战 `>= 60 FPS`；Tab 视图可框选下达集火与航点 |
| **T-008** | P2 | `economy.gd`, `world.gd` | 扩展 15 类货品与 3 类仓储、废料回收闭环、多模块空间站与劳动力曲线 | T-001 | 取消凭空刷货后，10,000 日模拟全仓库存非负且造船消耗正常传导 |
| **T-009** | P2 | `economy.gd`, `flight.gd` | 实装 `TradeReservation` 预留锁与熔断、IS/OOS 双层模拟与 6 大舰队职责 | T-008 | `economy_conservation_10000d()` 无幽灵预留锁，OOS 商船可被真实拦截 |
| **T-010** | P2 | `politics.gd`, `portrait.gd` | 实装 4 维属性、压力 `0–400` 崩溃、秘密/把柄/计谋、政体契约与派系内战；升级 `128×144` 肖像 | T-001 | `stress_hooks_factions()` 全绿；肖像随年龄与压力动态变化 |
| **T-011** | P2 | `frontier.gd`, `EventEngine`, `NestedTooltip` | 落地 JSON 事件引擎（`>= 35` 个事件）、行旅危险与 CK3 式嵌套工具提示 | T-010, T-002 | 悬停概念词可中键锁定并递归钻取 3 层以上公式与规则说明 |
| **T-012** | P3 | `DataRegistry`, `agent_bridge.gd`, `verify.gd` | 全面迁移至 `.tres`/JSON 数据驱动与 `.skin` 变体；实装终局危机；升级协议 v2 | T-009, T-011 | 支持零代码外挂示例 Mod；`verify_agent.ps1` v2 全流程通过 |

---

## 第 9 章：核心数值平衡模型与三核耦合公式集

为了避免在 P1–P3 重构过程中出现数值膨胀、武器同质化或经济/政治系统失衡，工程团队与数值策划 Agent 必须依据本章建立的数学模型与预算约束对 `hull_catalog.gd`、`economy.gd` 与 `politics.gd` 进行统一校准。

### 9.1 四级舰体装配点（OP）、部署点（DP）与后勤维护预算模型

当前 `hull_catalog.gd:28-38` 中的 `BASE_COMBAT` 与 `hull_catalog.gd:161` 的 `combat_catalog()` 仅通过简单的线性公式分配 `op`、`capacity` 与 `dissipation`（例如主力舰固定为 `op = 23 + 3*13 + role*2`），且完全没有设计**部署点（DP）**与**每日维护补给消耗**，导致后期玩家只需堆砌最高级主力舰即可碾压一切。

重构后的四级舰体必须严格遵循下表的**非线性规模-效率剪刀差**：

| 舰级 (`Size`) | 部署点 (`DP`) | 装配点 (`OP`) 预算 | 基础幅能容量 (`Flux Cap`) | 基础散热 (`Flux Diss/s`) | 每日维护补给 (`Supply/Day`) | 核心战术定位与约束 |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **护卫舰 (`FRIGATE`)** | `4 – 6` | `35 – 55` | `1,800 – 3,200` | `120 – 220` | `2 – 4` | 高机动、低维护、擅长侧翼绕后击穿无盾装甲与夺取战略点 |
| **驱逐舰 (`DESTROYER`)** | `9 – 14` | `65 – 95` | `4,000 – 6,500` | `240 – 380` | `5 – 9` | 舰队中坚、护航反导核心，兼顾中等装甲与炮塔射界覆盖 |
| **巡洋舰 (`CRUISER`)** | `18 – 28` | `115 – 160` | `8,500 – 13,500` | `450 – 700` | `12 – 20` | 战线核心，具备独立大型槽位或双机库，可承受长时间正面交火 |
| **主力舰 (`CAPITAL`)** | `40 – 60` | `220 – 310` | `18,000 – 28,000` | `850 – 1,350` | `30 – 50` | 战略威慑支点，极高单舰压制力，但航速慢、转身迟钝且极度依赖后勤补给 |

* **电容与散热插槽上限耦合**：取消当前 `hull_catalog.gd:56` 中全舰级统一 `0..12` 的硬编码插槽上限，改为按舰级动态设定上限：`FRIGATE` 最多 `10` 点、`DESTROYER` 最多 `20` 点、`CRUISER` 最多 `30` 点、`CAPITAL` 最多 `50` 点。每 `1` 点 OP 投入电容提供固定百分比或阶梯容量加成，每 `1` 点 OP 投入散热提供线性散热增量，迫使玩家在“装满重武器”与“留出 OP 堆散热/护盾插件”之间做出真实取舍。

---

### 9.2 武器伤害、射程与幅能效率三角平衡矩阵

当前 `hull_catalog.gd:11-18` 的 `BASE_WEAPONS` 虽然区分了 4 种伤害类型，但缺乏严格的**幅能效率（Flux Efficiency = 每秒伤害 / 每秒幅能消耗）**与**弹丸初速-射程匹配**。重构后的武器数值表必须满足以下三角约束关系：

1. **射程与幅能效率反比律**：射程越远的武器（如长弧主炮 `lance`、轨道炮 `rail`），其单点幅能换取的伤害越低（幅能效率 `0.7 – 1.0`）；近距离突击实弹与等离子武器幅能效率较高（`1.3 – 1.8`），鼓励舰船冒险接敌。
2. **四类伤害职能锚定**：
   * **动能武器 (`KINETIC`)**：对护盾 `2.0×`、对装甲 `0.5×`。高射速与高初速（`550 – 750 px/s`），核心任务是快速压满敌舰硬辐能条，但单发伤害偏低，面对未剥离的重型装甲网格时极易被 $\frac{D}{A+D}$ 公式压制到 15% 保底。
   * **高爆武器 (`HIGH_EXPLOSIVE`)**：对护盾 `0.5×`、对装甲 `2.0×`。高单发伤害（`DPH`）配合较低射速或有限备弹（如重型榴弹炮、鱼雷），专门用于在护盾崩溃或绕后时一击撕开敌舰局部装甲网格。
   * **能量武器 (`ENERGY`)**：对护盾/装甲均为 `1.0×`。泛用性极强但单位时间幅能消耗显著高于实弹武器，其中**连续光束武器 (`Beam`)** 命中护盾仅产生软辐能，适合持续压制敌舰散热空间并拦截小型快艇。
   * **破片武器 (`FRAGMENTATION`)**：对护盾/装甲仅 `0.25×`、对裸露船体 `1.0×`。极低 OP 与极低幅能消耗，主要承担点防御（PD）拦截导弹与战机的任务，或在敌舰装甲被高爆武器彻底剥离后高效收割船体。

---

### 9.3 15 类货品价格弹性与空间站投资回报周期模型

在第 4 章扩展为 15 类货品后，必须重新校准 `economy.gd:3` 的 `BASE` 基准价格与库存水位线性定价区间，保证：
1. **初级采集与跑商保底利润率**：玩家驾驶小型货船从 Tier 0 矿站采购 `ore` 或 `gas_h2` 运往 Tier 1 精炼站时，单趟毛利润稳定在 `25% – 45%` 之间，确保前期新手期（类似「熄火之前」阶段）有稳定的正向现金流。
2. **高阶制造与劳动力效率杠杆**：Tier 2/3 组件（`hull_parts`、`electronics`、`ordnance`）的基准价设为 Tier 0 原矿的 `4 – 8` 倍，但生产周期更长、耗电量更大。建造居住区并稳定供应 `food_med` 与 `water` 后，虽然每日产生固定消费支出，但通过 $+35\% \sim +60\%$ 的零原料消耗产出加成，空间站的综合净利润率可提升 `40%` 以上，在 `120 – 180` 游戏日内收回居住区建造成本。
3. **通胀与通缩防线**：所有空间站维护费、船员薪资（`politics.gd:521-525` 的每日固定 `¢4` 需升级为按船级与技能星级阶梯扣费）、弹药补给与战损维修均作为货币回收槽（Money Sink），防止玩家及 AI 势力在 1,000 游戏日后现金无限膨胀。

---

### 9.4 政治恐怖值（Dread）、压力与正统性量化边界

为确保 CK3 式政治博弈在太空沙盒中具有明确的可预测性与策略深度，定义以下三组核心状态转换公式：

1. **恐怖值威慑判定 (`Dread` vs `Boldness`)**：
   设领主当前恐怖值为 $D \in [0, 100]$，下属角色（站长/船长/封臣）的性格胆量向量为 $B \in [-100, +100]$：
   $$\Delta_{\text{fear}} = D - (B + 35)$$
   * 当 $\Delta_{\text{fear}} \ge 45$ 时，该下属进入 **`TERRIFIED`（惊恐）** 状态：彻底禁止加入任何反叛派系、禁止发起敌意计谋，且契约谈判接受度 $+30$。
   * 当 $15 \le \Delta_{\text{fear}} < 45$ 时，进入 **`INTIMIDATED`（畏惧）** 状态：加入派系的效用权重 $-50\%$。
   * 当 $\Delta_{\text{fear}} < 15$（通常对应 `勇敢 Brave` 或 `野心勃勃 Ambitious` 的角色）时，恐怖值完全失效，必须依靠好感、联姻同盟或把柄控制。
2. **新君即位惩罚与正统性缓冲 (`Legitimacy 0–5`)**：
   继承发生时，新任领袖对所有下属施加初始 `-20` 的“新君即位（Short Reign）”好感惩罚（每年衰减 `+4`）。若新领袖拥有 `legitimacy >= 4`（高正统性），该惩罚减半为 `-10` 且封臣税收贡献 $+10\%$；若因低贱联姻、战败或暴政导致 `legitimacy == 0`，惩罚翻倍至 `-40` 并直接触发派系不满度加速累积。

---

## 第 10 章：UI/UX 信息架构重设计、测试矩阵与风险控制手册

### 10.1 核心界面重设计规范（迁移至 `.tscn` 预制体）

针对第 1 章审计中发现的 `game.gd` / `panels.gd` / `dock_view.gd` 纯代码拼接 UI 与高重构成本问题，将主要界面拆分为以下四个标准化 `.tscn` 交互场景：

1. **`CreatorScreen.tscn`（开局登记与宇宙定制）**：
   * 保留现有的三栏结构（`01 海关登记`、`02 外貌档案`、`03 航区参数`），新增**性格特质点选（最多 3 个互斥性格特质）**与**家族徽章编辑器**（几何底纹 + 象征图标 + 识别色，继承至旗下所有空间站与舰船涂装）。
2. **`RefitBench.tscn`（可视化舰船整备台，替代 `dock_view.gd:show_refit()`）**：
   * 左侧展示放大后的分层舰船蓝图底图与像素比例尺网格；
   * 在每个武器槽位的精确坐标处生成可点击的热区图标（颜色区分实弹/能量/导弹/通用，尺寸区分 S/M/L）；
   * 鼠标悬停或选中槽位时，实时在蓝图上渲染半透明的**射界扇形弧（`arc`）**，并在右侧弹出当前港口公开库/黑市库中兼容该槽位尺寸的武器对比卡片（直接对比当前已装武器与候选武器的 DPS、幅能效率与 OP 差值）。
3. **`LogicalOverview.tscn`（空间站逻辑概览，替代 `panels.gd:market()` 的纯文本列表）**：
   * 采用自左向右的有向流图展示 `原料输入 -> 生产模块（含劳动力加成百分比条） -> 成品输出`；
   * 每个节点显示实时库存水位条、预留锁虚线标记（正在运入/运出的 AI 订单量）、自动/手动定价滑块与贸易黑名单开关。
4. **`TacticalMapLayer.tscn`（全屏 `Tab` 战术视图与星图传感器层）**：
   * 战斗中按 `Tab` 键平滑缩放并切换至矢量俯瞰图，支持左键框选多艘友军护航舰、右键在地图上直接绘制集火连线或移动航路点，并在屏幕边缘保留小尺寸态势摘要。

---

### 10.2 `verify.gd` 新增自动化回归测试用例规约

在保留 `verify.gd` 现有 12 组测试（`generation()` 至 `ui_flow()`）的基础上，工程团队每完成一个阶段，必须同步合入以下 4 组自动化验收测试：

1. **`armor_grid_and_shields()`（P1 验收门禁）**：
   * **前置条件**：生成一艘装备 `FRONT` 护盾（弧度 `120°`）与 `7×5` 装甲网格的重甲巡洋舰。
   * **断言 1（方向性护盾绕后）**：从正前方（`0°`）发射高爆弹，断言护盾吸收伤害并产生硬辐能、`armor_grid` 无损；从正后方（`180°`）发射相同高爆弹，断言硬辐能不变、尾部对应网格单元 `armor_grid` 真实扣血。
   * **断言 2（非线性公式与 5% 保底）**：连续以单发 `16` 伤的脉冲武器与单发 `120` 伤的重型榴弹炮轰击同一完好网格，断言前者单发穿透率严格受制于 $\frac{D}{A+D}$ 且低于 `20%`；当网格装甲归零后，断言有效装甲仍保留 `5%` 基值，不会出现一击秒杀船体。
2. **`economy_conservation_10000d()`（P2 验收门禁）**：
   * **前置条件**：使用固定种子生成 24 星系宇宙，禁用任何凭空刷货逻辑，开启 IS/OOS 模拟与 `TradeReservation` 预留锁。
   * **断言 1（守恒与非负）**：运行 `world.tick(10000)` 后，全宇宙所有空间站 15 类货品库存与建筑仓储均 `>= 0`。
   * **断言 2（防死锁熔断）**：人为在模拟中途摧毁一艘正在执行跨星系贸易预留的货船，推进 `30` 游戏日后，断言 `EconomyManager.reservations` 中不存在指向已销毁舰船的残留预留锁。
3. **`stress_hooks_factions()`（P2 验收门禁）**：
   * **前置条件**：创建一个拥有 `just`（公正）与 `compassionate`（同情）特质的角色。
   * **断言 1（压力与崩溃）**：连续触发 4 次违背特质的暗杀/敲诈抉择，断言 `stress` 跨越 `100` 阈值并自动弹出 1 级精神崩溃事件且赋予应对特质。
   * **断言 2（把柄与派系叛乱）**：发现下属站长走私秘密并勒索为 `Strong Hook`，断言该站长被强制移出独立派系；移除把柄并降低好感至 `-60` 后，断言派系不满度推进至 `100%` 并正确触发内战状态。
4. **`render_leak_smoke()`（P0/P1 验收门禁）**：
   * **前置条件**：实例化完整 `game.tscn` 主场景。
   * **断言**：连续执行 `50` 次停靠 `dock()`、切换 5 个侧边栏页签、离港 `depart()` 与 10 秒战斗模拟并清理战场，断言 `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == 0`，且 `BattleWorld2D` 子节点总数回到初始基线。

---

### 10.3 重构风险识别与工程降级预案

在将轻量级 Demo 演进为三核深度沙盒的过程中，团队必须提前布防以下四类高风险技术隐患：

| 风险类别 | 触发场景与潜在破坏 | 预防措施与运行时降级预案 |
| :--- | :--- | :--- |
| **GL Compatibility 着色器兼容性风险** | 部分老旧核显或集显在 OpenGL ES 3.0 后端对动态分支与纹理数组采样出现编译警告或黑块 | 所有 `.gdshader` 严禁使用复杂循环与 `textureSize()` 等高版本特性，限定使用 `ShaderModel 3.0` 基础指令集；在设置界面提供“简化渲染模式”开关，一键回退至无 Shader 纯 `Sprite2D` 叠层绘制 |
| **IS/OOS 切换瞬时卡顿与数值悖论** | 玩家跃迁进入拥有 30+ 艘船的繁忙星系时，瞬时实例化大量 `ShipVisual2D` 节点与粒子引发掉帧 | 建立 `ShipVisual2D` 对象池（Object Pool），预热常用护卫/货船节点；跃迁切换帧采用分帧异步装配纹理，并统一 IS 与 OOS 的炮塔命中修正系数，避免战果在观察与否间剧烈反转 |
| **旧存档跨版本迁移字段丢失** | 玩家载入 v3–v6 存档后，因缺失新引入的 `armor_grid`、`stress` 或 `modules` 导致空指针崩溃 | 编写独立的 `SaveMigrator` 单元测试集，覆盖 v3/v4/v5/v6 四个版本的真实快照样本；在 `load_state()` 入口强制执行完整性校验，迁移失败时自动保留原文件并提示用户回滚 |
| **全实体经济早期断链死锁** | 取消核心区凭空刷货后，若某星区开局海盗过于活跃导致矿船全灭，可能引发全星区燃料断供 | 开局生成器 `world.new_game()` 必须校验每个核心势力首都圈内至少具备“矿区 + 精炼 + 能源”基础闭环；保留低保底的“自由港应急走私配给”事件作为极端断链时的经济恢复阀门 |

---

## 第 11 章：AI Coding Agent 执行守则、代码规范与提效检查清单

鉴于本意见书的主要执行主体包含自动化 AI Coding Agent 与多成员工程团队，本章制定强制性的编码约束与工作流门禁，确保在长达 12 周的重构周期内代码库保持高内聚、低耦合与零回归退化。

### 11.1 GDScript 4.6.3 静态类型与内存安全强制规范

1. **全量类型注解（Strict Typing）**：
   - 所有新增与重构的 `.gd` 脚本必须在函数签名、成员变量与局部关键集合中显式声明类型（如 `var ships: Dictionary[int, ShipData]` 或在 Godot 4.6.3 中使用强类型包装类与显式返回值 `-> bool` / `-> void`）。
   - 严禁在核心逻辑循环（如 `combat.gd`、`economy.gd`、`politics.gd`）中继续通过未校验的字符串键动态读写 `Dictionary`（如 `vessel.battle.hard_flux`），所有状态访问必须通过模型类的属性或明确定义的 Getter/Setter 完成。
2. **闭环信号与 `RefCounted` 循环引用防范**：
   - 在 `game.gd`、`panels.gd` 与 `dock_view.gd` 的旧代码中，大量使用匿名 Lambda（`func(): ...`）直接捕获 `world` 或 `game` 引用并连接到动态创建的 `Button.pressed` 信号。重构为 `.tscn` 场景化节点后，若信号连接跨越多层节点或绑定到 `RefCounted` 控制器，必须在节点 `_exit_tree()` 时显式断开或使用弱引用 `weakref()`，防止产生幽灵节点与内存泄漏。
3. **固定物理步长与帧率无关性**：
   - 凡涉及运动学积分（`flight.gd:maneuver()`、`step()`）、弹丸碰撞（`combat.gd:project()`）与护盾旋转插值的逻辑，必须严格在 `_physics_process(delta)` 中以固定 `delta = 1.0 / 60.0` 执行，严禁依赖渲染帧时间或 `Time.get_ticks_msec()` 直接驱动游戏状态机（`Time.get_ticks_msec()` 仅可用于纯视觉特效如 `sector_view.gd` 的相机震动相位或 `audio.gd` 的节流防抖）。

---

### 11.2 美术资产生成与导出管线 (`pixel_art.gd` / `export_pixels.gd`) 同步规范

1. **图集缓存键完整性 (`Pixels.cache`)**：
   - 当前 `art/pixel_art.gd:497-512` 使用字符串键（如 `"ship:%s:%s"`）缓存 `ImageTexture`。升级为分层资产与派系涂装后，缓存键必须包含 `hull_id`、`faction_style`、`livery_hex` 与 `layer_type`（`hull` / `emissive` / `turret` / `turret_base`），严禁不同图层共用同一缓存键导致贴图覆盖错乱。
   - 角色肖像 `portrait()` 升级至 `128×144` 并接入年龄、伤病与压力状态后，缓存键需包含年龄分段、压力等级（`0..3`）与派系制服 ID，并在角色状态跃迁时主动淘汰旧缓存，防止 `Pixels.cache` 随数百年模拟无限膨胀。
2. **离线导出校验 (`art/export_pixels.gd`)**：
   - 每次修改 `pixel_art.gd` 的几何轮廓、Greebling 算法或派系色板后，Agent 必须运行一次 `godot --headless --path . --script art/export_pixels.gd`，检查生成的 `art/hulls.png`、`art/portrait_examples.png` 与 `art/pixel_preview.png` 是否存在越界裁剪、透明背景污染或孤立噪点像素。
3. **语义色彩全局常量统一**：
   - 将分散在 `pixel_art.gd`（`INK`、`TEAL`、`AMBER`、`RUST`）、`sector_view.gd`（`GRID`、`CYAN`、`GOLD`）与 `game.gd`（`INK`、`GOLD`、`DIM`）中的硬编码十六进制色值统一收口至单一全局色彩表 `PaletteConfig.gd`，确保 2D 战场渲染、GLSL 着色器传参、战术地图与 UI 控件严格遵守《远行星号》的语义色彩编码规范。

---

### 11.3 每次提交（Commit / PR）必过自动化门禁清单

AI Agent 在完成任一工单（`T-001` 至 `T-012`）的代码修改后，必须在向人类审查者汇报前依次执行以下四步本地验证，任何一步失败均视为未完成：

1. **资源与脚本导入校验**：
   ```powershell
   godot --headless --path . --editor --import --quit
   ```
   确认新增的 `.tscn`、`.tres` 与 `.gdshader` 文件无解析错误、UID 冲突或脚本编译报错。
2. **核心回归测试套件执行**：
   ```powershell
   godot --headless --path . --script verify.gd
   ```
   确认 `checks - failures == checks` 全量绿灯退出码为 `0`，且新增工单对应的单元测试已合入 `verify.gd`。
3. **离线像素资产管线验证（涉及美术脚本改动时）**：
   ```powershell
   godot --headless --path . --script art/export_pixels.gd
   ```
   确认所有程序化资产尺寸、透明度通道与图集排列无误。
4. **Agent 协议端到端冒烟验证（涉及 `agent_bridge.gd` 或核心玩法改动时）**：
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\verify_agent.ps1
   ```
   确认外部代理进程能够通过文件 IPC 正常完成开局、观察、航行、停靠、交易与战斗闭环，无协议字段缺失或超时阻塞。
