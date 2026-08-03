param(
  [Parameter(Mandatory = $true)]
  [ValidateRange(1, 100)]
  [int]$Round,

  [string]$Serial = 'APH7N19528013778',

  [string]$AdbPath = 'C:\Users\Administrator\AppData\Local\Android\Sdk\platform-tools\adb.exe',

  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$packageName = 'com.taobao.power_image_example'
$activityName = "$packageName/.MainActivity"
$gpuFrequencyPath = '/sys/class/devfreq/gpufreq/cur_freq'
$surfaceLayer =
    'SurfaceView - com.taobao.power_image_example/com.taobao.power_image_example.MainActivity#0'

$scenarios = @(
  [pscustomobject]@{ Format = 'static_webp'; Library = 'power_image'; Entry = 'benchmark_static_power_image' },
  [pscustomobject]@{ Format = 'static_webp'; Library = 'cached_network_image'; Entry = 'benchmark_static_cached_network_image' },
  [pscustomobject]@{ Format = 'static_webp'; Library = 'extended_image'; Entry = 'benchmark_static_extended_image' },
  [pscustomobject]@{ Format = 'animated_webp'; Library = 'power_image'; Entry = 'benchmark_power_image' },
  [pscustomobject]@{ Format = 'animated_webp'; Library = 'cached_network_image'; Entry = 'benchmark_cached_network_image' },
  [pscustomobject]@{ Format = 'animated_webp'; Library = 'extended_image'; Entry = 'benchmark_extended_image' },
  [pscustomobject]@{ Format = 'gif'; Library = 'power_image'; Entry = 'benchmark_gif_power_image' },
  [pscustomobject]@{ Format = 'gif'; Library = 'cached_network_image'; Entry = 'benchmark_gif_cached_network_image' },
  [pscustomobject]@{ Format = 'gif'; Library = 'extended_image'; Entry = 'benchmark_gif_extended_image' }
)

function Invoke-Adb {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  $output = & $AdbPath -s $Serial @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "adb failed ($LASTEXITCODE): $($Arguments -join ' ')"
  }
  return $output
}

function Get-WindowXml {
  Invoke-Adb -Arguments @('shell', 'uiautomator dump /sdcard/window.xml') |
      Out-Null
  return (Invoke-Adb -Arguments @('shell', 'cat /sdcard/window.xml')) -join ''
}

function Start-CleanApp {
  Invoke-Adb -Arguments @('shell', "am force-stop $packageName") | Out-Null
  Invoke-Adb -Arguments @('shell', "pm clear $packageName") | Out-Null
  Invoke-Adb -Arguments @('shell', "am start -W -n $activityName") | Out-Null

  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $xml = Get-WindowXml
    if ($xml.Contains('content-desc="power_image example app"')) {
      return
    }
    Start-Sleep -Milliseconds 500
  }
  throw 'The benchmark home page did not become ready.'
}

