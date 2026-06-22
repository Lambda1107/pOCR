# pOCR

[中文文档](README.zh.md)

Native macOS menu bar OCR app. Run OCR entirely on-device with **PaddleOCR-VL**,
or send images to a cloud endpoint — the PaddleOCR cloud API, SiliconFlow,
any **OpenAI-compatible** model, or **Kimi (Moonshot)**.

## Features

- **Native GUI:** Lightweight Menu Bar app (Status Bar item)
- **Clipboard OCR:** Takes an image from the clipboard, runs OCR, copies the
  text back
- **Four OCR engines**, switchable from Settings:
  - **Local (PaddleOCR-VL)** — runs entirely on-device, no API keys, no network
  - **Cloud API (PaddleOCR)** — PaddleOCR-VL via the official cloud SDK
  - **SiliconFlow API** — vision models hosted by SiliconFlow (e.g. DeepSeek-OCR)
  - **OpenAI Compatible API** — any OpenAI-protocol endpoint; configure base
    URL + model + token + custom headers
  - **Kimi (Moonshot)** — Moonshot's vision models (e.g. `kimi-k2.6`), with
    reasoning/thinking disabled by default for fast plain-text OCR
- **Configurable system prompts** for the LLM and Kimi modes
- **Global Shortcut:** Configurable hotkey (default: `Cmd+Shift+A`)

## Quick Start (from a Release download)

1. Go to the project's **Releases** page and download the latest `pOCR.dmg`.
2. Double-click the `.dmg` to mount it.
3. Drag the **pOCR** app onto the **Applications** folder alias in the DMG
   window (this copies it to `/Applications`).
4. Eject the mounted `pOCR` volume.
5. First launch. The app is **not Apple Developer code-signed**, so macOS will
   block it. Open it with one of these methods:
   - **Right-click** (or `Control`-click) `pOCR.app` → **Open** → in the dialog
     click **Open** again. This "Gatekeeper approval" persists, so subsequent
     launches work by double-clicking.
   - Or, in **System Settings → Privacy & Security**, scroll to the blocked
     "pOCR" message and click **Open Anyway**.

### "App is damaged and can't be opened" / "file broken"

This error is almost always the Gatekeeper quarantine flag, not real damage —
it shows up for unsigned apps downloaded via a browser. Remove the quarantine
attribute:

```bash
xattr -cr /Applications/pOCR.app
```

(`-c` clears all extended attributes, `-r` recurses into the bundle.) After
this, double-click to launch.

If it still won't open, also strip the quarantine bit explicitly:

```bash
xattr -d com.apple.quarantine /Applications/pOCR.app
```

## Requirements

- macOS 13.0+ (Ventura or newer)
- Swift 5.7+ (Xcode Command Line Tools)
- [uv](https://docs.astral.sh/uv/) (Python package manager)

## Installation

```bash
# 1. Build the app (Python venv is auto-initialized on first run)
make

# 2. Run
open build/pOCR.app
# or
make run
```

## Usage

1. Launch the app (icon appears in the Menu Bar)
2. Copy an image to clipboard (`Cmd+Ctrl+Shift+4`)
3. Click the Menu Bar icon → **Run OCR from Clipboard** (or press `Cmd+Shift+A`)
4. Wait for the icon to stop spinning
5. Text is copied to clipboard!

### Configuring cloud providers

Open **Settings** (Menu Bar icon → Settings, or the gear tab) and pick an OCR
engine. Tokens for cloud modes are stored locally in
`~/.config/pocr/credentials.json` and never leave the machine except as the API
auth header to the chosen provider.

- **OpenAI Compatible API:** set Base URL (e.g. `https://api.openai.com/v1` — a
  bare host, `.../v1`, or a full `/chat/completions` endpoint all work), Model,
  Token, optional custom headers (one `Key: Value` per line; applied after the
  default `Authorization` so they can override it), and a system prompt.
- **Kimi (Moonshot):** set Token and optionally the model and system prompt. The
  endpoint is preset to `https://api.moonshot.ai/v1`. "Disable Thinking" is on
  by default.

Use the **Test Connection** button in each section to verify credentials before
relying on a provider.

## Architecture

- **Language:** Swift 5
- **UI Framework:** SwiftUI + AppKit
- **Local OCR Engine:** PaddleOCR-VL (via the `paddleocr` Python API), pipeline
  PP-DocLayoutV3 (layout analysis) + PaddleOCR-VL (VLM recognition)
- **Cloud engines:** OpenAI-compatible `/v1/chat/completions` chat API, sending
  the clipboard image as a vision `image_url` content part. The generic LLM
  mode and the Kimi mode share one request/response engine.

## Testing

```bash
python3 tests/test_providers_integration.py
```

Integration test against the real Moonshot API. It reads the local,
gitignored `kimi-key` file and verifies URL resolution, custom-header parsing
and override, request body construction, response content parsing, and the
thinking-disabled path. (No credentials are checked into the repo.)

## License

MIT
