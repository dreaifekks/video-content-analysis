# Video Content Analysis for macOS

A Codex skill for acquiring and analyzing YouTube videos on macOS. It covers the local workflow from `yt-dlp` acquisition through caption extraction, optional local Whisper transcription, adaptive frame sampling, and timestamped analysis.

## Features

- Acquire videos, Shorts, livestreams, scheduled lives, member content the user can lawfully access, and playlists.
- Save media, metadata, descriptions, thumbnails, and available captions locally.
- Use local Whisper only when platform captions are missing or inadequate.
- Adapt screenshot frequency to visual-change density.
- Accept `auto`, `low`, `standard`, `high`, or `max` visual-analysis intensity.
- Keep backup, cloud sync, report publishing, and access-control bypass outside the skill.

## Platform

- Target: macOS.
- Validated: Apple Silicon.
- Intel Mac: use another compatible local Whisper engine and verify it locally.
- Linux, WSL, and Windows are outside the validated scope of this repository.

Install the required acquisition and media tools with Homebrew:

```bash
brew install yt-dlp ffmpeg
```

Local transcription additionally requires one supported engine: `mlx_whisper`, `whisper`, `whisper-cli`, or `whisper-cpp`. Apple Silicon prefers `mlx_whisper` when available.

## Install as a Codex Skill

Clone the repository into the user skill directory:

```bash
mkdir -p "$HOME/.agents/skills"
git clone https://github.com/dreaifekks/video-content-analysis.git \
  "$HOME/.agents/skills/video-content-analysis"
```

Codex detects skill changes automatically in supported surfaces. Restart Codex if the skill does not appear.

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

There is no default total-frame limit. Intensity controls the candidate interval and change threshold; it does not export every encoded video frame or duplicate unchanged frames. Set `FRAME_COUNT` only when an explicit hard limit is needed.

The underlying acquisition helper can also be run directly:

```bash
scripts/fetch_youtube.sh "YOUTUBE_URL" "/path/to/analysis-workdir"
```

For content already available through the user's own browser session:

```bash
YT_DLP_COOKIES_FROM_BROWSER="chrome:Profile 1" \
  scripts/fetch_youtube.sh "YOUTUBE_URL" "/path/to/analysis-workdir"
```

Authentication only reuses access the user already has. Keep browser profiles and cookie files device-local, and never commit them to the repository.

## License

Licensed under the [Apache License 2.0](LICENSE), SPDX identifier `Apache-2.0`.
