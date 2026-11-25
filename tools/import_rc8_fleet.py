"""Index technical IDs and design facts from an unmodified RC8 data directory.

Usage: python tools/import_rc8_fleet.py <starsector-core/data> [output-dir]
This importer reads text definitions only. It does not import art, prose,
original hull contours, exact hardpoint coordinates, scripts, or sounds.
"""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path


VERSION = "0.98a-RC8"
ARCHIVE = "https://f005.backblazeb2.com/file/fractalsoftworks/release/starsector_linux-0.98a-RC8.zip"


def loose_json(path):
    # The shipped files allow hash comments, bare enumeration values, .5,
    # trailing commas, and in manticore_pather.skin a redundant closing brace.
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    token = r'("(?:[^"\\]|\\.)*")|(?://|#)[^\r\n]*|(?<![\w.])(-?\.\d+)|([A-Za-z_][A-Za-z_\d]*)'

    def normalize(match):
        quoted, fraction, bare = match.groups()
        if quoted:
            return quoted
        if fraction:
            return fraction.replace(".", "0.", 1)
        if bare:
            return bare if bare in ("null", "true", "false") else json.dumps(bare)
        return ""

    text = re.sub(token, normalize, text).strip()
    text = re.sub(r",\s*([}\]])", r"\1", text)
    value, end = json.JSONDecoder(strict=False).raw_decode(text)
    suffix = text[end:].strip()
    if suffix and not (path.name == "manticore_pather.skin" and suffix == "}"):
        raise ValueError(f"unexpected trailing data in {path}")
    return value


def table(path):
    with path.open(encoding="cp1252", newline="") as stream:
        return [row for row in csv.DictReader(stream) if row["id"].strip() and not row.get("name", row["id"]).startswith("#")]


def split(value):
    return [item.strip() for item in value.split(",") if item.strip()]


def fraction(value, default=0):
    return float(value) if value not in ("", None) else default


def source_slot(slot):
    # Discrete fore/mid/aft and port/starboard sectors describe tactical
    # placement, without using source pixel coordinates for the new artwork.
    position = slot.get("locations", [0, 0])
    return {
        "id": slot["id"], "size": slot.get("size", "SMALL"),
        "family": slot.get("type", "UNIVERSAL"), "mount": slot.get("mount", "TURRET"),
        "arc": slot.get("arc", 0), "angle": slot.get("angle", 0),
        "side": 1 if position[1] < -5 else -1 if position[1] > 5 else 0,
        "section": 1 if position[0] > 12 else -1 if position[0] < -12 else 0,
    }


def hull_entry(path, row, obj, root):
    hints = split(row["hints"])
    kind = "ship"
    if "MODULE" in hints:
        kind = "module"
    elif "STATION" in hints or row["id"] == "station_small":
        kind = "station"
    elif obj["hullSize"] == "FIGHTER":
        kind = "fighter"
    elif row["id"] == "shuttlepod":
        kind = "auxiliary"
    numeric = {
        "fleet pts": "fleet_points", "hitpoints": "hp", "armor rating": "armor", "max flux": "flux",
        "flux dissipation": "dissipation", "ordnance points": "op", "fighter bays": "bays",
        "max speed": "speed", "max turn rate": "turn", "acceleration": "acceleration",
        "deceleration": "deceleration", "mass": "mass", "shield arc": "shield_arc",
        "shield efficiency": "shield_efficiency", "shield upkeep": "shield_upkeep",
        "min crew": "crew", "max crew": "max_crew", "cargo": "cargo", "fuel": "fuel",
        "fuel/ly": "fuel_per_ly", "max burn": "burn", "supplies/rec": "deployment",
        "supplies/mo": "upkeep", "peak CR sec": "peak_seconds", "CR to deploy": "cr_deploy",
        "base value": "price",
    }
    return {
        "id": row["id"], "reference_name": row["name"] or obj.get("hullName",row["id"]),
        "designation": row["designation"], "category": kind, "size": obj["hullSize"], "path": path.relative_to(root).as_posix(),
        "manufacturer": row["tech/manufacturer"], "source_system": row["system id"],
        "shield": row["shield type"], "defense": row["defense id"],
        "hints": hints, "tags": split(row["tags"]), "style": obj.get("style", ""),
        "stats": {dest: fraction(row[col]) for col, dest in numeric.items()},
        "slots": [source_slot(s) for s in obj.get("weaponSlots", [])],
        "engine_count": len(obj.get("engineSlots", [])), "builtins": obj.get("builtInMods", []),
        "built_in_weapons": obj.get("builtInWeapons", {}), "wings": obj.get("builtInWings", []),
    }


