<#
.SYNOPSIS
    First-boot hardening for dockur/windows guests, driven by selection.json.
.DESCRIPTION
    dockur copies the /oem folder to C:\OEM and runs install.bat at the end of
    unattended setup. install.bat calls this script, which removes the apps,
    capabilities and features marked "remove": true, disables the selected
    services, applies registry tweaks, points the machine at the egress proxy,
    sets the Windows firewall, and runs hash-verified offline installers.

    Runs without prompts. Safe to re-run: items already gone are skipped.
.PARAMETER Config
    Path to selection.json. Defaults to selection.json next to this script.
.PARAMETER DryRun
    Report what would change without changing anything (doubles as an audit).
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\OEM\harden.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$Config = (Join-Path $PSScriptRoot 'selection.json'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# Services this script will never disable, whatever the selection file says.
# RDP must stay up: Guacamole reaches the VM over RDP.
$Protected = @(
    'TermService', 'UmRdpService', 'SessionEnv',          # Remote Desktop
    'WinDefend', 'mpssvc', 'BFE', 'SecurityHealthService', # Defender + firewall
    'EventLog', 'Dnscache', 'Dhcp', 'NlaSvc', 'netprofm',  # core networking/logging
    'CryptSvc', 'RpcSs', 'LSM', 'wuauserv'                 # wuauserv: use the disableWindowsUpdate tweak
)

$LogPath    = Join-Path $PSScriptRoot 'harden.log'
$ReportPath = Join-Path $PSScriptRoot 'harden-report.json'
$Report     = New-Object System.Collections.Generic.List[object]

Start-Transcript -Path $LogPath -Append | Out-Null

function Add-Result([string]$Kind, [string]$Name, [string]$Status, [string]$Detail = '') {
    $Report.Add([pscustomobject]@{ kind = $Kind; name = $Name; status = $Status; detail = $Detail })
    Write-Output ('{0,-11} {1,-10} {2} {3}' -f $Kind, $Status, $Name, $Detail)
}

function Invoke-Change([string]$Kind, [string]$Name, [scriptblock]$Action) {
    if ($DryRun) { Add-Result $Kind $Name 'would' ; return }
    try   { & $Action; Add-Result $Kind $Name 'done' }
    catch { Add-Result $Kind $Name 'failed' $_.Exception.Message }
}

function Set-Reg([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# --- load selection ----------------------------------------------------------

if (-not (Test-Path $Config)) { Write-Error "Selection file not found: $Config"; Stop-Transcript | Out-Null; exit 1 }
$Sel = Get-Content -Raw -Path $Config | ConvertFrom-Json
Write-Output "harden.ps1 starting  config=$Config  dryRun=$DryRun  $(Get-Date -Format s)"

# --- 1. AppX packages (installed for all users + provisioned for new users) ---

$provisioned = Get-AppxProvisionedPackage -Online
foreach ($app in ($Sel.appx | Where-Object { $_.remove })) {
    $prov = $provisioned | Where-Object { $_.DisplayName -eq $app.name }
    $inst = Get-AppxPackage -AllUsers -Name $app.name -ErrorAction SilentlyContinue
    if (-not $prov -and -not $inst) { Add-Result 'appx' $app.name 'absent'; continue }
    Invoke-Change 'appx' $app.name {
        foreach ($p in $prov) { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -AllUsers -ErrorAction Stop | Out-Null }
        foreach ($i in $inst) { Remove-AppxPackage -Package $i.PackageFullName -AllUsers -ErrorAction Stop }
    }
}

# --- 2. Windows capabilities (Features on Demand) -----------------------------

$caps = Get-WindowsCapability -Online
foreach ($cap in ($Sel.capabilities | Where-Object { $_.remove })) {
    # Capability names carry a version suffix, e.g. MathRecognizer~~~~0.0.1.0
    $matches_ = $caps | Where-Object { ($_.Name -like "$($cap.name)~*" -or $_.Name -like "$($cap.name).*~*") -and $_.State -eq 'Installed' }
    if (-not $matches_) { Add-Result 'capability' $cap.name 'absent'; continue }
    foreach ($m in $matches_) {
        Invoke-Change 'capability' $m.Name { Remove-WindowsCapability -Online -Name $m.Name -ErrorAction Stop | Out-Null }
    }
}

# --- 3. Optional features ----------------------------------------------------

foreach ($feat in ($Sel.features | Where-Object { $_.remove })) {
    $f = Get-WindowsOptionalFeature -Online -FeatureName $feat.name -ErrorAction SilentlyContinue
    if (-not $f -or $f.State -ne 'Enabled') { Add-Result 'feature' $feat.name 'absent'; continue }
    Invoke-Change 'feature' $feat.name { Disable-WindowsOptionalFeature -Online -FeatureName $feat.name -NoRestart -ErrorAction Stop | Out-Null }
}

# --- 4. Services -------------------------------------------------------------

foreach ($svc in ($Sel.services | Where-Object { $_.disable })) {
    if ($Protected -contains $svc.name) { Add-Result 'service' $svc.name 'protected' 'skipped: required for RDP, security or networking'; continue }
    $s = Get-Service -Name $svc.name -ErrorAction SilentlyContinue
    if (-not $s) { Add-Result 'service' $svc.name 'absent'; continue }
    if ($s.StartType -eq 'Disabled') { Add-Result 'service' $svc.name 'already'; continue }
    Invoke-Change 'service' $svc.name {
        Stop-Service -Name $svc.name -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svc.name -StartupType Disabled -ErrorAction Stop
    }
}

# --- 5. Registry / policy tweaks ---------------------------------------------

$T = $Sel.tweaks
$tweakActions = [ordered]@{
    telemetryMinimum = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 }
    disableCopilotAndRecall = {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
    }
    disableConsumerFeatures = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 }
    disableAdvertisingId    = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1 }
    disableLLMNR            = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0 }
    disableNetbiosOverTcp   = {
        # 2 = disable NetBIOS over TCP/IP; applied per interface, including ones added later by the same NIC
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' |
            ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name 'NetbiosOptions' -Value 2 }
    }
    requireSmbSigning = {
        Set-SmbClientConfiguration -RequireSecuritySignature $true -Force
        Set-SmbServerConfiguration -RequireSecuritySignature $true -Force
    }
    disableAutorun = {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoAutorun' 1
    }
    disableWDigest = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential' 0 }
    lsaProtection  = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL' 1 }
    defenderPua    = { Set-MpPreference -PUAProtection Enabled -ErrorAction Stop }
    rdpRequireNla  = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 1 }
    rdpDisableDriveRedirect = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' 'fDisableCdm' 1 }
    rdpDisableClipboard     = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' 'fDisableClip' 1 }
    disableWindowsUpdate = {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Set-Service  wuauserv -StartupType Disabled
    }
}
foreach ($key in $tweakActions.Keys) {
    $entry = $T.$key
    if ($null -eq $entry)  { Add-Result 'tweak' $key 'unset'; continue }
    if (-not $entry.enabled) { Add-Result 'tweak' $key 'kept'; continue }
    Invoke-Change 'tweak' $key $tweakActions[$key]
}

