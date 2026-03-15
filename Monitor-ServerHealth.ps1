#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Server Health Monitor
.DESCRIPTION
    Collects key health metrics from a Windows Server and outputs
    a color-coded console report plus an optional HTML report file.
.PARAMETER HtmlReport
    Path to save an HTML report. If omitted, only console output is shown.
.PARAMETER CpuWarnPct
    CPU usage % threshold for a WARNING (default 75).
.PARAMETER CpuCritPct
    CPU usage % threshold for CRITICAL (default 90).
.PARAMETER MemWarnPct
    Memory usage % threshold for WARNING (default 80).
.PARAMETER MemCritPct
    Memory usage % threshold for CRITICAL (default 95).
.PARAMETER DiskWarnPct
    Disk usage % threshold for WARNING (default 80).
.PARAMETER DiskCritPct
    Disk usage % threshold for CRITICAL (default 95).
.EXAMPLE
    .\Monitor-ServerHealth.ps1
.EXAMPLE
    .\Monitor-ServerHealth.ps1 -HtmlReport "C:\Reports\health.html"
.EXAMPLE
    .\Monitor-ServerHealth.ps1 -CpuWarnPct 60 -CpuCritPct 85 -HtmlReport ".\report.html"
#>

[CmdletBinding()]
param(
    [string]$HtmlReport       = "",
    [int]$CpuWarnPct          = 75,
    [int]$CpuCritPct          = 90,
    [int]$MemWarnPct          = 80,
    [int]$MemCritPct          = 95,
    [int]$DiskWarnPct         = 80,
    [int]$DiskCritPct         = 95
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────
#  Helper: status label + console colour
# ─────────────────────────────────────────────
function Get-Status {
    param([double]$Value, [double]$Warn, [double]$Crit)
    if ($Value -ge $Crit) { return "CRITICAL" }
    if ($Value -ge $Warn) { return "WARNING"  }
    return "OK"
}

function Write-StatusLine {
    param([string]$Label, [string]$Value, [string]$Status)
    $colour = switch ($Status) {
        "CRITICAL" { "Red"    }
        "WARNING"  { "Yellow" }
        default    { "Green"  }
    }
    Write-Host ("[{0,-8}] {1,-30} {2}" -f $Status, $Label, $Value) -ForegroundColor $colour
}

# ─────────────────────────────────────────────
#  Collect: System Info
# ─────────────────────────────────────────────
$ts        = Get-Date
$hostname  = $env:COMPUTERNAME
$os        = (Get-CimInstance Win32_OperatingSystem)
$uptime    = (Get-Date) - $os.LastBootUpTime
$uptimeStr = "{0}d {1}h {2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes

# ─────────────────────────────────────────────
#  Collect: CPU
# ─────────────────────────────────────────────
# Sample twice 1 second apart for a stable reading
$cpu1 = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
Start-Sleep -Seconds 1
$cpu2 = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$cpuPct   = [math]::Round(($cpu1 + $cpu2) / 2, 1)
$cpuStatus = Get-Status $cpuPct $CpuWarnPct $CpuCritPct

# ─────────────────────────────────────────────
#  Collect: Memory
# ─────────────────────────────────────────────
$totalMemMB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 0)
$freeMemMB  = [math]::Round($os.FreePhysicalMemory     / 1KB, 0)
$usedMemMB  = $totalMemMB - $freeMemMB
$memPct     = [math]::Round(($usedMemMB / $totalMemMB) * 100, 1)
$memStatus  = Get-Status $memPct $MemWarnPct $MemCritPct

# ─────────────────────────────────────────────
#  Collect: Disks (fixed drives only)
# ─────────────────────────────────────────────
$disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" |
    ForEach-Object {
        $usedGB  = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
        $totalGB = [math]::Round($_.Size / 1GB, 2)
        $freePct = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
        $usedPct = 100 - $freePct
        [PSCustomObject]@{
            Drive    = $_.DeviceID
            UsedGB   = $usedGB
            TotalGB  = $totalGB
            UsedPct  = $usedPct
            Status   = Get-Status $usedPct $DiskWarnPct $DiskCritPct
        }
    }

