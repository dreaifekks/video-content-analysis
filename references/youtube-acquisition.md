# YouTube Acquisition Guide

## Windows Prerequisites

This branch targets native Windows. Install current releases of PowerShell 7, `yt-dlp`, `ffmpeg`, `ffprobe`, and Node.js 22 or newer. Make the commands available on `PATH` or supply explicit binary paths to the acquisition helper.

Verify the commands before downloading:

```powershell
$PSVersionTable.PSVersion
Get-Command yt-dlp, ffmpeg, ffprobe, node
yt-dlp --version
node --version
```

Existing compatible binaries may instead be supplied through the helper's explicit path parameters. Local transcription additionally requires the OpenAI Whisper CLI and its compatible Python/PyTorch runtime; an existing model cache can be passed with `-ModelDirectory`.

## Input and Output Contract

Run `scripts/fetch_youtube.ps1` with one YouTube URL and one dedicated output directory. The helper writes locally:

- video media, normally remuxed to MKV;
- human and automatic captions exposed by YouTube;
- cleaned `*.info.json` metadata;
- descriptions and thumbnails;
- `archive.txt` for repeat-run deduplication when media download is enabled.

Use a separate output directory for each unrelated request. This is an analysis workspace, not a separate backup workflow.

## Authentication Route

Use no browser profile for public content. For content the user can already access through their own account, explicitly pass the name of a dedicated Firefox profile:

```powershell
& .\scripts\fetch_youtube.ps1 `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\analysis-workdir' `
  -FirefoxProfileName 'CodexYouTubeMember'
```

Fully exit Firefox before the run so `yt-dlp` can read the local profile database. Keep the profile device-local. Never ask the user to paste raw cookie contents, commit them, copy them into the skill, or include them in a report.

Authentication reuses access the user already has. It is not a DRM bypass and must not be used to evade access controls.

## Acquisition Controls

- `-SubtitleLanguages`: Caption language expression. Default: `en,zh-Hans,zh-Hant,ja,.*-orig`.
- `-Retries`: Network, fragment, and extractor retry count. Default: `10`; `infinite` is also accepted.
- `-NoPlaylist`: Download only the addressed video when a URL also contains playlist context.
- `-SkipMedia`: Fetch metadata, descriptions, thumbnails, and captions without downloading video media.
- `-LiveFromStart`: Ask `yt-dlp` to acquire a running livestream from its beginning when supported.
- `-WaitForVideo MIN[-MAX]`: Wait for a scheduled livestream to become available.
- `-YtDlpPath`, `-FfmpegPath`, `-FfprobePath`, and `-NodePath`: Use explicit binary paths instead of commands on `PATH`.

Set a focused caption expression whenever the source language is known. Use `all,-live_chat` only when broad multilingual coverage is actually needed; automatic translations can create many files and trigger rate limits.

If the first run downloads no useful captions, inspect the `subtitles` and `automatic_captions` keys in `*.info.json`. When a human caption exists under another language tag, fetch it without redownloading media. Metadata-only runs intentionally ignore `archive.txt`, so the same video can be revisited for a targeted caption:

```powershell
& .\scripts\fetch_youtube.ps1 `
  -Url 'YOUTUBE_URL' `
  -OutputDir 'C:\path\to\the-same-workdir' `
  -SkipMedia `
  -SubtitleLanguages 'es'
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
3. For access errors, distinguish public availability from user-authenticated availability. Do not add browser authentication blindly.
4. For Firefox profile errors, fully exit Firefox and verify the profile name locally without displaying cookie data.
5. For scheduled lives, use `-WaitForVideo`; for running lives, add `-LiveFromStart` only when full-from-start capture is intended.
6. If media downloads but captions do not exist, continue through local transcription.
7. If a playlist partially fails, preserve successful items, report failed video IDs, and avoid claiming full coverage.

Treat downloaded metadata as local evidence. Even cleaned `*.info.json` files may contain fields that should not be published without review.