# --- 5b. Remote Desktop (always on: Guacamole connects over RDP 3389) ----------

Invoke-Change 'rdp' 'allow connections (fDenyTSConnections=0)' {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0
}
Invoke-Change 'rdp' 'listen on TCP 3389' {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'PortNumber' 3389
}
Invoke-Change 'rdp' 'TermService automatic + running' {
    foreach ($s in 'TermService', 'UmRdpService', 'SessionEnv') {
        Set-Service -Name $s -StartupType Automatic -ErrorAction Stop
    }
    Start-Service -Name TermService -ErrorAction Stop
}
# Users allowed to log on over RDP. make-oem.sh fills this with WIN_USER from .env.
# S-1-5-32-555 = Remote Desktop Users (SID works in any display language)
$rdpGroup = Get-LocalGroup -SID 'S-1-5-32-555'
foreach ($u in @($Sel.remoteDesktop.users)) {
    if (-not $u) { continue }
    if (-not (Get-LocalUser -Name $u -ErrorAction SilentlyContinue)) { Add-Result 'rdp' "user $u" 'missing' 'no such local account'; continue }
    if (Get-LocalGroupMember -Group $rdpGroup -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$u" }) { Add-Result 'rdp' "user $u" 'already'; continue }
    Invoke-Change 'rdp' "add $u to Remote Desktop Users" { Add-LocalGroupMember -Group $rdpGroup -Member $u -ErrorAction Stop }
}

# --- 5c. Edition check and product key -----------------------------------------

$os = Get-CimInstance Win32_OperatingSystem
if ($os.Caption -notmatch 'Pro') {
    Add-Result 'edition' $os.Caption 'warning' 'expected Windows 11 Pro; a Pro key will not activate this edition'
} else {
    Add-Result 'edition' $os.Caption 'ok'
}

$keyFile = Join-Path $PSScriptRoot 'product-key.txt'
if (Test-Path $keyFile) {
    $key = (Get-Content $keyFile -Raw).Trim().ToUpper()
    $masked = 'XXXXX-XXXXX-XXXXX-XXXXX-' + $key.Substring([Math]::Max(0, $key.Length - 5))
    if ($key -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') {
        Add-Result 'license' $masked 'refused' 'product-key.txt is not in XXXXX-XXXXX-XXXXX-XXXXX-XXXXX form'
    } else {
        Invoke-Change 'license' "install key $masked" {
            $svc = Get-CimInstance SoftwareLicensingService
            Invoke-CimMethod -InputObject $svc -MethodName InstallProductKey -Arguments @{ ProductKey = $key } -ErrorAction Stop | Out-Null
            Invoke-CimMethod -InputObject $svc -MethodName RefreshLicenseStatus -ErrorAction Stop | Out-Null
        }
        if ($Report[$Report.Count - 1].status -eq 'done') {
            $script:ActivateAfterProxy = $true  # activation needs the proxy from section 6
            # Windows now holds the key; don't leave a copy in C:\OEM.
            Remove-Item $keyFile -Force -ErrorAction SilentlyContinue
        }
        # On failure the file stays so you can see what was tried and re-run harden.ps1.
    }
} else {
    Add-Result 'license' 'product-key.txt' 'absent' 'no key supplied; Windows runs unactivated (fine for testing)'
}

# --- 6. Egress proxy ---------------------------------------------------------

if ($Sel.proxy.enabled) {
    $px = $Sel.proxy.server; $bypass = $Sel.proxy.bypass
    Invoke-Change 'proxy' "winhttp $px" { netsh.exe winhttp set proxy proxy-server="$px" bypass-list="$bypass" | Out-Null; if ($LASTEXITCODE) { throw "netsh exit $LASTEXITCODE" } }
    Invoke-Change 'proxy' "system (WinINet) $px" {
        # Machine-wide proxy so every user, including ones created later, gets it
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxySettingsPerUser' 0
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyEnable' 1
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyServer' $px 'String'
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyOverride' $bypass 'String'
    }
    Invoke-Change 'proxy' "Edge policy $px" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ProxyMode' 'fixed_servers' 'String'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ProxyServer' $px 'String'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ProxyBypassList' $bypass 'String'
    }
    Invoke-Change 'proxy' 'HTTP(S)_PROXY env (git, node, curl)' {
        [Environment]::SetEnvironmentVariable('HTTP_PROXY',  "http://$px", 'Machine')
        [Environment]::SetEnvironmentVariable('HTTPS_PROXY', "http://$px", 'Machine')
        [Environment]::SetEnvironmentVariable('NO_PROXY',    'localhost,127.0.0.1', 'Machine')
    }
}