def build(root):
    hull_dir = root / "hulls"
    geometries = {}
    duplicate_geom = []
    for path in sorted(hull_dir.rglob("*.ship")):
        obj = loose_json(path)
        key = obj["hullId"]
        if key in geometries:
            duplicate_geom.append({"id": key, "path": path.relative_to(root).as_posix()})
        else:
            geometries[key] = (path, obj)
    hull_table = hull_dir / "ship_data.csv"
    hulls = []
    for row in table(hull_table):
        path, obj = geometries.pop(row["id"])
        hulls.append(hull_entry(path, row, obj, root))
    skins = []
    for path in sorted(hull_dir.rglob("*.skin")):
        obj = loose_json(path)
        keys = ("weaponSlotChanges", "removeWeaponSlots", "removeBuiltInMods", "builtInMods",
                "removeBuiltInWeapons", "builtInWeapons", "builtInWings", "removeEngineSlots",
                "fighterBays", "fleetPoints", "ordnancePoints", "baseValueMult", "maxSpeed",
                "suppliesToRecover", "suppliesPerMonth", "shieldType", "shieldArc", "tech",
                "systemId", "addHints", "removeHints", "restoreToBaseHull", "tags")
        changes = {k: obj[k] for k in keys if k in obj}
        for slot in changes.get("weaponSlotChanges", {}).values():
            for field in ("locations", "location"):
                slot.pop(field, None)
        skins.append({"id": obj["skinHullId"], "base": obj["baseHullId"],"reference_name":obj.get("hullName",obj["skinHullId"]),
                      "path": path.relative_to(root).as_posix(), "changes": changes})
    variants = []
    for path in sorted((root / "variants").rglob("*.variant")):
        obj = loose_json(path)
        sub = obj.get("modules", [])
        if isinstance(sub, list):
            sub = {key: value for d in sub for key, value in d.items()}
        variants.append({"id": obj["variantId"], "hull": obj["hullId"], "reference_name":obj.get("displayName",""),
                         "path": path.relative_to(root).as_posix(),
                         "wings": obj.get("wings", []), "modules": sub, "mods": obj.get("hullMods", []),
                         "guns": [g.get("weapons", {}) for g in obj.get("weaponGroups", [])],
                         "vents": obj.get("fluxVents", 0), "caps": obj.get("fluxCapacitors", 0)})
    wings = [{"id": r["id"], "variant": r["variant"], "role": r["role"].lower(), "count": int(r["num"]),
              "refit": fraction(r["refit"]), "range": fraction(r["range"])} for r in table(hull_dir / "wing_data.csv")]
    expected = (200, 66, 447, 31)
    if tuple(map(len, (hulls, skins, variants, wings))) != expected:
        raise ValueError("The supplied content differs from the RC8 base release")
    return {"source": {"version": VERSION, "archive": ARCHIVE,
                       "archive_sha1": "6827a55298d6606db85b1c69b25f2a245c8028ba",
                       "ship_csv_sha256": hashlib.sha256(hull_table.read_bytes()).hexdigest()},
            "hulls": hulls, "skins": skins, "variants": variants, "wings": wings,
            "extra_geometry": duplicate_geom + [{"id": k, "path": v[0].relative_to(root).as_posix()}
                                                for k, v in geometries.items()]}


def write_index(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    # A record per line keeps changes to individual definitions reviewable.
    with path.open("w", encoding="utf-8", newline="\n") as file:
        file.write("{\n")
        keys = list(data)
        for i, (key, group) in enumerate(data.items()):
            file.write("  " + json.dumps(key) + ": ")
            if isinstance(group, list):
                file.write("[\n")
                file.write(",\n".join("    " + json.dumps(e, ensure_ascii=False, separators=(",", ":")) for e in group))
                file.write("\n  ]")
            else:
                file.write(json.dumps(group, ensure_ascii=False))
            file.write(",\n" if i + 1 < len(keys) else "\n")
        file.write("}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("output", nargs="?", type=Path, default=Path(__file__).resolve().parents[1] / "data" / "fleet")
    args = parser.parse_args()
    write_index(args.output / "manifest.json", build(args.data))
