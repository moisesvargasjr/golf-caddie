#!/usr/bin/python3 -I
"""pbx-resolve.py <worktree>: resolve a conflicted GolfCaddie.xcodeproj/project.pbxproj.

Both sides of every stacked Duo v2 branch only ADD files, so a --union merge
is right except that it repeats entries both sides added (e.g. after two
different merges of the same branches). Those repeats are dropped; then it
checks that no object id is defined twice.
"""
import re
import subprocess
import sys

wt = sys.argv[1]
path = "GolfCaddie.xcodeproj/project.pbxproj"
stage = lambda n: subprocess.run(["git", "-C", wt, "show", f":{n}:{path}"], capture_output=True,
                                 text=True, check=True).stdout
base, ours, theirs = stage(1), stage(2), stage(3)
tmp = {}
for name, text in (("base", base), ("ours", ours), ("theirs", theirs)):
    tmp[name] = f"{wt}/.pbx-{name}"
    open(tmp[name], "w").write(text)
merged = subprocess.run(["git", "merge-file", "-p", "--union", tmp["ours"], tmp["base"], tmp["theirs"]],
                        capture_output=True, text=True).stdout
for f in tmp.values():
    subprocess.run(["rm", "-f", f])
out = merged.splitlines(keepends=True)

# Lines both sides carried end up twice when one side had them outside the
# conflict hunk: keep the first of each one-line object definition, and of
# each entry within a ( ... ) list.
clean, seen_defs, list_seen = [], set(), None
one_line_def = re.compile(r"^\t\t[0-9A-F]{24} /\*.*\*/ = \{.*\};\n?$")
for line in out:
    if one_line_def.match(line):
        if line in seen_defs:
            continue
        seen_defs.add(line)
    stripped = line.strip()
    if stripped.endswith("= ("):
        list_seen = set()
    elif stripped in (");", ")"):
        list_seen = None
    elif list_seen is not None:
        if line in list_seen:
            continue
        list_seen.add(line)
    clean.append(line)
text = "".join(clean)

defs = re.findall(r"^\t\t([0-9A-F]{24}) /\*.*\*/ = \{", text, flags=re.M)
dupes = sorted({d for d in defs if defs.count(d) > 1})
if dupes:
    sys.exit(f"duplicate object definitions: {dupes}")
open(f"{wt}/{path}", "w").write(text)
print(f"resolved {path}: {len(defs)} objects, no duplicates")
