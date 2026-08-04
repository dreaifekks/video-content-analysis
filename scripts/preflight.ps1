#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$UseBrowserAuth,
    [string]$FirefoxProfileName,
    [switch]$SkipMedia,
    [switch]$RequireWhisper,
    [switch]$RequireCuda,
    [string]$YtDlpPath,
    [string]$FfmpegPath,
    [string]$CacheRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexSkills\video-content-analysis')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-IniSections {
    param([Parameter(Mandatory)][string]$Path)

    $sections = @()
    $sectionName = $null
    $values = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*\[([^]]+)\]\s*$') {
            if ($null -ne $sectionName) {
                $sections += [pscustomobject]@{ Name = $sectionName; Values = $values }
            }
            $sectionName = $matches[1]
            $values = [ordered]@{}
        } elseif ($null -ne $sectionName -and $line -match '^\s*([^=]+?)\s*=\s*(.*)$') {
            $values[$matches[1]] = $matches[2]
        }
    }
    if ($null -ne $sectionName) {
        $sections += [pscustomobject]@{ Name = $sectionName; Values = $values }
    }
    $sections
}

function Resolve-FirefoxProfile {
    param([string]$ProfileName)

    $firefoxRoot = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Mozilla\Firefox'
    $iniPath = Join-Path $firefoxRoot 'profiles.ini'
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) {
        throw 'Firefox profiles.ini was not found.'
    }

    $profiles = @(Get-IniSections -Path $iniPath | Where-Object { $_.Name -like 'Profile*' })
    if (-not $profiles.Count) { throw 'No Firefox profiles were listed in profiles.ini.' }

    if ($ProfileName) {
        $profile = $profiles | Where-Object {
            $_.Values.Contains('Name') -and $_.Values['Name'] -eq $ProfileName
        } | Select-Object -First 1
        if (-not $profile) { throw "Firefox profile not found: $ProfileName" }
    } else {
        $profile = $profiles | Where-Object {
            $_.Values.Contains('Default') -and $_.Values['Default'] -eq '1'
        } | Select-Object -First 1
        if (-not $profile) { $profile = $profiles | Select-Object -First 1 }
    }

    if (-not $profile.Values.Contains('Path')) { throw 'The selected Firefox profile has no Path entry.' }
    $profilePath = $profile.Values['Path']
    if ($profile.Values.Contains('IsRelative') -and $profile.Values['IsRelative'] -eq '1') {
        $profilePath = Join-Path $firefoxRoot $profilePath
    }
    $profilePath = [IO.Path]::GetFullPath($profilePath)
    $resolvedName = if ($profile.Values.Contains('Name')) { $profile.Values['Name'] } else { $profile.Name }

    [pscustomobject]@{
        Name = $resolvedName
        Path = $profilePath
        CookiesDatabaseFound = Test-Path -LiteralPath (Join-Path $profilePath 'cookies.sqlite') -PathType Leaf
    }
}

function Resolve-CommandPath {
    param(
        [string]$ExplicitPath,
        [Parameter(Mandatory)][string]$CommandName,
        [string]$CachedPath
    )

    if ($ExplicitPath) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return [IO.Path]::GetFullPath($ExplicitPath)
        }
        $explicitCommand = Get-Command $ExplicitPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($explicitCommand) { return $explicitCommand.Source }
        return $null
    }
    if ($CachedPath -and (Test-Path -LiteralPath $CachedPath -PathType Leaf)) {
        return [IO.Path]::GetFullPath($CachedPath)
    }
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $null
}

$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
$browserAuthRequested = [bool]($UseBrowserAuth -or $FirefoxProfileName)
$issues = [Collections.Generic.List[string]]::new()
$profile = $null
$firefoxRunning = @(Get-Process -Name firefox -ErrorAction SilentlyContinue).Count -gt 0

if ($browserAuthRequested) {
    if (-not $FirefoxProfileName) {
        $issues.Add('Browser authentication requires an explicit -FirefoxProfileName; the default or first Firefox profile is never selected implicitly.')
    } else {
        try {
            $profile = Resolve-FirefoxProfile -ProfileName $FirefoxProfileName
            if (-not $profile.CookiesDatabaseFound) {
                $issues.Add('The selected Firefox profile has no cookies.sqlite database.')
            }
        } catch {
            $issues.Add($_.Exception.Message)
        }
    }
    if ($firefoxRunning) {
        $issues.Add('Firefox must be fully closed before its authenticated session is read.')
    }
}

