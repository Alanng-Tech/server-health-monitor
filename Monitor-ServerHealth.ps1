powershell
<#
.Synopsis
    Monitors Server Health and generates an HTML Report.
#>

function Monitor-ServerHealth {
    $hostname = hostname
    
    # 1. Gather Data
    $Disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace/1GB,2)}}, @{Name="TotalGB";Expression={[math]::Round($_.Size/1GB,2)}}
    $CPU = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $Mem = Get-CimInstance Win32_OperatingSystem | Select-Object @{Name="Usage";Expression={[math]::Round((($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)/$_.TotalVisibleMemorySize) * 100, 2)}}
    $Services = Get-Service | Where-Object {$_.Status -eq "Stopped" -and $_.StartType -eq "Automatic"}
    $Events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2} -MaxEvents 10 -ErrorAction SilentlyContinue

    # 2. Build Table Rows
    $diskRows = foreach($d in $Disk) {
        "<tr><td>$($d.DeviceID)</td><td>$($d.FreeGB) / $($d.TotalGB) GB</td><td>$([math]::Round(($d.TotalGB - $d.FreeGB)/$d.TotalGB * 100, 1))%</td></tr>"
    }

    $svcRows = foreach($s in $Services) {
        "<tr><td>$($s.DisplayName)</td><td>$($s.Name)</td><td>Stopped</td></tr>"
    }

    $eventRows = foreach($e in $Events) {
        "<tr><td>$($e.TimeCreated)</td><td>$($e.LevelDisplayName)</td><td>$($e.Message)</td></tr>"
    }

    # 3. Create the HTML Report using a clean Here-String
    # IMPORTANT: The "@ must be at the very start of the line with NO spaces.
$htmlReport = @"
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; padding: 20px; background: #f4f7f6; }
        .card { background: white; padding: 15px; margin-bottom: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        table { border-collapse: collapse; width: 100%; background: white; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #0078d4; color: white; }
        .header { display: flex; justify-content: space-between; align-items: center; }
        .status-ok { color: green; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Server Health Report: $hostname</h1>
        <p>Generated: $(Get-Date)</p>
    </div>

    <div class="card">
        <h3>System Overview</h3>
        <p><strong>CPU Usage:</strong> $CPU%</p>
        <p><strong>Memory Usage:</strong> $($Mem.Usage)%</p>
    </div>

    <div class="card">
        <h3>Disk Usage</h3>
        <table>
            <thead><tr><th>Drive</th><th>Used / Total</th><th>Usage %</th></tr></thead>
            <tbody>$diskRows</tbody>
        </table>
    </div>

    <div class="card">
        <h3>Stopped Automatic Services</h3>
        <table>
            <thead><tr><th>Display Name</th><th>Service Name</th><th>Status</th></tr></thead>
            <tbody>$($svcRows -join '')</tbody>
        </table>
    </div>

    <div class="card">
        <h3>Recent Critical/Error Events</h3>
        <table>
            <thead><tr><th>Time</th><th>Level</th><th>Message</th></tr></thead>
            <tbody>$($eventRows -join '')</tbody>
        </table>
    </div>
</body>
</html>
"@

    # 4. Save and Open
    $Path = "$HOME\Downloads\MonitorReport.html"
    $htmlReport | Out-File $Path -Encoding utf8
    Invoke-Item $Path
}

# Run the function
Monitor-ServerHealth
