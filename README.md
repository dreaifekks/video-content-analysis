# Video Content Analysis

A cross-platform Codex skill for acquiring and analyzing YouTube videos locally. It covers `yt-dlp` acquisition, caption selection, optional local Whisper transcription, adaptive frame sampling, and timestamped evidence-aware analysis.

This branch adds a native Windows PowerShell workflow while retaining the existing macOS workflow.

## Features

- Acquire videos, Shorts, livestreams, scheduled lives, playlists, and member content the user's account can lawfully access.
- Save media, metadata, descriptions, thumbnails, and available captions locally.
- Prefer platform captions and transcribe only when they are missing or inadequate.
- Adapt screenshot frequency with `auto`, `low`, `standard`, `high`, or `max` visual intensity.
- Keep backup, cloud sync, report publishing, and access-control bypass outside the skill.

## Platforms

| Platform | Acquisition | Local transcription | Status |
| --- | --- | --- | --- |
| macOS | Bash, `yt-dlp`, Deno 2.3+, FFmpeg | MLX Whisper preferred on Apple Silicon | Validated on Apple Silicon |
| Windows | PowerShell 7, `uv`/yt-dlp, Node.js 22+ EJS, FFmpeg | OpenAI Whisper with CUDA preferred | Validated with Python 3.12 and NVIDIA RTX 5070 Ti |
| Linux / WSL | Not provided | Not provided | Not validated |

Windows browser authentication uses an optional dedicated Firefox profile. Public videos do not require a browser profile. Never paste or publish raw cookies.

## Install as a Codex Skill

A skill is the complete directory containing `SKILL.md`, `agents/`, `scripts/`, and `references/`. Install the directory, not only the `SKILL.md` file.

### Ask Codex to install it

Use this prompt:

```text
Use $skill-installer to install video-content-analysis from
dreaifekks/video-content-analysis, ref agent/windows-support,
path ., with the name video-content-analysis.
```

The explicit repo/ref/path form is important because the branch name contains a slash.

### Run the bundled installer helper

Windows PowerShell:

```powershell
uv run python "$env:USERPROFILE\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py" `
  --repo dreaifekks/video-content-analysis `
  --ref "agent/windows-support" `
  --path . `
  --name video-content-analysis
```

macOS:

```bash
python3 "$HOME/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py" \
  --repo dreaifekks/video-content-analysis \
  --ref "agent/windows-support" \
  --path . \
  --name video-content-analysis
```

The Windows command uses the required `uv` runtime. The macOS helper command requires `python3`; use the Codex prompt or direct clone route when it is unavailable. The installer refuses to overwrite an existing `~/.codex/skills/video-content-analysis` directory.

### Clone the branch directly

Use this route when you want `git pull` updates from the development branch.

Windows PowerShell:

```powershell
$destination = Join-Path $HOME '.codex\skills\video-content-analysis'
git clone --branch agent/windows-support --single-branch `
  https://github.com/dreaifekks/video-content-analysis.git `
  $destination
```

macOS:

```bash
git clone --branch agent/windows-support --single-branch \
  https://github.com/dreaifekks/video-content-analysis.git \
  "$HOME/.codex/skills/video-content-analysis"
```

The skill becomes available on the next Codex turn. Restart Codex if it does not appear.

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
| `max` | Densest useful sampling for exhaustive review. |

There is no default total-frame limit. Intensity controls candidate frequency and change threshold; it does not export every encoded frame or duplicate unchanged frames.

## Windows Quick Start

```powershell
$skillPath = Join-Path $HOME '.codex\skills\video-content-analysis'
& "$skillPath\scripts\preflight.ps1"
& "$skillPath\scripts\fetch_youtube.ps1" `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir' `
  -NoPlaylist
```

For restricted content, pass the name of a dedicated Firefox profile only after authorizing local browser authentication and fully exiting Firefox. See `references/windows-setup.md`.

The first local Windows transcription setup downloads a multi-gigabyte CUDA/PyTorch runtime:

```powershell
& "$skillPath\scripts\setup_windows.ps1" -WithWhisper
```

## macOS Quick Start

```bash
scripts/fetch_youtube.sh "YOUTUBE_URL" "/path/to/analysis-workdir"
```

For authenticated content, use only a user-owned authorized browser session as described in `references/youtube-acquisition.md`.

## License

Licensed under the [Apache License 2.0](LICENSE), SPDX identifier `Apache-2.0`.