$node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
$nodeVersion = $null
$nodeVersionSupported = $false
if (-not $node) {
    $issues.Add('Node.js 22.0.0 or newer is required for YouTube EJS challenge solving.')
} else {
    $nodeVersion = ([string] (& $node.Source --version)).Trim()
    if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v?(?<major>\d+)(?:\.|$)') {
        $issues.Add('The Node.js version could not be determined.')
    } elseif ([int] $matches['major'] -lt 22) {
        $issues.Add("Node.js 22.0.0 or newer is required; found $nodeVersion.")
    } else {
        $nodeVersionSupported = $true
    }
}

$uv = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $uv) {
    $knownUv = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local\bin\uv.exe'
    if (Test-Path -LiteralPath $knownUv -PathType Leaf) {
        $uv = [pscustomobject]@{ Source = $knownUv }
    }
}

$cachedYtDlp = Join-Path $CacheRoot 'venv\Scripts\yt-dlp.exe'
$resolvedYtDlp = Resolve-CommandPath -ExplicitPath $YtDlpPath -CommandName 'yt-dlp' -CachedPath $cachedYtDlp
$ytDlpReady = [bool]($resolvedYtDlp -or $uv)
if (-not $ytDlpReady) { $issues.Add('Neither yt-dlp nor uv was found. Run setup_windows.ps1 or install uv.') }
if ($YtDlpPath -and -not $resolvedYtDlp) { $issues.Add('-YtDlpPath could not be resolved.') }

$cachedFfmpeg = Join-Path $CacheRoot 'bin\ffmpeg.exe'
$resolvedFfmpeg = Resolve-CommandPath -ExplicitPath $FfmpegPath -CommandName 'ffmpeg' -CachedPath $cachedFfmpeg
if (-not $SkipMedia -and -not $resolvedFfmpeg) {
    $issues.Add('ffmpeg was not found. Run setup_windows.ps1 or pass -FfmpegPath.')
}
if ($FfmpegPath -and -not $resolvedFfmpeg) { $issues.Add('-FfmpegPath could not be resolved.') }

$python = Join-Path $CacheRoot 'venv\Scripts\python.exe'
$whisper = Join-Path $CacheRoot 'venv\Scripts\whisper.exe'
$whisperRuntimeFound = (Test-Path -LiteralPath $python -PathType Leaf) -and (Test-Path -LiteralPath $whisper -PathType Leaf)
$whisperRuntime = $null
if ($whisperRuntimeFound) {
    $runtimeJson = & $python -c "import json, torch, whisper; print(json.dumps({'torch': torch.__version__, 'cuda_available': torch.cuda.is_available(), 'cuda_runtime': torch.version.cuda, 'gpu': torch.cuda.get_device_name(0) if torch.cuda.is_available() else None, 'turbo_available': 'turbo' in whisper.available_models()}))"
    if ($LASTEXITCODE -eq 0) {
        try { $whisperRuntime = $runtimeJson | ConvertFrom-Json } catch { $whisperRuntime = $null }
    }
}
if ($RequireWhisper -and -not $whisperRuntimeFound) {
    $issues.Add('The local Whisper runtime is missing. Run setup_windows.ps1 -WithWhisper.')
}
if ($RequireWhisper -and $whisperRuntimeFound -and -not $whisperRuntime) {
    $issues.Add('The local Whisper runtime could not import torch and whisper.')
}
if ($RequireCuda -and (-not $whisperRuntime -or -not $whisperRuntime.cuda_available)) {
    $issues.Add('CUDA is unavailable to the local Whisper runtime.')
}

if (-not $IsWindows) { $issues.Add('This helper supports Windows only.') }

[pscustomobject]@{
    Windows = $IsWindows
    PowerShell = $PSVersionTable.PSVersion.ToString()
    PublicAcquisitionReady = [bool]($IsWindows -and $nodeVersionSupported -and $ytDlpReady -and ($SkipMedia -or $resolvedFfmpeg))
    BrowserAuthenticationRequested = $browserAuthRequested
    FirefoxProfileName = if ($profile) { $profile.Name } else { $null }
    FirefoxProfileFound = [bool]$profile
    FirefoxCookiesDatabaseFound = [bool]($profile -and $profile.CookiesDatabaseFound)
    FirefoxRunning = $firefoxRunning
    NodePath = if ($node) { $node.Source } else { $null }
    NodeVersion = $nodeVersion
    NodeVersionSupported = $nodeVersionSupported
    UvPath = if ($uv) { $uv.Source } else { $null }
    YtDlpPath = $resolvedYtDlp
    FfmpegPath = $resolvedFfmpeg
    WhisperRuntimeFound = $whisperRuntimeFound
    WhisperRuntime = $whisperRuntime
    Issues = $issues.ToArray()
} | ConvertTo-Json -Depth 6

if ($issues.Count) { exit 2 }
