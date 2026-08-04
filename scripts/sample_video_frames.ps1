#requires -Version 7.0

<#
.SYNOPSIS
Adaptively samples representative frames from a video on Windows.

.DESCRIPTION
Auto mode probes visual-change density and selects a low, standard, or high
sampling profile. Explicit low, standard, high, and max profiles are also
supported. Sampling intensity controls frequency; there is no total-frame cap
unless FrameCount or FRAME_COUNT is supplied.

.PARAMETER InputPath
Path to the input video.

.PARAMETER OutputDir
Destination directory. Defaults to frames/<video-name> beside the input.

.PARAMETER Intensity
auto, low, standard, high, or max. Defaults to VIDEO_ANALYSIS_INTENSITY, then auto.

.PARAMETER FrameCount
Optional hard frame limit. Omit it for unlimited sampling.

.PARAMETER FfmpegPath
Optional path to ffmpeg.exe or the directory containing it.

.PARAMETER FfprobePath
Optional path to ffprobe.exe or the directory containing it. If ffprobe cannot
be found, duration probing falls back to ffmpeg.

.PARAMETER ToolCacheRoot
Optional tool cache root containing bin/ffmpeg.exe and bin/ffprobe.exe.

.EXAMPLE
pwsh ./scripts/sample_video_frames.ps1 -InputPath C:\videos\talk.mkv -Intensity auto

.EXAMPLE
pwsh ./scripts/sample_video_frames.ps1 -InputPath C:\videos\talk.mkv -OutputDir C:\frames\talk -Intensity high -FrameCount 80
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $InputPath,

    [Parameter(Position = 1)]
    [string] $OutputDir,

    [Parameter(Position = 2)]
    [string] $Intensity,

    [Nullable[int]] $FrameCount,

    [string] $FfmpegPath,

    [string] $FfprobePath,

    [string] $ToolCacheRoot,

    [Nullable[int]] $FrameWidth,

    [Nullable[double]] $MinGap,

    [Nullable[double]] $MaxGap,

    [Nullable[double]] $SceneThreshold
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function ConvertTo-InvariantNumber {
    param(
        [Parameter(Mandatory)]
        [double] $Value
    )

    return $Value.ToString('0.######', $invariantCulture)
}

function ConvertFrom-EnvironmentInteger {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Value
    )

    [int] $parsed = 0
    if (-not [int]::TryParse($Value, [System.Globalization.NumberStyles]::Integer, $invariantCulture, [ref] $parsed)) {
        throw "$Name must be a positive integer."
    }
    return $parsed
}

function ConvertFrom-EnvironmentNumber {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Value
    )

    [double] $parsed = 0
    if (-not [double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, $invariantCulture, [ref] $parsed)) {
        throw "$Name must be a number."
    }
    return $parsed
}

function Test-PositiveFiniteNumber {
    param([double] $Value)

    return $Value -gt 0 -and -not [double]::IsNaN($Value) -and -not [double]::IsInfinity($Value)
}

function Resolve-ExplicitToolPath {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $Path = Join-Path $Path "$Name.exe"
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Supplied $Name path does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Resolve-NativeTool {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [string] $ExplicitPath,

        [string[]] $SiblingDirectories = @(),

        [string[]] $CacheRoots = @(),

        [switch] $Optional
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return Resolve-ExplicitToolPath -Name $Name -Path $ExplicitPath
    }

    $command = Get-Command "$Name.exe", $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($directory in $SiblingDirectories) {
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            $candidates.Add((Join-Path $directory "$Name.exe"))
        }
    }
    foreach ($root in $CacheRoots) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $candidates.Add((Join-Path $root "bin\$Name.exe"))
            $candidates.Add((Join-Path $root "$Name.exe"))
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }

    if ($Optional) {
        return $null
    }
    throw "$Name was not found on PATH or in a supplied/cache path."
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Failed to start native command: $FilePath"
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $standardOutput
            StdErr = $standardError
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-VideoDuration {
    param(
        [Parameter(Mandatory)]
        [string] $VideoPath,

        [Parameter(Mandatory)]
        [string] $Ffmpeg,

        [string] $Ffprobe
    )

    if (-not [string]::IsNullOrWhiteSpace($Ffprobe)) {
        $probeResult = Invoke-NativeCapture -FilePath $Ffprobe -Arguments @(
            '-v', 'error',
            '-show_entries', 'format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1',
            $VideoPath
        )
        if ($probeResult.ExitCode -eq 0) {
            [double] $duration = 0
            $durationText = $probeResult.StdOut.Trim()
            if ([double]::TryParse($durationText, [System.Globalization.NumberStyles]::Float, $invariantCulture, [ref] $duration) -and
                (Test-PositiveFiniteNumber $duration)) {
                return $duration
            }
        }
        Write-Warning 'ffprobe did not return a positive duration; falling back to ffmpeg input metadata.'
    }

    $metadataResult = Invoke-NativeCapture -FilePath $Ffmpeg -Arguments @('-hide_banner', '-i', $VideoPath)
    $metadata = "$($metadataResult.StdOut)`n$($metadataResult.StdErr)"
    $durationMatch = [regex]::Match(
        $metadata,
        'Duration:\s*(?<hours>\d+):(?<minutes>\d{2}):(?<seconds>\d{2}(?:\.\d+)?)',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $durationMatch.Success) {
        throw 'Could not determine a positive video duration with ffprobe or ffmpeg.'
    }

    $hours = [double]::Parse($durationMatch.Groups['hours'].Value, $invariantCulture)
    $minutes = [double]::Parse($durationMatch.Groups['minutes'].Value, $invariantCulture)
    $seconds = [double]::Parse($durationMatch.Groups['seconds'].Value, $invariantCulture)
    $duration = ($hours * 3600) + ($minutes * 60) + $seconds
    if (-not (Test-PositiveFiniteNumber $duration)) {
        throw 'Could not determine a positive video duration.'
    }
    return $duration
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}
$resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).ProviderPath

