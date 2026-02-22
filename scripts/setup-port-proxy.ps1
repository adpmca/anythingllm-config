# setup-port-proxy.ps1 — Forward Docker host gateway port to WSL2
#
# Problem: Docker containers use host.docker.internal -> 192.168.65.254 to reach
# the Windows host. copilot-api runs in WSL2 and is only exposed to Windows at
# 127.0.0.1:4141. Traffic to 192.168.65.254:4141 never reaches it.
#
# Fix: Windows port proxy that forwards 0.0.0.0:4141 -> 127.0.0.1:4141.
#      WSL2 automatically forwards copilot-api's port to Windows localhost,
#      so this bridges Docker containers -> Windows host -> WSL2.
#
# Run once as Administrator:
#   PowerShell -ExecutionPolicy Bypass -File scripts\setup-port-proxy.ps1
#
# The scheduled task created here re-applies the proxy rule at every logon
# (netsh portproxy rules survive reboot but can be lost after WSL restarts).

param(
    [int]$Port = 4141
)

$ErrorActionPreference = "Stop"

function Log { param([string]$msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" }

# ── 1. Check admin privileges ─────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator. Re-launching with elevation..."
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ── 2. Get WSL2 VM IP ─────────────────────────────────────────────────────────
# WSL2 runs in a separate VM. We must proxy to its actual Linux IP, not 127.0.0.1
# (which would create a loop since netsh itself listens there).
Log "Detecting WSL2 IP..."
$wslIp = (wsl -u ajay bash -c "ip addr show eth0 | grep 'inet ' | awk '{print `$2}' | cut -d/ -f1").Trim() -replace '^inet\s+', ''
if (-not $wslIp) { Write-Error "Could not detect WSL2 IP. Is WSL running?" }
Log "WSL2 IP: $wslIp"

# ── 3. Add port proxy rule ─────────────────────────────────────────────────────
Log "Adding port proxy: 0.0.0.0:$Port -> $wslIp`:$Port"
netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 2>$null | Out-Null
netsh interface portproxy add v4tov4 `
    listenaddress=0.0.0.0 `
    listenport=$Port `
    connectaddress=$wslIp `
    connectport=$Port

Log "Current port proxy rules:"
netsh interface portproxy show v4tov4

# ── 3. Open Windows Firewall for the port ─────────────────────────────────────
$ruleName = "copilot-api-$Port"
Log "Configuring firewall rule '$ruleName'..."
Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
New-NetFirewallRule `
    -DisplayName $ruleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $Port `
    -Description "Allow Docker containers to reach copilot-api in WSL2 via port proxy" | Out-Null

# ── 4. Register scheduled task to re-apply on logon ───────────────────────────
$taskName = "copilot-api-port-proxy"
$scriptPath = $PSCommandPath
Log "Registering startup task '$taskName'..."

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId "BUILTIN\Administrators" -RunLevel Highest

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Re-apply netsh port proxy so Docker containers can reach copilot-api in WSL2" | Out-Null

Log "Scheduled task registered. Port proxy will be re-applied on every logon."
Log ""
Log "Done. Docker containers can now reach copilot-api at http://host.docker.internal:$Port/"
Log "(Proxying Windows 0.0.0.0:$Port -> WSL2 $wslIp`:$Port)"
