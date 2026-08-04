# Windows Setup and YouTube Acquisition

## Platform Contract

Use native Windows with PowerShell 7. The validated route uses:

- `uv` for a managed Python 3.12 environment and current `yt-dlp`;
- Node.js 22.0.0 or newer for yt-dlp's YouTube EJS challenge components;
- FFmpeg from `PATH` or the skill-managed cache, with FFprobe used when separately available;
- OpenAI Whisper with CUDA-enabled PyTorch on a supported NVIDIA GPU.

Do not substitute WSL for this workflow. Keep the runtime cache under `%LOCALAPPDATA%\CodexSkills\video-content-analysis`; never commit it to the skill repository.

Set the canonical skill path before using the examples:

```powershell
$skillPath = Join-Path $HOME '.codex\skills\video-content-analysis'
```

## Preflight

Run:

```powershell
& "$skillPath\scripts\preflight.ps1"
```

For content that requires the user's YouTube session:

```powershell
& "$skillPath\scripts\preflight.ps1" `
  -FirefoxProfileName 'CodexYouTubeMember'
```

Resolve blocking results before acquisition. Public videos do not require a Firefox profile or cookies.

## Dedicated Firefox Profile

Use a dedicated normal Firefox profile for restricted or member content:

1. Open Firefox's profile manager with `firefox.exe -P`.
2. Create a profile such as `CodexYouTubeMember`.
3. Sign in to YouTube and verify that the profile can play the requested content.
4. Fully exit every Firefox process before cookie extraction.

The scripts resolve the profile through Firefox's `profiles.ini`. They must never display cookie values. Do not use Private Browsing because its temporary session is not a stable acquisition source.

Use no browser authentication for public content. Add `-FirefoxProfileName` only after the user authorizes reuse of that local session.
The scripts require the profile name explicitly and reject `-UseBrowserAuth` by itself, so they never fall back to the default or first Firefox profile. Use `firefox.exe -P` to confirm the dedicated profile's name.

Do not install cookie-export extensions, change Chrome policies, or copy cookie-decryption helpers into trusted locations. Chromium cookie format changes can break direct extraction; the dedicated Firefox route avoids that fragile path without weakening local browser security.

## Tool Setup

Install Node.js 22.0.0 or newer and `uv` through the user's preferred Windows package manager if they are absent. Then provision the skill-managed FFmpeg runtime:

```powershell
& "$skillPath\scripts\setup_windows.ps1"
```

Local Whisper additionally downloads several gigabytes. Obtain approval before the first setup:

```powershell
& "$skillPath\scripts\setup_windows.ps1" -WithWhisper
```

The Whisper route uses a managed Python 3.12 virtual environment, CUDA-enabled PyTorch, the `turbo` model by default, and the local NVIDIA GPU when available.

For a Windows machine without a compatible NVIDIA GPU, use the slower explicit CPU route:

```powershell
& "$skillPath\scripts\setup_windows.ps1" `
  -WithWhisper `
  -TorchIndexUrl 'https://download.pytorch.org/whl/cpu'
& "$skillPath\scripts\transcribe_local_whisper.ps1" `
  -InputPath 'C:\path\video.mkv' `
  -Cpu
```

## Acquisition

Public video, Short, replay, or playlist:

```powershell
& "$skillPath\scripts\fetch_youtube.ps1" `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir' `
  -NoPlaylist
```

Restricted content available in the dedicated Firefox profile:

```powershell
& "$skillPath\scripts\fetch_youtube.ps1" `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir' `
  -FirefoxProfileName 'CodexYouTubeMember' `
  -NoPlaylist
```

Ordinary watch, Short, live, and youtu.be URLs default to one item even when they contain `list=`. An explicit `/playlist` URL defaults to playlist mode; pass `-IncludePlaylist` when the user explicitly wants the playlist attached to a watch URL. For a running or scheduled live, use the script's live-from-start and wait controls only when the user wants those behaviors. Keep one dedicated output directory per unrelated request.

The helper writes locally:

- video media, normally merged or remuxed to MKV;
- human and automatic captions exposed by YouTube;
- info JSON, descriptions, and thumbnails;
- `archive.txt` for repeat-run deduplication.

It uses a current yt-dlp route with Node EJS components. Repeat runs should preserve completed files, resume partial work where supported, and skip video IDs already recorded in the archive.

## Caption and Transcription Selection

1. Prefer a human caption in the source language.
2. Use an automatic caption when no human caption exists and mark it as noisy evidence.
3. Inspect `subtitles` and `automatic_captions` in info JSON before deciding that captions are unavailable.
4. Retry a focused subtitle language when a useful track exists but was not selected.
5. Run `scripts/transcribe_local_whisper.ps1` only when captions remain absent or inadequate.

Retry a targeted caption without redownloading media or being blocked by `archive.txt`:

```powershell
& "$skillPath\scripts\fetch_youtube.ps1" `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\the-same-analysis-workdir' `
  -SubtitleLanguages 'es' `
  -SkipMedia
```

Do not download every automatic translation by default; broad selection can create many files and trigger rate limits.

## Failure Triage

1. Check PowerShell 7, Node.js, `uv`, FFmpeg, and the managed cache with `preflight.ps1`.
2. Update yt-dlp before deeper extraction diagnosis; YouTube changes frequently.
3. Distinguish public availability from authenticated availability. Do not add cookies blindly.
4. If authenticated acquisition fails, verify the requested profile exists, can play the video, and Firefox is fully closed.
5. For a scheduled live, enable the wait control. For a running live, use live-from-start only when full capture from the beginning is intended.
6. If media succeeds but captions are absent, continue with local transcription.
7. If a playlist partially fails, preserve successful items and read the timestamped `acquisition-*.errors.log`. Report video IDs named there and disclose any error whose ID cannot be recovered.

Treat downloaded metadata as local evidence. Even cleaned info JSON may contain fields that should not be published without review.
