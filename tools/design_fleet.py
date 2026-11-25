"""Bake local balance, original hull plans and legal loadouts from the RC8 reference index.

The game reads the resulting editable records, and never needs the reference
archive or Python. Layouts are drawn in local +X-forward space from the yard's
own hull sections; only mount roles, sectors and mechanical facts are inputs.
"""
import copy
import hashlib
import json
import math
import random
from pathlib import Path

from import_rc8_fleet import write_index

HERE = Path(__file__).resolve().parents[1] / "data" / "fleet"
SIZE = {"FRIGATE": 0, "DESTROYER": 1, "CRUISER": 2, "CAPITAL_SHIP": 3, "FIGHTER": 0}
CLASSES = json.loads((HERE / "size_classes.json").read_text(encoding="utf8"))
IMAGES = [tier["canvas"] for tier in CLASSES]
LIGHT, MEDIUM, LARGE = 1, 2, 3
MOUNT_FAMILIES = json.loads((HERE / "mount_families.json").read_text(encoding="utf8"))
PORTS = {family["source"]: name for name, family in MOUNT_FAMILIES.items()}
ACCEPTS = {name: family["accepts"] for name, family in MOUNT_FAMILIES.items()}
FIRST = [
    ("kite", "beacon_ff", "信标级轻艇", "侦察 / 通勤", "dart"),
    ("buffalo", "raven_dd", "渡鸦级货船", "物流 / 跑商", "box"),
    ("wolf", "needle_ff", "锋针级护卫舰", "近距护航", "lancet"),
    ("shepherd", "stonebite_ff", "石吻级采矿船", "浅层采掘", "fork"),
    ("crig", "hooklamp_dd", "钩灯级回收船", "残骸回收", "crane"),
    ("dominator", "warden_ca", "戍星级巡洋舰", "正面装甲压制", "bulwark"),
    ("venture", "ridge_ca", "井脊级采冶船", "深层采掘 / 大宗货运", "truss"),
    ("onslaught", "longnight_bb", "长夜级战列舰", "重型正面火力", "breaker"),
    ("atlas", "farshore_bb", "远岸级超货船", "远洋大宗物流", "train"),
]
LINES = [
    ("白帆", "white_sail", "lasher tarsus mule sunder"),
    ("赤枝", "red_branch", "tempest dram gemini hammerhead"),
    ("潮痕", "tide_mark", "shrike phaeton apogee conquest"),
    ("石弧", "stone_arc", "enforcer colossus colossus3 onslaught_xiv"),
    ("青栈", "green_dock", "omen mercury mudskipper dominator_xiv"),
    ("银梭", "silver_spindle", "medusa revenant starliner gryphon"),
    ("铁鹞", "iron_kite", "falcon valkyrie venture_p retribution"),
    ("玄塔", "black_tower", "centurion_LG prometheus heron legion"),
    ("新炬", "new_torch", "brawler hound mudskipper2 manticore"),
    ("裂湾", "rift_bay", "scarab phantom mora eagle"),
    ("环砧", "ring_anvil", "aurora ox venture_pather paragon"),
]
ROLES = [("快反护航", "escort"), ("边境物流", "cargo"), ("远征采冶", "survey"), ("重型火力", "battery")]
PAINT = ["bc795f", "81afb4", "9a9dcc", "929955", "d4ab6c", "af8290", "728da9", "a49d89"]
NOUNS = "尘镜 烬塔 井鸥 琥环 候鸟 黑檀 潮闸 海崖 弦月 折光 钢藤 旋桨 机杼 岚墙 耀斑 空港 石钟 流冰 灯芯 霜叶 铁棘 星砧 漂木 春潮 高墙 暮礁 望台 灰羽 铜兽 锈杉 青黑 梯田 墨鳐 穹柱 飞泷 北垣 绯庭 晨露 锁钥 茧房 鸦石 沙鹭 蜂房 回澜 琉箔 白桉 鹿角 暗渠 芦苇 游灯 蓝穴 雪哨 独木 弧顶 苔藓 双辰 笔架 暮蒲 原野 林鸮 雷鼓".split()
SUFFIX = ["突击舰", "航巡舰", "作业舰", "执勤舰", "支援舰", "远航舰", "装甲舰", "护航舰"]

