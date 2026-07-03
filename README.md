# llama-cpp-server-manager

Profile-based model serving for [llama.cpp](https://github.com/ggml-org/llama.cpp). Switch between models without editing the systemd service.

## Quick start

On a machine that already has this set up:

```bash
# See what's available (interactive picker if run with no args)
llama-switch

# Switch and restart in one step
llama-switch qwen36-27b-think-code --restart

# Tail the server
journalctl -u llama-cpp -f
```

The server listens on `http://0.0.0.0:8090` (OpenAI-compatible `/v1/...` endpoints + llama.cpp's native API).

## Installation (new machine)

Tested on Debian/Ubuntu. Run as root.

### 1. Build / install `llama-server`

Either build from source:

```bash
apt install -y build-essential cmake git libcurl4-openssl-dev
git clone https://github.com/ggml-org/llama.cpp.git /opt/llama.cpp
cd /opt/llama.cpp
cmake -B build -DGGML_CUDA=OFF        # add -DGGML_CUDA=ON for NVIDIA
cmake --build build --config Release -j
install -m 0755 build/bin/llama-server /usr/local/bin/llama-server
```

…or drop a prebuilt `llama-server` binary into `/usr/local/bin/`.

Verify: `llama-server --version`.

### 2. Create the service user and base directory

```bash
useradd --system --home /var/lib/llama-cpp --shell /usr/sbin/nologin llama-cpp
install -d -o llama-cpp -g llama-cpp /var/lib/llama-cpp
# GPU access (only needed if using a GPU build)
usermod -aG video,render llama-cpp
```

### 3. Clone this repo into the base directory

```bash
git clone git@github.com:Schwaggot/llama-cpp-server-manager.git /tmp/lcsm
cp -r /tmp/lcsm/{profiles,serve.sh,llama-switch,README.md,LICENSE} /var/lib/llama-cpp/
install -d -o llama-cpp -g llama-cpp /var/lib/llama-cpp/models
chown -R llama-cpp:llama-cpp /var/lib/llama-cpp
chmod +x /var/lib/llama-cpp/serve.sh
```

### 4. Install the `llama-switch` CLI and systemd unit

```bash
ln -sf /var/lib/llama-cpp/llama-switch /usr/local/bin/llama-switch
apt install -y whiptail        # for the interactive picker

cat >/etc/systemd/system/llama-cpp.service <<'EOF'
[Unit]
Description=llama.cpp Server (profile-based)
After=network.target

# NVIDIA GPU only: keep the driver initialized so the CUDA device nodes persist
# across the boot window. Weak dependency, so it is a no-op without a GPU.
After=nvidia-persistenced.service
Wants=nvidia-persistenced.service

[Service]
Type=simple
User=llama-cpp
Group=llama-cpp

# NVIDIA GPU only: /dev/nvidia-uvm is created lazily at boot, so the server can
# lose the race and fail CUDA init. Force the node into existence first. The
# leading '+' runs this as root, which the setuid nvidia-modprobe needs since
# NoNewPrivileges= neutralizes its setuid bit. Adjust the path if needed.
ExecStartPre=+/usr/bin/nvidia-modprobe -c 0 -u

ExecStart=/var/lib/llama-cpp/serve.sh
Restart=on-failure
RestartSec=5

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/llama-cpp
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable llama-cpp

# NVIDIA GPU only: enable persistence so the driver stays initialized at boot.
systemctl enable --now nvidia-persistenced
```

### 5. Download at least one model

Models live in **`/var/lib/llama-cpp/models/`** and must be readable by the `llama-cpp` user. Pull GGUFs from Hugging Face — Unsloth's `UD-Q*_K_XL` quants are the default choice referenced by the bundled profiles.

```bash
cd /var/lib/llama-cpp/models

# Example: Qwen3.6 27B (dense, multimodal)
curl -L -o Qwen3.6-27B-UD-Q4_K_XL.gguf \
  "https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/Qwen3.6-27B-UD-Q4_K_XL.gguf?download=true"
curl -L -o Qwen3.6-27B-mmproj-BF16.gguf \
  "https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/mmproj-BF16.gguf?download=true"

chown llama-cpp:llama-cpp Qwen3.6-27B-*.gguf
```

For multi-part GGUFs (`*-00001-of-000NN.gguf`, …) download every part into the same directory; point `MODEL_PATH` in the profile at part 1 only.

The filename in `MODEL_PATH` of each bundled profile is what you need locally — `grep MODEL_PATH /var/lib/llama-cpp/profiles/*.conf` shows the full list.

### 6. Activate a profile and start the server

```bash
llama-switch qwen36-27b-think-code --restart
systemctl status llama-cpp
```

## Directory layout

```
/var/lib/llama-cpp/
├── models/              # GGUF model files (download target)
├── profiles/            # Model config profiles (.conf)
│   ├── active.conf      # Symlink to the current profile
│   ├── qwen36-27b.conf
│   └── …
├── serve.sh             # Launcher script (reads active profile)
├── llama-switch         # Profile switcher CLI (symlinked into /usr/local/bin)
└── README.md
```

## Day-to-day usage

```bash
# List available profiles (shows which is active)
llama-switch --list

# Interactive picker
llama-switch

# Switch only
llama-switch qwen36-27b

# Switch and restart in one step
llama-switch glm-4.7-flash --restart

# Manual service control
systemctl start llama-cpp
systemctl stop llama-cpp
systemctl status llama-cpp
journalctl -u llama-cpp -f    # tail logs
```

## Adding a new model

1. **Download the GGUF** into `/var/lib/llama-cpp/models/` (and the `mmproj` file too if the model is multimodal). Make sure it is readable by the `llama-cpp` user.

2. **Create a profile** by copying an existing one:

   ```bash
   cp /var/lib/llama-cpp/profiles/qwen36-27b.conf \
      /var/lib/llama-cpp/profiles/my-new-model.conf
   ```

3. **Edit the profile** — at minimum:
   - `MODEL_NAME` — friendly name (used as `--alias`)
   - `MODEL_PATH` — path to the GGUF file
   - `MMPROJ_PATH` — path to vision projector GGUF (leave empty if none)
   - Sampling parameters (`TEMP`, `TOP_P`, `TOP_K`, `MIN_P`) per the model's docs
   - `EXTRA_FLAGS` — any model-specific flags (e.g. `--jinja`, `--chat-template-kwargs`)

4. **Switch and start**:

   ```bash
   llama-switch my-new-model --restart
   ```

## Profile format

Profiles are bash files sourced by `serve.sh`. All variables have sensible defaults; you only need to set what differs.

| Variable         | Description                          | Default     |
|------------------|--------------------------------------|-------------|
| `MODEL_NAME`     | Display name / alias                 | (none)      |
| `MODEL_PATH`     | Path to GGUF file (required)         | -           |
| `MMPROJ_PATH`    | Path to multimodal projector GGUF    | (none)      |
| `HOST`           | Listen address                       | `0.0.0.0`   |
| `PORT`           | Listen port                          | `8090`      |
| `GPU_LAYERS`     | Number of layers on GPU              | `auto`      |
| `CTX_SIZE`       | Context window size                  | `32768`     |
| `BATCH_SIZE`     | Batch size                           | `8192`      |
| `UBATCH_SIZE`    | Micro-batch size                     | `4096`      |
| `FLASH_ATTN`     | Flash attention                      | `on`        |
| `THREADS`        | CPU threads                          | `16`        |
| `PARALLEL`       | Parallel request slots               | `1`         |
| `CACHE_TYPE_K`   | KV cache key quantization            | (none)      |
| `CACHE_TYPE_V`   | KV cache value quantization          | (none)      |
| `TEMP`           | Temperature                          | (none)      |
| `TOP_P`          | Top-p sampling                       | (none)      |
| `TOP_K`          | Top-k sampling                       | (none)      |
| `MIN_P`          | Min-p sampling                       | (none)      |
| `REPEAT_PENALTY` | Repetition penalty                   | (none)      |
| `EXTRA_FLAGS`    | Additional flags (added verbatim)    | (none)      |

## Environment override

You can bypass the active symlink by setting `LLAMA_PROFILE`:

```bash
LLAMA_PROFILE=glm-4.7-flash.conf /var/lib/llama-cpp/serve.sh
```

This is handy for spinning up a second instance on another port without touching the active profile:

```bash
sudo -u llama-cpp PORT=8081 LLAMA_PROFILE=qwen36-27b.conf /var/lib/llama-cpp/serve.sh
```
