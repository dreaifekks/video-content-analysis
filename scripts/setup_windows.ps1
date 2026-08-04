#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$CacheRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexSkills\video-content-analysis'),
    [string]$PythonVersion = '3.12',
    [switch]$WithWhisper,
    [string]$TorchIndexUrl = 'https://download.pytorch.org/whl/cu128'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
if ($CacheRoot -eq [IO.Path]::GetPathRoot($CacheRoot)) {
    throw 'CacheRoot must be a dedicated directory, not a drive root.'
}

$uvCommand = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
if ($uvCommand) {
    $uvPath = $uvCommand.Source
} else {
    $knownUv = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local\bin\uv.exe'
    if (-not (Test-Path -LiteralPath $knownUv -PathType Leaf)) {
        throw 'uv is required. Install uv, then rerun this setup script.'
    }
    $uvPath = $knownUv
}

$venvPath = Join-Path $CacheRoot 'venv'
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
$ytDlpPath = Join-Path $venvPath 'Scripts\yt-dlp.exe'
$whisperPath = Join-Path $venvPath 'Scripts\whisper.exe'
$binDir = Join-Path $CacheRoot 'bin'
$modelDir = Join-Path $CacheRoot 'models\whisper'
New-Item -ItemType Directory -Path $CacheRoot,$binDir,$modelDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    & $uvPath venv $venvPath --python $PythonVersion
    if ($LASTEXITCODE -ne 0) { throw "Failed to create the Python $PythonVersion environment." }
}

& $uvPath pip install --upgrade --python $venvPython yt-dlp imageio-ffmpeg
if ($LASTEXITCODE -ne 0) { throw 'Failed to install yt-dlp and imageio-ffmpeg.' }

$bundledFfmpeg = (& $venvPython -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())').Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $bundledFfmpeg -PathType Leaf)) {
    throw 'imageio-ffmpeg did not provide a usable ffmpeg executable.'
}
$ffmpegPath = Join-Path $binDir 'ffmpeg.exe'
Copy-Item -LiteralPath $bundledFfmpeg -Destination $ffmpegPath -Force

if ($WithWhisper) {
    & $uvPath pip install --upgrade --python $venvPython torch --index-url $TorchIndexUrl
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install PyTorch.' }

    & $uvPath pip install --upgrade --python $venvPython openai-whisper
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install OpenAI Whisper.' }
}

$whisperInstalled = Test-Path -LiteralPath $whisperPath -PathType Leaf
$runtime = $null
if ($whisperInstalled) {
    $runtimeJson = & $venvPython -c "import json, torch, whisper; print(json.dumps({'torch': torch.__version__, 'cuda_available': torch.cuda.is_available(), 'cuda_runtime': torch.version.cuda, 'gpu': torch.cuda.get_device_name(0) if torch.cuda.is_available() else None, 'turbo_available': 'turbo' in whisper.available_models()}))"
    if ($LASTEXITCODE -ne 0) { throw 'OpenAI Whisper or PyTorch could not be imported.' }
    $runtime = $runtimeJson | ConvertFrom-Json
}

$node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
$ytDlpVersion = if (Test-Path -LiteralPath $ytDlpPath -PathType Leaf) { (& $ytDlpPath --version).Trim() } else { $null }

[pscustomobject]@{
    CacheRoot = $CacheRoot
    Python = $venvPython
    YtDlp = $ytDlpPath
    YtDlpVersion = $ytDlpVersion
    Ffmpeg = $ffmpegPath
    ModelDirectory = $modelDir
    WhisperInstalled = $whisperInstalled
    WhisperRuntime = $runtime
    NodePath = if ($node) { $node.Source } else { $null }
    NodeRequiredForAcquisition = $true
} | ConvertTo-Json -Depth 6