# ─────────────────────────────────────────────
#  Collect: Top 5 CPU-hungry Processes
# ─────────────────────────────────────────────
$topProcs = Get-Process |
    Sort-Object CPU -Descending |
    Select-Object -First 5 |
    ForEach-Object {
        [PSCustomObject]@{
            Name      = $_.ProcessName
            PID       = $_.Id
            CPU_s     = [math]::Round($_.CPU, 1)
            MemMB     = [math]::Round($_.WorkingSet64 / 1MB, 1)
        }
    }

# ─────────────────────────────────────────────
#  Collect: Critical Windows Services
# ─────────────────────────────────────────────
$watchedServices = @(
    "wuauserv",   # Windows Update
    "WinDefend",  # Windows Defender
    "EventLog",   # Windows Event Log
    "Spooler",    # Print Spooler
    "LanmanServer", # Server (file sharing)
    "Dnscache",   # DNS Client
    "W32Time"     # Windows Time
)

$services = $watchedServices | ForEach-Object {
    try {
        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
        if ($svc) {
            [PSCustomObject]@{
                Name        = $svc.DisplayName
                ServiceName = $svc.Name
                Status      = $svc.Status
                HealthStatus = if ($svc.Status -eq "Running") { "OK" } else { "WARNING" }
            }
        }
    } catch { $null }
} | Where-Object { $_ }

# ─────────────────────────────────────────────
#  Collect: Recent Critical/Error Event Log Entries (last 24h)
# ─────────────────────────────────────────────
$since = (Get-Date).AddHours(-24)
$events = @()
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'System','Application'
        Level     = 1,2          # Critical=1, Error=2
        StartTime = $since
    } -MaxEvents 10 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, LevelDisplayName, ProviderName,
        @{N="Message"; E={ $_.Message -replace "`r`n"," " | ForEach-Object { if ($_.Length -gt 120) { $_.Substring(0,120)+"…" } else { $_ } } }}
} catch {}

# ─────────────────────────────────────────────
#  Overall health roll-up
# ─────────────────────────────────────────────
$allStatuses = @($cpuStatus, $memStatus) + ($disks.Status) + ($services.HealthStatus)
$overallStatus = if ($allStatuses -contains "CRITICAL") { "CRITICAL" }
                 elseif ($allStatuses -contains "WARNING") { "WARNING" }
                 else { "OK" }