# --- 6b. Activation (after the proxy, so Windows can reach the licensing servers) ---

if ($script:ActivateAfterProxy) {
    Invoke-Change 'license' 'activate online via egress proxy' {
        # 55c92734-... is the Windows client licensing application ID
        $prod = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"
        foreach ($p in $prod) { Invoke-CimMethod -InputObject $p -MethodName Activate -ErrorAction Stop | Out-Null }
    }
    # If this fails (proxy allowlist, no network yet), Windows keeps retrying on its own;
    # force it later with:  slmgr /ato   and check with:  slmgr /xpr
}

# --- 7. Windows firewall -----------------------------------------------------

$fw = $Sel.firewall
Invoke-Change 'firewall' "profiles on, inbound=$($fw.defaultInbound)" {
    Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction $fw.defaultInbound -DefaultOutboundAction Allow -ErrorAction Stop
}
Invoke-Change 'firewall' "allow RDP 3389 from $($fw.rdpAllowFrom)" {
    Get-NetFirewallRule -DisplayName 'Lab RDP*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName 'Lab RDP TCP' -Direction Inbound -Protocol TCP -LocalPort 3389 -RemoteAddress $fw.rdpAllowFrom -Action Allow | Out-Null
    New-NetFirewallRule -DisplayName 'Lab RDP UDP' -Direction Inbound -Protocol UDP -LocalPort 3389 -RemoteAddress $fw.rdpAllowFrom -Action Allow | Out-Null
    if ($fw.rdpAllowFrom -ne 'Any') {
        # Built-in rules would still allow RDP from anywhere; switch them off. (English group name.)
        Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    }
}
foreach ($group in 'File and Printer Sharing', 'Network Discovery') {
    Invoke-Change 'firewall' "disable group '$group'" {
        Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    }
}