if ([string]::IsNullOrWhiteSpace($Intensity)) {
    $Intensity = if ([string]::IsNullOrWhiteSpace($env:VIDEO_ANALYSIS_INTENSITY)) {
        'auto'
    }
    else {
        $env:VIDEO_ANALYSIS_INTENSITY
    }
}
$requestedIntensity = $Intensity.Trim().ToLowerInvariant()
if ($requestedIntensity -eq 'medium') {
    $requestedIntensity = 'standard'
}
if ($requestedIntensity -notin @('auto', 'low', 'standard', 'high', 'max')) {
    throw 'Intensity must be auto, low, standard, high, or max.'
}

if ($null -eq $FrameCount -and -not [string]::IsNullOrWhiteSpace($env:FRAME_COUNT)) {
    $FrameCount = ConvertFrom-EnvironmentInteger -Name 'FRAME_COUNT' -Value $env:FRAME_COUNT
}
if ($null -ne $FrameCount -and $FrameCount -lt 1) {
    throw 'FrameCount must be a positive integer.'
}

if ($null -eq $FrameWidth) {
    $FrameWidth = if ([string]::IsNullOrWhiteSpace($env:FRAME_WIDTH)) {
        1600
    }
    else {
        ConvertFrom-EnvironmentInteger -Name 'FRAME_WIDTH' -Value $env:FRAME_WIDTH
    }
}
if ($FrameWidth -lt 1) {
    throw 'FrameWidth must be a positive integer.'
}

if ($null -eq $MinGap -and -not [string]::IsNullOrWhiteSpace($env:FRAME_MIN_GAP)) {
    $MinGap = ConvertFrom-EnvironmentNumber -Name 'FRAME_MIN_GAP' -Value $env:FRAME_MIN_GAP
}
if ($null -eq $MaxGap -and -not [string]::IsNullOrWhiteSpace($env:FRAME_MAX_GAP)) {
    $MaxGap = ConvertFrom-EnvironmentNumber -Name 'FRAME_MAX_GAP' -Value $env:FRAME_MAX_GAP
}
if ($null -eq $SceneThreshold -and -not [string]::IsNullOrWhiteSpace($env:FRAME_SCENE_THRESHOLD)) {
    $SceneThreshold = ConvertFrom-EnvironmentNumber -Name 'FRAME_SCENE_THRESHOLD' -Value $env:FRAME_SCENE_THRESHOLD
}
if ($null -ne $MinGap -and -not (Test-PositiveFiniteNumber $MinGap)) {
    throw 'MinGap must be a positive number of seconds.'
}
if ($null -ne $MaxGap -and -not (Test-PositiveFiniteNumber $MaxGap)) {
    throw 'MaxGap must be a positive number of seconds.'
}
if ($null -ne $SceneThreshold -and
    ([double]::IsNaN($SceneThreshold) -or [double]::IsInfinity($SceneThreshold) -or $SceneThreshold -lt 0 -or $SceneThreshold -gt 1)) {
    throw 'SceneThreshold must be between 0 and 1.'
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $inputDirectory = [System.IO.Path]::GetDirectoryName($resolvedInputPath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedInputPath)
    $OutputDir = Join-Path $inputDirectory "frames\$baseName"
}
$resolvedOutputDir = [System.IO.Path]::GetFullPath($OutputDir)
if (Test-Path -LiteralPath $resolvedOutputDir -PathType Leaf) {
    throw "Output path is a file: $resolvedOutputDir"
}
[void] (New-Item -ItemType Directory -Path $resolvedOutputDir -Force)

