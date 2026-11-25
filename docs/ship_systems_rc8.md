# 43 项舰载系统的实战对照

本表覆盖舰船目录中所有已装配的原版系统 ID。舰名列给出一艘可用于复现的舰体。Merlon 的原版系统栏为空，游戏内显示未配备，按 F 不会触发效果。中文列描述玩家可以在本作触发或观察的效果。最后一列是原版对应的脚本或引擎系统类型。

## 核对依据

版本为 Fractal Softworks 发布的 Starsector 0.98a-RC8。核对了发行包中的 `data/shipsystems/ship_systems.csv`、逐项的 `data/shipsystems/<id>.system` 及 `data/strings/descriptions.csv` 中的 `SHIP_SYSTEM` 条目。对脚本系统还查阅了随包提供的系统脚本和 `starfarer.api.jar` 中相应实现。已有舰型映射取自本项目的 `data/fleet/manifest.json`，包括 Hive Unit 预设中各碎片武器的原装槽位。[官方 RC8 发行包](https://f005.backblazeb2.com/file/fractalsoftworks/release/starsector_linux-0.98a-RC8.zip)

| 系统 ID | 原版名称 | 示例舰体 | 本作战斗表现 | 原版实现 |
| --- | --- | --- | --- | --- |
| `maneuveringjets` | Maneuvering Jets | `kite` | 辅助喷口提高加速度和转向速度，适合绕到对手侧面。 | `ManeuveringJetsStats` |
| `burndrive` | Burn Drive | `dominator` | 固定舰首加速突进，燃烧时无法转向和开盾。再次启动可中断。 | `BurnDriveStats` |
| `microburn` | Plasma Burn | `shrike` | 沿舰首短促加速。两次充能逐次恢复。 | `MicroBurnStats` |
| `microburn_omega` | Microburn | `shard_left` | 沿舰首短促加速。三次充能逐次恢复。 | `MicroBurnOmegaStats` |
| `plasmajets` | Plasma Jets | `aurora` | 大幅提高航速和加速度，并保留侧移与转向。 | `PlasmaJetsStats` |
| `orion_device` | Orion Device | `retribution` | 向舰尾释放一次定向爆炸，同时立即获得向前的速度。 | `OrionDeviceStats` |
| `convulsive_lunge` | Convulsive Lunge | `shrouded_tendril` | 沿启动时选择的方向突进，突进期间封锁武器。 | `ConvulsiveLungeSystemScript` |
| `combat_burn` | Combat Burn | `onslaught_mk1` | 持续朝舰首推进，关闭护盾。再次启动可退出。 | `CombatBurnStats` |
| `temporalshell` | Temporal Shell | `scarab` | 加速舰内时间，提高机动、武器循环和辐能耗散速度。 | `TemporalShellStats` |
| `displacer` | Phase Skimmer | `wolf` | 沿当前航向短距闪现。三格充能可连续使用。 | `DISPLACER` |
| `phaseteleporter` | Phase Teleporter | `hyperion` | 传送至光标位置，超出范围时抵达范围边缘。 | `TELEPORTER` |
| `displacer_threat` | Displacer | `skirmish_unit` | 沿运动方向闪现。自带三格充能，可由友方能量鞭击补充。 | `DisplacerGlowScript` |
| `displacer_degraded` | Degraded Phase Skimmer | `wolf_d_pirates` | 沿运动方向短距闪现，有两格缓慢恢复的充能。 | `DISPLACER` |
| `flarelauncher` | Flare Launcher | `crig` | 向四周释放诱饵，吸引导弹和点防火力。导弹碰到诱饵后销毁。 | `WEAPON` |
| `flarelauncher_active` | Active Flare Launcher | `buffalo` | 诱饵会主动飞向附近敌弹，也会干扰导引和点防。 | `WEAPON` |
| `flarelauncher_fighter` | Decoy Flare Launcher | `gremlin` | 发射吸引点防火力的诱饵，敌方导弹保留原有制导。 | `WEAPON` |
| `canister_flak` | Canister Flak | `manticore` | 环形射出近炸弹罐，弹罐在敌方导弹和舰载机附近爆炸。 | `WEAPON` |
| `ammofeed` | Accelerated Ammo Feeder | `lasher` | 弹道武器射速翻倍，单次开火的辐能消耗减半。 | `AmmoFeedStats` |
| `highenergyfocus` | High Energy Focus | `sunder` | 能量武器伤害提高一半，消耗一格可再生充能。 | `HighEnergyFocusStats` |
| `fastmissileracks` | Fast Missile Racks | `venture` | 立即结束导弹武器的装填冷却，弹仓余量保持当前值。 | `FAST_RELOAD` |
| `targetingfeed` | Targeting Feed | `heron` | 向己方出击联队提供目标数据，提高舰载机攻击伤害。 | `TargetingFeedStats` |
| `lidararray` | Lidar Array | `invictus` | 平时提高武器射程。启动后固定炮位提高射程、射速、精度，炮塔和光束停火。 | `LidarArrayStats` |
| `fortressshield` | Fortress Shield | `paragon` | 牺牲武器火力换取高效护盾，持续积累硬辐能。再次启动可退出。 | `FortressShieldStats` |
| `damper` | Damper Field | `centurion_LG` | 降低所受伤害，同时封锁护盾、武器与主动排散。 | `DamperFieldStats` |
| `damper_omega` | Entropy Damper | `facet` | 所受伤害和产生的辐能减半，加速修复失能武器与引擎。关闭护盾。 | `DamperFieldOmegaStats` |
| `emp` | EMP Emitter | `omen` | 持续向附近敌舰设备、舰载机和导弹施加电磁脉冲，本舰武器停火。 | `EMP` |
| `acausaldisruptor` | Quantum Disruptor | `harbinger` | 使范围内选定的一艘敌舰短暂过载。 | `AcausalDisruptorStats` |
| `darkened_gaze` | Darkened Gaze | `shrouded_eye` | 舰首持续发射窄束凝视射线，正面护盾露出缺口，转向受限并持续积累辐能。再次启动可关闭。 | `DarkenedGazeSystemScript` |
| `entropyamplifier` | Entropy Amplifier | `afflictor` | 在一定时间内放大指定敌舰承受的伤害。 | `EntropyAmplifierStats` |
| `mine_strike` | Mine Strike | `doom` | 在指定位置投放相位雷，缓慢追踪敌舰，接近后延时引爆。可在相位中使用。 | `MineStrikeStats` |
| `reservewing` | Reserve Deployment | `gemini` | 派出临时后备机，短时间内增加出战飞机数量，随后回收。 | `ReserveWingStats` |
| `recalldevice` | Recall Device | `scintilla` | 将出战联队传回航母，缩短重新出击的等待。 | `RecallDeviceStats` |
| `forgevats` | Missile Autoforge | `gryphon` | 消耗大量辐能为导弹武器补充弹药，战斗内可使用两次。 | `AMMO_RELOAD` |
| `forgevats_station` | Heavy Missile Autoforge | `ravelin` | 周期性为导弹武器补足弹药。 | `AMMO_RELOAD` |
| `construction_swarm` | Construction Swarm | `fabricator_unit` | 放出施工蜂群，根据编组规模建造同阵营的侦击、突击、远火、监督或蜂巢单元。 | `ConstructionSwarmSystemScript` |
| `extraction_protocol` | Extraction Protocol | `standoff_unit` | 向舰尾撤离并自动开火，结束后补充弹药、结束装填并排散辐能。 | `ExtractionProtocolSystemScript` |
| `drone_strike` | Termination Sequence | `tempest` | 消耗一架终结者无人机，使其追踪敌舰并在命中时爆炸。 | `DroneStrikeStats` |
| `mote_control` | Mote Attractor | `ziggurat` | 平时释放拦截导弹与飞机的微粒。启动后把微粒吸引到指定位置或目标舰。 | `MoteControlScript` |
| `nova_burst` | Nova Burst | `nova` | 舰尾发生大范围爆炸并获得强劲的向前冲量，可连用两次。 | `NovaBurstStats` |
| `fragment_volley` | Fragment Volley | `hive_unit` | 延长非点防碎片武器射程并让它们快速自动齐射。 | `FragmentVolleySystemScript` |
| `energy_lash` | Energy Lash | `overseer_unit` | 电弧对敌舰施加电磁伤害并可迫使相位舰过载。对友方威胁舰则补充或触发对应系统。 | `EnergyLashSystemScript` |
| `incursion_mode` | Incursion Mode | `assault_unit` | 提高舰速、辐能耗散与武器充能恢复速度。 | `IncursionModeSystemScript` |
| `tenebrous_expulsion` | Tenebrous Expulsion | `shrouded_maelstrom` | 向前喷出可拦截火力、干扰制导的暗幕，同时向后撤离。 | `TenebrousExpulsionSystemScript` |

## 参数与适配范围

- 次数上限与自然充能速度取自原版表格。最后一格耗尽时无法启动；没有自然充能的系统可由相应支援能力、靠港或结束交战后补充。此处以连续脱战 12 秒作为遭遇结束。
- 含 `f/u (base cap)` 的启动费用按本作舰体基础容量计算。伤害、世界距离、推进冲量和部分持续消耗使用本作单位。瞬发动作在指令到达时生效；本作合并了原版部分预热、启动和收束动画。
- 未开火的导弹架和已满的弹仓都可以接收操作指令，其实际收益取决于当前装填和弹药。主动诱饵会转向来弹，舰载机专用诱饵只作为点防目标。
- 联队共用一套位置和生命值。后备机暂时增加实际攻击机数，终结序列消耗一架的生命份额。微粒使用有上限的独立实体和周期性拦截，凝视使用沿舰首的单条脉冲射线。
- 建造蜂群可以生成侦击、突击、远火、监督和蜂巢单元。本作以友军部署点选择舰种，每个制造者最多维持两艘在建或存活的增援。原版还使用施工资源、战备水平、部署配额和多个装配预设。
- 碎片齐射识别原装非点防碎片炮位与其对应的本地武器。换上其他武器不会得到齐射增益。暗幕具有独立位置和生命值，能够遮挡弹丸和光束。

## 复现

在项目根目录运行两项测试，分别核对 43 个独立场景以及共用战斗逻辑。

```powershell
godot --headless --path . --script res://tests/ship_systems.gd
godot --headless --path . --script res://tests/battle_mechanics.gd
```
