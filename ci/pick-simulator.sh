#!/bin/bash
# Gibt die UDID eines verfügbaren iPhone-Simulators mit der neuesten iOS-Version aus.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys, re
data = json.load(sys.stdin)["devices"]
def ver(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
best = None
for rt, devices in data.items():
    if "iOS" not in rt:
        continue
    for d in devices:
        if not d["name"].startswith("iPhone"):
            continue
        score = (ver(rt), "Pro" in d["name"] and "Max" not in d["name"])
        if best is None or score > best[0]:
            best = (score, d["udid"], d["name"], rt)
if best is None:
    sys.exit("Kein iPhone-Simulator gefunden")
print(best[1])
print(f"Simulator: {best[2]} ({best[3]})", file=sys.stderr)
'
