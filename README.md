# Video Content Analysis for Windows

A Codex skill for acquiring and analyzing YouTube videos on Windows. It covers the local workflow from `yt-dlp` acquisition through caption extraction, optional local Whisper transcription, adaptive frame sampling, and timestamped analysis.

## Features

- Acquire videos, Shorts, livestreams, scheduled lives, member content the user can lawfully access, and playlists.
- Save media, metadata, descriptions, thumbnails, and available captions locally.
- Use local Whisper only when platform captions are missing or inadequate.
- Adapt screenshot frequency to visual-change density.
- Accept `auto`, `low`, `standard`, `high`, or `max` visual-analysis intensity.
- Keep backup, cloud sync, report publishing, and access-control bypass outside the skill.

## Platform

- Target: native Windows with PowerShell 7.
- Acquisition: current `yt-dlp`, `ffmpeg`, `ffprobe`, and Node.js 22 or newer.
- Local transcription: OpenAI Whisper CLI plus a compatible PyTorch installation; CUDA is preferred when available, and CPU can be selected explicitly.
- macOS, Linux, and WSL are outside the validated scope of this branch.

## Install as a Codex Skill

Ask Codex to install the Windows branch:

```text
Use $skill-installer to install video-content-analysis from
dreaifekks/video-content-analysis, ref agent/windows-support,
path ., with the name video-content-analysis.
```

Or clone the branch directly with PowerShell:

```powershell
$destination = Join-Path $HOME '.codex\skills\video-content-analysis'
git clone --branch agent/windows-support --single-branch `
  https://github.com/dreaifekks/video-content-analysis.git `
  $destination
```

Install the complete repository directory, not only `SKILL.md`. The skill becomes available on the next Codex turn; restart Codex if it does not appear.

## Use

Invoke the skill explicitly and optionally add a visual-analysis intensity:

```text
$video-content-analysis high "YOUTUBE_URL"
```

Without an intensity token, the skill uses `auto` and probes visual-change density before sampling.

| Intensity | Intended use |
| --- | --- |
| `auto` | Detect visual-change density and choose a profile. |
| `low` | Mostly static or visually simple material. |
| `standard` | General video analysis. |
| `high` | Trading charts, dashboards, code, dense slides, and demonstrations. |
| `max` | The densest useful sampling for exhaustive review. |

There is no default total-frame limit. Intensity controls the candidate interval and change threshold; it does not export every encoded video frame or duplicate unchanged frames. Use `-FrameCount` only when an explicit hard limit is needed.

The acquisition helper can also be run directly:

```powershell
& .\scripts\fetch_youtube.ps1 `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir'
```

For content available through the user's dedicated Firefox profile:

```powershell
& .\scripts\fetch_youtube.ps1 `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir' `
  -FirefoxProfileName 'CodexYouTubeMember'
```

Authentication only reuses access the user already has. Keep the browser profile device-local, fully exit Firefox before acquisition, and never commit cookies to the repository.

## License

Licensed under the [Apache License 2.0](LICENSE), SPDX identifier `Apache-2.0`.
