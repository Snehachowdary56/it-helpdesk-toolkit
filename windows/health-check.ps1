<#
.SYNOPSIS
  Routine Windows workstation/server check: automatic services that are stopped, disk space,
  System and Application event log errors in the last 24 hours, uptime and pending reboot.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\health-check.ps1 -ReportPath C:\Temp\health.json
  Exit code: 0 OK, 1 WARN, 2 CRITICAL.
#>
param(
  [string]$ReportPath = "",
  [int]$DiskWarnPercent = 80,
  [int]$DiskCritPercent = 90,
  [string[]]$CriticalServices = @("EventLog", "Dnscache", "LanmanWorkstation")
)
$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding($Level, $Check, $Message) { $findings.Add([pscustomobject]@{ level = $Level; check = $Check; message = $Message }) }

# Services: critical ones must run; list other automatic services that are stopped
foreach ($name in $CriticalServices) {
  $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
  if (-not $svc) { Add-Finding "WARN" "service" "$name not installed" }
  elseif ($svc.Status -ne "Running") { Add-Finding "CRIT" "service" "$name is $($svc.Status) (Start-Service $name)" }
  else { Add-Finding "OK" "service" "$name is running" }
}
# @( ) makes this a list even when only one service matches; Windows PowerShell 5.1 has no .Count on a single object
$stopped = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notmatch "gupdate|edgeupdate|sppsvc|RemoteRegistry|MapsBroker|tiledata" })
if ($stopped.Count -gt 0) {
  Add-Finding "WARN" "service" "$($stopped.Count) automatic service(s) stopped: $(($stopped | Select-Object -First 5 -ExpandProperty Name) -join ', ')"
} else {
  Add-Finding "OK" "service" "0 automatic services stopped"
}

# Disk space on fixed drives
foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3") {
  $used = [math]::Round((1 - $d.FreeSpace / $d.Size) * 100)
  $level = if ($used -ge $DiskCritPercent) { "CRIT" } elseif ($used -ge $DiskWarnPercent) { "WARN" } else { "OK" }
  Add-Finding $level "disk" "$($d.DeviceID) $used% used, $([math]::Round($d.FreeSpace / 1GB, 1)) GB free"
}

# Event log errors (level 1 critical, 2 error) in the last 24 hours
foreach ($log in "System", "Application") {
  $events = Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2; StartTime = (Get-Date).AddDays(-1) } -ErrorAction SilentlyContinue
  $count = @($events).Count
  $top = $events | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count))" }
  Add-Finding ($(if ($count -gt 25) { "WARN" } else { "OK" })) "eventlog" "$log log: $count error(s) in 24h$(if ($top) { ': ' + ($top -join ', ') })"
}

# Uptime and pending reboot
$os = Get-CimInstance Win32_OperatingSystem
$uptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
Add-Finding ($(if ($uptimeDays -gt 30) { "WARN" } else { "OK" })) "uptime" "up $uptimeDays days ($($os.Caption))"
$pending = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or
           (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
Add-Finding ($(if ($pending) { "WARN" } else { "OK" })) "reboot" "pending reboot: $pending"

$overall = if ($findings.level -contains "CRIT") { "CRITICAL" } elseif ($findings.level -contains "WARN") { "WARN" } else { "OK" }
"Health check: $env:COMPUTERNAME at $((Get-Date).ToUniversalTime().ToString('s'))Z"
$findings | ForEach-Object { "[$($_.level)] $($_.check): $($_.message)" }
"Overall: $overall"
if ($ReportPath) {
  [pscustomobject]@{ computer = $env:COMPUTERNAME; overall = $overall; findings = $findings } | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportPath -Encoding utf8
}
exit $(switch ($overall) { "OK" { 0 } "WARN" { 1 } default { 2 } })