# Original side elevations projected onto the deck plane. X runs from the
# engine bulkhead (-100) toward the bow (100); Y measures half-beam. Re-entrant
# corners are real breaks between spars, nacelles, tanks and flight decks.
SIDES = {
    "arrow": "-92,13 -96,33 -68,38 -81,79 -53,95 -23,48 24,35 34,22 76,13 99,4",
    "rail": "-94,15 -95,49 -58,52 -38,44 37,40 43,27 76,31 98,18 96,10",
    "falx": "-80,12 -94,45 -70,63 -80,97 -44,81 19,46 68,30 88,11 100,4",
    "gantry": "-96,20 -94,50 -80,50 -79,80 -60,80 -57,53 -28,53 -24,94 0,92 6,46 42,40 52,26 99,21 98,10",
    "trident": "-84,12 -97,41 -68,60 -32,55 -28,79 8,90 38,68 85,63 98,48 64,43 28,51 22,25 58,15 78,6",
    "crane": "-91,18 -88,52 -56,84 -43,82 -35,54 36,77 94,60 94,47 49,53 18,37 -3,35 31,15 56,8",
    "bulb": "-77,14 -91,50 -79,75 -35,88 10,81 26,64 23,42 53,42 62,26 91,14 97,4",
    "notch": "-91,14 -96,53 -67,54 -63,77 -22,78 -8,56 8,56 15,82 49,77 51,48 86,30 97,10",
    "box": "-87,18 -92,62 -73,62 -72,84 -20,84 -17,63 13,62 16,87 54,81 56,58 78,41 94,34 94,12",
    "saw": "-91,17 -95,45 -59,65 -57,41 -19,70 -16,48 16,78 19,55 57,69 65,43 89,39 89,10",
    "citadel": "-91,20 -99,57 -66,57 -61,77 -23,77 -19,96 4,96 10,72 39,62 64,48 65,36 93,31 100,10",
    "blade": "-77,10 -92,34 -80,42 -72,78 -50,85 -14,59 64,22 100,9 97,3",
    "crab": "-73,18 -98,42 -95,72 -70,88 -40,83 -19,54 2,52 39,83 80,78 100,58 66,58 39,63 15,35 49,16 69,9",
    "catamaran": "-75,17 -99,29 -91,66 -61,79 -34,68 -5,75 69,72 83,63 99,41 87,31 52,31 28,40 -7,38 -17,23 36,16 55,7",
    "runway": "-86,15 -96,32 -92,75 -73,84 48,84 79,64 95,45 92,26 65,30 33,46 -4,44 5,22 58,14 75,6",
    "paddle": "-92,12 -96,30 -60,39 -54,71 -22,96 18,91 46,71 38,51 20,40 47,24 89,18 96,6",
    "crescent": "-59,14 -77,35 -84,70 -63,98 -23,93 -48,71 -35,54 0,45 25,61 56,69 94,52 78,31 62,40 33,35 20,21 62,16 80,5",
    "outrigger": "-81,13 -98,28 -85,85 -54,89 -31,74 -39,62 -68,64 -65,46 -13,32 24,41 46,29 85,22 98,8",
}
FORMS = {
    "dart": ("arrow","blade"), "lancet": ("falx","arrow"), "box": ("box","rail"),
    "fork": ("trident","crab"), "crane": ("crane","outrigger"), "bulwark": ("citadel","notch"),
    "truss": ("gantry","catamaran"), "breaker": ("trident","citadel"), "train": ("gantry","box"),
    "wing": ("crescent","falx"), "spindle": ("blade","paddle"), "hangar": ("runway","catamaran"),
    "barge": ("paddle","box"), "arc": ("crescent","outrigger"),
}
SECONDARY = ["falx","rail","gantry","trident","catamaran","citadel","arrow","paddle","notch","crane","runway"]


def side_plan(key, span, beam, sign):
    vertices = []
    for pair in SIDES[key].split():
        x, y = map(int,pair.split(","))
        vertices.append([round((x/100)*span,2),round((y/100)*beam*sign,2)])
    return vertices


def inside(point, polygon):
    x,y=point
    odd=False
    for (ax,ay),(bx,by) in zip(polygon,polygon[1:]+polygon[:1]):
        if (ay > y) != (by > y) and x < (bx-ax)*(y-ay)/(by-ay)+ax:
            odd = not odd
    return odd


def seed(key):
    return int.from_bytes(hashlib.sha256(key.encode()).digest()[:8], "big")


