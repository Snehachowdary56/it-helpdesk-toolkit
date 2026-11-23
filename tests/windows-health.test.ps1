# Runs windows/health-check.ps1 on the Windows CI runner and checks its report.
$ErrorActionPreference = "Stop"
$report = Join-Path $env:RUNNER_TEMP "health.json"
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\..\windows\health-check.ps1" -ReportPath $report
$code = $LASTEXITCODE
$r = Get-Content $report -Raw | ConvertFrom-Json
function Assert($cond, $msg) { if (-not $cond) { throw "FAILED: $msg" } else { "ok - $msg" } }
Assert ($code -in 0, 1, 2) "exit code is 0, 1 or 2 (got $code)"
Assert ($r.overall -in "OK", "WARN", "CRITICAL") "overall status is set ($($r.overall))"
Assert ((@($r.findings | Where-Object check -eq "disk")).Count -ge 1) "reports at least one fixed disk"
Assert ((@($r.findings | Where-Object check -eq "eventlog")).Count -eq 2) "checks System and Application event logs"
Assert ((@($r.findings | Where-Object { $_.check -eq "service" -and $_.message -like "EventLog is Running" })).Count -eq 1) "EventLog service is running"
# A critical service that does not exist must be flagged
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\..\windows\health-check.ps1" -CriticalServices "NoSuchService123" -ReportPath $report | Out-Null
$r2 = Get-Content $report -Raw | ConvertFrom-Json
Assert ((@($r2.findings | Where-Object message -like "NoSuchService123 not installed")).Count -eq 1) "missing service is flagged"
"All Windows health check tests passed"
