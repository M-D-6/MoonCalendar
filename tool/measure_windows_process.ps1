param(
    [ValidateRange(5, 300)]
    [int]$Samples = 30,
    [ValidateRange(1, 5)]
    [int]$IntervalSeconds = 1
)

$ErrorActionPreference = 'Stop'
$processName = 'mooncalendar'
$initial = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
if ($initial.Count -eq 0) {
    throw "No $processName.exe process found. Start MoonCalendar first, preferably on the Weather page."
}

Write-Host "Tracking all $processName.exe processes. Close unrelated MoonCalendar instances before comparing runs."
Write-Host ("Initial PID(s): " + (($initial | ForEach-Object { $_.Id }) -join ', '))
Write-Host "Sampling for $($Samples * $IntervalSeconds) seconds; switch pages before starting another run."

$cpuByPid = @{}
foreach ($p in $initial) { $cpuByPid[[int]$p.Id] = [double]$p.CPU }
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$previousElapsed = 0.0
$logicalProcessors = [Math]::Max(1, [Environment]::ProcessorCount)

for ($i = 1; $i -le $Samples; $i++) {
    Start-Sleep -Seconds $IntervalSeconds
    $now = $watch.Elapsed.TotalSeconds
    $elapsed = [Math]::Max(0.001, $now - $previousElapsed)
    $previousElapsed = $now
    $current = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
    if ($current.Count -eq 0) {
        Write-Host 'MoonCalendar exited; stopping measurement.'
        break
    }

    $workingBytes = [long]0
    $privateBytes = [long]0
    $cpuDelta = 0.0
    $currentPids = @{}
    foreach ($p in $current) {
        $pidValue = [int]$p.Id
        $currentPids[$pidValue] = $true
        $workingBytes += [long]$p.WorkingSet64
        $privateBytes += [long]$p.PrivateMemorySize64
        $cpuNow = [double]$p.CPU
        if ($cpuByPid.ContainsKey($pidValue)) {
            $cpuDelta += [Math]::Max(0.0, $cpuNow - [double]$cpuByPid[$pidValue])
        }
        $cpuByPid[$pidValue] = $cpuNow
    }
    foreach ($knownPid in @($cpuByPid.Keys)) {
        if (-not $currentPids.ContainsKey([int]$knownPid)) { $cpuByPid.Remove($knownPid) }
    }

    [pscustomobject]@{
        Time       = (Get-Date).ToString('HH:mm:ss')
        Processes  = $current.Count
        CPU_TotalPct = [Math]::Round((100.0 * $cpuDelta / $elapsed / $logicalProcessors), 2)
        WorkingSetMB = [Math]::Round($workingBytes / 1MB, 1)
        PrivateMB    = [Math]::Round($privateBytes / 1MB, 1)
    }
}
