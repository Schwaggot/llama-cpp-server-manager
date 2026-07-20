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

# GPU presence check before starting. llama-server treats a failed CUDA init as
# non-fatal and silently falls back to CPU, which serves at a fraction of the
# expected speed while the unit still looks healthy. "auto" enforces the check
# only on hosts that actually have an NVIDIA device node.
REQUIRE_GPU="auto"
GPU_WAIT_SECS="60"

# shellcheck source=/dev/null
source "$PROFILE"

# --- GPU readiness gate ---
# At boot the NVIDIA stack can come up after this service. /dev/nvidia-uvm in
# particular is created lazily, and losing that race makes CUDA init fail with
# "unknown error". Wait for a usable CUDA device, then hard-fail so systemd
# restarts us instead of quietly serving from CPU.
if [[ "$REQUIRE_GPU" == "auto" ]]; then
    if [[ -e /dev/nvidia0 ]] || command -v nvidia-smi >/dev/null 2>&1; then
        REQUIRE_GPU="yes"
    else
        REQUIRE_GPU="no"
    fi
fi

if [[ "$REQUIRE_GPU" == "yes" && "$GPU_LAYERS" != "0" ]]; then
    echo "GPU required: waiting up to ${GPU_WAIT_SECS}s for a usable CUDA device..."
    deadline=$(( SECONDS + GPU_WAIT_SECS ))
    gpu_ok=0
    while (( SECONDS < deadline )); do
        # nvidia-modprobe is setuid-root and creates the UVM nodes on demand.
        # Best-effort: the systemd unit already does this via ExecStartPre.
        command -v nvidia-modprobe >/dev/null 2>&1 && nvidia-modprobe -c 0 -u >/dev/null 2>&1 || true

        if /usr/local/bin/llama-server --list-devices 2>/dev/null | grep -q '^ *CUDA'; then
            gpu_ok=1
            break
        fi
        sleep 2
    done

    if (( gpu_ok == 0 )); then
        echo "ERROR: no usable CUDA device after ${GPU_WAIT_SECS}s." >&2
        echo "Refusing to start on CPU. Diagnostics:" >&2
        /usr/local/bin/llama-server --list-devices >&2 2>&1 || true
        nvidia-smi >&2 2>&1 || true
        exit 1
    fi
    echo "CUDA device present:"
    /usr/local/bin/llama-server --list-devices 2>/dev/null | grep '^ *CUDA' || true
fi

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
