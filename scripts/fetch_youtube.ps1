#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Url,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputDir,
    [switch]$UseBrowserAuth,
    [string]$FirefoxProfileName,
    [string]$YtDlpPath,
    [string]$FfmpegPath,
    [string]$CacheRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexSkills\video-content-analysis'),
    [string]$SubtitleLanguages = 'en,zh-Hans,zh-Hant,ja,.*-orig',
    [ValidateScript({ $_ -eq 'infinite' -or $_ -match '^\d+$' })][string]$Retries = '10',
    [switch]$NoPlaylist,
    [switch]$IncludePlaylist,
    [switch]$SkipMedia,
    [switch]$LiveFromStart,
    [ValidateScript({ -not $_ -or $_ -match '^\d+(?:-\d+)?$' })][string]$WaitForVideo
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
    if (-not (Test-Path -LiteralPath (Join-Path $profilePath 'cookies.sqlite') -PathType Leaf)) {
        throw 'The selected Firefox profile has no cookies.sqlite database.'
    }
    $resolvedName = if ($profile.Values.Contains('Name')) { $profile.Values['Name'] } else { $profile.Name }

    [pscustomobject]@{ Name = $resolvedName; Path = $profilePath }
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
        throw "$CommandName could not be resolved from the explicit path or command name."
    }
    if ($CachedPath -and (Test-Path -LiteralPath $CachedPath -PathType Leaf)) {
        return [IO.Path]::GetFullPath($CachedPath)
    }
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $null
}

function Resolve-YtDlpInvocation {
    param([string]$ExplicitPath, [Parameter(Mandatory)][string]$LocalCacheRoot)

    $cachedYtDlp = Join-Path $LocalCacheRoot 'venv\Scripts\yt-dlp.exe'
    $directPath = Resolve-CommandPath -ExplicitPath $ExplicitPath -CommandName 'yt-dlp' -CachedPath $cachedYtDlp
    if ($directPath) {
        return [pscustomobject]@{ Program = $directPath; Prefix = [string[]]@(); Source = 'direct' }
    }

    $uv = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $uv) {
        $knownUv = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local\bin\uv.exe'
        if (Test-Path -LiteralPath $knownUv -PathType Leaf) {
            $uv = [pscustomobject]@{ Source = $knownUv }
        }
    }
    if (-not $uv) { throw 'Neither yt-dlp nor uv was found. Run setup_windows.ps1 or install uv.' }
    [pscustomobject]@{
        Program = $uv.Source
        Prefix = [string[]]@('tool','run','--from','yt-dlp','yt-dlp')
        Source = 'uv tool run'
    }
}

try { $uri = [Uri]$Url } catch { throw 'Url must be a valid HTTPS YouTube URL.' }
$hostName = $uri.DnsSafeHost.ToLowerInvariant()
$validYouTubeHost = $hostName -eq 'youtu.be' -or $hostName -eq 'youtube.com' -or $hostName.EndsWith('.youtube.com')
if ($uri.Scheme -ne 'https' -or -not $validYouTubeHost) {
    throw 'Url must use https://youtube.com, a YouTube subdomain, or https://youtu.be.'
}
if ($NoPlaylist -and $IncludePlaylist) {
    throw 'Choose either -NoPlaylist or -IncludePlaylist, not both.'
}
$explicitPlaylistUrl = $uri.AbsolutePath.TrimEnd('/') -eq '/playlist'
$playlistMode = if ($IncludePlaylist -or (-not $NoPlaylist -and $explicitPlaylistUrl)) {
    'playlist'
} else {
    'single video'
}

$OutputDir = [IO.Path]::GetFullPath($OutputDir)
if ($OutputDir -eq [IO.Path]::GetPathRoot($OutputDir)) {
    throw 'OutputDir must be a dedicated directory, not a drive root.'
}
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)

$browserAuthRequested = [bool]($UseBrowserAuth -or $FirefoxProfileName)
if ($browserAuthRequested -and -not $FirefoxProfileName) {
    throw 'Browser authentication requires an explicit -FirefoxProfileName; the default or first Firefox profile is never selected implicitly.'
}

$profile = $null
if ($browserAuthRequested) {
    if (@(Get-Process -Name firefox -ErrorAction SilentlyContinue).Count) {
        throw 'Firefox is running. Fully exit Firefox before reading its authenticated session.'
    }
    $profile = Resolve-FirefoxProfile -ProfileName $FirefoxProfileName
    $authMode = 'Firefox browser session'
} else {
    $authMode = 'none'
}

$node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $node) { throw 'Node.js 22.0.0 or newer is required for YouTube EJS challenge solving.' }
$nodeVersion = ([string] (& $node.Source --version)).Trim()
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v?(?<major>\d+)(?:\.|$)') {
    throw 'The Node.js version could not be determined.'
}
if ([int] $matches['major'] -lt 22) {
    throw "Node.js 22.0.0 or newer is required; found $nodeVersion."
}
$env:PATH = "$(Split-Path -Parent $node.Source);$env:PATH"

$ytDlp = Resolve-YtDlpInvocation -ExplicitPath $YtDlpPath -LocalCacheRoot $CacheRoot

