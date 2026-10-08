# Removal catalog

Generated from `selections/default.json` by `gen-catalog.py`; edit the JSON, not this file.
**Default** is what happens if you change nothing. Flip `remove` / `disable` / `enabled` / `install` in your copy of the JSON.

## Store apps (AppX)

Removed for all existing users and de-provisioned so new profiles don't get them back. Edge isn't an AppX package and can't be removed this way; it's also what the proxy policy configures.

| Item | Default | Why |
|---|---|---|
| `Microsoft.BingNews` | **remove** | News feed; network chatter |
| `Microsoft.BingWeather` | **remove** | Weather feed |
| `Microsoft.BingSearch` | **remove** | Web search in Start |
| `Microsoft.Copilot` | **remove** | Cloud AI assistant; sends content off-box |
| `Microsoft.549981C3F5F10` | **remove** | Cortana |
| `Microsoft.GamingApp` | **remove** | Xbox app |
| `Microsoft.Xbox.TCUI` | **remove** | Xbox UI component |
| `Microsoft.XboxGameOverlay` | **remove** | Game Bar |
| `Microsoft.XboxGamingOverlay` | **remove** | Game Bar |
| `Microsoft.XboxIdentityProvider` | **remove** | Xbox sign-in |
| `Microsoft.XboxSpeechToTextOverlay` | **remove** | Xbox speech overlay |
| `Microsoft.GetHelp` | **remove** | Support app |
| `Microsoft.Getstarted` | **remove** | Tips |
| `Microsoft.MicrosoftOfficeHub` | **remove** | Office/365 promo hub |
| `Microsoft.MicrosoftSolitaireCollection` | **remove** | Game |
| `Microsoft.MicrosoftStickyNotes` | **remove** | Cloud-synced notes |
| `Microsoft.OutlookForWindows` | **remove** | New Outlook; cloud mail |
| `microsoft.windowscommunicationsapps` | **remove** | Legacy Mail and Calendar |
| `Microsoft.People` | **remove** | Contacts |
| `Microsoft.PowerAutomateDesktop` | **remove** | Automation runtime; extra attack surface |
| `Microsoft.Todos` | **remove** | Cloud to-do |
| `Microsoft.WindowsAlarms` | **remove** | Clock app |
| `Microsoft.WindowsCamera` | **remove** | No camera in the VM |
| `Microsoft.WindowsFeedbackHub` | **remove** | Telemetry upload UI |
| `Microsoft.WindowsMaps` | **remove** | Maps |
| `Microsoft.WindowsSoundRecorder` | **remove** | Microphone app |
| `Microsoft.YourPhone` | **remove** | Phone Link; device pairing |
| `Microsoft.ZuneMusic` | **remove** | Media Player app |
| `Microsoft.ZuneVideo` | **remove** | Films and TV |
| `Clipchamp.Clipchamp` | **remove** | Video editor |
| `MicrosoftCorporationII.QuickAssist` | **remove** | Remote-help tool abused in support scams |
| `MicrosoftCorporationII.MicrosoftFamily` | **remove** | Family Safety |
| `MSTeams` | **remove** | Teams (personal) |
| `MicrosoftTeams` | **remove** | Teams (older package name) |
| `Microsoft.Windows.DevHome` | **remove** | Dev Home |
| `Microsoft.StorePurchaseApp` | **remove** | Store purchase flow |
| `Microsoft.Windows.Photos` | keep | Default image viewer; remove if apps never open images |
| `Microsoft.Paint` | keep | Paint |
| `Microsoft.ScreenSketch` | keep | Snipping Tool; handy for screenshots during support |
| `Microsoft.WindowsCalculator` | keep | Calculator |
| `Microsoft.WindowsNotepad` | keep | Notepad; useful for editing config |
| `Microsoft.WindowsTerminal` | keep | Terminal |
| `Microsoft.WindowsStore` | keep | Store; hard to restore once removed. Remove only if you install everything from C:\OEM |
| `Microsoft.DesktopAppInstaller` | keep | winget; keep unless you install only from C:\OEM |
| `Microsoft.SecHealthUI` | keep | Windows Security UI; removing it hides Defender status |