$existingFrames = @(Get-ChildItem -LiteralPath $resolvedOutputDir -Filter 'frame_*.jpg' -File -ErrorAction Stop)
if ($existingFrames.Count -gt 0) {
    throw "Output directory already contains sampled frames: $resolvedOutputDir. Choose an empty output directory to avoid mixing runs."
}

$cacheRoots = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($ToolCacheRoot)) {
    $cacheRoots.Add($ToolCacheRoot)
}
if (-not [string]::IsNullOrWhiteSpace($env:VIDEO_ANALYSIS_TOOL_CACHE)) {
    $cacheRoots.Add($env:VIDEO_ANALYSIS_TOOL_CACHE)
}
if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $cacheRoots.Add((Join-Path $env:LOCALAPPDATA 'CodexSkills\video-content-analysis'))
}
$cacheRoots.Add((Join-Path $PSScriptRoot '..\tools'))

$resolvedFfmpegPath = Resolve-NativeTool -Name 'ffmpeg' -ExplicitPath $FfmpegPath -CacheRoots $cacheRoots
$ffmpegDirectory = Split-Path -Parent $resolvedFfmpegPath
$resolvedFfprobePath = Resolve-NativeTool -Name 'ffprobe' -ExplicitPath $FfprobePath `
    -SiblingDirectories @($ffmpegDirectory) -CacheRoots $cacheRoots -Optional
if ($null -eq $resolvedFfprobePath) {
    Write-Warning 'ffprobe was not found; using ffmpeg input metadata for duration probing.'
}

$duration = Get-VideoDuration -VideoPath $resolvedInputPath -Ffmpeg $resolvedFfmpegPath -Ffprobe $resolvedFfprobePath
$durationText = ConvertTo-InvariantNumber $duration

$effectiveIntensity = $requestedIntensity
$probeIntervalText = 'not_run'
$densitySceneAverageText = 'not_run'
$densityChangeRatioText = 'not_run'
$densityProbeFrames = 0

if ($requestedIntensity -eq 'auto') {
    $probeInterval = [Math]::Min(30.0, [Math]::Max(1.0, $duration / 240.0))
    $probeIntervalText = ConvertTo-InvariantNumber $probeInterval
    $densityFilter = "fps=1/$probeIntervalText,select='gte(scene,0)',metadata=print"
    $densityResult = Invoke-NativeCapture -FilePath $resolvedFfmpegPath -Arguments @(
        '-hide_banner', '-loglevel', 'info',
        '-i', $resolvedInputPath,
        '-map', '0:v:0', '-an',
        '-vf', $densityFilter,
        '-f', 'null', '-'
    )

    if ($densityResult.ExitCode -eq 0) {
        $densityOutput = "$($densityResult.StdOut)`n$($densityResult.StdErr)"
        $scoreMatches = [regex]::Matches(
            $densityOutput,
            'lavfi\.scene_score=(?<score>(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        $scores = [System.Collections.Generic.List[double]]::new()
        foreach ($scoreMatch in $scoreMatches) {
            $scores.Add([double]::Parse($scoreMatch.Groups['score'].Value, $invariantCulture))
        }
        $densityProbeFrames = $scores.Count

        if ($densityProbeFrames -gt 0) {
            $scoreTotal = 0.0
            $changedFrames = 0
            foreach ($score in $scores) {
                $scoreTotal += $score
                if ($score -ge 0.08) {
                    $changedFrames += 1
                }
            }
            $densitySceneAverage = $scoreTotal / $densityProbeFrames
            $densityChangeRatio = $changedFrames / $densityProbeFrames
            $densitySceneAverageText = ConvertTo-InvariantNumber $densitySceneAverage
            $densityChangeRatioText = ConvertTo-InvariantNumber $densityChangeRatio

            if ($densityProbeFrames -lt 3) {
                $effectiveIntensity = 'standard'
            }
            elseif ($densitySceneAverage -lt 0.01 -and $densityChangeRatio -lt 0.03) {
                $effectiveIntensity = 'low'
            }
            elseif ($densitySceneAverage -ge 0.10 -or $densityChangeRatio -ge 0.35) {
                $effectiveIntensity = 'high'
            }
            else {
                $effectiveIntensity = 'standard'
            }
        }
        else {
            $effectiveIntensity = 'standard'
        }
    }
    else {
        Write-Warning 'Visual-density probe failed; using the standard profile.'
        $effectiveIntensity = 'standard'
        $densitySceneAverageText = 'probe_failed'
        $densityChangeRatioText = 'probe_failed'
    }
}

