---
name: video-content-analysis
description: Analyze video or audio content from local media, caption files, subtitles, transcripts, or already-acquired YouTube videos, livestreams, and playlists. Use when asked to summarize a video or live, extract timestamped topics, compare multiple videos, inspect slides/charts/demos, identify claims and action items, or transcribe media that lacks captions. This skill is analysis-only; downloading or authentication, backup or sync, and report publishing are out of scope.
---

# Video Content Analysis

Analyze locally available video evidence and produce a source-grounded report. Prefer existing timed text, add local transcription only when needed, and inspect frames when visual content materially affects the meaning.

## Scope Boundary

- Accept local media, audio, subtitle, caption, transcript, and metadata files.
- Treat URL acquisition, authenticated access, DRM, archiving, backup, cloud sync, and publication as separate workflows.
- If the user supplies only a URL, identify the missing input and use a separately authorized acquisition method before continuing. Do not bypass access controls.
- Keep media and generated transcripts local. Do not upload them to a remote transcription service without explicit user approval.

## Workflow

1. Inventory the available inputs and the user's question.
   - Prefer `*.vtt`, `*.srt`, or other timestamped captions.
   - Otherwise use a supplied transcript or notes.
   - If only media is available, run `scripts/transcribe_local_whisper.sh`.
   - Record title, duration, language, and coverage gaps when known.

2. Build an evidence map.
   - Normalize repeated caption fragments and styling noise without deleting meaningful repetition.
   - Preserve timestamps when present; never invent timestamps for plain text.
   - For long media or collections, analyze one segment or item at a time, then synthesize.

3. Add visual evidence when useful.
   - Run `scripts/sample_video_frames.sh` for slide decks, charts, screen recordings, demonstrations, or visually ambiguous passages.
   - Inspect additional frames around important transcript timestamps instead of relying only on evenly sampled frames.
   - Distinguish what is visible from what the speaker claims.

4. Produce the report in the user's requested language.
   - Separate source facts, speaker claims, and analyst inference.
   - Cite timestamps where the source provides them.
   - Mark uncertain names, numbers, quotations, or missing sections.
   - Include coverage and material limitations.

Read `references/analysis-guide.md` for the detailed analysis passes, output shapes, and quality checks.

## Local Transcription

Run:

```bash
scripts/transcribe_local_whisper.sh "/path/to/video-or-audio" [output_dir] [base_name]
```

The helper requires `ffmpeg` plus one supported local engine: `mlx_whisper`, `whisper`, `whisper-cli`, or `whisper-cpp`. It auto-detects engines on `PATH`; use environment variables documented by `--help` to select a binary, model, language, or prompt.

The bundled scripts target Bash on macOS, Linux, or WSL. Native Windows execution is not assumed.

## Visual Sampling

Run:

```bash
scripts/sample_video_frames.sh "/path/to/video" [output_dir]
```

The helper requires `ffmpeg` and `ffprobe`. It samples up to 12 evenly spaced frames by default and writes `frames.tsv` with approximate timestamps. Override behavior with `FRAME_COUNT` and `FRAME_WIDTH`.

## Completion Checklist

- State which media, captions, transcripts, metadata, and frames were actually examined.
- Give an executive summary and timestamped key points when timing exists.
- Include important claims, decisions, examples, and actionable takeaways appropriate to the request.
- For collections, provide per-item notes before the cross-item synthesis.
- Report transcription quality, unexamined ranges, conflicts, and other caveats.
- Do not claim full-video coverage when only samples or partial transcripts were analyzed.
