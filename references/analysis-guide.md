# Video Analysis Guide

## Evidence Priority

Use the strongest available source in this order:

1. Human-authored captions or transcript.
2. Platform captions or automatic subtitles.
3. Locally generated speech-to-text.
4. Visual frames and metadata only.

Use visual evidence alongside text for slides, charts, code, demonstrations, on-screen labels, or passages where words such as "this" and "here" depend on the image. A transcript alone is not complete evidence for those cases.

## Analysis Passes

### 1. Coverage pass

Record the source files, duration, language, transcript timing, missing spans, and transcription method. For a collection, track coverage separately for every item.

### 2. Content-map pass

For a single video, divide the timed transcript into coherent sections. For long material, process manageable chronological chunks with a small overlap and retain chunk start/end times. Capture:

- topic and purpose;
- claims, evidence, and examples;
- decisions, recommendations, or action items;
- named entities, numbers, dates, and terminology that may require checking;
- visual references that need frame inspection.

For a collection, finish the item-level map before comparing items.

### 3. Verification pass

- Recheck important names, numbers, dates, and direct wording against captions, audio, frames, or metadata.
- Treat automatic transcription as noisy evidence, especially for proper nouns, jargon, and numeric values.
- Label a statement as a speaker claim unless the available evidence independently establishes it.
- Label conclusions not stated by the source as analyst inference.
- Never fabricate a timestamp. Use an untimed section label when timing is unavailable.

### 4. Visual pass

Start with the platform sampler in its default `auto` mode: `scripts/sample_video_frames.sh` on macOS or `scripts/sample_video_frames.ps1` on Windows. It probes visual-change density, keeps sparse coverage through static intervals, and lowers the interval around stronger changes. Read both `frames.tsv` and `sampling.tsv` before deciding whether coverage is sufficient.

Automatic density is only a visual-change proxy. A moving face can change pixels without adding much information, while a static price chart can contain important values. Add a semantic-density pass using the timed transcript:

- mark clusters of numbers, price levels, dates, symbols, commands, decisions, and action items;
- mark phrases that point to the image, such as “here,” “this level,” “look at the chart,” or “on screen”;
- mark slide, chart, code, dashboard, order-book, or demonstration sections;
- inspect frames at those timestamps and immediately before or after important changes.

Choose a manual intensity when the user requests one or the source type clearly warrants it:

| Intensity | Use |
| --- | --- |
| `low` | Fast pass over visually simple or mostly static material. |
| `standard` | General-purpose review with moderate coverage. |
| `high` | Chart-heavy trading, dashboards, code, demonstrations, or dense slides. |
| `max` | Explicitly requested exhaustive visual review, preferably on short material or narrowed ranges. |

Run a manual profile on macOS with:

```bash
scripts/sample_video_frames.sh \
  "/path/to/video" "/path/to/new-frame-output" high
```

Run the equivalent profile on Windows with:

```powershell
& "$skillPath\scripts\sample_video_frames.ps1" `
  -InputPath 'C:\path\video.mkv' `
  -OutputDir 'C:\path\new-frame-output' `
  -Intensity high
```

Use a new output directory for every sampling run. There is no default total-frame limit; the intensity profile continues sampling across the entire video according to its interval and change threshold. This does not mean extracting every encoded video frame or duplicating unchanged frames. Set `FRAME_COUNT` on macOS or `-FrameCount` on Windows only when the user explicitly requests a hard limit. Minimum gap, maximum gap, and scene threshold are expert overrides.

For direct Codex use, prefer a compact invocation such as `$video-content-analysis high "YOUTUBE_URL"`. In Codex CLI or the IDE extension, `$` mentions a skill and `/skills` opens the skill selector; `/skill high` is not a per-skill command alias. After selection, a bare intensity token must be honored without asking the user to translate it into an environment variable.

Note whether each observation comes from text, audio, the image, or a combination. Do not infer off-screen events from a sampled frame.

### 5. Synthesis pass

Answer the user's actual question rather than merely restating the transcript. Preserve important disagreements and changes over time. Compress repetition, but retain repeated points when repetition itself signals emphasis or a recurring pattern.

## Suggested Output Shapes

### Single video or livestream

1. Executive summary.
2. Key topics with timestamps when available.
3. Important claims, evidence, and examples.
4. Visual findings when relevant.
5. Decisions or actionable takeaways.
6. Caveats and coverage.

### Playlist or multi-video set

1. Overall synthesis.
2. Per-item notes with title, date, duration, and coverage when known.
3. Recurring themes and meaningful differences.
4. Changes, contradictions, or developments across items.
5. Follow-up questions or items needing deeper review.
6. Failed, missing, or partial coverage.

### Focused question

Lead with the direct answer, then provide the smallest amount of timestamped evidence needed to support it. State when the source does not answer the question.

## Quality Checks

- Match the report language and depth to the user's request.
- Ground every material conclusion in examined evidence.
- Keep source facts, speaker claims, and analyst inference distinct.
- Preserve timestamps through chunking and synthesis.
- Check that sampled frames do not substitute for unreviewed video sections.
- Check `sampling.tsv`; disclose the requested/effective intensity and any explicit frame limit.
- Disclose partial coverage and low-confidence transcription.
- Avoid reproducing long copyrighted passages; summarize and quote only short excerpts needed for analysis.
