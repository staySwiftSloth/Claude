#!/usr/bin/env bash
# Build the per-VM OEM folder that dockur copies to C:\OEM on first boot.
#
#   ./make-oem.sh app-a 172.31.11.2     # VM name, that VM's egress proxy IP
#
# Uses selections/<vm>.json if it exists, otherwise selections/default.json.
# Writes the VM's proxy address and RDP user (WIN_USER from .env) into the copy,
# and its Windows 11 Pro key from keys/product-keys.env if one is set.
# Output: build/oem-<vm>/
set -euo pipefail
cd "$(dirname "$0")"

vm="${1:?usage: make-oem.sh <vm-name> <egress-ip>}"
egress_ip="${2:?usage: make-oem.sh <vm-name> <egress-ip>}"

win_user=""
if [[ -f .env ]]; then win_user="$(sed -n 's/^WIN_USER=//p' .env | tail -1)"; fi

sel="selections/${vm}.json"
[[ -f "$sel" ]] || sel="selections/default.json"

out="build/oem-${vm}"
rm -rf "$out"
mkdir -p "$out/installers"
chmod 700 "$out"
cp oem/install.bat oem/harden.ps1 "$out/"

# Selection: set proxy + RDP user; copy only the installers this VM asks for
python3 - "$sel" "$out/selection.json" "$egress_ip" "$win_user" <<'PY'
import json, sys, shutil, os
src, dst, ip, user = sys.argv[1:5]
sel = json.load(open(src))
sel["proxy"]["server"] = f"{ip}:3128"
rd = sel.setdefault("remoteDesktop", {"users": []})
if user and user not in rd["users"]:
    rd["users"].append(user)
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

# Product key: this VM's line, else DEFAULT, else none (VM runs unactivated)
key_note="no product key"
if [[ -f keys/product-keys.env ]]; then
  key="$(sed -n "s/^${vm}=//p" keys/product-keys.env | tail -1 | tr -d '[:space:]')"
  [[ -n "$key" ]] || key="$(sed -n 's/^DEFAULT=//p' keys/product-keys.env | tail -1 | tr -d '[:space:]')"
  if [[ -n "$key" ]]; then
    key="${key^^}"
    [[ "$key" =~ ^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$ ]] || { echo "✗ key for $vm is not XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" >&2; exit 1; }
    ( umask 077; printf '%s' "$key" > "$out/product-key.txt" )
    key_note="Pro key ...${key: -5}"
  fi
fi

# install.bat must have CRLF line endings for cmd.exe
sed -i 's/\r\?$/\r/' "$out/install.bat"

echo "built $out from $sel (proxy ${egress_ip}:3128, rdp user ${win_user:-none}, ${key_note})"
