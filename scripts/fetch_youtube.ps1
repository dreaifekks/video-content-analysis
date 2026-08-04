#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Url,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputDir,
    [ValidateNotNullOrEmpty()][string]$FirefoxProfileName,
    [string]$YtDlpPath,
    [string]$FfmpegPath,
    [string]$FfprobePath,
    [string]$NodePath,
    [string]$SubtitleLanguages = 'en,zh-Hans,zh-Hant,ja,.*-orig',
    [ValidateScript({ $_ -eq 'infinite' -or $_ -match '^\d+$' })][string]$Retries = '10',
    [switch]$NoPlaylist,
    [switch]$SkipMedia,
    [switch]$LiveFromStart,
    [ValidateScript({ -not $_ -or $_ -match '^\d+(?:-\d+)?$' })][string]$WaitForVideo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Resolve-Executable {
    param(
        [string]$ExplicitPath,
        [Parameter(Mandatory)][string]$CommandName
    )

    $candidate = if ($ExplicitPath) { $ExplicitPath } else { $CommandName }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return [IO.Path]::GetFullPath($candidate)
    }

    $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Path
    }

    $hint = if ($ExplicitPath) {
        'Check the explicit binary path.'
    } else {
        "Install it and add it to PATH, or pass its explicit binary path."
    }
    throw "$CommandName was not found. $hint"
}

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
    param([Parameter(Mandatory)][string]$ProfileName)

    $firefoxRoot = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Mozilla\Firefox'
    $profilesIni = Join-Path $firefoxRoot 'profiles.ini'
    if (-not (Test-Path -LiteralPath $profilesIni -PathType Leaf)) {
        throw 'Firefox profiles.ini was not found.'
    }

    $profile = Get-IniSections -Path $profilesIni |
        Where-Object {
            $_.Name -like 'Profile*' -and
            $_.Values.Contains('Name') -and
            $_.Values['Name'] -eq $ProfileName
        } |
        Select-Object -First 1

    if (-not $profile) {
        throw "Firefox profile not found: $ProfileName"
    }
    if (-not $profile.Values.Contains('Path')) {
        throw "Firefox profile '$ProfileName' has no Path entry."
    }

    $profilePath = $profile.Values['Path']
    if ($profile.Values.Contains('IsRelative') -and $profile.Values['IsRelative'] -eq '1') {
        $profilePath = Join-Path $firefoxRoot $profilePath
    }
    $profilePath = [IO.Path]::GetFullPath($profilePath)

    if (-not (Test-Path -LiteralPath (Join-Path $profilePath 'cookies.sqlite') -PathType Leaf)) {
        throw "Firefox profile '$ProfileName' has no cookies.sqlite database."
    }
    $profilePath
}

try {
    $uri = [Uri]$Url
    if (-not $uri.IsAbsoluteUri) { throw 'not absolute' }
    $hostName = $uri.DnsSafeHost.ToLowerInvariant()
} catch {
    throw 'Url must be a valid absolute HTTPS YouTube URL.'
}

$validYouTubeHost =
    $hostName -eq 'youtu.be' -or
    $hostName -eq 'youtube.com' -or
    $hostName.EndsWith('.youtube.com')
if ($uri.Scheme -ne 'https' -or -not $validYouTubeHost) {
    throw 'Url must use https://youtube.com, a YouTube subdomain, or https://youtu.be.'
}

$OutputDir = [IO.Path]::GetFullPath($OutputDir)
if ($OutputDir -eq [IO.Path]::GetPathRoot($OutputDir)) {
    throw 'OutputDir must be a dedicated directory, not a drive root.'
}

$ytDlp = Resolve-Executable -ExplicitPath $YtDlpPath -CommandName 'yt-dlp'
$ffmpeg = Resolve-Executable -ExplicitPath $FfmpegPath -CommandName 'ffmpeg'
$ffprobe = Resolve-Executable -ExplicitPath $FfprobePath -CommandName 'ffprobe'
$node = Resolve-Executable -ExplicitPath $NodePath -CommandName 'node'

$nodeVersion = ([string] (& $node --version)).Trim()
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v?(?<major>\d+)(?:\.|$)') {
    throw 'The Node.js version could not be determined.'
}
if ([int]$matches['major'] -lt 22) {
    throw "Node.js 22.0.0 or newer is required; found $nodeVersion."
}