# --- 8. Offline installers (hash-verified) -----------------------------------

$sumsFile = Join-Path $PSScriptRoot 'installers\SHA256SUMS'
$sums = @{}
if (Test-Path $sumsFile) {
    foreach ($line in Get-Content $sumsFile) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') { $sums[$Matches[2].Trim()] = $Matches[1].ToLower() }
    }
}
foreach ($inst in ($Sel.installers | Where-Object { $_.install })) {
    $path = Join-Path $PSScriptRoot $inst.file
    $leaf = Split-Path $inst.file -Leaf
    if (-not (Test-Path $path))  { Add-Result 'installer' $leaf 'missing' "put it in oem\installers or run fetch-installers.sh"; continue }
    if (-not $sums.ContainsKey($leaf)) { Add-Result 'installer' $leaf 'refused' 'no SHA256SUMS entry'; continue }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower()
    if ($actual -ne $sums[$leaf]) { Add-Result 'installer' $leaf 'refused' "hash mismatch $actual"; continue }
    Invoke-Change 'installer' $leaf {
        $p = if ($path -like '*.msi') {
            Start-Process msiexec.exe -ArgumentList "/i `"$path`" $($inst.args)" -Wait -PassThru
        } else {
            Start-Process $path -ArgumentList $inst.args -Wait -PassThru
        }
        if ($p.ExitCode -notin 0, 3010) { throw "exit code $($p.ExitCode)" }
    }
}

# --- report ------------------------------------------------------------------

$Report | ConvertTo-Json -Depth 3 | Set-Content -Path $ReportPath -Encoding UTF8
$failed = @($Report | Where-Object { $_.status -in 'failed', 'refused' }).Count
Write-Output "harden.ps1 finished  changes=$(@($Report | Where-Object status -eq 'done').Count)  failed/refused=$failed  report=$ReportPath"
Write-Output 'Some removals (features, capabilities, LSA protection) take effect after the next restart.'
Stop-Transcript | Out-Null
exit 0
