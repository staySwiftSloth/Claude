# Windows lab: dockur VMs, Guacamole, per-app networks, egress firewall

Each app runs in its own Windows VM ([dockur/windows](https://github.com/dockur/windows): Windows under QEMU/KVM inside a Linux container). The VMs are stripped down on first boot, from a list you choose. You reach them through Guacamole in a browser, and they reach the internet only through a per-app allowlist.

```
browser ─► guacamole :8080 ─► guacd ──RDP──► app-a   (app-a-net, internal)
                                  └──RDP──► app-b   (app-b-net, internal)
app-a / app-b ─► egress :3128 ─► internet       per-subnet allowlist, private ranges blocked
Claude ─► mcp-firewall :8081 ─► edge-mcp (mcp-net, internal) ─► egress ─► internet
```

## Where each control sits

| Control | Enforced by | Stops |
|---|---|---|
| App ↔ app isolation | Separate `internal: true` Docker networks | VM A reaching VM B at all |
| Internet access | `egress` (squid), per-source-subnet allowlist | Anything not on that app's list, plus all private, link-local and metadata addresses |
| Proxy use inside Windows | `harden.ps1` (WinHTTP, WinINet, Edge policy, `HTTP(S)_PROXY`) | Apps silently failing. With no route out, the proxy is the only path anyway |
| Inbound to each VM | Windows firewall: block by default, RDP only | Other listeners being reachable from guacd's segment |
| Who can open a desktop | Guacamole users and connection permissions | Direct RDP: no VM port is published on the host |
| Claude's browser tools | `mcp-firewall` auth map (tokens, tools, URLs) | Unapproved tools and URLs from MCP clients |

The MCP firewall is an MCP (HTTP/JSON-RPC) gateway. It decides what Claude's browser tools may do. It does **not** route or filter the VMs' packets; the internal networks and the egress proxy do that.

## Choosing what gets removed

`selections/default.json` is the selectable list, and **[CATALOG.md](CATALOG.md)** shows it as tables: 45 Store apps, 19 capabilities, 16 optional features, 25 services, 15 policy tweaks and 5 offline installers. Each entry has a default and a reason.

- Flip `remove`, `disable`, `enabled` or `install` to change an entry.
- For a per-VM profile, copy the file to `selections/app-a.json`. `make-oem.sh` uses it automatically.
- After editing, run `python3 gen-catalog.py` to refresh CATALOG.md.

RDP, Defender, the firewall and core networking services are on a protected list in `harden.ps1` and can't be disabled through the JSON. That protection exists because disabling RDP would lock Guacamole out.

### How "before installation" works

dockur copies the VM's OEM folder to `C:\OEM` and runs `install.bat` in the last step of unattended setup. So the removals happen before anyone logs in. Store apps are also de-provisioned, so new user profiles don't get them back.

## Windows 11 Pro and product keys

Every VM installs **Windows 11 Pro** (`VERSION: "11"` in `docker-compose.yml`, which is dockur's Pro edition). Don't switch to `11l` or `11e`: those are LTSC and Enterprise editions, and a Pro key won't activate them. Your ISO must be a standard Windows 11 multi-edition ISO, which includes Pro.

To add keys:

```bash
cp keys/product-keys.env.example keys/product-keys.env
nano keys/product-keys.env
```

```
DEFAULT=
app-a=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
app-b=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
```

- **Lookup order:** a VM uses its own line, then `DEFAULT`, and runs unactivated if neither is set. Running unactivated is fine for testing.
- **One key per VM:** a retail key activates one machine.
- **Getting it in:** `make-oem.sh` checks the format and writes the key into that VM's OEM folder only (`build/oem-<vm>/product-key.txt`, mode 600). Both `keys/product-keys.env` and `build/` are git-ignored.
- **On first boot:** `harden.ps1` installs the key, then activates once the egress proxy is set. The proxy allows Microsoft's licensing hosts for every VM (`egress/allow/activation.txt`). It then deletes the key from `C:\OEM`.
- **Changing a key later:** run `slmgr /ipk <key>` then `slmgr /ato` inside the VM. Use `slmgr /xpr` to check status. Activation results are in `harden-report.json`, with the key masked to its last 5 characters.
- **Clean up after first boot:** delete `build/` once every VM has finished installing. dockur has copied what it needs by then, and this removes the last copy of each key outside Windows.

## Remote Desktop

Guacamole connects to each VM over **RDP on TCP/UDP 3389**, using NLA. Port 3389 isn't published on the host, so the only way in is through Guacamole. `harden.ps1` always sets RDP up, whatever the selection file says:

- allows connections (`fDenyTSConnections=0`) and confirms the listener is on port 3389
- sets `TermService`, `UmRdpService` and `SessionEnv` to Automatic and starts the RDP service
- adds `WIN_USER` (from `.env`) to Remote Desktop Users. You can add other accounts in `remoteDesktop.users` in the selection file
- opens 3389 in the Windows firewall (`Lab RDP TCP/UDP` rules) while everything else inbound stays blocked
- requires NLA (`rdpRequireNla`) and blocks drive redirection. Clipboard is allowed by default; set `rdpDisableClipboard` to true to block it

The connections are in `guacamole/02-connections.sql` (`hostname app-a`, `port 3389`, `security nla`).

## Installation files

| File | Runs on | Purpose |
|---|---|---|
| `oem/install.bat` | VM, first boot | Entry point dockur calls; runs harden.ps1 and always exits 0 so setup can't stall |
| `oem/harden.ps1` | VM | Reads selection.json and applies it. Unattended, safe to re-run, `-DryRun` shows what would change |
| `oem/installers/` | VM | Offline installers. The VMs can't download them, since their only exit is the allowlist |
| `oem/installers/SHA256SUMS` | VM | harden.ps1 runs only installers listed here with a matching hash |
| `fetch-installers.sh` | host | Downloads pinned installers and writes SHA256SUMS. Only VC++ is filled in; add pinned URLs for the rest |
| `make-oem.sh <vm> <egress-ip>` | host | Builds `build/oem-<vm>/`: scripts, that VM's selection with its proxy IP and RDP user, its Pro key, and only the installers it asks for |
| `keys/product-keys.env` | host | Your Windows 11 Pro keys, one per VM (copy from `.example`; git-ignored) |
| `setup.sh` | host | Checks KVM, `.env`, ISO and auth map; generates the Guacamole schema; builds every OEM folder |

Results inside each VM: `C:\OEM\harden.log` (full transcript) and `C:\OEM\harden-report.json` (one line per item: `done`, `absent`, `already`, `kept`, `protected`, `failed`, `refused`, `missing`).

## First run

```bash
cp .env.example .env               # set WIN_USER, WIN_PASSWORD, DB passwords
cp keys/product-keys.env.example keys/product-keys.env   # optional: Windows 11 Pro keys
mkdir -p isos                       # save the Windows 11 ISO from Microsoft as isos/windows.iso
./fetch-installers.sh               # optional: offline installers + hashes
./setup.sh                          # checks, Guacamole schema, OEM folders
docker compose up -d
docker compose logs -f app-a        # first install takes roughly 10–30 min per VM
```

Then open `http://localhost:8080`, log in as `guacadmin` / `guacadmin`, and **change that password straight away**. Open `app-a` and enter `WIN_USER` / `WIN_PASSWORD` when prompted. No credentials are stored in Guacamole.

Why you supply the ISO: dockur normally downloads Windows on first start, but these VMs sit on internal networks with no route out. Using a local `/custom.iso` keeps that true from the first boot. If you would rather let dockur download it, put the VM on a network with internet access for the first start only, then move it back.

## Adding an app VM

1. In `docker-compose.yml`, copy the `app-b` service and an `app-b-net` network block, using the next free subnet (for example `172.31.13.0/24`).
2. Add `app-c-net` with fixed IPs to `guacd` (`.3`) and `egress` (`.2`).
3. In `egress/squid.conf`, add `acl seg_app_c src …`, an allowlist ACL and the matching `http_access` lines. Create `egress/allow/app-c.txt`.
4. Add `[app-c]=172.31.13.2` to `VMS` in `setup.sh`, then run `./setup.sh`.
5. Add an `app-c` block to `guacamole/02-connections.sql`. That file is only read when the DB is first created, so on an existing install add the connection in the Guacamole admin UI instead.
6. Run `docker compose up -d app-c`, then `docker compose restart egress guacd`.

## Checking it

```bash
# Proxy verdicts per VM (source IP shows which segment)
docker compose exec egress tail -f /var/log/squid/access.log

# What harden.ps1 did, from inside a VM (PowerShell)
Get-Content C:\OEM\harden-report.json | ConvertFrom-Json | Group-Object status
powershell -ExecutionPolicy Bypass -File C:\OEM\harden.ps1 -DryRun     # audit: lists anything that came back
```

Test isolation from inside app-a:

- `Test-NetConnection app-b -Port 3389` should fail, because there's no route between the networks.
- `Invoke-WebRequest https://example.com` should succeed through the proxy.
- `Invoke-WebRequest https://github.com` should get a 403 from squid unless it's on app-a's list.

## Known limits

- **Edge for Linux and dockur are amd64-only**, and dockur needs `/dev/kvm`. A cloud VM needs nested virtualisation enabled.
- **Telemetry floor:** `AllowTelemetry=0` and `DisableWindowsConsumerFeatures` are fully honoured only on Enterprise and Education. On Windows 11 Pro the lowest level is "required" diagnostic data, and some suggested-app suppression is ignored.
- **`rdpAllowFrom`:** dockur NATs port 3389 into the VM, so Windows may see the container's gateway as the source rather than guacd. Leave it `Any` (the network itself limits who can connect) unless you've confirmed which address shows up.
- **Firewall group names** (`Remote Desktop`, `File and Printer Sharing`) are matched in English. On another display language those steps quietly do nothing, so check the report.
- **Not run on Windows here.** The JSON, compose file and OEM build were checked on Linux. `harden.ps1` was reviewed but not executed. Run it with `-DryRun` on your first VM and read the report before relying on it.
