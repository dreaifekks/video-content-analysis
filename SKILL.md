---
name: video-content-analysis
description: Acquire and analyze YouTube videos, Shorts, livestreams, scheduled lives, member-only videos the user can lawfully access, and playlists. Use when asked to fetch a YouTube URL with yt-dlp, save video and metadata, extract human or automatic captions, transcribe missing speech locally, adapt frame-sampling density or visual-analysis intensity, summarize content with timestamps, or compare multiple videos. This skill includes local acquisition and analysis but excludes backup or cloud sync, access-control bypass, and report publishing.
---

# Video Content Analysis

Run the complete local evidence pipeline: acquire the source with `yt-dlp`, prefer available captions, transcribe only when captions are missing, inspect representative frames, and produce a source-grounded report.

## Scope Boundary

- Include YouTube acquisition, metadata, descriptions, thumbnails, captions, local transcription, frame sampling, and content analysis.
- Accept public content and restricted or member content that the user's own account can already access.
- Use browser cookies or a cookie file only when the user authorizes that local authentication route. Never request raw cookie values or bypass access controls.
- Keep all acquired and generated files local unless a separate, explicitly requested workflow handles backup, sync, or publication.
- Do not include Google Drive, Dropbox, Telegram, Notion, or other destination-specific behavior in this skill.

## Quick Start

Acquire a public video, live replay, Short, or playlist into a dedicated directory:

```bash
scripts/fetch_youtube.sh "YOUTUBE_URL" "/path/to/analysis-workdir"
```

For content available only through the user's browser session:

```bash
YT_DLP_COOKIES_FROM_BROWSER="chrome:Profile 1" \
  scripts/fetch_youtube.sh "YOUTUBE_URL" "/path/to/analysis-workdir"
```

For a currently running or scheduled livestream:

```bash
LIVE_FROM_START=1 WAIT_FOR_VIDEO=30 \
  scripts/fetch_youtube.sh "YOUTUBE_URL" "/path/to/analysis-workdir"
```

Read `references/youtube-acquisition.md` before handling authenticated content, live streams, playlists, or acquisition failures.

## Workflow

1. Choose a dedicated local work directory and determine whether authentication is needed.
   - Try public acquisition without cookies first for public URLs.
   - For member or otherwise restricted content, use only a user-owned authorized browser session or cookie file.

2. Run `scripts/fetch_youtube.sh`.
   - Download media by default.
   - Save `.info.json`, description, thumbnail, human subtitles, and automatic subtitles when YouTube exposes them.
   - Keep `archive.txt` for safe repeat runs.
   - Do not copy the result to any backup destination.

3. Inventory the acquired evidence.
   - Prefer human-authored `*.vtt`, `*.srt`, or other timed captions.
   - Otherwise use automatic captions.
   - Read `.info.json` and description files for title, channel, date, duration, and context.
   - If no useful caption was downloaded, inspect the subtitle language keys in `.info.json` and rerun acquisition with a targeted `YT_DLP_SUB_LANGS` value when an available track was missed.
   - If captions are absent or materially incomplete after that check, run `scripts/transcribe_local_whisper.sh` on the media file.

4. Add visual evidence.
   - Run `scripts/sample_video_frames.sh`; its default `auto` mode probes visual-change density and samples changing intervals more frequently than static intervals.
   - Use `VIDEO_ANALYSIS_INTENSITY=high` for chart-heavy trading, dense slide, code, or dashboard videos. Reserve `max` for short material or explicitly requested exhaustive review.
   - Treat automatic density as a visual-change proxy, then inspect extra frames around transcript-dense timestamps such as numbers, decisions, demonstrations, and references to on-screen content.

5. Analyze and report.
   - Preserve real timestamps and never invent them for untimed text.
   - Separate source facts, speaker claims, and analyst inference.
   - For long videos, analyze chronological segments before synthesis.
   - For playlists, produce per-video coverage and notes before cross-video synthesis.
   - Report missing captions, failed items, uncertain names or numbers, and unexamined ranges.

Read `references/analysis-guide.md` for the evidence passes, output shapes, and quality checks.

## Local Transcription

When captions are missing, run:

```bash
scripts/transcribe_local_whisper.sh "/path/to/video-or-audio" [output_dir] [base_name]
```

The helper requires `ffmpeg` plus one supported local engine: `mlx_whisper`, `whisper`, `whisper-cli`, or `whisper-cpp`. It auto-detects engines on `PATH`; use `--help` for model, language, binary, and prompt overrides.

## Visual Sampling

Run:

```bash
scripts/sample_video_frames.sh "/path/to/video" [output_dir]
```

The helper requires `ffmpeg` and `ffprobe`. It writes adaptive frames, exact selected timestamps in `frames.tsv`, and the detected profile and sampling parameters in `sampling.tsv`.

Set a manual analysis intensity when the user requests a faster or deeper visual review:

```bash
VIDEO_ANALYSIS_INTENSITY=high \
  scripts/sample_video_frames.sh "/path/to/video" [output_dir]
```

Supported values are `auto`, `low`, `standard`, `high`, and `max`. `FRAME_COUNT` remains available as a hard budget override. Read `references/analysis-guide.md` before choosing `high` or `max` for long media.

The bundled scripts target Bash on macOS, Linux, or WSL. Native Windows execution is not assumed.

## Completion Checklist

- Report the local work directory and acquired media count.
- State whether captions came from YouTube, local transcription, or neither.
- State which metadata, transcripts, and frames were actually examined.
- Report the requested and effective visual-analysis intensity from `sampling.tsv`.
- Give the requested analysis with timestamps when supported by the evidence.
- For playlists, distinguish successful, partial, and failed items.
- Disclose acquisition, transcription, visual-sampling, and coverage limitations.