def clamp(value, low, high):
    return max(low, min(high, value))


def identity_rows():
    rows = list(FIRST)
    for line, slug, ids in LINES:
        for ref, (role, tag) in zip(ids.split(), ROLES):
            rows.append((ref, f"{slug}_{tag}", f"{line}级{role}舰", role, ""))
    assert len({r[0] for r in rows}) == len(rows) == 53
    return rows


def merge_skin(base, skin):
    hull = copy.deepcopy(base)
    changes = skin["changes"]
    hull.update(id=skin["id"], base=base["id"], path=skin["path"])
    hull["hints"] = sorted(set(hull["hints"] + changes.get("addHints", [])) - set(changes.get("removeHints", [])))
    hull["tags"] = sorted(set(hull["tags"] + changes.get("tags", [])))
    mapping = {"fleetPoints": "fleet_points", "ordnancePoints": "op", "fighterBays": "bays", "maxSpeed": "speed",
               "suppliesToRecover": "deployment", "suppliesPerMonth": "upkeep", "shieldArc": "shield_arc"}
    for key, field in mapping.items():
        if key in changes:
            hull["stats"][field] = changes[key]
    hull["stats"]["price"] *= changes.get("baseValueMult", 1)
    hull["manufacturer"] = changes.get("tech", hull["manufacturer"])
    hull["source_system"] = changes.get("systemId", hull["source_system"])
    hull["shield"] = changes.get("shieldType", hull["shield"])
    hull["builtins"] = sorted(set(hull["builtins"] + changes.get("builtInMods", [])) - set(changes.get("removeBuiltInMods", [])))
    hull["built_in_weapons"].update(changes.get("builtInWeapons", {}))
    for removed in changes.get("removeBuiltInWeapons", []):
        hull["built_in_weapons"].pop(removed, None)
    hull["wings"] = changes.get("builtInWings", hull["wings"])
    hull["slots"] = [slot for slot in hull["slots"] if slot["id"] not in changes.get("removeWeaponSlots", [])]
    for slot in hull["slots"]:
        changed = changes.get("weaponSlotChanges", {}).get(slot["id"], {})
        for key in ("size", "mount", "angle", "arc", "type"):
            if key in changed:
                slot["family" if key == "type" else key] = changed[key]
    hull["damaged"] = changes.get("restoreToBaseHull", False)
    return hull


def yard_style(hull):
    if "CARRIER" in hull["hints"] or hull["stats"]["bays"] >= 2:
        return "hangar"
    if "TANKER" in hull["hints"]:
        return "barge"
    if "FREIGHTER" in hull["hints"] or "LINER" in hull["hints"]:
        return "train" if hull["stats"]["cargo"] >= 300 else "box"
    if hull["shield"] == "PHASE":
        return "arc"
    if "High" in hull["manufacturer"] or hull["style"] in ("REMNANT", "OMEGA"):
        return "wing"
    if hull["stats"]["armor"] >= 1000:
        return "breaker"
    if hull["stats"]["speed"] >= 140:
        return "dart"
    return ["lancet", "bulwark", "spindle", "truss"][seed(hull["id"]) % 4]


def make_outline(key, frame, size, serial):
    rng = random.Random(seed(key))
    width, height = IMAGES[size]
    length = (width / 2 - 3) * rng.uniform(.84, .98)
    beam = (height / 2 - 3) * rng.uniform(.63 if frame in ("dart", "spindle") else .80, 1.0)
    upper_type, lower_type = FORMS[frame]
    if 9 <= serial < 53:
        # All four designs from a yard share a structural signature on one
        # flank; the working flank and fittings follow the individual mission.
        yard,role=divmod(serial-9,4)
        if role in (0,3):
            lower_type=SECONDARY[yard]
        else:
            upper_type=SECONDARY[(yard+role*3)%len(SECONDARY)]
    if serial >= 53 and rng.randrange(3) == 0:
        lower_type=rng.choice(list(SIDES))
    upper=side_plan(upper_type,length,beam,-1)
    lower=side_plan(lower_type,length*rng.uniform(.83,1),beam*rng.uniform(.71,1),1)
    stern=[[-round(length*.60,2), round(beam*.10,2)],[-round(length*.66,2),-round(beam*.09,2)]]
    result=upper+list(reversed(lower))+stern
    return result, upper, lower