$profile = switch ($effectiveIntensity) {
    'low' {
        [pscustomobject]@{ BaselineFrames = 8; MinGap = 30.0; MaxGap = 300.0; SceneThreshold = 0.08; AbsoluteGapFloor = 1.0 }
    }
    'standard' {
        [pscustomobject]@{ BaselineFrames = 16; MinGap = 10.0; MaxGap = 120.0; SceneThreshold = 0.01; AbsoluteGapFloor = 0.5 }
    }
    'high' {
        [pscustomobject]@{ BaselineFrames = 32; MinGap = 3.0; MaxGap = 30.0; SceneThreshold = 0.005; AbsoluteGapFloor = 0.25 }
    }
    'max' {
        [pscustomobject]@{ BaselineFrames = 60; MinGap = 1.0; MaxGap = 10.0; SceneThreshold = 0.002; AbsoluteGapFloor = 0.1 }
    }
    default {
        throw "Unexpected effective intensity: $effectiveIntensity"
    }
}

$requestedMinGap = if ($null -eq $MinGap) { $profile.MinGap } else { [double] $MinGap }
$requestedMaxGap = if ($null -eq $MaxGap) { $profile.MaxGap } else { [double] $MaxGap }
$effectiveSceneThreshold = if ($null -eq $SceneThreshold) { $profile.SceneThreshold } else { [double] $SceneThreshold }

$coverageGap = $duration / $profile.BaselineFrames
$coverageGap = [Math]::Min($coverageGap, $requestedMaxGap)
$coverageGap = [Math]::Max($coverageGap, $profile.AbsoluteGapFloor)

$frameBudgetText = if ($null -eq $FrameCount) { 'unlimited' } else { [string] $FrameCount }
if ($FrameCount -eq 1) {
    $candidateGap = $duration + 1.0
}
elseif ($null -eq $FrameCount) {
    $candidateGap = [Math]::Min($requestedMinGap, $coverageGap)
    $candidateGap = [Math]::Max($candidateGap, $profile.AbsoluteGapFloor)
}
else {
    $budgetGap = (($duration / $FrameCount) * 1.000001) + 0.000001
    $candidateGap = [Math]::Min($requestedMinGap, $coverageGap)
    $candidateGap = [Math]::Max($candidateGap, $budgetGap)
    $candidateGap = [Math]::Max($candidateGap, $profile.AbsoluteGapFloor)
}
$maximumGap = [Math]::Max($coverageGap, $candidateGap)

$candidateGapText = ConvertTo-InvariantNumber $candidateGap
$maximumGapText = ConvertTo-InvariantNumber $maximumGap
$sceneThresholdText = ConvertTo-InvariantNumber $effectiveSceneThreshold
$frameManifestPath = Join-Path $resolvedOutputDir 'frames.tsv'
$samplingManifestPath = Join-Path $resolvedOutputDir 'sampling.tsv'

