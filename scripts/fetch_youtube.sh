#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  fetch_youtube.sh "YOUTUBE_URL" "/path/to/output_dir"

Platform:
  macOS. Install yt-dlp and ffmpeg with Homebrew or provide compatible binaries.

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
command -v deno >/dev/null || { echo "Deno 2.3.0 or newer is required for YouTube EJS challenge solving." >&2; exit 127; }
deno_version="$(deno --version | awk 'NR == 1 { print $2 }')"
if ! awk -v version="$deno_version" 'BEGIN {
  split(version, parts, ".")
  exit !((parts[1] > 2) || (parts[1] == 2 && parts[2] >= 3))
}'; then
  echo "Deno 2.3.0 or newer is required; found $deno_version." >&2
  exit 1
fi

mkdir -p "$output_dir"

yt_args=(
  --ignore-config
  --no-plugin-dirs
  --remote-components ejs:github
  --newline
  --no-abort-on-error
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

if [[ "${NO_PLAYLIST:-0}" == "1" && "${INCLUDE_PLAYLIST:-0}" == "1" ]]; then
  echo "Choose either NO_PLAYLIST=1 or INCLUDE_PLAYLIST=1, not both." >&2
  exit 2
elif [[ "${INCLUDE_PLAYLIST:-0}" == "1" ]]; then
  yt_args+=(--yes-playlist)
  playlist_mode="playlist"
elif [[ "${NO_PLAYLIST:-0}" == "1" ]]; then
  yt_args+=(--no-playlist)
  playlist_mode="single video"
elif [[ "$url" == */playlist\?* ]]; then
  yt_args+=(--yes-playlist)
  playlist_mode="playlist"
else
  yt_args+=(--no-playlist)
  playlist_mode="single video"
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
echo "Playlist mode: $playlist_mode"
echo "Caption languages: $sub_langs"

set +e
run_stamp="$(date -u '+%Y%m%d-%H%M%S')"
acquisition_log="$output_dir/acquisition-$run_stamp.log"
error_log="$output_dir/acquisition-$run_stamp.errors.log"
"$yt_dlp_bin" "${yt_args[@]}" "$url" 2>&1 | tee "$acquisition_log"
yt_status="${PIPESTATUS[0]}"
set -e
grep -Ei '(^|[[:space:]])ERROR:' "$acquisition_log" > "$error_log" || true

shopt -s nullglob nocaseglob
media_files=("$output_dir"/*.mkv "$output_dir"/*.mp4 "$output_dir"/*.webm "$output_dir"/*.mov "$output_dir"/*.m4v)
subtitle_files=("$output_dir"/*.vtt "$output_dir"/*.srt "$output_dir"/*.ass "$output_dir"/*.srv3)
metadata_files=("$output_dir"/*.info.json)
thumbnail_files=("$output_dir"/*.jpg "$output_dir"/*.jpeg "$output_dir"/*.png "$output_dir"/*.webp)
media_count="${#media_files[@]}"
subtitle_count="${#subtitle_files[@]}"
metadata_count="${#metadata_files[@]}"
thumbnail_count="${#thumbnail_files[@]}"

echo
echo "Acquisition summary"
echo "Media files: $media_count"
echo "Caption files: $subtitle_count"
echo "Metadata files: $metadata_count"
echo "Thumbnail files: $thumbnail_count"
echo "Acquisition log: $acquisition_log"
echo "Error log: $error_log"

if [[ $yt_status -ne 0 ]]; then
  echo "yt-dlp reported one or more acquisition or post-processing failures (status $yt_status). Preserve successful files, review $error_log, and treat a playlist as partial." >&2
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
