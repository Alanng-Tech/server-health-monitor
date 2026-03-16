powershell
$ScriptPath = "$HOME\Downloads\Monitor-ServerHealth.ps1"

$Content = @'
function Monitor-ServerHealth {
    $hostname = hostname
    $Disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace/1GB,2)}}, @{Name="TotalGB";Expression={[math]::Round($_.Size/1GB,2)}}
    $CPU = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $Mem = Get-CimInstance Win32_OperatingSystem | Select-Object @{Name="Usage";Expression={[math]::Round((($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)/$_.TotalVisibleMemorySize) * 100, 2)}}
    $Services = Get-Service | Where-Object {$_.Status -eq "Stopped" -and $_.StartType -eq "Automatic"}
    $Events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2} -MaxEvents 10 -ErrorAction SilentlyContinue

    $diskRows = foreach($d in $Disk) { "<tr><td>$($d.DeviceID)</td><td>$($d.FreeGB) / $($d.TotalGB) GB</td></tr>" }
    $svcRows = if ($Services) { foreach($s in $Services) { "<tr><td>$($s.DisplayName)</td><td>Stopped</td></tr>" } } else { "<tr><td colspan='2'>All automatic services running</td></tr>" }
    $eventRows = if ($Events) { foreach($e in $Events) { "<tr><td>$($e.TimeCreated)</td><td>$($e.Message)</td></tr>" } } else { "<tr><td colspan='2'>No recent critical errors</td></tr>" }

$htmlReport = @"
<html>
<head>
    <style>
        body { font-family: sans-serif; padding: 20px; background: #f4f7f6; }
        .card { background: white; padding: 15px; margin-bottom: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background-color: #0078d4; color: white; }
    </style>
</head>
<body>
    <h1>Server Health: $hostname</h1>
    <div class="card">
        <h3>Overview</h3>
        <p>CPU: $CPU% | Memory: $($Mem.Usage)%</p>
    </div>
    <div class="card">
        <h3>Disk Usage</h3>
        <table><tr><th>Drive</th><th>Free / Total</th></tr>$($diskRows -join "")</table>
    </div>
    <div class="card">
        <h3>Stopped Services</h3>
        <table><tr><th>Service</th><th>Status</th></tr>$($svcRows -join "")</table>
    </div>
    <div class="card">
        <h3>Recent Errors</h3>
        <table><tr><th>Time</th><th>Message</th></tr>$($eventRows -join "")</table>
    </div>
</body>
</html>
"@
    $ReportPath = "$HOME\Downloads\HealthReport.html"
    $htmlReport | Out-File $ReportPath -Encoding utf8
    Invoke-Item $ReportPath
}
Monitor-ServerHealth
'@

$Content | Out-File $ScriptPath -Encoding utf8
& $ScriptPath
