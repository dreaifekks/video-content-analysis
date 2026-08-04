#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  transcribe_local_whisper.sh "/path/to/video-or-audio" [output_dir] [base_name]

Platform:
  macOS. Apple Silicon prefers mlx_whisper; verify another engine on Intel Mac.

Environment:
  LOCAL_WHISPER_ENGINE      auto | mlx_whisper | whisper | whisper_cpp
                            Default: auto
  LOCAL_WHISPER_BIN         Optional explicit binary path.
  LOCAL_WHISPER_MODEL       OpenAI Whisper CLI model. Default: turbo
  LOCAL_WHISPER_MLX_MODEL   MLX model. Default: mlx-community/whisper-large-v3-turbo
  LOCAL_WHISPER_CPP_MODEL   Path to a whisper.cpp ggml model. Required for whisper_cpp.
  LOCAL_WHISPER_LANGUAGE    Optional language code. Empty means auto-detect.
  LOCAL_WHISPER_FORMAT      vtt | srt | txt. Default: vtt
  LOCAL_WHISPER_PROMPT      Optional domain vocabulary or initial prompt.
  LOCAL_WHISPER_MLX_CONDITION_ON_PREVIOUS_TEXT
                            Default: False to reduce repetition in long recordings.
  LOCAL_WHISPER_VERBOSE     Default: False for mlx_whisper.

