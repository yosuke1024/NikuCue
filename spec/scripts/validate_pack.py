#!/usr/bin/env python3
"""Validate this specification pack, not an iOS application.
Python 3.10+; standard library only. Does not use network or mutate inputs.
"""
from pathlib import Path
import json
import re
import sys

BASE = Path(__file__).resolve().parents[1]

def load(relative: str):
    with (BASE / relative).open(encoding="utf-8") as f:
        return json.load(f)

def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)

def placeholders(text: str) -> set[str]:
    return set(re.findall(r"\{([A-Za-z][A-Za-z0-9_]*)\}", text))

def main() -> None:
    langs = {code: load(f"localization/{code}.json") for code in ("ja", "en", "th")}
    keys = set(langs["en"])
    for code, data in langs.items():
        require(set(data) == keys, f"Localization keys differ: {code}")
        for key, value in data.items():
            require(isinstance(value, str) and bool(value.strip()), f"Empty/invalid string: {code}/{key}")
            require(placeholders(value) == placeholders(langs["en"][key]), f"Placeholder mismatch: {code}/{key}")
    character = load("assets-spec/character_spec.json")
    nodes = character["nodes"]
    node_ids = {n["id"] for n in nodes}
    require(len(node_ids) == len(nodes), "Duplicate node IDs")
    by_id = {n["id"]: n for n in nodes}
    require(len([n for n in nodes if n["parent"] is None]) == 1, "Rig must have one root")
    for n in nodes:
        seen = {n["id"]}
        p = n["parent"]
        while p is not None:
            require(p in by_id, f"Missing parent {p}")
            require(p not in seen, f"Cycle at {p}")
            seen.add(p)
            p = by_id[p]["parent"]
    clips = load("assets-spec/animations.json")["clips"]
    clip_ids = {c["id"] for c in clips}
    require(len(clip_ids) == len(clips) == 8, "Expected eight unique animation clips")
    for c in clips:
        require(set(c["controls"]) <= node_ids, f"Missing animation node: {c['id']}")
        require(c["expression"] in character["expressions"], "Invalid expression")
        require(c["durationMs"] > 0 and c["reducedMotion"], "Invalid clip timing/accessibility")
        times = [x["endMs"] for x in c.get("timeline", [])]
        require(times == sorted(set(times)), "Non-monotonic timeline")
        if times:
            require(times[-1] == c["durationMs"], "Timeline duration mismatch")
    reactions = load("assets-spec/reactions.json")["items"]
    ids = [r["id"] for r in reactions]
    require(len(ids) == len(set(ids)), "Duplicate reaction IDs")
    for r in reactions:
        require(r["clipId"] in clip_ids, f"Unknown reaction clip: {r['id']}")
        require(bool(r["messageKeys"]) and set(r["messageKeys"]) <= keys, f"Unknown reaction strings: {r['id']}")
    meta = load("store/metadata.json")["locales"]
    for code, m in meta.items():
        for field, limit in [("title", 30), ("subtitle", 30), ("promo", 170), ("description", 4000), ("iapName", 30), ("iapDescription", 45)]:
            # Python code-point counts are conservative for Thai combining marks;
            # final Store Connect field acceptance still needs manual verification.
            require(len(m[field]) <= limit, f"{code}/{field} exceeds pack limit {limit}: {len(m[field])}")
        require(len(m["keywords"].encode("utf-8")) <= 100, f"{code} keywords exceed conservative 100-byte budget")
    cases = load("qa/scenarios.json")["cases"]
    require(len(cases) == 40 and len({c['id'] for c in cases}) == 40, "Expected 40 unique QA scenarios")
    require(all(c["status"] == "not_run" for c in cases), "Specs must not claim iOS tests have run")
    sources = (BASE / "docs/13_SOURCES_DECISIONS.md").read_text(encoding="utf-8")
    defined = set(re.findall(r"### \[(S\d+)\]", sources))
    for md in BASE.rglob("*.md"):
        referenced = set(re.findall(r"\[(S\d+)\]", md.read_text(encoding="utf-8")))
        require(referenced <= defined, f"Undefined sources in {md.relative_to(BASE)}: {referenced-defined}")
    print(json.dumps({"status":"PASS", "scope":"Specification consistency only; no iOS build or runtime tests", "localization_keys_per_language":len(keys), "languages":list(langs), "rig_nodes":len(nodes), "animation_clips":len(clips), "reaction_rules":len(reactions), "qa_scenarios_not_run":len(cases), "source_entries":len(defined)}, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, TypeError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
