#!/usr/bin/env python3
"""Regenerate the bundled symbol sets from their upstream sources.

Usage: scripts/update-sets.py [SET_ID ...]

Reads Sets/catalog.json and, for each set (or only the ones named), downloads
`source.url`, converts it to the bundled format and writes `Sets/<file>`. It
also refreshes each set's licence text from `source.licenseUrl`.

The bundled format is a flat JSON object {"command": "replacement"} with the
command written without its leading backslash, sorted by command. Entries are
dropped when the command or replacement is empty or contains whitespace (the
input method ends a command at a space), or when the command contains a
backslash (typing one starts a new command, so it could never be reached;
`\\` for a literal backslash is built into the input method instead). Lean's
"$CURSOR" marker is removed, so the cursor lands after the inserted text.

This script only converts data. The rule that sets in different classes never
share a command is checked by the test suite (`./build.sh test`), which every
build and install runs. See ARCHITECTURE.md.
"""
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETS = ROOT / "Sets"


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read().decode("utf-8")


def parse_flat(text):
    return json.loads(text)


def parse_agda_keymap(text):
    """agda-mode-vscode's keymap.js: `module.exports = {trie}` where each node
    maps a character to a child node and ">>" to the candidate list. Agda's
    default is the first candidate; an input method inserts exactly one."""
    body = text[text.index("=") + 1:].strip().rstrip(";")
    out = {}

    def walk(node, prefix):
        for k, v in node.items():
            if k == ">>":
                if v:
                    out[prefix] = v[0]
            else:
                walk(v, prefix + k)

    walk(json.loads(body), "")
    return out


def parse_gemoji(text):
    """github/gemoji db/emoji.json: a list of {emoji, aliases, ...}. Every alias
    becomes a command wrapped in colons, as typed on GitHub: ":smile:"."""
    return {f":{alias}:": e["emoji"] for e in json.loads(text) for alias in e["aliases"]}


PARSERS = {"flat": parse_flat, "agda-keymap": parse_agda_keymap, "gemoji": parse_gemoji}


def normalise(table):
    out = {}
    for k, v in table.items():
        v = v.replace("$CURSOR", "")
        if not k or not v or "\\" in k or any(c.isspace() for c in k + v):
            continue
        out[k] = v
    return dict(sorted(out.items()))


def main(argv):
    catalog = json.loads((SETS / "catalog.json").read_text(encoding="utf-8"))
    wanted = set(argv)
    known = {s["id"] for c in catalog["classes"] for s in c["sets"]}
    unknown = wanted - known
    if unknown:
        sys.exit(f"unknown set(s): {' '.join(sorted(unknown))}; known: {' '.join(sorted(known))}")
    for cls in catalog["classes"]:
        for s in cls["sets"]:
            if wanted and s["id"] not in wanted:
                continue
            src = s["source"]
            table = normalise(PARSERS[src["format"]](fetch(src["url"])))
            path = SETS / s["file"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(table, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
            lic = SETS / src["licenseFile"]
            lic.parent.mkdir(parents=True, exist_ok=True)
            lic.write_text(fetch(src["licenseUrl"]), encoding="utf-8")
            print(f"{cls['name']} / {s['name']}: {len(table)} commands -> Sets/{s['file']}")


if __name__ == "__main__":
    main(sys.argv[1:])
