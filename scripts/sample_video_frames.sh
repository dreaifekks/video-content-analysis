#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sample_video_frames.sh "/path/to/video" [output_dir] [intensity]

Arguments:
  intensity                 auto, low, standard, high, or max. Default: auto

Environment:
  VIDEO_ANALYSIS_INTENSITY  Fallback intensity when the positional value is omitted.
  FRAME_COUNT               Optional hard frame limit. Unset means unlimited.
  FRAME_WIDTH               Maximum output width in pixels. Default: 1600
  FRAME_MIN_GAP             Optional minimum seconds between candidate frames.
  FRAME_MAX_GAP             Optional maximum seconds without a coverage frame.
  FRAME_SCENE_THRESHOLD     Optional visual-change threshold from 0 to 1.

Outputs:
  <output_dir>/frame_0001.jpg ...
  <output_dir>/frames.tsv with selected timestamps
  <output_dir>/sampling.tsv with density and sampling settings

The default auto mode probes visual-change density, chooses a profile, and then
samples static intervals sparsely while adding frames around stronger changes.
Intensity controls sampling frequency, not a default total-frame ceiling.
The output directory must not already contain frame_*.jpg files.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

input_path="$1"
output_dir="${2:-}"
requested_intensity="${3:-${VIDEO_ANALYSIS_INTENSITY:-auto}}"
frame_width="${FRAME_WIDTH:-1600}"

if [[ ! -f "$input_path" ]]; then
  echo "Input file not found: $input_path" >&2
  exit 1
fi

requested_intensity="$(printf '%s' "$requested_intensity" | tr '[:upper:]' '[:lower:]')"
if [[ "$requested_intensity" == "medium" ]]; then
  requested_intensity="standard"
fi

case "$requested_intensity" in
  auto|low|standard|high|max) ;;
  *)
    echo "VIDEO_ANALYSIS_INTENSITY must be auto, low, standard, high, or max." >&2
    exit 2
    ;;
esac

[[ "$frame_width" =~ ^[1-9][0-9]*$ ]] || {
  echo "FRAME_WIDTH must be a positive integer." >&2
  exit 2
}

if [[ -n "${FRAME_COUNT:-}" && ! "${FRAME_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "FRAME_COUNT must be a positive integer." >&2
  exit 2
fi

is_positive_number() {
  local value="$1"
  [[ "$value" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] &&
    awk -v value="$value" 'BEGIN { exit !(value > 0) }'
}

is_threshold() {
  local value="$1"
  [[ "$value" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] &&
    awk -v value="$value" 'BEGIN { exit !(value >= 0 && value <= 1) }'
}

for gap_name in FRAME_MIN_GAP FRAME_MAX_GAP; do
  gap_value="${!gap_name:-}"
  if [[ -n "$gap_value" ]] && ! is_positive_number "$gap_value"; then
    echo "$gap_name must be a positive number of seconds." >&2
    exit 2
  fi
done

if [[ -n "${FRAME_SCENE_THRESHOLD:-}" ]] && ! is_threshold "$FRAME_SCENE_THRESHOLD"; then
  echo "FRAME_SCENE_THRESHOLD must be between 0 and 1." >&2
  exit 2
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 127; }
command -v ffprobe >/dev/null || { echo "ffprobe not found" >&2; exit 127; }
command -v awk >/dev/null || { echo "awk not found" >&2; exit 127; }
command -v mktemp >/dev/null || { echo "mktemp not found" >&2; exit 127; }

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
if ! is_positive_number "$duration"; then
  echo "Could not determine a positive video duration." >&2
  exit 1
fi

density_log=""
frame_log=""
timestamps_file=""
cleanup() {
  [[ -z "$density_log" || ! -f "$density_log" ]] || rm -f -- "$density_log"
  [[ -z "$frame_log" || ! -f "$frame_log" ]] || rm -f -- "$frame_log"
  [[ -z "$timestamps_file" || ! -f "$timestamps_file" ]] || rm -f -- "$timestamps_file"
}
trap cleanup EXIT

effective_intensity="$requested_intensity"
probe_interval="not_run"
density_scene_average="not_run"
density_change_ratio="not_run"
density_probe_frames="0"

if [[ "$requested_intensity" == "auto" ]]; then
  probe_interval="$(awk -v duration="$duration" 'BEGIN {
    value = duration / 240
    if (value < 1) value = 1
    if (value > 30) value = 30
    printf "%.6f", value
  }')"
  density_log="$(mktemp "${TMPDIR:-/tmp}/video-density.XXXXXX")"

  if ffmpeg -hide_banner -loglevel error \
    -i "$input_path" \
    -map 0:v:0 -an \
    -vf "fps=1/${probe_interval},select='gte(scene,0)',metadata=print:file=${density_log}" \
    -f null -; then
    density_stats="$(awk -F= '
      /lavfi.scene_score=/ {
        value = $2 + 0
        total += value
        if (value >= 0.08) changed += 1
        count += 1
      }
      END {
        if (count > 0) {
          printf "%.6f\t%.6f\t%d", total / count, changed / count, count
        } else {
          printf "0\t0\t0"
        }
      }
    ' "$density_log")"
    IFS=$'\t' read -r density_scene_average density_change_ratio density_probe_frames <<< "$density_stats"

    if [[ "$density_probe_frames" -lt 3 ]]; then
      effective_intensity="standard"
    elif awk -v average="$density_scene_average" -v ratio="$density_change_ratio" \
      'BEGIN { exit !(average < 0.01 && ratio < 0.03) }'; then
      effective_intensity="low"
    elif awk -v average="$density_scene_average" -v ratio="$density_change_ratio" \
      'BEGIN { exit !(average >= 0.10 || ratio >= 0.35) }'; then
      effective_intensity="high"
    else
      effective_intensity="standard"
    fi
  else
    echo "Visual-density probe failed; using the standard profile." >&2
    effective_intensity="standard"
    density_scene_average="probe_failed"
    density_change_ratio="probe_failed"
  fi
fi

case "$effective_intensity" in
  low)
    baseline_frames=8
    profile_min_gap=30
    profile_max_gap=300
    profile_scene_threshold=0.08
    absolute_gap_floor=1
    ;;
  standard)
    baseline_frames=16
    profile_min_gap=10
    profile_max_gap=120
    profile_scene_threshold=0.01
    absolute_gap_floor=0.5
    ;;
  high)
    baseline_frames=32
    profile_min_gap=3
    profile_max_gap=30
    profile_scene_threshold=0.005
    absolute_gap_floor=0.25
    ;;
  max)
    baseline_frames=60
    profile_min_gap=1
    profile_max_gap=10
    profile_scene_threshold=0.002
    absolute_gap_floor=0.1
    ;;