# ─────────────────────────────────────────────
#  Console Output
# ─────────────────────────────────────────────
$divider = "=" * 65
Write-Host ""
Write-Host $divider -ForegroundColor Cyan
Write-Host ("  SERVER HEALTH REPORT  |  {0}  |  {1}" -f $hostname, $ts.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Cyan
Write-Host $divider -ForegroundColor Cyan

$overallColor = switch ($overallStatus) { "CRITICAL"{"Red"} "WARNING"{"Yellow"} default{"Green"} }
Write-Host ("  OVERALL STATUS: {0}" -f $overallStatus) -ForegroundColor $overallColor
Write-Host ("  Uptime: {0}" -f $uptimeStr)
Write-Host ""

Write-Host "── SYSTEM ──────────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-StatusLine "CPU Usage"    ("{0}%" -f $cpuPct)                  $cpuStatus
Write-StatusLine "Memory Usage" ("{0}% ({1}MB / {2}MB)" -f $memPct, $usedMemMB, $totalMemMB) $memStatus

Write-Host ""
Write-Host "── DISK ────────────────────────────────────────────────────" -ForegroundColor DarkCyan
foreach ($d in $disks) {
    Write-StatusLine ("Disk $($d.Drive)") ("{0}% used  ({1}GB / {2}GB)" -f $d.UsedPct, $d.UsedGB, $d.TotalGB) $d.Status
}

Write-Host ""
Write-Host "── SERVICES ────────────────────────────────────────────────" -ForegroundColor DarkCyan
foreach ($svc in $services) {
    Write-StatusLine $svc.Name $svc.Status $svc.HealthStatus
}

Write-Host ""
Write-Host "── TOP 5 PROCESSES (by CPU time) ───────────────────────────" -ForegroundColor DarkCyan
$topProcs | Format-Table -AutoSize | Out-String | Write-Host

if ($events.Count -gt 0) {
    Write-Host "── RECENT ERRORS / CRITICAL EVENTS (last 24h) ─────────────" -ForegroundColor DarkCyan
    foreach ($ev in $events) {
        $col = if ($ev.LevelDisplayName -eq "Critical") { "Red" } else { "Yellow" }
        Write-Host (" [{0}] {1} - {2}: {3}" -f $ev.LevelDisplayName, $ev.TimeCreated.ToString("HH:mm"), $ev.ProviderName, $ev.Message) -ForegroundColor $col
    }
    Write-Host ""
}

Write-Host $divider -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────
#  HTML Report (optional)
# ─────────────────────────────────────────────
if ($HtmlReport -ne "") {

    function Status-Badge ([string]$s) {
        $cls = switch ($s) { "CRITICAL"{"crit"} "WARNING"{"warn"} default{"ok"} }
        return "<span class='badge $cls'>$s</span>"
    }

    $diskRows = ($disks | ForEach-Object {
        "<tr><td>$($_.Drive)</td><td>$($_.UsedGB) GB / $($_.TotalGB) GB</td>" +
        "<td><div class='bar-wrap'><div class='bar bar-$($_.Status.ToLower())' style='width:$($_.UsedPct)%'></div></div>$($_.UsedPct)%</td>" +
        "<td>$(Status-Badge $_.Status)</td></tr>"
    }) -join ""

    $svcRows = ($services | ForEach-Object {
        "<tr><td>$($_.Name)</td><td>$($_.ServiceName)</td><td>$(Status-Badge $_.HealthStatus)</td><td>$($_.Status)</td></tr>"
    }) -join ""

    $procRows = ($topProcs | ForEach-Object {
        "<tr><td>$($_.Name)</td><td>$($_.PID)</td><td>$($_.CPU_s)s</td><td>$($_.MemMB) MB</td></tr>"
    }) -join ""

    $eventRows = if ($events.Count -gt 0) {
        ($events | ForEach-Object {
            $cls = if ($_.LevelDisplayName -eq "Critical") { "crit" } else { "warn" }
            "<tr><td>$($_.TimeCreated.ToString('HH:mm:ss'))</td><td><span class='badge $cls'>$($_.LevelDisplayName)</span></td><td>$($_.ProviderName)</td><td>$($_.Message)</td></tr>"
        }) -join ""
    } else { "<tr><td colspan='4' class='no-events'>No critical/error events in the last 24 hours ✓</td></tr>" }

    $overallClass = $overallStatus.ToLower()

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Server Health — $hostname</title>
<style>
  :root {
    --bg:#0f1117; --surface:#1a1d27; --border:#2a2d3e;
    --text:#e2e8f0; --muted:#64748b;
    --ok:#22c55e; --warn:#f59e0b; --crit:#ef4444;
    --accent:#38bdf8;
  }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { background:var(--bg); color:var(--text); font-family:'Segoe UI',system-ui,sans-serif; font-size:14px; padding:24px; }
  h1 { font-size:1.5rem; color:var(--accent); margin-bottom:4px; }
  .meta { color:var(--muted); margin-bottom:24px; font-size:13px; }
  .overall { display:inline-flex; align-items:center; gap:10px; background:var(--surface);
             border:1px solid var(--border); border-radius:10px; padding:10px 20px; margin-bottom:28px; }
  .overall .label { font-weight:700; font-size:1.1rem; }
  .overall.ok   .label { color:var(--ok);   }
  .overall.warning .label { color:var(--warn); }
  .overall.critical .label { color:var(--crit); }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:16px; margin-bottom:28px; }
  .card { background:var(--surface); border:1px solid var(--border); border-radius:10px; padding:18px; }
  .card h3 { font-size:.75rem; text-transform:uppercase; letter-spacing:.08em; color:var(--muted); margin-bottom:10px; }
  .big-num { font-size:2.4rem; font-weight:700; line-height:1; }
  .big-num.ok   { color:var(--ok);   }
  .big-num.warning { color:var(--warn); }
  .big-num.critical { color:var(--crit); }
  .sub  { font-size:12px; color:var(--muted); margin-top:4px; }
  section { margin-bottom:28px; }
  section h2 { font-size:.8rem; text-transform:uppercase; letter-spacing:.1em; color:var(--muted);
               border-bottom:1px solid var(--border); padding-bottom:8px; margin-bottom:12px; }
  table { width:100%; border-collapse:collapse; }
  th,td { padding:9px 12px; text-align:left; border-bottom:1px solid var(--border); }
  th { font-size:.75rem; text-transform:uppercase; letter-spacing:.07em; color:var(--muted); }
  tr:last-child td { border-bottom:none; }
  .badge { display:inline-block; font-size:.7rem; font-weight:700; padding:2px 8px;
           border-radius:4px; text-transform:uppercase; letter-spacing:.05em; }
  .badge.ok   { background:rgba(34,197,94,.15);  color:var(--ok);   }
  .badge.warn { background:rgba(245,158,11,.15); color:var(--warn); }
  .badge.crit { background:rgba(239,68,68,.15);  color:var(--crit); }
  .bar-wrap { background:rgba(255,255,255,.08); border-radius:4px; height:6px;
              display:inline-block; width:120px; vertical-align:middle; margin-right:8px; }
  .bar { height:100%; border-radius:4px; }
  .bar-ok       { background:var(--ok);   }
  .bar-warning  { background:var(--warn); }
  .bar-critical { background:var(--crit); }
  .no-events { color:var(--ok); text-align:center; padding:16px !important; }
  footer { color:var(--muted); font-size:12px; margin-top:32px; text-align:center; }
</style>
</head>
<body>
<h1>⚡ Server Health Report</h1>
<p class="meta">Host: <strong>$hostname</strong> &nbsp;|&nbsp; Generated: $($ts.ToString("yyyy-MM-dd HH:mm:ss")) &nbsp;|&nbsp; Uptime: $uptimeStr</p>

<div class="overall $overallClass">
  <span>Overall Status:</span>
  <span class="label">$overallStatus</span>
</div>

<div class="grid">
  <div class="card">
    <h3>CPU Usage</h3>
    <div class="big-num $($cpuStatus.ToLower())">$cpuPct<span style="font-size:1.2rem">%</span></div>
    <div class="sub">Threshold: warn $CpuWarnPct% / crit $CpuCritPct%</div>
  </div>
  <div class="card">
    <h3>Memory Usage</h3>
    <div class="big-num $($memStatus.ToLower())">$memPct<span style="font-size:1.2rem">%</span></div>
    <div class="sub">${usedMemMB}MB used of ${totalMemMB}MB</div>
  </div>
  <div class="card">
    <h3>Services Monitored</h3>
    <div class="big-num" style="color:var(--accent)">$($services.Count)</div>
    <div class="sub">$(($services | Where-Object { $_.HealthStatus -ne 'OK' }).Count) not running</div>
  </div>
  <div class="card">
    <h3>Events (24h)</h3>
    <div class="big-num" style="color:$(if($events.Count -gt 0){'var(--warn)'}else{'var(--ok)'})">$($events.Count)</div>
    <div class="sub">Critical/Error events</div>
  </div>
</div>

<section>
  <h2>Disk Usage</h2>
  <table>
    <thead><tr><th>Drive</th><th>Used / Total</th><th>Usage</th><th>Status</th></tr></thead>
    <tbody>$diskRows</tbody>
  </table>
</section>

<section>
  <h2>Services</h2>
  <table>
    <thead><tr><th>Display Name</th><th>Service</th><th>Health</th><th>State</th></tr></thead>
    <tbody>$svcRows</tbody>
  </table>
</section>

<section>
  <h2>Top 5 Processes (CPU Time)</h2>
  <table>
    <thead><tr><th>Process</th><th>PID</th><th>CPU (s)</th><th>Memory</th></tr></thead>
    <tbody>$procRows</tbody>
  </table>
</section>

<section>
  <h2>Recent Error / Critical Events (last 24h)</h2>
  <table>
    <thead><tr><th>Time</th><th>Level</th><th>Source</th><th>Message</th></tr></thead>
    <tbody>$eventRows</tbody>
  </table>
</section>

<footer>Generated by Monitor-ServerHealth.ps1 on $hostname</footer>
</body>
</html>
"@

    $html | Out-File -FilePath $HtmlReport -Encoding UTF8
    Write-Host "  HTML report saved: $HtmlReport" -ForegroundColor Cyan
    Write-Host ""
}
