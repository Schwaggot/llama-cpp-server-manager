#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/var/lib/llama-cpp"
PROFILES_DIR="$BASE_DIR/profiles"
ACTIVE_LINK="$BASE_DIR/profiles/active.conf"

# --- resolve profile ---
if [[ -L "$ACTIVE_LINK" ]]; then
    PROFILE="$(readlink -f "$ACTIVE_LINK")"
elif [[ -n "${LLAMA_PROFILE:-}" ]]; then
    PROFILE="$PROFILES_DIR/$LLAMA_PROFILE"
else
    echo "ERROR: No active profile. Run:  llama-switch <profile-name>" >&2
    echo "Available profiles:" >&2
    ls "$PROFILES_DIR"/*.conf 2>/dev/null | grep -v active.conf | xargs -I{} basename {} .conf >&2
    exit 1
fi

if [[ ! -f "$PROFILE" ]]; then
    echo "ERROR: Profile not found: $PROFILE" >&2
    exit 1
fi

echo "Loading profile: $PROFILE"

# --- defaults (can be overridden by profile) ---
HOST="0.0.0.0"
PORT="8090"
GPU_LAYERS="auto"
CTX_SIZE="32768"
BATCH_SIZE="8192"
UBATCH_SIZE="4096"
FLASH_ATTN="on"
THREADS="16"
PARALLEL="1"
CACHE_TYPE_K=""
CACHE_TYPE_V=""
TEMP=""
TOP_P=""
MIN_P=""
TOP_K=""
REPEAT_PENALTY=""
MMPROJ_PATH=""
MODEL_DRAFT_PATH=""
EXTRA_FLAGS=""
MODEL_NAME=""

# shellcheck source=/dev/null
source "$PROFILE"

# --- build command ---
CMD=( /usr/local/bin/llama-server
    --model "$MODEL_PATH"
    --host "$HOST"
    --port "$PORT"
    --gpu-layers "$GPU_LAYERS"
    --ctx-size "$CTX_SIZE"
    --flash-attn "$FLASH_ATTN"
    --batch-size "$BATCH_SIZE"
    --ubatch-size "$UBATCH_SIZE"
    --threads "$THREADS"
    --parallel "$PARALLEL"
)

[[ -n "$MMPROJ_PATH" && -f "$MMPROJ_PATH" ]] && CMD+=( --mmproj "$MMPROJ_PATH" )
[[ -n "$MODEL_DRAFT_PATH" && -f "$MODEL_DRAFT_PATH" ]] && CMD+=( --model-draft "$MODEL_DRAFT_PATH" )
[[ -n "$CACHE_TYPE_K" ]]  && CMD+=( --cache-type-k "$CACHE_TYPE_K" )
[[ -n "$CACHE_TYPE_V" ]]  && CMD+=( --cache-type-v "$CACHE_TYPE_V" )
[[ -n "$TEMP" ]]           && CMD+=( --temp "$TEMP" )
[[ -n "$TOP_P" ]]          && CMD+=( --top-p "$TOP_P" )
[[ -n "$MIN_P" ]]          && CMD+=( --min-p "$MIN_P" )
[[ -n "$TOP_K" ]]          && CMD+=( --top-k "$TOP_K" )
[[ -n "$REPEAT_PENALTY" ]] && CMD+=( --repeat-penalty "$REPEAT_PENALTY" )
[[ -n "$MODEL_NAME" ]]     && CMD+=( --alias "$MODEL_NAME" )

# Extra flags are word-split intentionally
if [[ -n "$EXTRA_FLAGS" ]]; then
    eval CMD+=( $EXTRA_FLAGS )
fi

echo "Starting: ${CMD[*]}"
exec "${CMD[@]}"