$resolvedFfmpeg = $null
$ffprobe = $null
if (-not $SkipMedia) {
    $cachedFfmpeg = Join-Path $CacheRoot 'bin\ffmpeg.exe'
    $resolvedFfmpeg = Resolve-CommandPath -ExplicitPath $FfmpegPath -CommandName 'ffmpeg' -CachedPath $cachedFfmpeg
    if (-not $resolvedFfmpeg) {
        throw 'ffmpeg was not found. Run setup_windows.ps1 or pass -FfmpegPath.'
    }

    $ffprobeCommand = Get-Command ffprobe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ffprobeCommand) {
        $ffprobe = $ffprobeCommand.Source
    } else {
        $siblingFfprobe = Join-Path (Split-Path -Parent $resolvedFfmpeg) 'ffprobe.exe'
        if (Test-Path -LiteralPath $siblingFfprobe -PathType Leaf) { $ffprobe = $siblingFfprobe }
    }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$ytArgs = @(
    '--ignore-config',
    '--no-plugin-dirs',
    '--js-runtimes', 'node',
    '--remote-components', 'ejs:github',
    '--newline',
    '--no-abort-on-error',
    '--continue',
    '--retries', $Retries,
    '--fragment-retries', $Retries,
    '--extractor-retries', $Retries,
    '--retry-sleep', '5',
    '-P', $OutputDir,
    '-o', '%(upload_date)s_%(title).160B_%(id)s.%(ext)s',
    '--write-description',
    '--write-info-json',
    '--clean-info-json',
    '--write-thumbnail',
    '--write-subs',
    '--write-auto-subs',
    '--sub-langs', $SubtitleLanguages,
    '--sub-format', 'vtt/srt/best',
    '--progress-delta', '5'
)

if ($playlistMode -eq 'playlist') { $ytArgs += '--yes-playlist' } else { $ytArgs += '--no-playlist' }

if ($SkipMedia) {
    $ytArgs += '--skip-download'
} else {
    $ytArgs += @(
        '--download-archive', (Join-Path $OutputDir 'archive.txt'),
        '-f', 'bestvideo*+bestaudio/best',
        '--merge-output-format', 'mkv',
        '--remux-video', 'mkv',
        '--ffmpeg-location', $resolvedFfmpeg
    )
    if ($ffprobe) { $ytArgs += '--embed-metadata' } else { $ytArgs += '--no-embed-metadata' }
}

if ($profile) {
    $ytArgs += @('--cookies-from-browser', "firefox:$($profile.Path)")
}
if ($LiveFromStart) { $ytArgs += '--live-from-start' }
if ($WaitForVideo) { $ytArgs += @('--wait-for-video', $WaitForVideo) }

Write-Host 'Acquiring YouTube source'
Write-Host "Output directory: $OutputDir"
Write-Host "Authentication: $authMode"
Write-Host "Caption languages: $SubtitleLanguages"

$invokeArgs = @($ytDlp.Prefix) + $ytArgs + @($Url)
$runStamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')
$acquisitionLog = Join-Path $OutputDir "acquisition-$runStamp.log"
$errorLog = Join-Path $OutputDir "acquisition-$runStamp.errors.log"
& $ytDlp.Program @invokeArgs 2>&1 | Tee-Object -FilePath $acquisitionLog
$ytDlpExitCode = $LASTEXITCODE
$errorLines = @(
    Select-String -LiteralPath $acquisitionLog -Pattern '(?i)(^|\s)ERROR:' |
        ForEach-Object { $_.Line }
)
[IO.File]::WriteAllLines($errorLog, [string[]] $errorLines, [Text.UTF8Encoding]::new($false))

$files = @(Get-ChildItem -LiteralPath $OutputDir -File -Recurse -ErrorAction SilentlyContinue)
$media = @($files | Where-Object { $_.Extension.ToLowerInvariant() -in @('.mkv','.mp4','.webm','.mov','.m4v') })
$subtitles = @($files | Where-Object { $_.Extension.ToLowerInvariant() -in @('.vtt','.srt','.ass','.srv3') })
$metadata = @($files | Where-Object { $_.Name -like '*.info.json' })
$thumbnails = @($files | Where-Object { $_.Extension.ToLowerInvariant() -in @('.jpg','.jpeg','.png','.webp') })
$partials = @($files | Where-Object { $_.Extension.ToLowerInvariant() -in @('.part','.ytdl') })
$mediaBytes = if ($media.Count) { ($media | Measure-Object Length -Sum).Sum } else { 0 }

$summary = [pscustomobject]@{
    OutputDirectory = $OutputDir
    Authentication = $authMode
    PlaylistMode = $playlistMode
    FirefoxProfileName = if ($profile) { $profile.Name } else { $null }
    YtDlpSource = $ytDlp.Source
    YtDlpExitCode = $ytDlpExitCode
    CompletedWithErrors = [bool]($ytDlpExitCode -ne 0)
    AcquisitionLog = $acquisitionLog
    ErrorLog = $errorLog
    ErrorCount = $errorLines.Count
    MediaCount = $media.Count
    MediaBytes = $mediaBytes
    SubtitleCount = $subtitles.Count
    MetadataCount = $metadata.Count
    ThumbnailCount = $thumbnails.Count
    PartialFileCount = $partials.Count
    Archive = if ($SkipMedia) { $null } else { Join-Path $OutputDir 'archive.txt' }
    MetadataEmbedded = [bool]$ffprobe
}
$summary | ConvertTo-Json -Depth 4

if ($ytDlpExitCode -ne 0) {
    throw "yt-dlp reported one or more acquisition or post-processing failures (exit $ytDlpExitCode). Preserve successful files, review $errorLog, and treat a playlist as partial."
}
if ($partials.Count) { throw "Partial download files remain in $OutputDir." }
if (-not $SkipMedia -and -not $media.Count) { throw 'No media files were acquired.' }
if ($SkipMedia -and -not $metadata.Count -and -not $subtitles.Count) {
    throw 'No metadata or captions were acquired.'
}
