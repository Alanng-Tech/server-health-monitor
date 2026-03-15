# Windows Server Health Monitor

A lightweight, dependency-free PowerShell script that checks the health of a Windows Server (or Windows 10/11 Pro machine) and outputs a color-coded console report — with an optional self-contained HTML report.

---

## What It Monitors

| Category | Details |
|----------|---------|
| **CPU** | Average usage % (sampled twice for stability) |
| **Memory** | Used vs. total physical RAM |
| **Disks** | All fixed drives — used/free with visual bar in HTML |
| **Services** | 7 critical Windows services (Defender, Event Log, DNS, etc.) |
| **Top Processes** | Top 5 processes by CPU time |
| **Event Log** | Last 24h Critical/Error events from System & Application logs |

---

## Quick Start

> **Requires:** PowerShell 5.1+, run as **Administrator**

```powershell
# 1. Allow local scripts to run (one-time setup — Windows 11 Pro / Server)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 2. Unblock the downloaded file (if prompted)
Unblock-File -Path ".\Monitor-ServerHealth.ps1"

# 3. Run it
.\Monitor-ServerHealth.ps1
```

---

## Usage Examples

```powershell
# Console output only
.\Monitor-ServerHealth.ps1

# Save an HTML report
.\Monitor-ServerHealth.ps1 -HtmlReport "C:\Reports\health.html"

# Custom thresholds
.\Monitor-ServerHealth.ps1 -CpuWarnPct 60 -CpuCritPct 85 -HtmlReport ".\report.html"
```

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-HtmlReport` | *(none)* | Path to save the HTML report. Omit for console-only output. |
| `-CpuWarnPct` | `75` | CPU % to trigger a **WARNING** |
| `-CpuCritPct` | `90` | CPU % to trigger **CRITICAL** |
| `-MemWarnPct` | `80` | Memory % to trigger a **WARNING** |
| `-MemCritPct` | `95` | Memory % to trigger **CRITICAL** |
| `-DiskWarnPct` | `80` | Disk % to trigger a **WARNING** |
| `-DiskCritPct` | `95` | Disk % to trigger **CRITICAL** |

---

## Console Output

The console output is color-coded:

-  **Green** — OK
-  **Yellow** — WARNING
-  **Red** — CRITICAL

---

## HTML Report

When `-HtmlReport` is specified, the script generates a dark-themed, self-contained HTML file with:

- Overall status badge
- Summary cards for CPU, Memory, Services, and Events
- Disk usage bars
- Services table
- Top processes table
- Recent error/critical event log entries

No external dependencies — the HTML file works offline.

---

## Scheduled Monitoring (Optional)

To run automatically on a schedule, create a Windows Task Scheduler job:

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
             -Argument '-File "C:\Scripts\Monitor-ServerHealth.ps1" -HtmlReport "C:\Reports\health.html"'
$trigger = New-ScheduledTaskTrigger -Daily -At "7:00AM"
Register-ScheduledTask -TaskName "ServerHealthCheck" -Action $action -Trigger $trigger -RunLevel Highest
```

---

## Customizing Watched Services

Edit the `$watchedServices` array near the top of the script to add or remove services:

```powershell
$watchedServices = @(
    "wuauserv",      # Windows Update
    "WinDefend",     # Windows Defender
    "EventLog",      # Windows Event Log
    "Spooler",       # Print Spooler
    "LanmanServer",  # File Sharing
    "Dnscache",      # DNS Client
    "W32Time"        # Windows Time
    # Add your own services here, e.g. "MSSQLSERVER", "W3SVC"
)
```

---

## Compatibility

| Environment | Supported |
|-------------|-----------|
| Windows 11 Pro | ✅ |
| Windows 10 Pro | ✅ |
| Windows Server 2016/2019/2022 | ✅ |

---