if ($FrameCount -eq 1) {
    $midpoint = $duration / 2.0
    $midpointText = ConvertTo-InvariantNumber $midpoint
    $singleFramePath = Join-Path $resolvedOutputDir 'frame_0001.jpg'
    $scaleFilter = "scale='min($FrameWidth,iw)':-2"
    $extractResult = Invoke-NativeCapture -FilePath $resolvedFfmpegPath -Arguments @(
        '-y', '-hide_banner', '-loglevel', 'error',
        '-ss', $midpointText,
        '-i', $resolvedInputPath,
        '-map', '0:v:0', '-an',
        '-frames:v', '1',
        '-vf', $scaleFilter,
        '-q:v', '2',
        $singleFramePath
    )
    if ($extractResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $singleFramePath -PathType Leaf)) {
        if (-not [string]::IsNullOrWhiteSpace($extractResult.StdErr)) {
            Write-Error $extractResult.StdErr.Trim()
        }
        throw 'Single-frame extraction failed.'
    }
    $singleFrameManifestLines = [System.Collections.Generic.List[string]]::new()
    $singleFrameManifestLines.Add('file' + "`t" + 'seconds')
    $singleFrameManifestLines.Add('frame_0001.jpg' + "`t" + $midpointText)
    [System.IO.File]::WriteAllLines($frameManifestPath, $singleFrameManifestLines, $utf8NoBom)
    $frameCountActual = 1
}
else {
    $endWindowStart = [Math]::Max(0.0, $duration - $candidateGap)
    $baselineTrigger = [Math]::Max($maximumGap - ($candidateGap / 2.0), $candidateGap / 2.0)
    $endWindowStartText = ConvertTo-InvariantNumber $endWindowStart
    $baselineTriggerText = ConvertTo-InvariantNumber $baselineTrigger
    $selectFilter = "fps=1/$candidateGapText,select='isnan(prev_selected_t)+gte(t-prev_selected_t,$baselineTriggerText)+gte(scene,$sceneThresholdText)+gte(t,$endWindowStartText)',scale='min($FrameWidth,iw)':-2,showinfo"
    $outputPattern = Join-Path $resolvedOutputDir 'frame_%04d.jpg'
    $extractResult = Invoke-NativeCapture -FilePath $resolvedFfmpegPath -Arguments @(
        '-y', '-hide_banner', '-loglevel', 'info',
        '-i', $resolvedInputPath,
        '-map', '0:v:0', '-an',
        '-vf', $selectFilter,
        '-q:v', '2', '-fps_mode', 'vfr',
        $outputPattern
    )
    if ($extractResult.ExitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($extractResult.StdErr)) {
            Write-Error $extractResult.StdErr.Trim()
        }
        throw 'Adaptive frame extraction failed.'
    }

    $frames = @(
        Get-ChildItem -LiteralPath $resolvedOutputDir -Filter 'frame_*.jpg' -File |
            Sort-Object {
                [long] ([regex]::Match($_.BaseName, '^frame_(?<index>\d+)$').Groups['index'].Value)
            }
    )
    if ($frames.Count -eq 0) {
        throw 'No frames were produced.'
    }
    $timestampMatches = [regex]::Matches(
        $extractResult.StdErr,
        'pts_time:(?<timestamp>[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )

    $manifestLines = [System.Collections.Generic.List[string]]::new()
    $manifestLines.Add('file' + "`t" + 'seconds')
    for ($index = 0; $index -lt $frames.Count; $index += 1) {
        $timestamp = if ($index -lt $timestampMatches.Count) {
            $timestampMatches[$index].Groups['timestamp'].Value
        }
        else {
            'unknown'
        }
        $manifestLines.Add($frames[$index].Name + "`t" + $timestamp)
    }
    [System.IO.File]::WriteAllLines($frameManifestPath, $manifestLines, $utf8NoBom)
    $frameCountActual = $frames.Count
}

$samplingLines = [System.Collections.Generic.List[string]]::new()
$samplingLines.Add('key' + "`t" + 'value')
$samplingLines.Add('requested_intensity' + "`t" + $requestedIntensity)
$samplingLines.Add('effective_intensity' + "`t" + $effectiveIntensity)
$samplingLines.Add('duration_seconds' + "`t" + $durationText)
$samplingLines.Add('density_probe_interval_seconds' + "`t" + $probeIntervalText)
$samplingLines.Add('density_scene_average' + "`t" + $densitySceneAverageText)
$samplingLines.Add('density_change_ratio' + "`t" + $densityChangeRatioText)
$samplingLines.Add('density_probe_frames' + "`t" + $densityProbeFrames)
$samplingLines.Add('candidate_gap_seconds' + "`t" + $candidateGapText)
$samplingLines.Add('maximum_coverage_gap_seconds' + "`t" + $maximumGapText)
$samplingLines.Add('scene_threshold' + "`t" + $sceneThresholdText)
$samplingLines.Add('frame_budget' + "`t" + $frameBudgetText)
$samplingLines.Add('frame_count' + "`t" + $frameCountActual)
[System.IO.File]::WriteAllLines($samplingManifestPath, $samplingLines, $utf8NoBom)

Write-Host 'Adaptive frame sampling complete'
Write-Host "Requested intensity: $requestedIntensity"
Write-Host "Effective intensity: $effectiveIntensity"
if ($null -eq $FrameCount) {
    Write-Host "Sampled frames: $frameCountActual (no total-frame limit)"
}
else {
    Write-Host "Sampled frames: $frameCountActual / limit $FrameCount"
}
Write-Host "Output directory: $resolvedOutputDir"
Write-Host "Frame manifest: $frameManifestPath"
Write-Host "Sampling manifest: $samplingManifestPath"