$toolDirectories = @(
    Split-Path -Parent $node
    Split-Path -Parent $ffmpeg
    Split-Path -Parent $ffprobe
) | Select-Object -Unique
$env:PATH = (($toolDirectories + $env:PATH) -join [IO.Path]::PathSeparator)

$firefoxProfilePath = $null
if ($FirefoxProfileName) {
    if (@(Get-Process -Name firefox -ErrorAction SilentlyContinue).Count) {
        throw 'Firefox is running. Fully exit Firefox before reading its authenticated session.'
    }
    $firefoxProfilePath = Resolve-FirefoxProfile -ProfileName $FirefoxProfileName
    $authMode = "Firefox profile '$FirefoxProfileName'"
} else {
    $authMode = 'none'
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$ytArgs = @(
    '--ignore-config',
    '--newline',
    '--ignore-errors',
    '--continue',
    '--retries', $Retries,
    '--fragment-retries', $Retries,
    '--extractor-retries', $Retries,
    '--retry-sleep', '5',
    '--js-runtimes', 'node',
    '--remote-components', 'ejs:github',
    '-P', $OutputDir,
    '-o', '%(upload_date)s_%(title).160B_%(id)s.%(ext)s',
    '--write-description',
    '--write-info-json',
    '--clean-info-json',
    '--write-thumbnail',
    '--write-subs',
    '--write-auto-subs',
    '--sub-langs', $SubtitleLanguages,
    '--sub-format', 'vtt/srt/best'
)

if ($NoPlaylist) {
    $ytArgs += '--no-playlist'
} else {
    $ytArgs += '--yes-playlist'
}

if ($SkipMedia) {
    $ytArgs += '--skip-download'
} else {
    $ytArgs += @(
        '--download-archive', (Join-Path $OutputDir 'archive.txt'),
        '--embed-metadata',
        '--merge-output-format', 'mkv',
        '--remux-video', 'mkv'
    )
}

if ($firefoxProfilePath) {
    $ytArgs += @('--cookies-from-browser', "firefox:$firefoxProfilePath")
}
if ($LiveFromStart) {
    $ytArgs += '--live-from-start'
}
if ($WaitForVideo) {
    $ytArgs += @('--wait-for-video', $WaitForVideo)
}

Write-Host 'Acquiring YouTube source'
Write-Host "Output directory: $OutputDir"
Write-Host "Authentication: $authMode"
Write-Host "Caption languages: $SubtitleLanguages"

& $ytDlp @ytArgs $Url
$ytDlpExitCode = $LASTEXITCODE

$files = @(Get-ChildItem -LiteralPath $OutputDir -File -ErrorAction SilentlyContinue)
$media = @($files | Where-Object {
    $_.Extension.ToLowerInvariant() -in @('.mkv', '.mp4', '.webm', '.mov', '.m4v')
})
$subtitles = @($files | Where-Object {
    $_.Extension.ToLowerInvariant() -in @('.vtt', '.srt', '.ass', '.srv3')
})
$metadata = @($files | Where-Object { $_.Name -like '*.info.json' })
$thumbnails = @($files | Where-Object {
    $_.Extension.ToLowerInvariant() -in @('.jpg', '.jpeg', '.png', '.webp')
})

Write-Host ''
Write-Host 'Acquisition summary'
Write-Host "Media files: $($media.Count)"
Write-Host "Caption files: $($subtitles.Count)"
Write-Host "Metadata files: $($metadata.Count)"
Write-Host "Thumbnail files: $($thumbnails.Count)"

if ($ytDlpExitCode -ne 0) {
    [Console]::Error.WriteLine(
        "yt-dlp exited with status $ytDlpExitCode; inspect successful and failed items before analysis."
    )
    exit $ytDlpExitCode
}
if (-not $SkipMedia -and -not $media.Count) {
    throw 'No media files were acquired.'
}
if ($SkipMedia -and -not $metadata.Count -and -not $subtitles.Count) {
    throw 'No metadata or captions were acquired.'
}

Write-Host 'Acquisition complete. Continue with caption selection, local transcription if needed, frame sampling, and analysis.'
