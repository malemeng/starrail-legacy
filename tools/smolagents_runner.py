"""
Open-source HuggingFace `smolagents` runner for Starrail Legacy (`agent_bridge.gd`).

Install:
    pip install smolagents openai

Usage (after clicking "托管: 关 -> 开" inside the game):
    python tools/smolagents_runner.py ^
        --api-base https://api.deepseek.com/v1 ^
        --api-key YOUR_KEY ^
        --model deepseek-chat ^
        --goal "通过跑商、买船建队、建站与创办企业最大化净资产"
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import traceback
import uuid
from pathlib import Path
from typing import Any

from smolagents import ActionStep, OpenAIServerModel, PlanningStep, ToolCallingAgent, tool


def default_takeover_dir() -> Path:
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "Godot" / "app_userdata" / "星轨遗产" / "agent_takeover"
    return Path.home() / ".local" / "share" / "godot" / "app_userdata" / "星轨遗产" / "agent_takeover"


class BridgeClient:
    def __init__(self, session_dir: Path, timeout_s: float = 45.0) -> None:
        self.dir = session_dir
        self.timeout_s = timeout_s
        self.req_path = self.dir / "request.json"
        self.tmp_path = self.dir / "request.json.tmp"
        self.res_path = self.dir / "response.json"
        self.shutdown_path = self.dir / "shutdown.json"
        self.log_path = self.dir / f"smolagents_run_{int(time.time())}.jsonl"

    def call(self, action: str, args: dict[str, Any] | None = None) -> dict[str, Any]:
        for attempt in range(2):
            data = self._call_once(action, args)
            if data.get("error") == "invalid_request" and "id" not in data and attempt == 0:
                time.sleep(0.05)
                continue
            return data
        return data

    def _call_once(self, action: str, args: dict[str, Any] | None = None) -> dict[str, Any]:
        if self.shutdown_path.exists():
            raise RuntimeError("Game process exited (shutdown.json detected).")
        req_id = uuid.uuid4().hex[:16]
        payload = {"id": req_id, "action": action, "args": args or {}}
        if self.res_path.exists():
            self.res_path.unlink(missing_ok=True)
        self.tmp_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        os.replace(self.tmp_path, self.req_path)

        deadline = time.time() + self.timeout_s
        while time.time() < deadline:
            if self.shutdown_path.exists():
                raise RuntimeError("Game process exited (shutdown.json detected).")
            if self.res_path.exists():
                try:
                    data = json.loads(self.res_path.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    time.sleep(0.05)
                    continue
                if data.get("id") == req_id or "id" not in data:
                    self.res_path.unlink(missing_ok=True)
                    self._log(action, args or {}, data)
                    return data
            time.sleep(0.05)
        raise TimeoutError(f"Timed out waiting for response to action={action}")

    def publish_thought(self, text: str) -> None:
        cleaned = " ".join(text.replace("<think>", "").replace("</think>", " ").split()).strip()
        if not cleaned:
            return
        tmp = self.dir / "thought.json.tmp"
        dst = self.dir / "thought.json"
        try:
            tmp.write_text(json.dumps({"thought": cleaned[:260]}, ensure_ascii=False), encoding="utf-8")
            os.replace(tmp, dst)
        except OSError:
            pass

    def _log(self, action: str, args: dict[str, Any], result: dict[str, Any]) -> None:
        entry = {"ts": time.time(), "action": action, "args": args, "ok": result.get("ok"), "result": result}
        with self.log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")


_CLIENT: BridgeClient | None = None


def _client() -> BridgeClient:
    assert _CLIENT is not None, "BridgeClient not initialized"
    return _CLIENT


def _compact_response(data: dict[str, Any], keep_state: bool = True) -> dict[str, Any]:
    if not isinstance(data, dict):
        return data
    if not keep_state:
        data.pop("state", None)
        return data
    state = data.get("state")
    if isinstance(state, dict):
        if "shipyard" in state and isinstance(state["shipyard"], list):
            state["shipyard_count"] = len(state["shipyard"])
            state["shipyard"] = [
                {"hull_id": s.get("hull_id"), "name": s.get("name"), "class": s.get("class"), "cargo": s.get("cargo"), "price": s.get("price")}
                for s in state["shipyard"][:8]
            ]
        for key, limit in (("ports", 12), ("contacts", 8), ("targets", 8)):
            if key in state and isinstance(state[key], list) and len(state[key]) > limit:
                state[f"{key}_total"] = len(state[key])
                state[key] = state[key][:limit]
        sys_obj = state.get("system")
        if isinstance(sys_obj, dict) and "planets" in sys_obj:
            sys_obj["planets_count"] = len(sys_obj["planets"])
            sys_obj.pop("planets", None)
    return data


@tool
def observe() -> str:
    """获取当前宇宙状态（精简版）：日期、角色资金/势力、当前飞船血量/燃料/货舱/停靠状态、附近空间站与目标。"""
    data = _compact_response(_client().call("observe"), keep_state=True)
    return json.dumps(data, ensure_ascii=False)


@tool
def trade_opportunities() -> str:
    """扫描已发现的空间站，返回按预估净利润排序的前10条高利润跑商航线。"""
    data = _compact_response(_client().call("trade_opportunities"), keep_state=False)
    routes = (data.get("result") or {}).get("routes", [])
    if isinstance(routes, list) and not routes:
        data["hint"] = "当前暂无高利润航线，请调用 observe() 查看 ports 后用 navigate_and_arrive(port_id, True) 前往其他空间站，或用 mine_or_salvage() 采矿。"
    return json.dumps(data, ensure_ascii=False)


@tool
def navigate_and_arrive(port_id: int, auto_dock: bool = True) -> str:
    """一键设定本星系或跨星系直达航线并自动推进时间直到抵达目标空间站（可自动停靠）。

    Args:
        port_id: 目标空间站 ID
        auto_dock: 抵达泊位后是否自动停靠
    """
    nav = _client().call("navigate_to_station", {"port_id": port_id, "auto_dock": auto_dock})
    if not nav.get("ok"):
        return json.dumps(nav, ensure_ascii=False)
    last_step: dict[str, Any] = nav
    for _ in range(40):
        obs = _client().call("observe")
        ship = obs.get("state", {}).get("ship", {})
        if int(ship.get("dock", 0)) == port_id:
            return json.dumps({"ok": True, "arrived": True, "dock": port_id, "day": obs["state"]["day"]}, ensure_ascii=False)
        last_step = _client().call("step", {"ticks": 300, "speed": 5})
        if not last_step.get("ok"):
            return json.dumps({"ok": False, "step": last_step}, ensure_ascii=False)
        step_res = last_step.get("result", {})
        if int(step_res.get("dock", 0)) == port_id:
            return json.dumps({"ok": True, "arrived": True, "dock": port_id}, ensure_ascii=False)
        if not step_res.get("waypoint_live", False):
            if auto_dock:
                dock_res = _client().call("dock")
                if dock_res.get("ok"):
                    return json.dumps({"ok": True, "arrived": True, "dock": port_id}, ensure_ascii=False)
            break
        if "eta_days" in step_res:
            time.sleep(0.45)
    if auto_dock:
        dock_res = _client().call("dock")
        if dock_res.get("ok"):
            return json.dumps({"ok": True, "arrived": True, "dock": port_id}, ensure_ascii=False)
    return json.dumps(_compact_response(last_step, keep_state=False), ensure_ascii=False)


@tool
def trade(ware: int, amount: int, black: bool = False) -> str:
    """在当前停靠的空间站买卖货物。

    Args:
        ware: 货物槽位编号 (0..15)
        amount: 交易数量（正数买入，负数卖出）
        black: 是否走黑市（默认 False）
    """
    return json.dumps(_client().call("trade", {"ware": ware, "amount": amount, "black": black}), ensure_ascii=False)


@tool
def supply_fleet() -> str:
    """在当前停靠站一键为所有己方停泊舰船维修并加满燃料。"""
    return json.dumps(_client().call("supply_fleet"), ensure_ascii=False)


@tool
def mine_or_salvage() -> str:
    """在当前星系的矿带采矿或打捞残骸（需处于离港飞行状态）。"""
    return json.dumps(_client().call("mine_or_salvage"), ensure_ascii=False)


@tool
def buy_ship(kind: int, port_id: int) -> str:
    """在停靠的空间站船坞购买指定型号的飞船。

    Args:
        kind: 船型索引
        port_id: 当前停靠空间站 ID
    """
    return json.dumps(_client().call("buy_ship", {"model": kind, "port": port_id}), ensure_ascii=False)


@tool
def debug_ship(ship_id: int) -> str:
    """查看己方舰船的燃料、航程、订单、近90日收支与最近调度记录。

    Args:
        ship_id: observe 返回的舰船 ID。
    """
    return json.dumps(_compact_response(_client().call("debug_ship", {"ship": ship_id}), keep_state=False), ensure_ascii=False)


@tool
def assign_ship(ship_id: int, job: str) -> str:
    """为名下其他空闲舰船指派自动作业任务。

    Args:
        ship_id: 飞船 ID
        job: 任务名，如 "自动贸易"、"自动采矿"、"护航"
    """
    return json.dumps(_client().call("set_default_behavior", {"ship": ship_id, "kind": job}), ensure_ascii=False)


@tool
def incorporate_station(port_id: int, name: str) -> str:
    """将自己拥有的已建成空间站注册为商业公司（需 ¢1800）。

    Args:
        port_id: 空间站 ID
        name: 公司名称
    """
    return json.dumps(_client().call("incorporate_station", {"port": port_id, "name": name}), ensure_ascii=False)


@tool
def incorporate_ship(ship_id: int, name: str) -> str:
    """用自有舰船出资注册公司，注册费 ¢1800。

    Args:
        ship_id: 出资舰船编号。
        name: 公司名称。
    """
    return json.dumps(_client().call("incorporate_ship", {"ship": ship_id, "name": name}), ensure_ascii=False)


@tool
def contribute_ship(ship_id: int, firm_id: int) -> str:
    """将整艘自有舰船无偿转入所管理的公司。

    Args:
        ship_id: 舰船编号。
        firm_id: 公司编号。
    """
    return json.dumps(_client().call("contribute_ship", {"ship": ship_id, "firm": firm_id}), ensure_ascii=False)


@tool
def start_pretext(firm_id: int, target_flag: int, kind: str = "tariff_dispute") -> str:
    """为纯商业公司针对目标势力制造战争借口。

    Args:
        firm_id: 公司 ID
        target_flag: 目标势力 flag 编号
        kind: 借口类型："tariff_dispute" | "asset_seizure" | "privateer_incident"
    """
    return json.dumps(_client().call("start_pretext", {"firm_id": firm_id, "target_flag": target_flag, "kind": kind}), ensure_ascii=False)


@tool
def declare_company_war(firm_id: int, target_flag: int) -> str:
    """消耗已就绪的战争借口发起商业私掠宣战。

    Args:
        firm_id: 公司 ID
        target_flag: 目标势力 flag 编号
    """
    return json.dumps(_client().call("declare_company_war", {"firm_id": firm_id, "target_flag": target_flag}), ensure_ascii=False)


@tool
def wait_days(days: int = 5) -> str:
    """原地推进游戏天数（等待市场恢复、施工或战争借口进度）。

    Args:
        days: 推进天数 (1..180)
    """
    return json.dumps(_client().call("wait", {"days": days}), ensure_ascii=False)


@tool
def raw_action(action: str, args_json: str = "{}") -> str:
    """调用 agent_bridge 支持的底层指令。常用指令：equity_catalog({})、buy_shares({"company_id":id,"shares":n})、sell_shares({"company_id":id,"shares":n})、ship_quote({"port_id":pid,"hull_id":hid})（hull_id见observe().state.shipyard）、station_expand({"port_id":pid})、dock({})。禁止猜测 help、port_catalog 或 scan_system。

    靠港后 disembark 离开旗舰。用 board_liner 传 ship、dest、fare 买票，wait 等待到站，或用 disembark_liner 在停靠时下船。按 state.fleet 的 ID 用 hire_captain 招募船长，用 assign_passenger_liner 派客船，用 assign_contractor 派工程舰。仅在 state.allow_cheats 为真时可用 cheat，如 {"kind":"credits","amount":1000}。

    Args:
        action: 动作名称
        args_json: JSON 对象字符串
    """
    args = json.loads(args_json) if args_json.strip() else {}
    return json.dumps(_compact_response(_client().call(action, args), keep_state=False), ensure_ascii=False)


def make_compact_callback(keep_recent: int = 6):
    def compact_memory(memory_step: Any, agent: ToolCallingAgent) -> None:
        raw_thought = ""
        if isinstance(memory_step, PlanningStep):
            raw_thought = str(getattr(memory_step, "plan", "") or "")
        elif isinstance(memory_step, ActionStep):
            msg = getattr(memory_step, "model_output_message", None)
            raw_thought = str(getattr(msg, "content", "") or getattr(memory_step, "model_output", "") or "")
            if not raw_thought and memory_step.tool_calls:
                raw_thought = "调用: " + ", ".join(tc.name for tc in memory_step.tool_calls)
        if raw_thought and _CLIENT is not None:
            _CLIENT.publish_thought(raw_thought)
        action_steps = [s for s in agent.memory.steps if isinstance(s, ActionStep)]
        if len(action_steps) <= keep_recent:
            return
        for old in action_steps[:-keep_recent]:
            if old.observations and not old.observations.startswith("[已压缩]"):
                calls = ", ".join(tc.name for tc in (old.tool_calls or [])) or "step"
                snippet = old.observations.replace("\n", " ")[:120]
                old.observations = f"[已压缩] {calls}: {snippet}"
            old.model_input_messages = None
    return compact_memory


def main() -> None:
    parser = argparse.ArgumentParser(description="Run HuggingFace smolagents against Starrail Legacy.")
    parser.add_argument("--session-dir", type=Path, default=default_takeover_dir())
    parser.add_argument("--api-base", default=os.environ.get("OPENAI_API_BASE", "http://localhost:11434/v1"))
    parser.add_argument("--api-key", default=os.environ.get("OPENAI_API_KEY", "ollama"))
    parser.add_argument("--model", default="qwen2.5:7b")
    parser.add_argument("--max-steps", type=int, default=0, help="0 表示无轮数上限，持续运行直到停止")
    parser.add_argument("--planning-interval", type=int, default=8)
    parser.add_argument("--keep-recent", type=int, default=4)
    parser.add_argument("--goal", default="")
    parser.add_argument("--rivals", default="", help="多 Agent 同宇宙竞技时的对手信息")
    args = parser.parse_args()

    if not args.session_dir.exists():
        raise SystemExit(f"Session directory not found: {args.session_dir}\n请先在游戏中点击顶栏「托管」开启会话。")

    global _CLIENT
    _CLIENT = BridgeClient(args.session_dir)
    log_file = (args.session_dir / "runner.log").open("a", encoding="utf-8", errors="replace")
    if sys.stdout is None or (getattr(sys.stdout, "encoding", "") or "").lower() != "utf-8":
        sys.stdout = log_file
    if sys.stderr is None or (getattr(sys.stderr, "encoding", "") or "").lower() != "utf-8":
        sys.stderr = log_file

    try:
        _CLIENT.publish_thought(f"正在连接模型 {args.model} 并生成首轮计划...")
        llm = OpenAIServerModel(model_id=args.model, api_base=args.api_base, api_key=args.api_key)
        unlimited = args.max_steps <= 0
        epoch_steps = 40 if unlimited else args.max_steps
        agent = ToolCallingAgent(
            tools=[
                observe, trade_opportunities, navigate_and_arrive, trade, supply_fleet,
                mine_or_salvage, buy_ship, assign_ship, debug_ship, incorporate_station, incorporate_ship, contribute_ship,
                start_pretext, declare_company_war, wait_days, raw_action,
            ],
            model=llm,
            max_steps=epoch_steps,
            planning_interval=args.planning_interval if args.planning_interval > 0 else None,
            step_callbacks={ActionStep: make_compact_callback(args.keep_recent), PlanningStep: make_compact_callback(args.keep_recent)},
        )
        goal_text = args.goal.strip()
        goal_block = (
            f"你的长期经营目标是：{goal_text}"
            if goal_text else
            "你可以完全自主决定自己的发展路线与长期目标（例如专精跑商贸易、采矿工业、创办公司与股权投资、舰队扩张、外交或自由探索等）。请先观察宇宙局势，再制定属于你自己的发展规划！"
        )
        rivals_note = (
            f"\n【多 Agent 同宇宙竞技】{args.rivals}。你们共享同一个宇宙的市场、造船厂、公司股权与外交战争系统，最终按总净资产排名。你可以自由选择专注跑商扩张、股权投资合作、或竞争对抗。"
            if args.rivals.strip() else ""
        )
        prompt = (
            f"你正在游玩太空沙盒经营游戏《星轨遗产》。{goal_block}{rivals_note}\n"
            "请先调用 observe() 和 trade_opportunities() 了解局势，然后制定并执行经营决策。\n"
            "注意：每次跨站移动优先使用 navigate_and_arrive(port_id, True)，低油低血时调用 supply_fleet()；"
            "可用空间站列表直接看 observe().state.ports，不要猜 help 或 port_catalog；查船价 ship_quote 需同时传 port_id 和 hull_id。"
        )
        final_result: Any = ""
        if unlimited:
            epoch = 0
            while not _CLIENT.shutdown_path.exists():
                epoch += 1
                cur_prompt = prompt if epoch == 1 else (
                    f"继续执行你在《星轨遗产》中的自主发展规划（第 {epoch} 阶段）。{goal_block}{rivals_note}\n"
                    "请先调用 observe() 和 trade_opportunities() 检查当前资金、船队与航线并继续扩张。"
                )
                final_result = agent.run(cur_prompt, reset=True)
                if _CLIENT.shutdown_path.exists():
                    break
        else:
            final_result = agent.run(prompt)
        print("\n=== Smolagents Run Summary ===")
        print(final_result)
        print(f"Trace saved to: {_CLIENT.log_path}")
    except Exception as exc:
        err_text = traceback.format_exc()
        (args.session_dir / "runner_error.log").write_text(err_text, encoding="utf-8")
        _CLIENT.publish_thought(f"运行异常: {type(exc).__name__}: {exc}")
        raise
    finally:
        log_file.close()


if __name__ == "__main__":
    main()
