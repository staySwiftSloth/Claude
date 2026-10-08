#!/usr/bin/env bash
# Build the per-VM OEM folder that dockur copies to C:\OEM on first boot.
#
#   ./make-oem.sh app-a 172.31.11.2     # VM name, that VM's egress proxy IP
#
# Uses selections/<vm>.json if it exists, otherwise selections/default.json,
# and writes the VM's proxy address into the copy. Output: build/oem-<vm>/
set -euo pipefail
cd "$(dirname "$0")"

vm="${1:?usage: make-oem.sh <vm-name> <egress-ip>}"
egress_ip="${2:?usage: make-oem.sh <vm-name> <egress-ip>}"

sel="selections/${vm}.json"
[[ -f "$sel" ]] || sel="selections/default.json"

out="build/oem-${vm}"
rm -rf "$out"
mkdir -p "$out/installers"
cp oem/install.bat oem/harden.ps1 "$out/"
# Copy only installers this VM's selection asks for, plus the checksum list
python3 - "$sel" "$out/selection.json" "$egress_ip" <<'PY'
import json, sys, shutil, os
src, dst, ip = sys.argv[1:4]
sel = json.load(open(src))
sel["proxy"]["server"] = f"{ip}:3128"
json.dump(sel, open(dst, "w"), indent=2)
for i in sel.get("installers", []):
    if i.get("install"):
        p = os.path.join("oem", i["file"])
        if os.path.exists(p):
            shutil.copy(p, os.path.join(os.path.dirname(dst), i["file"]))
        else:
            print(f"warning: {p} not found; the VM will report it as missing", file=sys.stderr)
PY
[[ -f oem/installers/SHA256SUMS ]] && cp oem/installers/SHA256SUMS "$out/installers/"

# install.bat must have CRLF line endings for cmd.exe
sed -i 's/\r\?$/\r/' "$out/install.bat"

echo "built $out from $sel (proxy ${egress_ip}:3128)"
