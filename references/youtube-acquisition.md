# YouTube Acquisition Guide

## macOS Prerequisites

This skill targets macOS. Install the acquisition and media dependencies with Homebrew when they are not already available:

```bash
brew install yt-dlp ffmpeg
```

Verify the host and commands before downloading:

```bash
test "$(uname -s)" = "Darwin"
command -v yt-dlp
command -v ffmpeg
command -v ffprobe
```

Homebrew is the recommended installation route, not a runtime requirement; existing compatible binaries on `PATH` are acceptable. Apple Silicon is the validated route when local MLX Whisper transcription is needed. An Intel Mac may use another local Whisper engine, but verify that path on the target machine before claiming support.

## Input and Output Contract

Run `scripts/fetch_youtube.sh` with one YouTube URL and one dedicated output directory. The helper writes locally:

- video media, normally remuxed to MKV;
- human and automatic captions exposed by YouTube;
- cleaned `*.info.json` metadata;
- descriptions and thumbnails;
- `archive.txt` for repeat-run deduplication when media download is enabled.

Use a separate output directory for each unrelated request. Do not treat this directory as a backup destination.

## Authentication Routes

Use no cookies for public content. For content the user can already access through their own account, select exactly one opt-in route:

```bash
YT_DLP_COOKIES_FROM_BROWSER="chrome"
```

```bash
YT_DLP_COOKIES_FILE="/path/to/cookies.txt"
```

`YT_DLP_COOKIES_FROM_BROWSER` accepts the syntax supported by the installed `yt-dlp`, such as `chrome:Profile 1`, `firefox`, or another supported browser. Keep cookie files and browser profiles device-local. Never ask the user to paste raw cookie contents, commit them, copy them into the skill, or include them in a report.

Authentication reuses access the user already has. It is not a DRM bypass and must not be used to evade access controls.

## Acquisition Controls

- `YT_DLP_SUB_LANGS`: Caption language expression. Default: `en,zh-Hans,zh-Hant,ja,.*-orig`. The exact tags cover common human captions, while `.*-orig` selects an original automatic-caption track when YouTube labels one. Override it for other human-caption languages.
- `YT_DLP_RETRIES`: Network and fragment retry count. Default: `10`.
- `NO_PLAYLIST=1`: Download only the addressed video when a URL also contains playlist context.
- `SKIP_MEDIA=1`: Fetch metadata, descriptions, thumbnails, and captions without downloading video media.
- `LIVE_FROM_START=1`: Ask `yt-dlp` to acquire a running livestream from its beginning when supported.
- `WAIT_FOR_VIDEO=MIN[-MAX]`: Wait for a scheduled livestream to become available.
- `YT_DLP_BIN`: Use an explicit `yt-dlp` binary path or command.

Set a focused caption expression whenever the source language is known. Use `all,-live_chat` only when broad multilingual coverage is actually needed; automatic translations can create many files and trigger rate limits.

If the first run downloads no useful captions, inspect the `subtitles` and `automatic_captions` keys in `*.info.json`. When a human caption exists under another language tag, fetch it without redownloading media. Metadata-only runs intentionally ignore `archive.txt`, so the same video can be revisited for a targeted caption:

```bash
SKIP_MEDIA=1 YT_DLP_SUB_LANGS="es" \
  scripts/fetch_youtube.sh "YOUTUBE_URL" "/path/to/the-same-workdir"
```

Only fall back to local transcription after targeted caption retrieval is unavailable or inadequate.

## Evidence Selection

After acquisition:

1. Identify the metadata and media belonging to each video ID.
2. Prefer human captions in the source language.
3. Use automatic captions when human captions are unavailable, and mark them as noisy evidence.
4. Run local Whisper only for videos without adequate captions.
5. Sample frames for sources where the image carries information not present in speech.

Do not load every playlist transcript into context at once. Analyze each item, retain a compact evidence note, and synthesize only after item-level coverage is clear.

## Failure Triage

1. Run `yt-dlp --version`; YouTube extraction changes frequently, so use a recent release before diagnosing deeper failures.
2. Confirm that the URL is a supported YouTube URL and that the output directory is writable.
3. For access errors, distinguish public availability from user-authenticated availability. Do not add cookies blindly.
4. For browser-cookie errors, verify the browser/profile selector locally without displaying cookie data.
5. For scheduled lives, use `WAIT_FOR_VIDEO`; for running lives, add `LIVE_FROM_START=1` only when full-from-start capture is intended.
6. If media downloads but captions do not exist, continue through local transcription.
7. If a playlist partially fails, preserve successful items, report failed video IDs, and avoid claiming full coverage.

Treat downloaded metadata as local evidence. Even cleaned `*.info.json` files may contain fields that should not be published without review.
