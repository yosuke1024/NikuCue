#!/usr/bin/env python3
"""Produces NikuCue/Resources/Character/character_spec.json from the pack contract plus the
documented rig revisions (docs/SPEC_REVISIONS.md). Node ids, hierarchy, kinds, z-order and
palette are never changed here; only positions/sizes that tune the silhouette.

Run: python3 tools/character/apply_rig_revisions.py
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "spec" / "assets-spec" / "character_spec.json"
OUT = ROOT / "NikuCue" / "Resources" / "Character" / "character_spec.json"

# REV-001: fore paw node position = shoulder (see SPEC_REVISIONS.md)
# REV-007: chibi proportions after the first review ("not cute": tall body, long legs, tiny high eyes)
REVISIONS = [
    {
        "id": "REV-001", "date": "2026-10-10",
        "change": "forePawL/forePawR position relative to their pivots is the shoulder point.",
        "reason": "With anchor [0.5,0.87/0.9] the node position is the shoulder; the pack value [0,-84] put the paw below the ground.",
        "nodes": {"forePawL": {"position": [0, 0]}, "forePawR": {"position": [0, 0]}},
    },
    {
        "id": "REV-007", "date": "2026-10-10",
        "change": "Rounder chibi proportions: larger head overlapping a short wide body, stubby fore paws, larger eyes set lower on the face, bigger cheeks and shorter rounded ears.",
        "reason": "Owner review of the first prototype render: 'not cute at all'. docs/04 §4 allows tuning the starting values; the hierarchy, ids and z-order are unchanged.",
        "nodes": {
            "shadow": {"size": [360, 44]},
            "bodyPivot": {"position": [0, 180]},
            "tailPivot": {"position": [165, -115]},
            "tail": {"size": [120, 250]},
            "body": {"size": [440, 360]},
            "hindPawL": {"position": [-166, -160], "size": [112, 62]},
            "hindPawR": {"position": [166, -160], "size": [112, 62]},
            "forePawLPivot": {"position": [-76, -30]},
            "forePawRPivot": {"position": [76, -30]},
            "forePawL": {"size": [100, 160], "anchor": [0.5, 0.9]},
            "forePawR": {"size": [100, 160], "anchor": [0.5, 0.9]},
            "headPivot": {"position": [0, 90]},
            "earLPivot": {"position": [-170, 318]},
            "earRPivot": {"position": [170, 318]},
            "earL": {"size": [150, 150]},
            "earR": {"size": [150, 150]},
            "head": {"position": [0, 170], "size": [510, 400]},
            "muzzle": {"position": [0, 88], "size": [146, 84]},
            "eyeL": {"position": [-98, 142], "size": [64, 80]},
            "eyeR": {"position": [98, 142], "size": [64, 80]},
            "nose": {"position": [0, 100], "size": [26, 18]},
            "mouth": {"position": [0, 76], "size": [60, 26]},
            "cheekL": {"position": [-166, 108], "size": [84, 36]},
            "cheekR": {"position": [166, 108], "size": [84, 36]},
        },
    },
]


def main() -> None:
    spec = json.loads(SRC.read_text(encoding="utf-8"))
    by_id = {n["id"]: n for n in spec["nodes"]}
    log = []
    for rev in REVISIONS:
        touched = []
        for node_id, fields in rev["nodes"].items():
            node = by_id[node_id]
            for key, value in fields.items():
                if node.get(key) != value:
                    node[key] = value
            touched.append(node_id)
        log.append({"id": rev["id"], "date": rev["date"], "nodes": touched, "change": rev["change"], "reason": rev["reason"]})
    spec["revisions"] = log
    spec["status"] = "Original-art specification with repository revisions; prototype art; requires visual approval"
    OUT.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} with {len(log)} revisions")


if __name__ == "__main__":
    main()
