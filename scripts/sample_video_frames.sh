#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sample_video_frames.sh "/path/to/video" [output_dir]

Environment:
  FRAME_COUNT   Maximum number of evenly spaced frames. Default: 12
  FRAME_WIDTH   Maximum output width in pixels. Default: 1600

Outputs:
  <output_dir>/frame_001.jpg ...
  <output_dir>/frames.tsv with approximate timestamps

The output directory must not already contain frame_*.jpg files.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

input_path="$1"
output_dir="${2:-}"
frame_count="${FRAME_COUNT:-12}"
frame_width="${FRAME_WIDTH:-1600}"

if [[ ! -f "$input_path" ]]; then
  echo "Input file not found: $input_path" >&2
  exit 1
fi

[[ "$frame_count" =~ ^[1-9][0-9]*$ ]] || { echo "FRAME_COUNT must be a positive integer" >&2; exit 2; }
[[ "$frame_width" =~ ^[1-9][0-9]*$ ]] || { echo "FRAME_WIDTH must be a positive integer" >&2; exit 2; }

command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 127; }
command -v ffprobe >/dev/null || { echo "ffprobe not found" >&2; exit 127; }
command -v awk >/dev/null || { echo "awk not found" >&2; exit 127; }

base_name="$(basename "$input_path")"
base_name="${base_name%.*}"
if [[ -z "$output_dir" ]]; then
  output_dir="$(dirname "$input_path")/frames/$base_name"
fi
mkdir -p "$output_dir"

shopt -s nullglob
existing_frames=("$output_dir"/frame_*.jpg)
if [[ ${#existing_frames[@]} -gt 0 ]]; then
  echo "Output directory already contains sampled frames: $output_dir" >&2
  echo "Choose an empty output directory to avoid mixing runs." >&2
  exit 1
fi

duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_path")"
if ! awk -v value="$duration" 'BEGIN { exit !(value > 0) }'; then
  echo "Could not determine a positive video duration." >&2
  exit 1
fi

interval="$(awk -v duration="$duration" -v count="$frame_count" 'BEGIN {
  if (count <= 1 || duration <= 1) {
    print 1
  } else {
    value = duration / (count - 1)
    if (value < 1) value = 1
    printf "%.6f", value
  }
}')"

ffmpeg -y -hide_banner -loglevel error \
  -i "$input_path" \
  -map 0:v:0 -an \
  -vf "fps=1/${interval},scale='min(${frame_width},iw)':-2" \
  -q:v 2 -frames:v "$frame_count" \
  "$output_dir/frame_%03d.jpg"

frames=("$output_dir"/frame_*.jpg)
if [[ ${#frames[@]} -eq 0 ]]; then
  echo "No frames were produced." >&2
  exit 1
fi

manifest="$output_dir/frames.tsv"
printf 'file\tapprox_seconds\n' > "$manifest"
frame_index=0
for frame in "${frames[@]}"; do
  seconds="$(awk -v frame_index="$frame_index" -v interval="$interval" 'BEGIN { printf "%.3f", frame_index * interval }')"
  printf '%s\t%s\n' "$(basename "$frame")" "$seconds" >> "$manifest"
  frame_index=$((frame_index + 1))
done

echo "Sampled ${#frames[@]} frame(s):"
echo "$output_dir"
echo "Manifest: $manifest"