esac

frame_budget="${FRAME_COUNT:-unlimited}"
requested_min_gap="${FRAME_MIN_GAP:-$profile_min_gap}"
requested_max_gap="${FRAME_MAX_GAP:-$profile_max_gap}"
scene_threshold="${FRAME_SCENE_THRESHOLD:-$profile_scene_threshold}"

coverage_gap="$(awk \
  -v duration="$duration" \
  -v baseline="$baseline_frames" \
  -v requested="$requested_max_gap" \
  -v floor="$absolute_gap_floor" \
  'BEGIN {
    value = duration / baseline
    if (value > requested) value = requested
    if (value < floor) value = floor
    printf "%.6f", value
  }')"

if [[ "$frame_budget" == "1" ]]; then
  candidate_gap="$(awk -v duration="$duration" 'BEGIN { printf "%.6f", duration + 1 }')"
elif [[ "$frame_budget" == "unlimited" ]]; then
  candidate_gap="$(awk \
    -v requested="$requested_min_gap" \
    -v coverage="$coverage_gap" \
    -v floor="$absolute_gap_floor" \
    'BEGIN {
      value = requested
      if (value > coverage) value = coverage
      if (value < floor) value = floor
      printf "%.6f", value
    }')"
else
  budget_gap="$(awk -v duration="$duration" -v budget="$frame_budget" \
    'BEGIN { printf "%.6f", ((duration / budget) * 1.000001) + 0.000001 }')"
  candidate_gap="$(awk \
    -v requested="$requested_min_gap" \
    -v coverage="$coverage_gap" \
    -v budget="$budget_gap" \
    -v floor="$absolute_gap_floor" \
    'BEGIN {
      value = requested
      if (value > coverage) value = coverage
      if (value < budget) value = budget
      if (value < floor) value = floor
      printf "%.6f", value
    }')"
fi

max_gap="$(awk -v coverage="$coverage_gap" -v candidate="$candidate_gap" \
  'BEGIN {
    value = coverage
    if (value < candidate) value = candidate
    printf "%.6f", value
  }')"

sampling_manifest="$output_dir/sampling.tsv"
frame_manifest="$output_dir/frames.tsv"