## Windows capabilities (Features on Demand)

Matched by prefix, so `Language.Speech` covers every installed speech language.

| Item | Default | Why |
|---|---|---|
| `Browser.InternetExplorer` | **remove** | IE mode engine (older builds) |
| `MathRecognizer` | **remove** | Handwriting maths input |
| `Microsoft.Windows.WordPad` | **remove** | WordPad; old RTF parser (gone in 24H2) |
| `App.StepsRecorder` | **remove** | Steps Recorder; captures screens |
| `App.Support.QuickAssist` | **remove** | Quick Assist (capability form) |
| `Media.WindowsMediaPlayer` | **remove** | Legacy Windows Media Player |
| `Hello.Face` | **remove** | Windows Hello face; no camera |
| `Print.Fax.Scan` | **remove** | Fax and Scan |
| `XPS.Viewer` | **remove** | XPS viewer |
| `Microsoft.Wallpapers.Extended` | **remove** | Extra wallpapers; disk space |
| `Microsoft.Windows.PowerShell.ISE` | **remove** | PowerShell ISE; use Terminal or VS Code |
| `Language.Speech` | **remove** | Speech recognition |
| `Language.TextToSpeech` | keep | Narrator voices; keep for accessibility |
| `Language.Handwriting` | **remove** | Pen input |
| `OneCoreUAP.OneSync` | **remove** | Sync engine for Mail and People |
| `WMIC` | **remove** | Deprecated WMI CLI; common in living-off-the-land attacks |
| `Print.Management.Console` | **remove** | Print management MMC |
| `OpenSSH.Client` | keep | ssh/scp client |
| `OpenSSH.Server` | **remove** | Inbound SSH; another remote door |

## Optional features

Disabled with the payload left on disk, so you can switch one back on without a source ISO.

| Item | Default | Why |
|---|---|---|
| `MicrosoftWindowsPowerShellV2Root` | **remove** | PowerShell 2.0; bypasses script logging and AMSI |
| `MicrosoftWindowsPowerShellV2` | **remove** | PowerShell 2.0 engine |
| `SMB1Protocol` | **remove** | SMBv1; EternalBlue-class bugs |
| `Internet-Explorer-Optional-amd64` | **remove** | IE11 (older builds) |
| `TelnetClient` | **remove** | Cleartext remote client |
| `TFTP` | **remove** | Unauthenticated file transfer |
| `WorkFolders-Client` | **remove** | Work Folders sync |
| `Printing-XPSServices-Features` | **remove** | XPS print path |
| `MediaPlayback` | **remove** | Legacy media stack |
| `WindowsMediaPlayer` | **remove** | Legacy WMP |
| `Recall` | **remove** | Recall screen-history store (Copilot+ builds) |
| `Microsoft-Windows-Subsystem-Linux` | **remove** | WSL; second OS inside the VM |
| `VirtualMachinePlatform` | **remove** | Nested virtualisation; the host already isolates |
| `Microsoft-Hyper-V-All` | **remove** | Hyper-V; nested virtualisation |
| `Containers-DisposableClientVM` | **remove** | Windows Sandbox; nested VM |
| `Printing-PrintToPDFServices-Features` | keep | Print to PDF; keep if apps export by printing |

## Services

These are never touched, whatever the file says: `TermService`, `UmRdpService`, `SessionEnv`, `WinDefend`, `mpssvc`, `BFE`, `SecurityHealthService`, `EventLog`, `Dnscache`, `Dhcp`, `NlaSvc`, `netprofm`, `CryptSvc`, `RpcSs`, `LSM`, `wuauserv`. RDP has to stay up because Guacamole connects over it. Windows Update has its own switch under tweaks.