Outputs:
  <output_dir>/<base_name>.local-whisper.transcript.md
  <output_dir>/audio/<base_name>.local.mp3 or .wav
  <output_dir>/segments/* raw transcription output
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
base_name="${3:-}"

if [[ ! -f "$input_path" ]]; then
  echo "Input file not found: $input_path" >&2
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 127; }

if [[ -z "$output_dir" ]]; then
  output_dir="$(dirname "$input_path")/transcripts"
fi

if [[ -z "$base_name" ]]; then
  base_name="$(basename "$input_path")"
  base_name="${base_name%.*}"
else
  base_name="$(basename "$base_name")"
fi

engine="${LOCAL_WHISPER_ENGINE:-auto}"
language="${LOCAL_WHISPER_LANGUAGE:-}"
format="${LOCAL_WHISPER_FORMAT:-vtt}"
model="${LOCAL_WHISPER_MODEL:-turbo}"
mlx_model="${LOCAL_WHISPER_MLX_MODEL:-mlx-community/whisper-large-v3-turbo}"
mlx_condition="${LOCAL_WHISPER_MLX_CONDITION_ON_PREVIOUS_TEXT:-False}"
verbose="${LOCAL_WHISPER_VERBOSE:-False}"
initial_prompt="${LOCAL_WHISPER_PROMPT:-}"

case "$format" in
  vtt|srt|txt) ;;
  *) echo "Unsupported LOCAL_WHISPER_FORMAT: $format" >&2; exit 2 ;;
esac

audio_dir="$output_dir/audio"
segments_dir="$output_dir/segments"
mkdir -p "$audio_dir" "$segments_dir"

resolve_engine() {
  if [[ "$engine" != "auto" ]]; then
    echo "$engine"
  elif [[ -n "${LOCAL_WHISPER_BIN:-}" ]]; then
    case "$(basename "$LOCAL_WHISPER_BIN")" in
      mlx_whisper) echo "mlx_whisper" ;;
      whisper) echo "whisper" ;;
      whisper-cli|whisper-cpp) echo "whisper_cpp" ;;
      *) echo "custom" ;;
    esac
  elif [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] && command -v mlx_whisper >/dev/null; then
    echo "mlx_whisper"
  elif command -v whisper >/dev/null; then
    echo "whisper"
  elif command -v whisper-cli >/dev/null || command -v whisper-cpp >/dev/null; then
    echo "whisper_cpp"
  else
    echo "missing"
  fi
}

resolved_engine="$(resolve_engine)"
effective_format="$format"

case "$resolved_engine" in
  mlx_whisper)
    if [[ -n "${LOCAL_WHISPER_BIN:-}" ]]; then
      bin="$LOCAL_WHISPER_BIN"
    elif command -v mlx_whisper >/dev/null; then
      bin="$(command -v mlx_whisper)"
    else
      echo "mlx_whisper not found. Set LOCAL_WHISPER_BIN or install it on PATH." >&2
      exit 127
    fi
    audio_path="$audio_dir/${base_name}.local.mp3"
    ffmpeg -y -hide_banner -loglevel error -i "$input_path" -vn -ac 1 -ar 16000 -b:a 64k "$audio_path"

    args=(
      "$audio_path"
      --model "$mlx_model"
      --task transcribe
      --output-dir "$segments_dir"
      --output-format "$format"
      --output-name "$base_name"
      --condition-on-previous-text "$mlx_condition"
      --verbose "$verbose"
    )
    [[ -n "$language" ]] && args+=(--language "$language")
    [[ -n "$initial_prompt" ]] && args+=(--initial-prompt "$initial_prompt")
    "$bin" "${args[@]}"
    raw_file="$segments_dir/${base_name}.${format}"
    engine_model="$mlx_model"
    ;;

  whisper)
    if [[ -n "${LOCAL_WHISPER_BIN:-}" ]]; then
      bin="$LOCAL_WHISPER_BIN"
    elif command -v whisper >/dev/null; then
      bin="$(command -v whisper)"
    else
      echo "whisper not found. Set LOCAL_WHISPER_BIN or install it on PATH." >&2
      exit 127
    fi
    audio_path="$audio_dir/${base_name}.local.mp3"
    audio_stem="$(basename "$audio_path")"
    audio_stem="${audio_stem%.*}"
    ffmpeg -y -hide_banner -loglevel error -i "$input_path" -vn -ac 1 -ar 16000 -b:a 64k "$audio_path"

    args=(
      "$audio_path"
      --model "$model"
      --task transcribe
      --output_dir "$segments_dir"
      --output_format "$format"
      --verbose False
    )
    [[ -n "$language" ]] && args+=(--language "$language")
    [[ -n "$initial_prompt" ]] && args+=(--initial_prompt "$initial_prompt")
    "$bin" "${args[@]}"
    raw_file="$segments_dir/${audio_stem}.${format}"
    engine_model="$model"
    ;;

  whisper_cpp)
    if [[ -n "${LOCAL_WHISPER_BIN:-}" ]]; then
      bin="$LOCAL_WHISPER_BIN"
    elif command -v whisper-cli >/dev/null; then
      bin="$(command -v whisper-cli)"
    elif command -v whisper-cpp >/dev/null; then
      bin="$(command -v whisper-cpp)"
    else
      echo "whisper-cli or whisper-cpp not found. Set LOCAL_WHISPER_BIN or install one on PATH." >&2
      exit 127
    fi

    if [[ -z "${LOCAL_WHISPER_CPP_MODEL:-}" ]]; then
      echo "LOCAL_WHISPER_CPP_MODEL is required for whisper_cpp." >&2
      exit 1
    fi

    wav_path="$audio_dir/${base_name}.local.wav"
    ffmpeg -y -hide_banner -loglevel error -i "$input_path" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$wav_path"
    args=(-m "$LOCAL_WHISPER_CPP_MODEL" -f "$wav_path" -ovtt -of "$segments_dir/${base_name}")
    [[ -n "$language" ]] && args+=(-l "$language")
    "$bin" "${args[@]}"
    effective_format="vtt"
    raw_file="$segments_dir/${base_name}.vtt"
    engine_model="$(basename "$LOCAL_WHISPER_CPP_MODEL")"
    ;;

  custom)
    echo "Unrecognized LOCAL_WHISPER_BIN. Set LOCAL_WHISPER_ENGINE explicitly." >&2
    exit 2
    ;;

  missing)
    echo "No local Whisper command found in PATH." >&2
    echo "Install mlx_whisper, whisper, whisper-cli, or whisper-cpp; or set LOCAL_WHISPER_BIN." >&2
    exit 127
    ;;

  *)
    echo "Unsupported LOCAL_WHISPER_ENGINE: $resolved_engine" >&2
    exit 2
    ;;
esac

if [[ ! -f "$raw_file" ]]; then
  echo "Expected transcript output was not found: $raw_file" >&2
  exit 1
fi

combined="$output_dir/${base_name}.local-whisper.transcript.md"
source_label="$(basename "$input_path")"
{
  echo "# Local Whisper Transcript"
  echo
  echo "- Source: $source_label"
  echo "- Engine: $resolved_engine"
  echo "- Model: $engine_model"
  echo "- Language: ${language:-auto}"
  echo "- Format: $effective_format"
  echo
  echo "## Transcript"
  echo
  cat "$raw_file"
  echo
} > "$combined"

echo "Transcript complete:"
echo "$combined"
