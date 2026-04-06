# llama-cpp-server-manager

Profile-based model serving for llama.cpp. Switch between models without editing the systemd service.

## Directory layout

```
/var/lib/llama-cpp/
├── models/              # GGUF model files
├── profiles/            # Model config profiles (.conf)
│   ├── active.conf      # Symlink to the current profile
│   ├── glm-4.7-flash.conf
│   └── gemma-4-26b.conf
├── serve.sh             # Launcher script (reads active profile)
└── README.md
```

## Quick reference

```bash
# List available profiles (shows which is active)
llama-switch

# Switch to a profile
llama-switch gemma-4-26b

# Switch and restart the service in one step
llama-switch glm-4.7-flash --restart

# Manual service control
systemctl start llama-cpp
systemctl stop llama-cpp
systemctl status llama-cpp
journalctl -u llama-cpp -f    # tail logs
```

## Adding a new model

1. **Download the GGUF** into `/var/lib/llama-cpp/models/`.

2. **Create a profile** by copying an existing one:

   ```bash
   cp /var/lib/llama-cpp/profiles/gemma-4-26b.conf \
      /var/lib/llama-cpp/profiles/my-new-model.conf
   ```

3. **Edit the profile** - update at minimum:
   - `MODEL_NAME` - friendly name (used as `--alias`)
   - `MODEL_PATH` - path to the GGUF file
   - `MMPROJ_PATH` - path to vision projector GGUF (leave empty if none)
   - Sampling parameters (`TEMP`, `TOP_P`, `TOP_K`, `MIN_P`) per the model's docs
   - `EXTRA_FLAGS` - any model-specific flags (e.g. `--jinja`, `--chat-template-kwargs`)

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
| `PORT`           | Listen port                          | `8080`      |
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