if [[ "$frame_budget" == "1" ]]; then
  midpoint="$(awk -v duration="$duration" 'BEGIN { printf "%.6f", duration / 2 }')"
  ffmpeg -y -hide_banner -loglevel error \
    -ss "$midpoint" -i "$input_path" \
    -map 0:v:0 -an -frames:v 1 \
    -vf "scale='min(${frame_width},iw)':-2" \
    -q:v 2 "$output_dir/frame_0001.jpg"
  printf 'file\tseconds\nframe_0001.jpg\t%s\n' "$midpoint" > "$frame_manifest"
  frame_count_actual=1
else
  end_window_start="$(awk -v duration="$duration" -v gap="$candidate_gap" 'BEGIN {
    value = duration - gap
    if (value < 0) value = 0
    printf "%.6f", value
  }')"
  frame_log="$(mktemp "${TMPDIR:-/tmp}/video-frames.XXXXXX")"
  timestamps_file="$(mktemp "${TMPDIR:-/tmp}/video-timestamps.XXXXXX")"
  baseline_trigger="$(awk -v maximum="$max_gap" -v candidate="$candidate_gap" 'BEGIN {
    value = maximum - (candidate / 2)
    if (value < candidate / 2) value = candidate / 2
    printf "%.6f", value
  }')"
  select_filter="fps=1/${candidate_gap},select='isnan(prev_selected_t)+gte(t-prev_selected_t,${baseline_trigger})+gte(scene,${scene_threshold})+gte(t,${end_window_start})',scale='min(${frame_width},iw)':-2,showinfo"

  if ! ffmpeg -y -hide_banner -loglevel info \
    -i "$input_path" \
    -map 0:v:0 -an \
    -vf "$select_filter" \
    -q:v 2 -fps_mode vfr \
    "$output_dir/frame_%04d.jpg" 2> "$frame_log"; then
    cat "$frame_log" >&2
    echo "Adaptive frame extraction failed." >&2
    exit 1
  fi

  awk '
    /showinfo/ && /pts_time:/ {
      for (field = 1; field <= NF; field += 1) {
        if ($field ~ /^pts_time:/) {
          sub(/^pts_time:/, "", $field)
          print $field
          break
        }
      }
    }
  ' "$frame_log" > "$timestamps_file"

  frames=("$output_dir"/frame_*.jpg)
  if [[ ${#frames[@]} -eq 0 ]]; then
    echo "No frames were produced." >&2
    exit 1
  fi

  timestamps=()
  while IFS= read -r timestamp; do
    [[ -z "$timestamp" ]] || timestamps+=("$timestamp")
  done < "$timestamps_file"

  printf 'file\tseconds\n' > "$frame_manifest"
  frame_index=0
  for frame in "${frames[@]}"; do
    timestamp="${timestamps[$frame_index]:-unknown}"
    printf '%s\t%s\n' "$(basename "$frame")" "$timestamp" >> "$frame_manifest"
    frame_index=$((frame_index + 1))
  done
  frame_count_actual="${#frames[@]}"
fi

{
  printf 'key\tvalue\n'
  printf 'requested_intensity\t%s\n' "$requested_intensity"
  printf 'effective_intensity\t%s\n' "$effective_intensity"
  printf 'duration_seconds\t%s\n' "$duration"
  printf 'density_probe_interval_seconds\t%s\n' "$probe_interval"
  printf 'density_scene_average\t%s\n' "$density_scene_average"
  printf 'density_change_ratio\t%s\n' "$density_change_ratio"
  printf 'density_probe_frames\t%s\n' "$density_probe_frames"
  printf 'candidate_gap_seconds\t%s\n' "$candidate_gap"
  printf 'maximum_coverage_gap_seconds\t%s\n' "$max_gap"
  printf 'scene_threshold\t%s\n' "$scene_threshold"
  printf 'frame_budget\t%s\n' "$frame_budget"
  printf 'frame_count\t%s\n' "$frame_count_actual"
} > "$sampling_manifest"

echo "Adaptive frame sampling complete"
echo "Requested intensity: $requested_intensity"
echo "Effective intensity: $effective_intensity"
if [[ "$frame_budget" == "unlimited" ]]; then
  echo "Sampled frames: $frame_count_actual (no total-frame limit)"
else
  echo "Sampled frames: $frame_count_actual / limit $frame_budget"
fi
echo "Output directory: $output_dir"
echo "Frame manifest: $frame_manifest"
echo "Sampling manifest: $sampling_manifest"
