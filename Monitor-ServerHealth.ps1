$ScriptPath = "$HOME\Downloads\Monitor-ServerHealth.ps1"
$ReportPath = "$HOME\Downloads\MonitorReport.html"

$Code = @'
function Monitor-ServerHealth {
    $hostname = hostname
    
    # 1. More Accurate CPU (Average over 2 seconds)
    $CPU = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 2 | 
            Select-Object -ExpandProperty CounterSamples | 
            Measure-Object -Property CookedValue -Average).Average
    $CPU = [math]::Round($CPU, 2)

    # 2. More Accurate RAM
    $OS = Get-CimInstance Win32_OperatingSystem
    $TotalRAM = $OS.TotalVisibleMemorySize
    $FreeRAM = $OS.FreePhysicalMemory
    $UsedRAMPercent = [math]::Round((($TotalRAM - $FreeRAM) / $TotalRAM) * 100, 2)

    $Disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace/1GB,2)}}, @{Name="TotalGB";Expression={[math]::Round($_.Size/1GB,2)}}
    $Services = Get-Service | Where-Object {$_.Status -eq "Stopped" -and $_.StartType -eq "Automatic"}
    $Events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2} -MaxEvents 10 -ErrorAction SilentlyContinue

    $diskRows = foreach($d in $Disk) { "<tr><td>$($d.DeviceID)</td><td>$($d.FreeGB) / $($d.TotalGB) GB</td></tr>" }
    $svcRows = if ($Services) { foreach($s in $Services) { "<tr><td>$($s.DisplayName)</td><td>Stopped</td></tr>" } } else { "<tr><td colspan='2'>All automatic services running</td></tr>" }

$htmlReport = @"
<html>
<head><style>body{font-family:sans-serif;padding:20px;background:#f4f7f6;}.card{background:white;padding:15px;margin-bottom:20px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ddd;padding:10px;text-align:left;}th{background-color:#0078d4;color:white;}</style></head>
<body>
    <h1>Server Health: $hostname</h1>
    <div class="card">
        <h3>Live Performance</h3>
        <p><strong>CPU Usage (2s Avg):</strong> $CPU%</p>
        <p><strong>Memory Usage:</strong> $UsedRAMPercent%</p>
    </div>
    <div class="card">
        <h3>Disk Usage</h3>
        <table><tr><th>Drive</th><th>Free / Total</th></tr>$($diskRows -join "")</table>
    </div>
    <div class="card">
        <h3>Services Info</h3>
        <table><tr><th>Service</th><th>Status</th></tr>$($svcRows -join "")</table>
    </div>
</body>
</html>
"@
    $Path = "$HOME\Downloads\MonitorReport.html"
    $htmlReport | Out-File $Path -Encoding utf8
    Start-Process "msedge.exe" $Path
}
Monitor-ServerHealth
'@

$Code | Out-File $ScriptPath -Encoding utf8
& $ScriptPath