def envelope(x, side):
    for left, right in zip(side, side[1:]):
        if x <= right[0]:
            f = clamp((x-left[0])/(right[0]-left[0]), 0, 1)
            return left[1] + (right[1]-left[1])*f
    return side[-1][1]


def sorted_slots(h):
    return [s for s in h["slots"] if s["family"] in PORTS and s["mount"] != "HIDDEN"]


def hardpoints(h, upper, lower, scale, outline):
    rng = random.Random(seed(h["id"] + "-battery"))
    output = []
    used = []
    length = upper[-1][0]
    for n, source in enumerate(sorted_slots(h)):
        school = PORTS[source["family"]]
        angle = -float(source["angle"])
        slot_type = "固定" if source["mount"] == "HARDPOINT" else "炮塔"
        best, gap = (0, 0), -1
        # A max-spacing sampler keeps banks legible on packed flight decks.
        for _ in range(35):
            x = length*clamp(source["section"]*.42 + rng.uniform(-.36,.36),-.82,.74)
            sign = source["side"] or rng.choice((-1, 1))
            edge = envelope(x, upper if sign < 0 else lower)
            y = edge*rng.uniform(.30 if source["side"] else .06,.80)
            if h.get("frame") in ("fork","crane","breaker","arc") and x > length*.26:
                y = edge*rng.uniform(.50,.82)
            if not inside((x,y),outline):
                continue
            dist = min(((x-a)**2+(y-b)**2 for a,b in used), default=10000)
            if dist > gap:
                best, gap = (x,y), dist
        used.append(best)
        output.append({"id": f"bay_{n+1:02}", "reference": source["id"],
                       "offset": [round(v*scale,2) for v in best],
                       "facing": angle, "arc": source["arc"], "type": slot_type,
                       "size": {"SMALL":1,"MEDIUM":2,"LARGE":3}.get(source["size"],1),
                       "family": school, "accepts": ACCEPTS[school], "builtin": source["id"] in h["built_in_weapons"]})
    return output


def choice(gun, guns, slot, pick_seed):
    candidates = [(k,v) for k,v in guns.items() if v["mount"] <= slot["size"] and v["family"] in slot["accepts"]]
    assert candidates
    if gun in guns and any(k == gun for k,_ in candidates):
        return gun
    matching = [(k,v) for k,v in candidates if k.split("_")[0] == gun]
    pool = matching or candidates
    closest = max(v["mount"] for _,v in pool)
    return random.Random(pick_seed).choice([k for k,v in pool if v["mount"] == closest])


def gun_class(slot):
    if slot["family"] in ("energy", "synergy"):
        return "lance" if slot["size"] == 3 else "pulse"
    if slot["family"] == "missile":
        return "missile"
    if slot["size"] == 1:
        return "pd" if slot["type"] == "炮塔" else "rail"
    return "howitzer" if slot["size"] == 3 else "rail"


