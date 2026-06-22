# pOCR

[English](README.md)

原生 macOS 菜单栏 OCR 应用。可使用 **PaddleOCR-VL** 完全在本地运行 OCR，
也可将图片发送到云端——PaddleOCR 云端 API、SiliconFlow、任意
**OpenAI 兼容**模型，或 **Kimi（Moonshot）**。

## 功能特性

- **原生 GUI：** 轻量级菜单栏应用（Status Bar 图标）
- **剪贴板 OCR：** 从剪贴板读取图片，运行 OCR，将识别出的文字写回剪贴板
- **四种 OCR 引擎**，可在设置中切换：
  - **本地（PaddleOCR-VL）** —— 完全在设备端运行，无需 API Key，无需联网
  - **云端 API（PaddleOCR）** —— 通过官方云 SDK 调用 PaddleOCR-VL
  - **SiliconFlow API** —— SiliconFlow 托管的视觉模型（如 DeepSeek-OCR）
  - **OpenAI 兼容 API** —— 任意 OpenAI 协议端点；可配置 base URL、模型、
    token、自定义请求头
  - **Kimi（Moonshot）** —— Moonshot 的视觉模型（如 `kimi-k2.6`），
    默认关闭推理/thinking 以获得快速的纯文本 OCR
- **可配置系统提示词**（LLM 模式与 Kimi 模式）
- **全局快捷键：** 可配置热键（默认 `Cmd+Shift+A`）

## 快速开始（从 Release 下载使用）

1. 进入本项目的 **Releases** 页面，下载最新的 `pOCR.dmg`。
2. 双击 `.dmg` 挂载。
3. 将 DMG 窗口中的 **pOCR** 应用拖到 **Applications** 文件夹别名上
   （这会把它复制到 `/Applications`）。
4. 推出已挂载的 `pOCR` 卷。
5. 首次启动。本应用**未经过 Apple 开发者代码签名**，macOS 会拦截它。
   使用以下任一方式打开：
   - **右键**（或按住 `Control` 点击）`pOCR.app` → **打开** → 在弹窗中再次
     点击 **打开**。这种"Gatekeeper 放行"会被记住，之后双击即可启动。
   - 或在 **系统设置 → 隐私与安全性** 中，滚动到被拦截的 "pOCR" 提示，
     点击 **仍要打开**。

### "应用已损坏，无法打开" / 文件损坏 问题

这个报错几乎都是 Gatekeeper 的隔离标记（quarantine flag）造成的，并非
真的损坏——浏览器下载的未签名应用常会出现。移除隔离属性即可：

```bash
xattr -cr /Applications/pOCR.app
```

（`-c` 清除所有扩展属性，`-r` 递归处理整个 bundle。）之后再双击启动。

如果仍然打不开，再显式删除 quarantine 标记：

```bash
xattr -d com.apple.quarantine /Applications/pOCR.app
```

## 系统要求

- macOS 13.0+（Ventura 或更新版本）
- Swift 5.7+（Xcode Command Line Tools）
- [uv](https://docs.astral.sh/uv/)（Python 包管理器）

## 从源码安装

```bash
# 1. 构建应用（首次运行时会自动初始化 Python venv）
make

# 2. 运行
open build/pOCR.app
# 或
make run
```

## 使用方法

1. 启动应用（菜单栏出现图标）
2. 将图片复制到剪贴板（`Cmd+Ctrl+Shift+4`）
3. 点击菜单栏图标 → **Run OCR from Clipboard**（或按 `Cmd+Shift+A`）
4. 等待图标停止旋转
5. 识别出的文字已复制到剪贴板！

### 配置云端服务商

打开 **Settings**（菜单栏图标 → Settings，或齿轮标签页）并选择 OCR 引擎。
云端模式的 token 保存在本地 `~/.config/pocr/credentials.json`，
除作为所选服务商的 API 认证头发送外，不会离开本机。

- **OpenAI 兼容 API：** 设置 Base URL（如 `https://api.openai.com/v1` ——
  裸主机名、`.../v1` 或完整的 `/chat/completions` 端点均可）、Model、
  Token、可选自定义请求头（每行一个 `Key: Value`，在默认 `Authorization`
  之后应用，因此可覆盖它）以及系统提示词。
- **Kimi（Moonshot）：** 设置 Token，可选模型和系统提示词。端点预设为
  `https://api.moonshot.ai/v1`。"Disable Thinking" 默认开启。

在各分区使用 **Test Connection** 按钮，可在依赖某服务商前验证凭据。

## 架构

- **语言：** Swift 5
- **UI 框架：** SwiftUI + AppKit
- **本地 OCR 引擎：** PaddleOCR-VL（通过 `paddleocr` Python API），
  pipeline 为 PP-DocLayoutV3（版面分析）+ PaddleOCR-VL（VLM 识别）
- **云端引擎：** OpenAI 兼容的 `/v1/chat/completions` chat API，
  将剪贴板图片作为视觉 `image_url` 内容片段发送。通用 LLM 模式与
  Kimi 模式共用同一套请求/响应引擎。

## 测试

```bash
python3 tests/test_providers_integration.py
```

针对真实 Moonshot API 的集成测试。读取本地、已 gitignore 的 `kimi-key`
文件，验证 URL 解析、自定义请求头解析与覆盖、请求体构造、响应内容解析
以及 thinking 关闭路径。（仓库中不检入任何凭据。）

## License

MIT
