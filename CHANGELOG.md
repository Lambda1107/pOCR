# Changelog

All notable changes to this project are documented in this file.
The format is loosely based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-06-22

### Added
- **OpenAI Compatible API** OCR mode. Point pOCR at any OpenAI-protocol endpoint
  with a configurable **Base URL + Model + Token + Custom Headers**. Smart base
  URL resolution accepts a bare host, `.../v1`, a trailing slash, or a full
  `/chat/completions` endpoint. Custom headers are applied after the default
  `Authorization`, so they can override the auth scheme.
- **Kimi (Moonshot)** OCR mode, preset to `https://api.moonshot.ai/v1` with
  default model `kimi-k2.6`. Reasoning/thinking is **disabled by default** for
  faster, cheaper plain-text OCR; a **Disable Thinking** toggle lets users
  re-enable it when needed. The field is safe on non-reasoning models.
- Configurable **System Prompt** for both the LLM and Kimi modes, with sensible
  Markdown-emphasizing English defaults. No role/identity text baked in.
- `tests/test_providers_integration.py` — an integration test that exercises the
  real Moonshot API (via the local, gitignored `kimi-key` file) and mirrors the
  Swift request/response logic: URL resolution, custom-header parsing/override,
  body construction, content parsing (string / array / reasoning fallback /
  error object), and the thinking-disabled path. Run with
  `python3 tests/test_providers_integration.py`.

### Changed
- Shared OpenAI-compatible engine (`performChatCompletionOCR` /
  `buildChatCompletionRequest` / `parseChatCompletionContent`) now backs both
  the generic LLM mode and Kimi mode, eliminating duplicated chat-completion
  plumbing.
- Default system prompts switched to English and explicitly request
  Markdown-formatted output.
- Settings window resized to 560×640 to fit the new configuration fields.

### Fixed
- Base URL with a trailing slash (e.g. `https://host/v1/`) no longer resolves to
  a duplicated `/v1/v1/chat/completions` path.
- Kimi default model is a real, available vision model (`kimi-k2.6`) instead of
  the non-existent `kimi-latest`.
- Moonshot endpoint corrected from `api.moonshot.cn` to `api.moonshot.ai`.

### Removed
- Dropped the `deepseek-ai/DeepSeek-V4-Flash` option from the SiliconFlow model
  list.

## [1.0.0] - 2026-06-20

### Added
- Python API direct calls.
- Settings options.
- File-based credentials.

## [0.5.0]

- SiliconFlow API (DeepSeek-OCR) provider.

## [0.4.0]

- Text selection in logs; API OCR self-reference fix.

## [0.3.0]

- Dual-mode OCR (local + cloud API); token stored in Keychain.

## [0.2.0]

- Auto-init venv on first run instead of bundling.