| Item | Default | Why |
|---|---|---|
| `DiagTrack` | **disable** | Connected User Experiences and Telemetry |
| `dmwappushservice` | **disable** | WAP push routing for telemetry |
| `RemoteRegistry` | **disable** | Remote registry edits |
| `WinRM` | **disable** | PowerShell remoting; lateral movement. Keep only if you manage VMs with Ansible/PSRemoting |
| `SSDPSrv` | **disable** | SSDP discovery |
| `upnphost` | **disable** | UPnP device host |
| `lmhosts` | **disable** | NetBIOS over TCP/IP helper |
| `RemoteAccess` | **disable** | Routing and Remote Access |
| `SharedAccess` | **disable** | Internet Connection Sharing; would turn the VM into a router |
| `icssvc` | **disable** | Mobile hotspot |
| `lfsvc` | **disable** | Geolocation |
| `MapsBroker` | **disable** | Offline maps downloads |
| `RetailDemo` | **disable** | Retail demo mode |
| `Fax` | **disable** | Fax |
| `PhoneSvc` | **disable** | Telephony state |
| `WerSvc` | **disable** | Error reporting uploads; set false if you want crash dumps |
| `wisvc` | **disable** | Windows Insider |
| `WMPNetworkSvc` | **disable** | Media sharing |
| `XblAuthManager` | **disable** | Xbox Live auth |
| `XblGameSave` | **disable** | Xbox cloud saves |
| `XboxNetApiSvc` | **disable** | Xbox networking |
| `XboxGipSvc` | **disable** | Xbox accessories |
| `SysMain` | **disable** | Superfetch; wasted I/O on a virtual disk |
| `Spooler` | leave | Print spooler (PrintNightmare). Set true if nothing prints, Print to PDF included |
| `WSearch` | leave | Search indexer; set true to save CPU/disk if Start search isn't used |

## Policy and registry tweaks

| Tweak | Default | What it does |
|---|---|---|
| `telemetryMinimum` | **on** | AllowTelemetry policy at the lowest level the edition accepts (0 = Enterprise/Education only; Pro floors at 1) |
| `disableCopilotAndRecall` | **on** | Policies that switch off Windows Copilot and Recall snapshots |
| `disableConsumerFeatures` | **on** | Stops auto-installed suggested apps (honoured fully on Enterprise/Education) |
| `disableAdvertisingId` | **on** | Per-user ad tracking ID |
| `disableLLMNR` | **on** | Multicast name resolution; poisoning target (Responder) |
| `disableNetbiosOverTcp` | **on** | NetBIOS name service on every adapter |
| `requireSmbSigning` | **on** | Blocks SMB relay |
| `disableAutorun` | **on** | No autorun from any drive, including the Z: shared folder |
| `disableWDigest` | **on** | No cleartext credentials in LSASS memory |
| `lsaProtection` | **on** | Runs LSASS as a protected process (RunAsPPL) |
| `defenderPua` | **on** | Defender blocks potentially unwanted apps |
| `rdpRequireNla` | **on** | RDP needs Network Level Authentication (Guacamole supports it) |
| `rdpDisableDriveRedirect` | **on** | Clients can't map their drives into the VM |
| `rdpDisableClipboard` | off | Blocks copy/paste through Guacamole. Set true for the strictest isolation |
| `disableWindowsUpdate` | off | Leave false and allowlist the update domains in egress unless you rebuild VMs often from fresh images |

## Offline installers

Placed in `oem/installers/` on the host (`fetch-installers.sh`), copied into the VM, and run only if their SHA-256 is in `SHA256SUMS`.

| File | Default | Silent args | What |
|---|---|---|---|
| `installers/vc_redist.x64.exe` | **install** | `/install /quiet /norestart` | Visual C++ 2015-2022 runtime; most desktop apps need it |
| `installers/PowerShell-x64.msi` | skip | `/qn /norestart ADD_PATH=1 ENABLE_PSREMOTING=0` | PowerShell 7 |
| `installers/Git-64-bit.exe` | skip | `/VERYSILENT /NORESTART /NOCANCEL /SP-` | Git for Windows |
| `installers/node-x64.msi` | skip | `/qn /norestart` | Node.js LTS |
| `installers/7z-x64.exe` | skip | `/S` | 7-Zip |
