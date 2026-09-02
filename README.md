# MLX Studio

Native macOS application for running and managing MLX language models locally — inspired by LM Studio, built with SwiftUI and [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm).

![macOS](https://img.shields.io/badge/macOS-15%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)

## Features

- **Chat** — multi-turn conversations with streaming responses
- **Model catalog** — curated MLX models (Qwen3, Llama 3.2, Gemma, Phi-4, SmolLM)
- **Custom models** — load any model from Hugging Face (`mlx-community/*`)
- **Inspector panel** — system prompt, temperature, top-p, max tokens
- **Local API server** — OpenAI-compatible endpoints (`/v1/chat/completions`, `/v1/models`)
- **Native UI** — `NavigationSplitView`, sidebar, inspector, Settings window

## Requirements

- macOS 15+ (Sequoia or later)
- Apple Silicon Mac (M1/M2/M3/M4/M5)
- Xcode 16+ with Metal Toolchain
- 8 GB+ unified memory (16 GB+ recommended for 4B+ models)

## mlx-lm Setup

On first launch MLX Studio checks for **mlx-lm** (Python). If missing, it offers one-click install into:

`~/Library/Application Support/MLXStudio/venv`

### Automatic scripts (also in `Scripts/`)

```bash
# Check if mlx-lm is installed
./Scripts/check-mlx-lm.sh

# Install mlx-lm into Application Support venv
./Scripts/install-mlx-lm.sh

# Start OpenAI-compatible Python server
./Scripts/start-mlx-lm-server.sh

# Remove bundled venv
./Scripts/uninstall-mlx-lm.sh
```

After install, enable **Use mlx-lm server** in the **Server** tab to run the Python backend on port 8080.

## Getting Started

1. Open the project in Xcode:

   ```bash
   open MLXStudio/MLXStudio.xcodeproj
   ```

2. Select your **Development Team** in Signing & Capabilities (target: MLXStudio).

3. Build and run (`⌘R`).

4. On first launch, pick a model in **Models** → **Load Model**. Models download from Hugging Face automatically.

## Usage

### Chat

1. Go to **Chat** in the sidebar.
2. Select a model from the toolbar or inspector.
3. Click **Load** in the inspector panel.
4. Type a message and press `⌘↩` or click send.

### Models

Browse featured models, search by name, or add a custom Hugging Face ID:

```
mlx-community/Qwen3-4B-4bit
```

### Local API Server

1. Open **Server** in the sidebar.
2. Enable **Local Server** (default port: `8080`).
3. Use from any OpenAI-compatible client:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Qwen3-1.7B-4bit",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Streaming is supported with `"stream": true`.

## Architecture

```
MLXStudio/
├── MLXStudioApp.swift      # App entry point
├── AppState.swift          # Global state (engine, server, conversations)
├── Models/                 # Data models
├── Services/
│   ├── MLXEngine.swift     # Model loading & inference (mlx-swift-lm)
│   ├── HubIntegration.swift # Hugging Face downloader/tokenizer bridge
│   └── LocalAPIServer.swift # OpenAI-compatible HTTP server
└── Views/                  # SwiftUI views
```

Built on:

- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) — LLM inference
- [swift-huggingface](https://github.com/huggingface/swift-huggingface) — model downloads
- [swift-transformers](https://github.com/huggingface/swift-transformers) — tokenizers

## Recommended Models by Memory

| Unified Memory | Recommended Models |
|----------------|-------------------|
| 8 GB           | SmolLM 135M, Qwen3 0.6B, Llama 3.2 1B |
| 16 GB          | Qwen3 1.7B, Qwen2.5 1.5B, Gemma 3 1B |
| 24 GB+         | Qwen3 4B, Phi-4 Mini |
| 32 GB+         | Qwen3 8B |

## Troubleshooting

**Metal Toolchain missing**

```bash
xcodebuild -downloadComponent MetalToolchain
```

**Out of memory**

Use a smaller quantized model (0.6B–1.7B) or unload the current model before loading another.

**Sandbox network**

The app requires network access to download models from Hugging Face. This is enabled in entitlements.

## License

MIT
