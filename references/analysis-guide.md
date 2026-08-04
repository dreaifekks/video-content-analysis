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

Start with evenly sampled frames, then inspect targeted frames near important timestamps. Note whether each observation comes from text, audio, the image, or a combination. Do not infer off-screen events from a sampled frame.

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
- Disclose partial coverage and low-confidence transcription.
- Avoid reproducing long copyrighted passages; summarize and quote only short excerpts needed for analysis.
