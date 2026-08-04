#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$InputPath,
    [string]$OutputDir,
    [string]$BaseName,
    [string]$Model = 'turbo',
    [string]$ModelDirectory,
    [string]$Language,
    [ValidateSet('vtt', 'srt', 'txt')][string]$OutputFormat = 'vtt',
    [string]$InitialPrompt,
    [ValidateSet('auto', 'cuda', 'cpu')][string]$Device = 'auto',
    [string]$FfmpegPath,
    [string]$WhisperPath
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

$InputPath = [IO.Path]::GetFullPath($InputPath)
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}

if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path -Parent $InputPath) 'transcripts'
}
$OutputDir = [IO.Path]::GetFullPath($OutputDir)

if (-not $BaseName) {
    $BaseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
}
if ($BaseName -in @('.', '..') -or
    $BaseName -match '[\\/]' -or
    $BaseName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw 'BaseName must be one safe Windows file name without a directory component.'
}

$ffmpeg = Resolve-Executable -ExplicitPath $FfmpegPath -CommandName 'ffmpeg'
$whisper = Resolve-Executable -ExplicitPath $WhisperPath -CommandName 'whisper'

$audioDir = Join-Path $OutputDir 'audio'
$segmentsDir = Join-Path $OutputDir 'segments'
New-Item -ItemType Directory -Path $audioDir, $segmentsDir -Force | Out-Null

$audioPath = Join-Path $audioDir "$BaseName.local.mp3"
& $ffmpeg -y -hide_banner -loglevel error -i $InputPath -vn -ac 1 -ar 16000 -b:a 64k $audioPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $audioPath -PathType Leaf)) {
    throw 'ffmpeg audio extraction failed.'
}

$whisperArgs = @(
    $audioPath,
    '--model', $Model,
    '--task', 'transcribe',
    '--output_dir', $segmentsDir,
    '--output_format', $OutputFormat,
    '--verbose', 'False',
    '--condition_on_previous_text', 'False'
)
if ($Language) {
    $whisperArgs += @('--language', $Language)
}
if ($ModelDirectory) {
    $modelDirectoryPath = [IO.Path]::GetFullPath($ModelDirectory)
    New-Item -ItemType Directory -Path $modelDirectoryPath -Force | Out-Null
    $whisperArgs += @('--model_dir', $modelDirectoryPath)
}
if ($InitialPrompt) {
    $whisperArgs += @('--initial_prompt', $InitialPrompt)
}
if ($Device -eq 'cuda') {
    $whisperArgs += @('--device', 'cuda')
} elseif ($Device -eq 'cpu') {
    $whisperArgs += @('--device', 'cpu', '--fp16', 'False')
}

$ffmpegDirectory = Split-Path -Parent $ffmpeg
$originalPath = $env:PATH
try {
    $env:PATH = "$ffmpegDirectory$([IO.Path]::PathSeparator)$originalPath"
    & $whisper @whisperArgs
    $whisperExitCode = $LASTEXITCODE
} finally {
    $env:PATH = $originalPath
}
if ($whisperExitCode -ne 0) {
    throw "Whisper failed with exit code $whisperExitCode"
}

$audioStem = [IO.Path]::GetFileNameWithoutExtension($audioPath)
$rawTranscript = Join-Path $segmentsDir "$audioStem.$OutputFormat"
if (-not (Test-Path -LiteralPath $rawTranscript -PathType Leaf)) {
    throw "Expected transcript output was not found: $rawTranscript"
}

$combined = Join-Path $OutputDir "$BaseName.local-whisper.transcript.md"
$sourceLabel = [IO.Path]::GetFileName($InputPath)
$effectiveLanguage = if ($Language) { $Language } else { 'auto' }
$header = @(
    '# Local Whisper Transcript',
    '',
    "- Source: $sourceLabel",
    '- Engine: OpenAI Whisper (local)',
    "- Model: $Model",
    "- Device: $Device",
    "- Language: $effectiveLanguage",
    "- Format: $OutputFormat",
    '',
    '## Transcript',
    ''
)
$body = Get-Content -Raw -LiteralPath $rawTranscript
$content = (($header -join "`r`n") + "`r`n" + $body).TrimEnd() + "`r`n"
[IO.File]::WriteAllText($combined, $content, [Text.UTF8Encoding]::new($false))

Write-Host 'Transcript complete:'
Write-Host $combined