function Open-BenchmarkEntry {
  param([Parameter(Mandatory = $true)][string]$Entry)

  $escapedEntry = [regex]::Escape($Entry)
  $entryPattern =
      'content-desc="' + $escapedEntry + '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'

  for ($attempt = 0; $attempt -lt 12; $attempt++) {
    $xml = Get-WindowXml
    $match = [regex]::Match($xml, $entryPattern)
    if ($match.Success) {
      $left = [int]$match.Groups[1].Value
      $top = [int]$match.Groups[2].Value
      $right = [int]$match.Groups[3].Value
      $bottom = [int]$match.Groups[4].Value
      if ($right -gt $left -and $bottom -gt $top) {
        $x = [int](($left + $right) / 2)
        $y = [int](($top + $bottom) / 2)
        Invoke-Adb -Arguments @('shell', "input tap $x $y") | Out-Null
        Start-Sleep -Seconds 4

        $pageXml = Get-WindowXml
        if ($pageXml.Contains("content-desc=`"${Entry}_grid`"")) {
          return
        }
        throw "Tapped $Entry but its grid did not open."
      }
    }

    Invoke-Adb -Arguments @('shell', 'input swipe 540 1850 540 500 250') |
        Out-Null
    Start-Sleep -Milliseconds 150
  }
  throw "Could not find benchmark entry: $Entry"
}

function Get-ProcessCpuSample {
  param([Parameter(Mandatory = $true)][int]$ProcessId)

  $processStat =
      (Invoke-Adb -Arguments @('shell', "cat /proc/$ProcessId/stat")) -join ''
  $processMatch = [regex]::Match($processStat, '^\d+ \(.+\) \S (.+)$')
  if (-not $processMatch.Success) {
    throw "Could not parse /proc/$ProcessId/stat."
  }
  $processFields = $processMatch.Groups[1].Value -split '\s+'
  $processTicks = [long]$processFields[10] + [long]$processFields[11]

  $systemStat = Invoke-Adb -Arguments @('shell', 'head -n 1 /proc/stat')
  $systemFields = (($systemStat -join '').Trim() -split '\s+')
  [long]$systemTicks = 0
  for ($index = 1; $index -le 8; $index++) {
    $systemTicks += [long]$systemFields[$index]
  }

  return [pscustomobject]@{
    ProcessTicks = $processTicks
    SystemTicks = $systemTicks
  }
}

function Get-OneCoreCpuPercent {
  param(
    [Parameter(Mandatory = $true)]$Start,
    [Parameter(Mandatory = $true)]$End,
    [Parameter(Mandatory = $true)][int]$CoreCount
  )

  $processDelta = $End.ProcessTicks - $Start.ProcessTicks
  $systemDelta = $End.SystemTicks - $Start.SystemTicks
  if ($systemDelta -le 0) {
    throw 'System CPU tick delta was not positive.'
  }
  return [math]::Round(($processDelta / $systemDelta) * $CoreCount * 100, 1)
}

function Get-AppFrameCounter {
  $surfaceDump = (Invoke-Adb -Arguments @('shell', 'dumpsys SurfaceFlinger')) -join "`n"
  $pattern =
      '(?ms)^' + [regex]::Escape($surfaceLayer) + '\r?$.*?frame-counter=(\d+)'
  $match = [regex]::Match($surfaceDump, $pattern)
  if (-not $match.Success) {
    throw 'Could not read the Flutter SurfaceView frame counter.'
  }
  return [long]$match.Groups[1].Value
}

function Invoke-ScrollPhase {
  param([Parameter(Mandatory = $true)][ValidateSet('down', 'up')][string]$Direction)

  if ($Direction -eq 'down') {
    $gesture = 'input swipe 540 1900 540 400 250'
  } else {
    $gesture = 'input swipe 540 400 540 1900 250'
  }

  $frequencies = [System.Collections.Generic.List[long]]::new()
  for ($index = 0; $index -lt 12; $index++) {
    $remoteCommand =
        "$gesture & i=0; while [ `$i -lt 5 ]; do cat $gpuFrequencyPath; " +
        'i=$(($i+1)); sleep 0.05; done; wait'
    $samples = Invoke-Adb -Arguments @('shell', $remoteCommand)
    foreach ($sample in $samples) {
      $value = 0L
      if ([long]::TryParse($sample.Trim(), [ref]$value)) {
        $frequencies.Add($value)
      }
    }
  }
  if ($frequencies.Count -eq 0) {
    throw 'No GPU frequency samples were captured.'
  }
  return $frequencies.ToArray()
}

function Get-BatteryTemperatureCelsius {
  $batteryDump = (Invoke-Adb -Arguments @('shell', 'dumpsys battery')) -join "`n"
  $match = [regex]::Match($batteryDump, '(?m)^\s*temperature:\s*(\d+)')
  if (-not $match.Success) {
    return [double]::NaN
  }
  return [math]::Round(([double]$match.Groups[1].Value) / 10, 1)
}

if (-not (Test-Path -LiteralPath $AdbPath)) {
  throw "adb not found: $AdbPath"
}

$deviceState = (& $AdbPath -s $Serial get-state).Trim()
if ($deviceState -ne 'device') {
  throw "Android device is unavailable: $Serial ($deviceState)"
}

$coreCount = [int]((Invoke-Adb -Arguments @('shell', 'nproc')) -join '').Trim()
Invoke-Adb -Arguments @('shell', 'svc power stayon true') | Out-Null

# Reverse every even round to reduce fixed-order thermal bias.
if (($Round % 2) -eq 0) {
  [array]::Reverse($scenarios)
}

foreach ($scenario in $scenarios) {
  Write-Host "START round=$Round format=$($scenario.Format) library=$($scenario.Library)"
  Start-CleanApp
  Open-BenchmarkEntry -Entry $scenario.Entry

  $processIdText =
      ((Invoke-Adb -Arguments @('shell', "pidof $packageName")) -join '').Trim()
  if (-not $processIdText) {
    throw 'The benchmark app process is not running.'
  }
  $processId = [int]($processIdText -split '\s+')[0]

  $startFrames = Get-AppFrameCounter
  $downFrameStartTime = [datetime]::UtcNow
  $downCpuStart = Get-ProcessCpuSample -ProcessId $processId
  $downFrequencies = Invoke-ScrollPhase -Direction down
  $downCpuEnd = Get-ProcessCpuSample -ProcessId $processId
  $middleFrames = Get-AppFrameCounter
  $downFrameEndTime = [datetime]::UtcNow

  $upFrameStartTime = [datetime]::UtcNow
  $upCpuStart = Get-ProcessCpuSample -ProcessId $processId
  $upFrequencies = Invoke-ScrollPhase -Direction up
  $upCpuEnd = Get-ProcessCpuSample -ProcessId $processId
  $endFrames = Get-AppFrameCounter
  $upFrameEndTime = [datetime]::UtcNow

  $allFrequencies = @($downFrequencies) + @($upFrequencies)
  $averageGpuMhz =
      [math]::Round((($allFrequencies | Measure-Object -Average).Average / 1000000), 0)
  $peakGpuMhz =
      [math]::Round((($allFrequencies | Measure-Object -Maximum).Maximum / 1000000), 0)
  $downSeconds = ($downFrameEndTime - $downFrameStartTime).TotalSeconds
  $upSeconds = ($upFrameEndTime - $upFrameStartTime).TotalSeconds

  $result = [pscustomobject]@{
    Round = $Round
    Format = $scenario.Format
    Library = $scenario.Library
    CpuColdDownPercent = Get-OneCoreCpuPercent `
        -Start $downCpuStart -End $downCpuEnd -CoreCount $coreCount
    CpuWarmUpPercent = Get-OneCoreCpuPercent `
        -Start $upCpuStart -End $upCpuEnd -CoreCount $coreCount
    GpuAverageMhz = $averageGpuMhz
    GpuPeakMhz = $peakGpuMhz
    SurfaceColdDownFps = [math]::Round(($middleFrames - $startFrames) / $downSeconds, 1)
    SurfaceWarmUpFps = [math]::Round(($endFrames - $middleFrames) / $upSeconds, 1)
    BatteryCelsius = Get-BatteryTemperatureCelsius
  }

  if ($OutputPath) {
    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
      New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    $result | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Append
  }
  Write-Output ($result | ConvertTo-Json -Compress)
}
