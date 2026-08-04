---
name: video-content-analysis
description: Windows-focused skill to acquire and analyze YouTube videos, Shorts, livestreams, scheduled lives, member-only videos the user can lawfully access, and playlists. Use on Windows when asked to fetch a YouTube URL with yt-dlp, save video and metadata, extract captions, transcribe missing speech locally, adapt frame-sampling density or visual-analysis intensity, summarize content with timestamps, or compare multiple videos. This skill excludes backup or cloud sync, access-control bypass, and report publishing.
---

# Video Content Analysis for Windows

Run the complete local evidence pipeline: acquire the source with `yt-dlp`, prefer available captions, transcribe only when captions are missing, inspect representative frames, and produce a source-grounded report.

## Scope Boundary

- Include YouTube acquisition, metadata, descriptions, thumbnails, captions, local transcription, frame sampling, and content analysis.
- Accept public content and restricted or member content that the user's own account can already access.
- Use a dedicated Firefox profile only when the user authorizes that local authentication route. Never request raw cookie values or bypass access controls.
- Keep all acquired and generated files local unless a separate, explicitly requested workflow handles backup, sync, or publication.
- Do not include Google Drive, Dropbox, Telegram, Notion, or other destination-specific behavior in this skill.

## Windows Platform Contract

- Target native Windows only. Do not claim validated macOS, Linux, or WSL support from this branch.
- Require PowerShell 7 plus `yt-dlp`, `ffmpeg`, `ffprobe`, and Node.js 22 or newer, either on `PATH` or supplied through the helpers' explicit path parameters.
- Require the OpenAI Whisper CLI for local transcription; prefer CUDA on a compatible NVIDIA GPU and allow explicit CPU use when necessary.
- Keep browser profiles, media, transcripts, and generated frames on the PC unless the user separately authorizes another workflow.
- Read the prerequisites in `references/youtube-acquisition.md` before the first acquisition run.

## Quick Start

For explicit Codex invocation, accept an optional intensity token immediately after the skill mention:

```text
$video-content-analysis high "YOUTUBE_URL"
```

Treat `auto`, `low`, `standard`, `high`, or `max` in that position as the requested visual-analysis intensity. Do not require the user to write environment-variable syntax. If no token is supplied, use `auto`.

Acquire a public video, live replay, Short, or playlist into a dedicated directory:

```powershell
& .\scripts\fetch_youtube.ps1 `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir'
```

For content available only through the user's dedicated Firefox profile:

```powershell
& .\scripts\fetch_youtube.ps1 `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir' `
  -FirefoxProfileName 'CodexYouTubeMember'
```

For a currently running or scheduled livestream:

```powershell
& .\scripts\fetch_youtube.ps1 `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir' `
  -LiveFromStart `
  -WaitForVideo 30
```

Read `references/youtube-acquisition.md` before handling authenticated content, live streams, playlists, or acquisition failures.

## Workflow

1. Choose a dedicated local work directory and determine whether authentication is needed.
   - Confirm the host is Windows and the required commands are available.
   - Try public acquisition without cookies first for public URLs.
   - For member or otherwise restricted content, use only a user-owned, explicitly named Firefox profile.

2. Run `scripts/fetch_youtube.ps1`.
   - Download media by default.
   - Save `.info.json`, description, thumbnail, human subtitles, and automatic subtitles when YouTube exposes them.
   - Keep `archive.txt` for safe repeat runs.
   - Do not copy the result to any backup destination.

3. Inventory the acquired evidence.
   - Prefer human-authored `*.vtt`, `*.srt`, or other timed captions.
   - Otherwise use automatic captions.
   - Read `.info.json` and description files for title, channel, date, duration, and context.
   - If no useful caption was downloaded, inspect subtitle language keys in `.info.json` and rerun acquisition with `-SubtitleLanguages` and `-SkipMedia` when an available track was missed.
   - If captions are absent or materially incomplete after that check, run `scripts/transcribe_local_whisper.ps1` on the media file.

4. Add visual evidence.
   - Run `scripts/sample_video_frames.ps1`; its default `auto` mode probes visual-change density and samples changing intervals more frequently than static intervals.
   - Use `-Intensity high` for chart-heavy trading, dense slide, code, or dashboard videos. Reserve `max` for short material or explicitly requested exhaustive review.
   - Treat automatic density as a visual-change proxy, then inspect extra frames around transcript-dense timestamps such as numbers, decisions, demonstrations, and references to on-screen content.

5. Analyze and report.
   - Preserve real timestamps and never invent them for untimed text.
   - Separate source facts, speaker claims, and analyst inference.
   - For long videos, analyze chronological segments before synthesis.
   - For playlists, produce per-video coverage and notes before cross-video synthesis.
   - Report missing captions, failed items, uncertain names or numbers, and unexamined ranges.

Read `references/analysis-guide.md` for evidence passes, output shapes, and quality checks.

## Local Transcription

When captions are missing, run:

```powershell
& .\scripts\transcribe_local_whisper.ps1 `
  -InputPath 'C:\path\to\video-or-audio' `
  -OutputDir 'C:\path\to\transcripts'
```

The helper requires `ffmpeg` and the OpenAI Whisper CLI on `PATH`, or explicit binary paths. Use its parameters for model, optional model directory, language, output format, prompt, and device selection.

## Visual Sampling

Run:

```powershell
& .\scripts\sample_video_frames.ps1 `
  -InputPath 'C:\path\to\video' `
  -OutputDir 'C:\path\to\frames' `
  -Intensity auto
```

The helper requires `ffmpeg` and preferably `ffprobe`. It writes adaptive frames, exact selected timestamps in `frames.tsv`, and the detected profile and sampling parameters in `sampling.tsv`.

Supported values are `auto`, `low`, `standard`, `high`, and `max`. By default there is no total-frame limit: intensity controls the candidate interval and visual-change threshold. `-FrameCount` adds a hard limit only when the user explicitly requests one. Read `references/analysis-guide.md` before choosing `high` or `max` for long media.

## Completion Checklist

- Report the local work directory and acquired media count.
- State whether captions came from YouTube, local transcription, or neither.
- State which metadata, transcripts, and frames were actually examined.
- Report the requested/effective visual-analysis intensity and any explicit frame limit from `sampling.tsv`.
- Give the requested analysis with timestamps when supported by the evidence.
- For playlists, distinguish successful, partial, and failed items.
- Disclose acquisition, transcription, visual-sampling, and coverage limitations.
