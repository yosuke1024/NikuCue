#!/usr/bin/env python3
"""Parses project.pbxproj (OpenStep plist) and checks referential integrity.
Not a substitute for opening the project in Xcode, but catches typos and dangling ids."""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "NikuCue.xcodeproj" / "project.pbxproj"


class Parser:
    def __init__(self, text: str):
        self.text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        self.text = re.sub(r"//[^\n]*", "", self.text)
        self.i = 0

    def ws(self):
        while self.i < len(self.text) and self.text[self.i] in " \t\r\n":
            self.i += 1

    def parse(self):
        self.ws()
        c = self.text[self.i]
        if c == "{":
            return self.dict()
        if c == "(":
            return self.array()
        if c == '"':
            return self.string()
        return self.bare()

    def dict(self):
        self.i += 1
        out = {}
        while True:
            self.ws()
            if self.text[self.i] == "}":
                self.i += 1
                return out
            key = self.parse()
            self.ws()
            assert self.text[self.i] == "=", f"expected = at {self.i}"
            self.i += 1
            value = self.parse()
            self.ws()
            assert self.text[self.i] == ";", f"expected ; at {self.i}: {self.text[self.i:self.i+40]!r}"
            self.i += 1
            out[key] = value

    def array(self):
        self.i += 1
        out = []
        while True:
            self.ws()
            if self.text[self.i] == ")":
                self.i += 1
                return out
            out.append(self.parse())
            self.ws()
            if self.text[self.i] == ",":
                self.i += 1

    def string(self):
        self.i += 1
        buf = ""
        while self.text[self.i] != '"':
            if self.text[self.i] == "\\":
                buf += self.text[self.i:self.i + 2]
                self.i += 2
            else:
                buf += self.text[self.i]
                self.i += 1
        self.i += 1
        return buf

    def bare(self):
        m = re.match(r"[A-Za-z0-9_./$:+-]+", self.text[self.i:])
        assert m, f"unexpected char at {self.i}: {self.text[self.i:self.i+20]!r}"
        self.i += m.end()
        return m.group(0)


def main() -> None:
    root = Parser(PATH.read_text(encoding="utf-8")).parse()
    objects = root["objects"]
    ids = set(objects)
    problems = []
    id_re = re.compile(r"^[0-9A-F]{24}$")

    def walk(value, path):
        if isinstance(value, dict):
            for k, v in value.items():
                walk(v, f"{path}.{k}")
        elif isinstance(value, list):
            for v in value:
                walk(v, path)
        elif isinstance(value, str) and id_re.match(value) and value not in ids:
            problems.append(f"dangling id {value} at {path}")

    walk(objects, "objects")
    if root["rootObject"] not in ids:
        problems.append("rootObject missing")
    project = objects[root["rootObject"]]
    assert project["isa"] == "PBXProject"
    targets = [objects[t] for t in project["targets"]]
    for t in targets:
        for phase in t["buildPhases"]:
            assert objects[phase]["isa"].endswith("BuildPhase"), f"{phase} is not a build phase"
        for g in t.get("fileSystemSynchronizedGroups", []):
            group = objects[g]
            assert group["isa"] == "PBXFileSystemSynchronizedRootGroup"
            if not (ROOT / group["path"]).is_dir():
                problems.append(f"synchronized folder missing: {group['path']}")
        cfg = objects[t["buildConfigurationList"]]
        for c in cfg["buildConfigurations"]:
            assert objects[c]["isa"] == "XCBuildConfiguration"
    for ref in project.get("packageReferences", []):
        pkg = objects[ref]
        if not (ROOT / pkg["relativePath"] / "Package.swift").is_file():
            problems.append(f"package missing: {pkg['relativePath']}")
    isas = {}
    for o in objects.values():
        isas[o["isa"]] = isas.get(o["isa"], 0) + 1
    if problems:
        print("FAIL")
        for p in problems:
            print(" -", p)
        sys.exit(1)
    print("PASS:", len(objects), "objects;", ", ".join(f"{k}×{v}" for k, v in sorted(isas.items())))
    print("targets:", [t["name"] for t in targets])


if __name__ == "__main__":
    main()
