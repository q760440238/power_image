param(
    [string]$Serial = 'APH7N19528013778',
    [int]$Iterations = 5,
    [int]$WarmupSeconds = 12,
    [int]$SampleSeconds = 20,
    [int]$CooldownSeconds = 8,
    [switch]$IncludeNative,
    [string[]]$ScenarioIds = @(),
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$packageName = 'com.taobao.power_image_example'
$gpuFrequencyPath = '/sys/class/devfreq/gpufreq/cur_freq'
$gpuMaxFrequencyPath = '/sys/class/devfreq/gpufreq/max_freq'

function Invoke-Adb([string[]]$AdbArguments) {
    $output = @(& adb -s $Serial @AdbArguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed: adb -s $Serial $($AdbArguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

function Get-AdbValue([string]$Command) {
    return ((Invoke-Adb @('shell', $Command)) -join '').Trim()
}

function Get-Percentile([object[]]$Values, [double]$Percentile) {
    [double[]]$numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if ($numbers.Count -eq 0) { return $null }
    if ($numbers.Count -eq 1) { return $numbers[0] }
    $position = ($numbers.Count - 1) * $Percentile
    $lower = [Math]::Floor($position)
    $upper = [Math]::Ceiling($position)
    if ($lower -eq $upper) { return $numbers[$lower] }
    $weight = $position - $lower
    return $numbers[$lower] * (1.0 - $weight) + $numbers[$upper] * $weight
}

function Get-BatteryTemperatureCelsius {
    $battery = (Invoke-Adb @('shell', 'dumpsys battery')) -join "`n"
    $match = [regex]::Match($battery, '(?m)^\s*temperature:\s*(\d+)')
    if (-not $match.Success) { return $null }
    return [double]$match.Groups[1].Value / 10.0
}

function Start-BenchmarkScenario($Scenario) {
    $null = Invoke-Adb @('shell', 'am', 'force-stop', $packageName)
    Start-Sleep -Seconds 2
    if ($Scenario.Route) {
        $null = Invoke-Adb @(
            'shell', 'am', 'start', '-W', '-n', $Scenario.Component,
            '--es', 'power_image_benchmark_route', $Scenario.Route
        )
    } else {
        $null = Invoke-Adb @('shell', 'am', 'start', '-W', '-n', $Scenario.Component)
    }
    Start-Sleep -Seconds $WarmupSeconds
    $processId = Get-AdbValue "pidof $packageName"
    if (-not $processId) { throw "Process did not start for $($Scenario.Id)" }
    return $processId
}

function Read-ProcessCounter([string]$ProcessId, $Timer) {
    $command = "cat /proc/$ProcessId/stat; grep '^VmRSS:' /proc/$ProcessId/status; cat $gpuFrequencyPath"
    $lines = @(Invoke-Adb @('shell', $command))
    $stat = $lines | Where-Object { $_ -match '^\d+\s+\(' } | Select-Object -First 1
    $rss = $lines | Where-Object { $_ -match '^VmRSS:' } | Select-Object -First 1
    $gpu = $lines | Where-Object { $_ -match '^\d+$' } | Select-Object -Last 1
    if (-not $stat -or -not $rss -or -not $gpu) {
        throw "Incomplete process sample for pid $ProcessId`: $($lines -join ' | ')"
    }
    $fields = $stat -split '\s+'
    $rssMatch = [regex]::Match($rss, '(\d+)')
    return [pscustomobject]@{
        Seconds = [double]$Timer.Elapsed.TotalSeconds
        CpuTicks = [long]$fields[13] + [long]$fields[14]
        RssKb = [long]$rssMatch.Groups[1].Value
        GpuFrequencyHz = [long]$gpu
    }
}

function Measure-SteadyState([string]$ProcessId, [int]$ClockTicks, [int]$CoreCount, [long]$GpuMaxHz) {
    $samples = New-Object System.Collections.Generic.List[object]
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $previous = Read-ProcessCounter $ProcessId $timer
    for ($index = 1; $index -le $SampleSeconds; $index++) {
        $targetSeconds = $previous.Seconds + 1.0
        $remainingMilliseconds = [Math]::Round(($targetSeconds - $timer.Elapsed.TotalSeconds) * 1000.0)
        if ($remainingMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([int]$remainingMilliseconds)
        }
        $current = Read-ProcessCounter $ProcessId $timer
        $elapsed = $current.Seconds - $previous.Seconds
        $cpuCorePercent = (($current.CpuTicks - $previous.CpuTicks) / [double]$ClockTicks) / $elapsed * 100.0
        $samples.Add([pscustomobject]@{
            second = $index
            cpu_core_percent = [Math]::Round($cpuCorePercent, 4)
            cpu_total_capacity_percent = [Math]::Round($cpuCorePercent / $CoreCount, 4)
            rss_kb = $current.RssKb
            gpu_frequency_hz = $current.GpuFrequencyHz
            gpu_frequency_max_ratio_percent = [Math]::Round($current.GpuFrequencyHz / [double]$GpuMaxHz * 100.0, 4)
        })
        $previous = $current
    }
    return @($samples | ForEach-Object { $_ })
}

function Get-MemorySnapshot([string]$ProcessId) {
    $text = (Invoke-Adb @('shell', "dumpsys meminfo $ProcessId")) -join "`n"
    function Match-Kb([string]$Pattern) {
        $match = [regex]::Match($text, $Pattern)
        if (-not $match.Success) { return $null }
        return [long]($match.Groups[1].Value -replace ',', '')
    }
    return [pscustomobject]@{
        total_pss_kb = Match-Kb '(?m)^\s*TOTAL\s+([\d,]+)'
        native_heap_pss_kb = Match-Kb '(?m)^\s*Native Heap\s+([\d,]+)'
        dalvik_heap_pss_kb = Match-Kb '(?m)^\s*Dalvik Heap\s+([\d,]+)'
        graphics_pss_kb = Match-Kb '(?m)^\s*GL mtrack\s+([\d,]+)'
        java_heap_summary_kb = Match-Kb '(?m)^\s*Java Heap:\s+([\d,]+)'
    }
}

function Get-SurfaceStats([string]$SurfaceActivity) {
    $surfaces = @(Invoke-Adb @('shell', 'dumpsys SurfaceFlinger --list'))
    if ($SurfaceActivity -eq 'MainActivity') {
        $surface = $surfaces |
            Where-Object { $_ -match '^SurfaceView - ' -and $_ -match [regex]::Escape($SurfaceActivity) } |
            Select-Object -Last 1
    } else {
        $surface = $surfaces |
            Where-Object { $_ -match '^com\.taobao\.power_image_example/' -and $_ -match [regex]::Escape($SurfaceActivity) } |
            Select-Object -Last 1
    }
    if (-not $surface) {
        return [pscustomobject]@{ surface = $null; displayed_fps = $null; frame_interval_p50_ms = $null; frame_interval_p95_ms = $null; samples = 0 }
    }
    $latency = @(Invoke-Adb @('shell', "dumpsys SurfaceFlinger --latency '$surface'"))
    [long[]]$timestamps = @($latency | Select-Object -Skip 1 | ForEach-Object {
        $columns = $_ -split '\s+'
        if ($columns.Count -ge 1 -and $columns[0] -match '^\d+$' -and [long]$columns[0] -gt 0) {
            [long]$columns[0]
        }
    } | Sort-Object -Unique)
    [double[]]$intervals = @()
    for ($index = 1; $index -lt $timestamps.Count; $index++) {
        $intervalMs = ($timestamps[$index] - $timestamps[$index - 1]) / 1000000.0
        if ($intervalMs -gt 0 -and $intervalMs -lt 1000) { $intervals += $intervalMs }
    }
    $median = Get-Percentile $intervals 0.50
    return [pscustomobject]@{
        surface = $surface
        displayed_fps = if ($median) { [Math]::Round(1000.0 / $median, 3) } else { $null }
        frame_interval_p50_ms = if ($median) { [Math]::Round($median, 3) } else { $null }
        frame_interval_p95_ms = if ($intervals.Count) { [Math]::Round((Get-Percentile $intervals 0.95), 3) } else { $null }
        samples = $intervals.Count
    }
}

$device = [ordered]@{
    serial = $Serial
    manufacturer = Get-AdbValue 'getprop ro.product.manufacturer'
    model = Get-AdbValue 'getprop ro.product.model'
    android_release = Get-AdbValue 'getprop ro.build.version.release'
    sdk = [int](Get-AdbValue 'getprop ro.build.version.sdk')
    build_fingerprint = Get-AdbValue 'getprop ro.build.fingerprint'
}
$clockTicks = [int](Get-AdbValue 'getconf CLK_TCK')
$coreCount = [int](Get-AdbValue 'getconf _NPROCESSORS_ONLN')
$gpuMaxHz = [long](Get-AdbValue "cat $gpuMaxFrequencyPath")

$scenarios = @(
    [pscustomobject]@{ Id = 'power_flutter'; Label = 'PowerImage Flutter codec'; Component = "$packageName/.MainActivity"; Route = '/benchmark/steady20/power_flutter'; SurfaceActivity = 'MainActivity' },
    [pscustomobject]@{ Id = 'extended'; Label = 'ExtendedImage 10.1.0'; Component = "$packageName/.MainActivity"; Route = '/benchmark/steady20/extended'; SurfaceActivity = 'MainActivity' }
)
if ($IncludeNative) {
    $scenarios += [pscustomobject]@{ Id = 'native_glide'; Label = 'Pure Android Glide 4.16.0'; Component = "$packageName/.NativeGlideBenchmarkActivity"; Route = $null; SurfaceActivity = 'NativeGlideBenchmarkActivity' }
}
if ($ScenarioIds.Count -gt 0) {
    $unknownScenarioIds = @($ScenarioIds | Where-Object { $_ -notin $scenarios.Id })
    if ($unknownScenarioIds.Count -gt 0) {
        throw "Unknown scenario id(s): $($unknownScenarioIds -join ', ')"
    }
    $scenarios = @($scenarios | Where-Object { $_.Id -in $ScenarioIds })
}

$runs = New-Object System.Collections.Generic.List[object]
for ($iteration = 0; $iteration -lt $Iterations; $iteration++) {
    for ($offset = 0; $offset -lt $scenarios.Count; $offset++) {
        $scenario = $scenarios[($iteration + $offset) % $scenarios.Count]
        Write-Host "RUN_START iteration=$($iteration + 1)/$Iterations scenario=$($scenario.Id)"
        $temperatureStart = Get-BatteryTemperatureCelsius
        $processId = Start-BenchmarkScenario $scenario
        $null = Invoke-Adb @('shell', 'dumpsys SurfaceFlinger --latency-clear')
        $samples = Measure-SteadyState $processId $clockTicks $coreCount $gpuMaxHz
        $memory = Get-MemorySnapshot $processId
        $surface = Get-SurfaceStats $scenario.SurfaceActivity
        $temperatureEnd = Get-BatteryTemperatureCelsius
        $run = [pscustomobject]@{
            iteration = $iteration + 1
            scenario = $scenario.Id
            label = $scenario.Label
            process_id = [int]$processId
            temperature_start_c = $temperatureStart
            temperature_end_c = $temperatureEnd
            memory = $memory
            surface = $surface
            samples = $samples
        }
        $runs.Add($run)
        $cpuMedian = Get-Percentile @($samples | ForEach-Object { $_.cpu_core_percent }) 0.50
        Write-Host ("RUN_DONE scenario={0} cpu_p50={1:N2}% pss={2}KB graphics={3}KB gpu_p50={4:N0}MHz fps={5}" -f
            $scenario.Id,
            $cpuMedian,
            $memory.total_pss_kb,
            $memory.graphics_pss_kb,
            ((Get-Percentile @($samples | ForEach-Object { $_.gpu_frequency_hz }) 0.50) / 1000000.0),
            $surface.displayed_fps)
        $null = Invoke-Adb @('shell', 'am', 'force-stop', $packageName)
        Start-Sleep -Seconds $CooldownSeconds
    }
}

$summaries = @()
foreach ($scenario in $scenarios) {
    $scenarioRuns = @($runs | Where-Object { $_.scenario -eq $scenario.Id })
    $samples = @($scenarioRuns | ForEach-Object { $_.samples })
    $summaries += [pscustomobject]@{
        scenario = $scenario.Id
        label = $scenario.Label
        runs = $scenarioRuns.Count
        one_second_samples = $samples.Count
        cpu_core_percent_p50 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.cpu_core_percent }) 0.50), 3)
        cpu_core_percent_p95 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.cpu_core_percent }) 0.95), 3)
        cpu_total_capacity_percent_p50 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.cpu_total_capacity_percent }) 0.50), 3)
        cpu_total_capacity_percent_p95 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.cpu_total_capacity_percent }) 0.95), 3)
        rss_kb_p50 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.rss_kb }) 0.50), 1)
        rss_kb_p95 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.rss_kb }) 0.95), 1)
        total_pss_kb_p50 = [Math]::Round((Get-Percentile @($scenarioRuns | ForEach-Object { $_.memory.total_pss_kb }) 0.50), 1)
        total_pss_kb_p95 = [Math]::Round((Get-Percentile @($scenarioRuns | ForEach-Object { $_.memory.total_pss_kb }) 0.95), 1)
        graphics_pss_kb_p50 = [Math]::Round((Get-Percentile @($scenarioRuns | ForEach-Object { $_.memory.graphics_pss_kb }) 0.50), 1)
        graphics_pss_kb_p95 = [Math]::Round((Get-Percentile @($scenarioRuns | ForEach-Object { $_.memory.graphics_pss_kb }) 0.95), 1)
        native_heap_pss_kb_p50 = [Math]::Round((Get-Percentile @($scenarioRuns | ForEach-Object { $_.memory.native_heap_pss_kb }) 0.50), 1)
        gpu_frequency_mhz_p50 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.gpu_frequency_hz / 1000000.0 }) 0.50), 1)
        gpu_frequency_mhz_p95 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.gpu_frequency_hz / 1000000.0 }) 0.95), 1)
        gpu_frequency_max_ratio_percent_p50 = [Math]::Round((Get-Percentile @($samples | ForEach-Object { $_.gpu_frequency_max_ratio_percent }) 0.50), 2)
        displayed_fps_p50 = [Math]::Round((Get-Percentile @($scenarioRuns | ForEach-Object { $_.surface.displayed_fps }) 0.50), 3)
        frame_interval_p95_ms_p50 = [Math]::Round((Get-Percentile @($scenarioRuns | ForEach-Object { $_.surface.frame_interval_p95_ms }) 0.50), 3)
        temperature_end_c_p50 = [Math]::Round((Get-Percentile @($scenarioRuns | ForEach-Object { $_.temperature_end_c }) 0.50), 1)
    }
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot '..\android\macrobenchmark\results\2026-08-04-VOG-AL10\steady20-wrap-frame-cache-ab.json'
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [IO.Path]::GetDirectoryName($resolvedOutput)
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$result = [ordered]@{
    schema_version = 1
    generated_at = [DateTimeOffset]::Now.ToString('o')
    device = $device
    config = [ordered]@{
        iterations = $Iterations
        warmup_seconds = $WarmupSeconds
        sample_seconds = $SampleSeconds
        cooldown_seconds = $CooldownSeconds
        cpu_clock_ticks_per_second = $clockTicks
        cpu_online_cores = $coreCount
        gpu_max_frequency_hz = $gpuMaxHz
        gpu_utilization_available = $false
        gpu_note = 'Production kernel denies access to gpu_scene_aware/utilisation; frequency is a workload proxy, not utilization.'
        materials = 'D:\power_image\测试素材\manifest.csv'
    }
    summary = $summaries
    runs = $runs
}
$json = $result | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($resolvedOutput, $json, [Text.UTF8Encoding]::new($false))
Write-Host "RESULT=$resolvedOutput"
$summaries | Format-Table scenario,cpu_core_percent_p50,cpu_core_percent_p95,total_pss_kb_p50,graphics_pss_kb_p50,gpu_frequency_mhz_p50,gpu_frequency_mhz_p95,displayed_fps_p50 -AutoSize
