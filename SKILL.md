---
name: video-content-analysis
description: Acquire and analyze YouTube videos, Shorts, livestreams, scheduled lives, member-only videos the user can lawfully access, and playlists on macOS or Windows. Use when asked to fetch a YouTube URL with yt-dlp, save media and metadata, select captions, transcribe missing speech locally, adapt visual sampling intensity, summarize with timestamps, or compare multiple videos. Includes Apple Silicon MLX Whisper and Windows NVIDIA/OpenAI Whisper routes; excludes backup, cloud sync, access-control bypass, and report publishing.
---

# Video Content Analysis

Run a local evidence pipeline: acquire the source, prefer available captions, transcribe only when captions are missing, inspect representative frames, and produce a source-grounded report.

## Guardrails

- Process public content or restricted content the user's own account can already access. Never bypass access controls.
- Use browser authentication only with the user's authorization. Never request, display, export, or commit raw cookie values.
- Keep media, browser profiles, metadata, transcripts, and frames local unless a separate workflow explicitly authorizes publication or transfer.
- Exclude backup, cloud sync, and destination-specific behavior from this skill.
- Do not install browser extensions, alter browser policies, or copy cookie-decryption helpers into trusted locations.

## Platform Routing

Determine the host before running scripts:

- **macOS:** Read `references/youtube-acquisition.md`. Use the bundled Bash scripts with Deno 2.3+ and prefer MLX Whisper on Apple Silicon.
- **Windows:** Read `references/windows-setup.md`. Use PowerShell 7 scripts and prefer OpenAI Whisper with CUDA on a supported NVIDIA GPU.
- **Linux or WSL:** Stop and report that this repository does not yet provide a validated route.

Use only the scripts for the detected host. Do not run the macOS shell scripts through WSL as a substitute for the Windows workflow.

## Invocation

Accept an optional intensity token immediately after the skill mention:

```text
$video-content-analysis high "YOUTUBE_URL"
```

Treat `auto`, `low`, `standard`, `high`, or `max` as the requested visual-analysis intensity. If omitted, use `auto`.

## Workflow

1. Select a dedicated local work directory and determine whether authentication is necessary.
   - Try acquisition without cookies for public URLs.
   - On Windows, restricted content requires an explicitly named, user-owned Firefox profile. On macOS, follow the platform reference for an authorized browser session or a pre-existing user-supplied cookie file; never ask the user to export or paste cookies.

2. Acquire the source.
   - macOS: run `scripts/fetch_youtube.sh`.
   - Windows: run `scripts/preflight.ps1`, resolve blocking items, then run `scripts/fetch_youtube.ps1`.
   - Treat ordinary watch, Short, live, and youtu.be URLs as one item even when they contain `list=`. Use `-IncludePlaylist` on Windows or `INCLUDE_PLAYLIST=1` on macOS only when the user explicitly requests that playlist. Explicit `/playlist` URLs select playlist mode by default.
   - Save media, cleaned info JSON, description, thumbnail, available captions, and `archive.txt`.
   - Preserve successful playlist items. If yt-dlp returns an error, read the timestamped acquisition/error logs, report failed video IDs named there, and mark IDs that cannot be recovered from the log as unknown.

3. Inventory the evidence.
   - Prefer human-authored timed captions, then automatic captions.
   - Inspect subtitle keys in info JSON and retry a targeted language before transcribing.
   - Read metadata and descriptions for title, channel, date, duration, and context.

4. Transcribe only when captions are absent or materially incomplete.
   - macOS: run `scripts/transcribe_local_whisper.sh`.
   - Windows: obtain approval before the first multi-gigabyte runtime setup, run `scripts/setup_windows.ps1 -WithWhisper`, then run `scripts/transcribe_local_whisper.ps1`.

5. Add visual evidence.
   - macOS: run `scripts/sample_video_frames.sh`.
   - Windows: run `scripts/sample_video_frames.ps1`.
   - Start with `auto`; use `high` for dense charts, slides, code, dashboards, or demonstrations. Reserve `max` for short material or explicitly requested exhaustive review.
   - Read `frames.tsv` and `sampling.tsv`, then inspect extra frames around transcript-dense timestamps.

6. Read `references/analysis-guide.md` and analyze the examined evidence.
   - Preserve real timestamps and never invent timing for untimed text.
   - Separate source facts, speaker claims, and analyst inference.
   - Analyze long videos chronologically before synthesis.
   - Analyze playlist items separately before cross-video synthesis.

## Quick Start

macOS acquisition:

```bash
scripts/fetch_youtube.sh "YOUTUBE_URL" "/path/to/analysis-workdir"
```

Windows public acquisition:

```powershell
$skillPath = Join-Path $HOME '.codex\skills\video-content-analysis'
& "$skillPath\scripts\preflight.ps1"
& "$skillPath\scripts\fetch_youtube.ps1" `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir' `
  -NoPlaylist
```

Windows authenticated acquisition uses the optional dedicated Firefox profile described in `references/windows-setup.md`. Fully exit Firefox before cookie extraction.

Windows local transcription:

```powershell
& "$skillPath\scripts\setup_windows.ps1" -WithWhisper
& "$skillPath\scripts\transcribe_local_whisper.ps1" -InputPath 'C:\path\video.mkv'
```

Windows adaptive frame sampling:

```powershell
& "$skillPath\scripts\sample_video_frames.ps1" `
  -InputPath 'C:\path\video.mkv' `
  -Intensity high
```

## Completion Checklist

- Report the local work directory and acquired media count.
- State whether captions came from YouTube, local transcription, or neither.
- State which metadata, transcripts, and frames were actually examined.
- Report requested/effective visual intensity and any explicit frame limit from `sampling.tsv`.
- Give the requested analysis with timestamps when supported by evidence.
- Distinguish successful, partial, and failed playlist items.
- Cite the timestamped acquisition/error log when a failed playlist ID cannot be recovered.
- Disclose acquisition, transcription, visual-sampling, and coverage limitations.
