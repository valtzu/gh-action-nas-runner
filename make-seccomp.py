#!/usr/bin/env python3
"""Write seccomp.json: Docker's default seccomp profile, except that
fchmodat2 fails with ENOSYS.

QNAP's 5.10 kernel answers fchmodat2 (syscall 452, new in Linux 6.6) with
EFAULT instead of ENOSYS. glibc 2.39+ changes a symlink's mode with it and
only falls back to its older path on ENOSYS, so inside the container GNU tar
fails on every symlink it extracts ("Cannot change mode to rwxr-xr-x: Bad
address"). Answering ENOSYS before the kernel sees the call brings the
fallback back; on a symlink that ends in EOPNOTSUPP, which tar ignores.

The base is the profile Container Station's engine (Docker 27.1.2) ships, so
the sandbox is otherwise the one the containers would get anyway.
"""
import json
import os
import urllib.request

MOBY_REF = "v27.1.2"
URL = f"https://raw.githubusercontent.com/moby/moby/{MOBY_REF}/profiles/seccomp/default.json"
ENOSYS = 38

with urllib.request.urlopen(URL) as r:
    profile = json.load(r)

rules = [r for r in profile["syscalls"] if "fchmodat2" in r["names"]]
# Only an unconditional allow is safe to take it out of.
assert rules and all(r["action"] == "SCMP_ACT_ALLOW" and r.keys() == {"names", "action"} for r in rules), rules
for r in rules:
    r["names"].remove("fchmodat2")
profile["syscalls"].append({"names": ["fchmodat2"], "action": "SCMP_ACT_ERRNO", "errnoRet": ENOSYS})

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "seccomp.json")
with open(out, "w") as f:
    json.dump(profile, f, indent="\t")
    f.write("\n")