def issue_name(ref, rank, dock, identity):
    if identity:
        return identity[1:4]
    prefix = NOUNS[rank % len(NOUNS)]
    suffix = SUFFIX[rank // len(NOUNS) % len(SUFFIX)]
    specific = {"hangar":"航空支援","barge":"液货运输","box":"区域货运","train":"远航货运",
                "arc":"相位侧袭","breaker":"装甲压制","wing":"机动封锁","dart":"快速护航"}
    return "yard_" + ref.lower(), prefix + "级" + suffix, specific.get(dock,"战列巡防")


def make_model(h, position, identity, guns, wings, variants):
    ref = h["id"]
    stats = h["stats"]
    size = SIZE[h["size"]]
    frame = identity[4] if identity and identity[4] else yard_style(h)
    h["frame"] = frame
    uid, name, role = issue_name(ref, position, frame, identity)
    if not identity and "base" in h:
        suffix = {"Pirate":"边境武装", "Luddic Path":"过载改型", "Hegemony":"卫戍改型",
                  "Tri-Tachyon":"科研改型", "Sindrian Diktat":"仪卫改型"}.get(h["manufacturer"], "改型")
        name = name.removesuffix("舰") + "·" + suffix
    outline, top, bottom = make_outline(uid, frame, size, position)
    scale = CLASSES[size]["world_units_per_pixel"]
    slots = hardpoints(h, top, bottom, scale, outline)
    stock = [choice(gun_class(s), guns, s, seed(ref+s["id"])) for s in slots]
    if ref == "kite":
        # The player launch has an integrated forward emitter and aft PD cupola.
        slots[0].update(family="synergy",accepts=ACCEPTS["synergy"],arc=28.0)
        slots[2].update(facing=180,arc=360)
        stock = ["pulse", "missile_00", "pd"]
    stock_groups = [3 if guns[g].get("pd") else 2 if guns[g].get("missile") else 1 for g in stock]
    dp = round(max(1,stats["deployment"]))
    hp = round(clamp(stats["hp"]*.052 + 55,55,1540))
    armor = round(clamp(stats["armor"]*.115,8,350),1)
    capacity = round(48 + stats["flux"]*.02,1)
    dissipation = round(10+stats["dissipation"]*.13,1)
    op = max(sum(guns[k]["op"] for k in stock)+4,round(stats["op"]*.72))
    source_system = h["source_system"]
    system = "phase" if h["shield"] == "PHASE" or source_system in ("displacer","teleport","temporalshell") else "boost"
    if any(s in source_system for s in ("burst","feed","override","missile","reserve","ammo","focus","forge","entropy")):
        system = "burst"
    if frame in ("box", "hangar","train","barge","fork","crane"):
        system = "repair"
    shield_type = h["shield"] if h["shield"] in ("NONE","FRONT","OMNI") else "NONE"
    market = not (set(h["hints"]) & {"UNBOARDABLE","HIDE_IN_CODEX"} or set(h["tags"]) & {"restricted","hide_in_codex"} or h.get("damaged"))
    if h.get("base") in ("onslaught", "legion", "dominator") and "restricted" not in h["tags"]:
        market = not h.get("damaged")
    tanks = round(max(stats["fuel"], 0))
    cap_crew = round(max(1,stats["crew"]*.13))
    model = {"id": uid, "reference": ref, "reference_base": h.get("base", ref), "name": name, "role": role,
             "size": size, "frame": frame, "market": market, "category": "ship",
             "hp": hp, "cargo": round(max(5, stats["cargo"]*.37+7)), "fuel": round(.7+stats["fuel_per_ly"]*.07,2),
             "fuel_tank": tanks, "burn": stats["burn"], "deployment": dp, "dp": dp, "upkeep": stats["upkeep"],
             "peak_seconds": stats["peak_seconds"], "cr_deploy": stats["cr_deploy"], "crew_min": cap_crew,
             "crew_max": max(cap_crew, round(stats["max_crew"]*.17)), "mass": round(max(10,stats["mass"]*.07)),
             "speed": round(clamp(.44+stats["speed"]*.0045,.40,1.58),3), "power": round(10+dp*1.7),
             "acceleration": stats["acceleration"], "deceleration": stats["deceleration"], "turn_rate": stats["turn"],
             "recipe": round(15+dp*3+size*8),
             "mine": round(8+size*4+(16 if frame in ("truss","fork","crane") else 0)),
             "salvage": 6 if frame in ("crane","truss") else 0, "reload":round(.18+size*.043,3),
             "style_id": seed(h["manufacturer"])%8, "paint": PAINT[seed(h["manufacturer"])%8],
             "bounds":[[round(a*scale,3),round(b*scale,3)] for a,b in outline],
             "sprite_size": IMAGES[size], "sprite_center":[n/2 for n in IMAGES[size]], "sprite_scale": scale,
             "shield_center": [round((top[1][0]+top[-2][0])*.075*scale,2),0],
             "shield_type": shield_type, "shield_arc": stats["shield_arc"], "shield_efficiency": stats["shield_efficiency"] or 1.,
             "shield_turn_rate":round(max(30,stats["turn"]*1.7)), "shield_upkeep": stats["shield_upkeep"],
             "phase":h["shield"]=="PHASE", "fighter_bays": int(stats["bays"]),
             "builtins":h["builtins"], "source_system":source_system, "wings":[], "reference_wings":[],
             "engine_slots":[], "mounts":slots, "combat":{"op":op,"armor":armor,"capacity":capacity,
             "dissipation":dissipation,"system":system,"stock":stock,"groups":stock_groups},
             "tuning_limit":CLASSES[size]["tuning_limit"], "presets":[]}
    if identity in FIRST:
        # Keep opening encounters, cargo capacity and material requirements on
        # their original scale while the new local mount designs take effect.
        hp0,cargo0,rec0,spd0,fuel0,pow0,mine0,sal0,cap0,diss0,arm0,sys0 = [
            (100,36,18,1,.78,17,12,0,100,24,32,"boost"),(145,105,28,.82,.95,12,12,0,92,21,41,"boost"),
            (185,52,42,.93,1.10,25,12,0,118,28,63,"burst"),(112,62,32,.79,.88,13,24,0,86,20,46,"repair"),
            (160,92,46,.85,1.11,15,13,6,119,25,56,"phase"),(410,82,78,.71,1.48,49,12,0,190,39,138,"burst"),
            (265,164,65,.64,1.35,19,38,0,149,30,102,"repair"),(720,128,132,.54,2.24,86,12,0,300,51,240,"burst"),
            (480,340,104,.60,1.67,25,13,0,195,38,165,"repair")][position]
        model.update(hp=hp0,cargo=cargo0,recipe=rec0,speed=spd0,fuel=fuel0,power=pow0,mine=mine0,salvage=sal0,market=True)
        model["combat"].update(capacity=cap0,dissipation=diss0,armor=arm0,system=sys0)
        if ref == "kite":
            model.update(shield_efficiency=1.0)
            model["combat"]["op"] = 20
    if "远征采冶" in role:
        model.update(mine=22+size*6,salvage=3)
    if "边境物流" in role:
        model["cargo"] = max(model["cargo"], 34+42*size)
    engines=clamp(round(math.sqrt(max(1,h["engine_count"]))*1.35),1,7)
    for n in range(engines):
        t=(n+.5)/engines
        y=min(p[1] for p in outline)*.5*(1-t)+max(p[1] for p in outline)*.5*t
        start=int(min(p[0] for p in outline))
        end=int(max(p[0] for p in outline))
        x=next((v for v in range(start,end) if inside((v,y),outline)),0)
        model["engine_slots"].append([round(x*scale+.5,2),round(y*scale,2)])
    by_id = {s["reference"]: j for j,s in enumerate(slots)}
    for v in variants:
        equipped = [""]*len(slots)
        groups = stock_groups.copy()
        for group, bank in enumerate(v["guns"]):
            for key, source_gun in bank.items():
                if key in by_id:
                    j=by_id[key];slot=slots[j]
                    equipped[j]=choice(gun_class(slot),guns,slot,seed(source_gun))
                    groups[j]=min(group+1,3)
        for j,s in enumerate(slots):
            if s["builtin"]:
                equipped[j]=stock[j]
        cost=sum(guns[k]["op"] for k in equipped if k)
        room=model["combat"]["op"]-cost
        if room < 0:
            # Same slot/weapon family, cheapest locally available issue.
            for j in sorted(range(len(slots)),key=lambda k:-guns.get(equipped[k],{}).get("op",0)):
                if not equipped[j] or slots[j]["builtin"]:
                    continue
                gun=guns[equipped[j]]
                k=min((k for k,w in guns.items() if w["family"]==gun["family"] and w["mount"]<=slots[j]["size"]),key=lambda k:guns[k]["op"])
                room+=gun["op"]-guns[k]["op"];equipped[j]=k
                if room>=0: break
        if room < 0:
            raise ValueError(f"unaffordable preset {v['path']}")
        vents=min(model["tuning_limit"],int(v["vents"]),room)
        caps=min(model["tuning_limit"],int(v["caps"]),room-vents)
        model["presets"].append({"id":v["id"],"reference_path":v["path"],"weapons":equipped,"groups":groups,
                                "auto":[False,True,True],"caps":caps,"vents":vents,"wings":v["wings"]})
    model["builtin_wings"] = h["wings"].copy()
    if model["fighter_bays"] or h["wings"]:
        options=next((v["wings"] for v in variants if v["wings"]),h["wings"]) or ["broadsword_wing"]
        bays=max(model["fighter_bays"],len(h["wings"]))
        model["fighter_bays"]=bays
        model["reference_wings"]=[options[j%len(options)] for j in range(bays)]
        model["wings"]=[wings[k]["role"] for k in model["reference_wings"]]
    return model


def main():
    manifest=json.loads((HERE/"manifest.json").read_text(encoding="utf8"))
    guns=json.loads((HERE/"weapons.json").read_text(encoding="utf8"))
    base={h["id"]:h for h in manifest["hulls"]}
    sources={**base,**{s["id"]:merge_skin(base[s["base"]],s) for s in manifest["skins"]}}
    rows=identity_rows(); identities={r[0]:r for r in rows}
    order=list(identities)+[k for k,h in sources.items() if k not in identities and h["category"]=="ship"]
    wings={w["id"]:w for w in manifest["wings"]}
    variants={}
    for v in manifest["variants"]:
        variants.setdefault(v["hull"],[]).append(v)
    models=[make_model(sources[ref],i,identities.get(ref),guns,wings,variants.get(ref,[])) for i,ref in enumerate(order)]
    assert len({m["id"] for m in models})==len(models)
    assert len({m["name"] for m in models})==len(models)
    variant_hull={v["id"]:v["hull"] for v in manifest["variants"]}
    equipment=[]
    local={m["reference"]:m["id"] for m in models}
    for ref,h in sources.items():
        if h["category"]=="ship":
            continue
        uid=f"yard_{h['category']}_{ref.lower()}"
        local[ref]=uid
        banks=[s for s in h["slots"] if s["family"] in PORTS]
        role="battery" if banks else "structure"
        if h["stats"]["bays"] or h["wings"]:
            role="hangar"
        elif h["shield"] in ("FRONT","OMNI") and not banks:
            role="shield"
        elif h["category"]=="fighter":
            role="flight"
        equipment.append({"id":uid,"reference":ref,"base":h.get("base",ref),"category":h["category"],"role":role,
            "hp":round(clamp(h["stats"]["hp"]*.052+8,8,950),1),"armor":round(clamp(h["stats"]["armor"]*.115,1,350),1),
            "banks":len(banks),"bays":int(h["stats"]["bays"]),"speed":round(clamp(h["stats"]["speed"]*.76,20,345)),
            "modules":[]})
    by_ref={t["reference"]:t for t in equipment}
    for model in models+equipment:
        subs=next((v["modules"] for v in variants.get(model["reference"],[]) if v["modules"]),{})
        model["modules"]=[]
        for i,(slot,child_variant) in enumerate(subs.items()):
            ref=variant_hull[child_variant]
            part=by_ref.get(ref)
            if part:
                if model.get("bounds"):
                    # The two replaceable casemates are mounted to opposite flanks of the local hull.
                    side=-1 if ref.endswith("_left") else 1
                    beam=max(abs(y) for _,y in model["bounds"] if y*side>0)
                    length=max(x for x,_ in model["bounds"])-min(x for x,_ in model["bounds"])
                    pos=[-0.09*length,side*beam*0.66]
                    half_len,half_beam=length*0.14,beam*0.22
                else:
                    angle=math.tau*i/len(subs)
                    ring=44+4*math.sqrt(len(subs))
                    pos=[ring*math.cos(angle),ring*math.sin(angle)]
                    half_len,half_beam=9+part["banks"]*0.8,6+part["bays"]*1.2
                outline=[[-half_len,-half_beam*.6],[-half_len*.7,-half_beam],
                         [half_len*.7,-half_beam],[half_len,0],[half_len*.65,half_beam],
                         [-half_len*.8,half_beam]]
                model["modules"].append({"mount":slot,"variant":child_variant,"reference":ref,
                    "id":part["id"],"role":part["role"],"hp":part["hp"],"armor":part["armor"],
                    "offset":[round(n,2) for n in pos],"bounds":[[round(x,2),round(y,2)] for x,y in outline],
                    "radius":round(math.hypot(half_len,half_beam),2)})
    wing_specs=[]
    for wing in wings.values():
        ref=variant_hull[wing["variant"]]
        airframe=by_ref[ref]
        wing_specs.append({"id":wing["id"],"project_id":"flight_"+wing["id"],"airframe":airframe["id"],
            "role":wing["role"],"count":wing["count"],"refit":wing["refit"],"range":wing["range"],
            "hp":airframe["hp"],"speed":airframe["speed"],
            "price":12+int(wing["count"])*5+round(wing["refit"]*2.5)})
    write_index(HERE/"fleet.json", {"models":models,"attachments":equipment,"wing_specs":wing_specs})
    print(f"{len(models)} mobile hull definitions, {sum(len(m['presets']) for m in models)} deployable fitting records")


if __name__=="__main__":
    main()
