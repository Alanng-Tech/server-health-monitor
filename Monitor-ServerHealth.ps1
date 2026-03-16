<#
.Synopsis
    Advanced Server Health Monitor with HTML reporting.
.Parameter HtmlReport
    Path to save the HTML report.
.Parameter CpuWarnPct
    CPU % threshold for Warning (default 75).
#>
Param(
    [string]$HtmlReport = "$HOME\Downloads\MonitorReport.html",
    [int]$CpuWarnPct = 75,
    [int]$CpuCritPct = 90,
    [int]$MemWarnPct = 80,
    [int]$MemCritPct = 95,
    [int]$DiskWarnPct = 80,
    [int]$DiskCritPct = 95
)

# 1. Configuration: Add any services you want to track specifically here
$watchedServices = @("WinDefend", "EventLog", "Dnscache", "Spooler", "LanmanServer", "W32Time")

# 2. Data Gathering
$hostname = hostname
$CPU = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 2 | Select-Object -ExpandProperty CounterSamples | Measure-Object -Property CookedValue -Average).Average, 2)
$OS = Get-CimInstance Win32_OperatingSystem
$MemUsed = [math]::Round((($OS.TotalVisibleMemorySize - $OS.FreePhysicalMemory) / $OS.TotalVisibleMemorySize) * 100, 2)
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, @{Name="UsedPct";Expression={[math]::Round(($_.Size - $_.FreeSpace)/$_.Size * 100, 1)}}, @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace/1GB,2)}}, @{Name="TotalGB";Expression={[math]::Round($_.Size/1GB,2)}}

# 3. Advanced Monitoring: Top Processes & Events
$TopProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
$Events = Get-WinEvent -FilterHashtable @{LogName=@('System','Application'); Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 15 -ErrorAction SilentlyContinue

# 4. Helper Function for Status Colors
function Get-StatusColor ($Value, $Warn, $Crit) {
    if ($Value -ge $Crit) { return "red" }
    if ($Value -ge $Warn) { return "orange" }
    return "green"
}

# 5. Build HTML Rows
$diskRows = foreach($d in $Disks) {
    $color = Get-StatusColor $d.UsedPct $DiskWarnPct $DiskCritPct
    "<tr><td>$($d.DeviceID)</td><td>$($d.FreeGB) / $($d.TotalGB) GB</td><td><b style='color:$color'>$($d.UsedPct)%</b></td></tr>"
}

$svcRows = foreach($sName in $watchedServices) {
    $s = Get-Service -Name $sName -ErrorAction SilentlyContinue
    $status = if ($s) { $s.Status } else { "Not Found" }
    $color = if ($status -eq "Running") { "green" } else { "red" }
    "<tr><td>$sName</td><td style='color:$color'>$status</td></tr>"
}

$procRows = foreach($p in $TopProcesses) {
    "<tr><td>$($p.ProcessName)</td><td>$($p.Id)</td><td>$([math]::Round($p.CPU, 1))</td></tr>"
}

# 6. Generate the HTML File
$htmlBody = @"
<html>
<head><style>
    body { font-family: 'Segoe UI', sans-serif; padding: 20px; background: #1e1e1e; color: white; }
    .card { background: #2d2d2d; padding: 15px; margin-bottom: 20px; border-radius: 8px; border-left: 5px solid #0078d4; }
    table { border-collapse: collapse; width: 100%; margin-top: 10px; color: #ddd; }
    th, td { border: 1px solid #444; padding: 10px; text-align: left; }
    th { background: #3d3d3d; }
    .status-badge { padding: 5px 10px; border-radius: 4px; font-weight: bold; }
</style></head>
<body>
    <h1>Server Health: $hostname</h1>
    <div class='card'>
        <h3>Performance Summary</h3>
        <p>CPU Usage: <span style='color:$(Get-StatusColor $CPU $CpuWarnPct $CpuCritPct)'>$CPU%</span></p>
        <p>Memory Usage: <span style='color:$(Get-StatusColor $MemUsed $MemWarnPct $MemCritPct)'>$MemUsed%</span></p>
    </div>
    <div class='card'><h3>Disk Inventory</h3><table><tr><th>Drive</th><th>Free/Total</th><th>Usage</th></tr>$($diskRows -join "")</table></div>
    <div class='card'><h3>Critical Services</h3><table><tr><th>Service</th><th>Status</th></tr>$($svcRows -join "")</table></div>
    <div class='card'><h3>Top 5 Processes (CPU Time)</h3><table><tr><th>Process</th><th>PID</th><th>CPU</th></tr>$($procRows -join "")</table></div>
    <div class='card'><h3>Recent System Errors (24h)</h3><ul>$(foreach($e in $Events){ "<li><b>$($e.TimeCreated):</b> $($e.Message)</li>" })</ul></div>
</body></html>
"@

$htmlBody | Out-File $HtmlReport -Encoding utf8
Start-Process "msedge.exe" $HtmlReport
