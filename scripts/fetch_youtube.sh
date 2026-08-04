#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  fetch_youtube.sh "YOUTUBE_URL" "/path/to/output_dir"

Environment:
  YT_DLP_BIN                   yt-dlp command or explicit binary path. Default: yt-dlp
  YT_DLP_COOKIES_FROM_BROWSER Optional browser source, e.g. chrome:Profile 1
  YT_DLP_COOKIES_FILE         Optional Netscape cookie file; mutually exclusive
                              with YT_DLP_COOKIES_FROM_BROWSER.
  YT_DLP_SUB_LANGS            Subtitle language expression. Default:
                              en,zh-Hans,zh-Hant,ja,.*-orig
  YT_DLP_RETRIES              Retry count or infinite. Default: 10
  NO_PLAYLIST                 Set to 1 to ignore playlist context in a video URL.
  SKIP_MEDIA                  Set to 1 to fetch metadata/captions without media.
  LIVE_FROM_START             Set to 1 for a currently running livestream.
  WAIT_FOR_VIDEO              Scheduled-live wait interval, e.g. 30 or 30-60.

Outputs:
  Media, captions, metadata, descriptions, and thumbnails under output_dir.
  Media downloads also maintain archive.txt for safe repeat runs.

Use authentication only for content the user's own account can already access.
This script does not back up, sync, upload, or publish acquired files.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 2
fi

url="$1"
output_dir="$2"

case "$url" in
  https://youtube.com/*|https://www.youtube.com/*|https://m.youtube.com/*|https://music.youtube.com/*|https://youtu.be/*) ;;
  *)
    echo "Expected an https://youtube.com or https://youtu.be URL." >&2
    exit 2
    ;;
esac

if [[ -z "$output_dir" || "$output_dir" == "/" ]]; then
  echo "Choose a dedicated output directory; the filesystem root is not allowed." >&2
  exit 2
fi

yt_dlp_bin="${YT_DLP_BIN:-yt-dlp}"
sub_langs="${YT_DLP_SUB_LANGS:-en,zh-Hans,zh-Hant,ja,.*-orig}"
retries="${YT_DLP_RETRIES:-10}"
cookies_from_browser="${YT_DLP_COOKIES_FROM_BROWSER:-}"
cookies_file="${YT_DLP_COOKIES_FILE:-}"

if [[ -n "$cookies_from_browser" && -n "$cookies_file" ]]; then
  echo "Set only one of YT_DLP_COOKIES_FROM_BROWSER or YT_DLP_COOKIES_FILE." >&2
  exit 2
fi

if [[ -n "$cookies_file" && ! -f "$cookies_file" ]]; then
  echo "YT_DLP_COOKIES_FILE does not point to a readable file." >&2
  exit 1
fi

if [[ ! "$retries" =~ ^[0-9]+$ && "$retries" != "infinite" ]]; then
  echo "YT_DLP_RETRIES must be a non-negative integer or infinite." >&2
  exit 2
fi

if ! command -v "$yt_dlp_bin" >/dev/null 2>&1 && [[ ! -x "$yt_dlp_bin" ]]; then
  echo "yt-dlp not found. Install it or set YT_DLP_BIN." >&2
  exit 127
fi

if [[ "${SKIP_MEDIA:-0}" != "1" ]]; then
  command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 127; }
fi

mkdir -p "$output_dir"

yt_args=(
  --newline
  --ignore-errors
  --continue
  --retries "$retries"
  --fragment-retries "$retries"
  --extractor-retries "$retries"
  --retry-sleep 5
  -P "$output_dir"
  -o "%(upload_date)s_%(title).160B_%(id)s.%(ext)s"
  --write-description
  --write-info-json
  --clean-info-json
  --write-thumbnail
  --write-subs
  --write-auto-subs
  --sub-langs "$sub_langs"
  --sub-format "vtt/srt/best"
)

if [[ "${NO_PLAYLIST:-0}" == "1" ]]; then
  yt_args+=(--no-playlist)
else
  yt_args+=(--yes-playlist)
fi

if [[ "${SKIP_MEDIA:-0}" == "1" ]]; then
  yt_args+=(--skip-download)
else
  yt_args+=(
    --download-archive "$output_dir/archive.txt"
    --embed-metadata
    --merge-output-format mkv
    --remux-video mkv
  )
fi

if [[ -n "$cookies_from_browser" ]]; then
  yt_args+=(--cookies-from-browser "$cookies_from_browser")
  auth_mode="browser session"
elif [[ -n "$cookies_file" ]]; then
  yt_args+=(--cookies "$cookies_file")
  auth_mode="cookie file"
else
  auth_mode="none"
fi

if [[ "${LIVE_FROM_START:-0}" == "1" ]]; then
  yt_args+=(--live-from-start)
fi

if [[ -n "${WAIT_FOR_VIDEO:-}" ]]; then
  yt_args+=(--wait-for-video "$WAIT_FOR_VIDEO")
fi

echo "Acquiring YouTube source"
echo "Output directory: $output_dir"
echo "Authentication: $auth_mode"
echo "Caption languages: $sub_langs"

set +e
"$yt_dlp_bin" "${yt_args[@]}" "$url"
yt_status=$?
set -e

media_count="$(find "$output_dir" -maxdepth 1 -type f \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.m4v' \) -print | wc -l | tr -d '[:space:]')"
subtitle_count="$(find "$output_dir" -maxdepth 1 -type f \( -iname '*.vtt' -o -iname '*.srt' -o -iname '*.ass' -o -iname '*.srv3' \) -print | wc -l | tr -d '[:space:]')"
metadata_count="$(find "$output_dir" -maxdepth 1 -type f -name '*.info.json' -print | wc -l | tr -d '[:space:]')"
thumbnail_count="$(find "$output_dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print | wc -l | tr -d '[:space:]')"

echo
echo "Acquisition summary"
echo "Media files: $media_count"
echo "Caption files: $subtitle_count"
echo "Metadata files: $metadata_count"
echo "Thumbnail files: $thumbnail_count"

if [[ $yt_status -ne 0 ]]; then
  echo "yt-dlp exited with status $yt_status; inspect successful and failed items before analysis." >&2
  exit "$yt_status"
fi

if [[ "${SKIP_MEDIA:-0}" != "1" && "$media_count" == "0" ]]; then
  echo "No media files were acquired." >&2
  exit 1
fi

if [[ "${SKIP_MEDIA:-0}" == "1" && "$metadata_count" == "0" && "$subtitle_count" == "0" ]]; then
  echo "No metadata or captions were acquired." >&2
  exit 1
fi

echo "Acquisition complete. Continue with caption selection, local transcription if needed, frame sampling, and analysis."
