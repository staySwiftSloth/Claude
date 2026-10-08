#!/usr/bin/env python3
"""Regenerate CATALOG.md from selections/default.json:  python3 gen-catalog.py"""
import json
d = json.load(open("selections/default.json"))
out = ["# Removal catalog",
       "",
       "Generated from `selections/default.json` by `gen-catalog.py`; edit the JSON, not this file.",
       "**Default** is what happens if you change nothing. Flip `remove` / `disable` / `enabled` / `install` in your copy of the JSON.",
       ""]
def table(title, key, flag, yes, no, note=""):
    out.extend([f"## {title}", ""] + ([note, ""] if note else []) +
               ["| Item | Default | Why |", "|---|---|---|"])
    for i in d[key]:
        out.append(f"| `{i['name']}` | {yes if i[flag] else no} | {i['why']} |")
    out.append("")
table("Store apps (AppX)", "appx", "remove", "**remove**", "keep",
      "Removed for all existing users and de-provisioned so new profiles don't get them back. Edge isn't an AppX package and can't be removed this way; it's also what the proxy policy configures.")
table("Windows capabilities (Features on Demand)", "capabilities", "remove", "**remove**", "keep",
      "Matched by prefix, so `Language.Speech` covers every installed speech language.")
table("Optional features", "features", "remove", "**remove**", "keep",
      "Disabled with the payload left on disk, so you can switch one back on without a source ISO.")
table("Services", "services", "disable", "**disable**", "leave",
      "These are never touched, whatever the file says: " + ", ".join(
        "`%s`" % s for s in ["TermService","UmRdpService","SessionEnv","WinDefend","mpssvc","BFE",
                             "SecurityHealthService","EventLog","Dnscache","Dhcp","NlaSvc","netprofm",
                             "CryptSvc","RpcSs","LSM","wuauserv"]) +
      ". RDP has to stay up because Guacamole connects over it. Windows Update has its own switch under tweaks.")
out.extend(["## Policy and registry tweaks", "", "| Tweak | Default | What it does |", "|---|---|---|"])
for k, v in d["tweaks"].items():
    out.append(f"| `{k}` | {'**on**' if v['enabled'] else 'off'} | {v['why']} |")
out.extend(["", "## Offline installers", "",
            "Placed in `oem/installers/` on the host (`fetch-installers.sh`), copied into the VM, and run only if their SHA-256 is in `SHA256SUMS`.", "",
            "| File | Default | Silent args | What |", "|---|---|---|---|"])
for i in d["installers"]:
    out.append(f"| `{i['file']}` | {'**install**' if i['install'] else 'skip'} | `{i['args']}` | {i['why']} |")
out.append("")
open("CATALOG.md", "w").write("\n".join(out))
print("wrote CATALOG.md")
