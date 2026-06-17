# pOCR

Native macOS menu bar OCR app powered by **PaddleOCR-VL-1.6** local model.

## Features

- **Native GUI:** Lightweight Menu Bar app (Status Bar item)
- **Clipboard OCR:** Takes image from clipboard, processes with PaddleOCR-VL-1.6 locally, and copies text back
- **Local Model:** Runs entirely on-device — no API keys, no network calls
- **Global Shortcut:** Configurable hotkey (default: `Cmd+Shift+A`)

## Requirements

- macOS 13.0+ (Ventura or newer)
- Swift 5.7+ (Xcode Command Line Tools)
- [uv](https://docs.astral.sh/uv/) (Python package manager)

## Installation

```bash
# 1. Install Python dependencies
uv sync

# 2. Build the app
make

# 3. Run
open build/pOCR.app
# or
make run
```

## Usage

1. Launch the app (icon appears in Menu Bar)
2. Copy an image to clipboard (`Cmd+Ctrl+Shift+4`)
3. Click the Menu Bar icon → **Run OCR from Clipboard** (or press `Cmd+Shift+A`)
4. Wait for the icon to stop spinning
5. Text is copied to clipboard!

## Architecture

- **Language:** Swift 5
- **UI Framework:** SwiftUI + AppKit
- **OCR Engine:** PaddleOCR-VL-1.6 (local, via `paddleocr` CLI)
- **Full Pipeline:** PP-DocLayoutV3 (layout analysis) + PaddleOCR-VL-1.6-0.9B (VLM recognition)

## License

MIT
