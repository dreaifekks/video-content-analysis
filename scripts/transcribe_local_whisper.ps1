#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$InputPath,
    [string]$OutputDir,
    [string]$BaseName,
    [string]$Model = 'turbo',
    [string]$Language,
    [ValidateSet('vtt','srt','txt')][string]$OutputFormat = 'vtt',
    [string]$InitialPrompt,
    [string]$CacheRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexSkills\video-content-analysis'),
    [switch]$Cpu
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InputPath = [IO.Path]::GetFullPath($InputPath)
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}
if (-not $OutputDir) { $OutputDir = Join-Path (Split-Path -Parent $InputPath) 'transcripts' }
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
if (-not $BaseName) { $BaseName = [IO.Path]::GetFileNameWithoutExtension($InputPath) }
if ($BaseName -in @('.','..') -or $BaseName -match '[\\/]' -or $BaseName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw 'BaseName must be one safe Windows file name without a directory component.'
}

$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
$python = Join-Path $CacheRoot 'venv\Scripts\python.exe'
$whisper = Join-Path $CacheRoot 'venv\Scripts\whisper.exe'
$ffmpeg = Join-Path $CacheRoot 'bin\ffmpeg.exe'
$modelDir = Join-Path $CacheRoot 'models\whisper'
foreach ($required in @($python,$whisper,$ffmpeg)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw 'The Whisper runtime is incomplete. Run setup_windows.ps1 -WithWhisper first.'
    }
}

$runtimeJson = & $python -c "import json, sys, torch, whisper; model = sys.argv[1]; print(json.dumps({'torch': torch.__version__, 'cuda_available': torch.cuda.is_available(), 'cuda_runtime': torch.version.cuda, 'gpu': torch.cuda.get_device_name(0) if torch.cuda.is_available() else None, 'model_available': model in whisper.available_models()}))" $Model
if ($LASTEXITCODE -ne 0) { throw 'OpenAI Whisper or PyTorch could not be imported.' }
$runtime = $runtimeJson | ConvertFrom-Json
if (-not $runtime.model_available) { throw "Unknown OpenAI Whisper model: $Model" }
if (-not $Cpu -and -not $runtime.cuda_available) {
    throw 'CUDA is unavailable. Install a compatible NVIDIA PyTorch runtime or explicitly pass -Cpu.'
}

$audioDir = Join-Path $OutputDir 'audio'
$segmentsDir = Join-Path $OutputDir 'segments'
New-Item -ItemType Directory -Path $audioDir,$segmentsDir,$modelDir -Force | Out-Null
$audioPath = Join-Path $audioDir "$BaseName.local.mp3"

& $ffmpeg -y -hide_banner -loglevel error -i $InputPath -vn -ac 1 -ar 16000 -b:a 64k $audioPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $audioPath -PathType Leaf)) {
    throw 'ffmpeg audio extraction failed.'
}

$env:PATH = "$(Split-Path -Parent $ffmpeg);$env:PATH"
$whisperArgs = @(
    $audioPath,
    '--model', $Model,
    '--model_dir', $modelDir,
    '--task', 'transcribe',
    '--output_dir', $segmentsDir,
    '--output_format', $OutputFormat,
    '--verbose', 'False',
    '--condition_on_previous_text', 'False'
)
if ($Language) { $whisperArgs += @('--language', $Language) }
if ($InitialPrompt) { $whisperArgs += @('--initial_prompt', $InitialPrompt) }
if ($Cpu) {
    $whisperArgs += @('--device','cpu','--fp16','False')
    $device = 'CPU'
} else {
    $whisperArgs += @('--device','cuda')
    $device = $runtime.gpu
}

& $whisper @whisperArgs
if ($LASTEXITCODE -ne 0) { throw "Whisper failed with exit code $LASTEXITCODE" }

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
    "- Device: $device",
    "- Language: $effectiveLanguage",
    "- Format: $OutputFormat",
    '- condition_on_previous_text: False',
    '',
    '## Transcript',
    ''
)
$body = Get-Content -Raw -LiteralPath $rawTranscript
Set-Content -LiteralPath $combined -Value (($header -join "`r`n") + "`r`n" + $body) -Encoding utf8

[pscustomobject]@{
    Transcript = $combined
    RawTranscript = $rawTranscript
    Audio = $audioPath
    Model = $Model
    Device = $device
    Language = $effectiveLanguage
    OutputFormat = $OutputFormat
} | ConvertTo-Json -Depth 4
