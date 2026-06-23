import SwiftUI
import Carbon
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "list.bullet.rectangle")
                }
        }
        .padding()
        .frame(width: 560, height: 640)
    }
}

struct LogsView: View {
    @ObservedObject private var logger = Logger.shared

    var body: some View {
        VStack(alignment: .leading) {
            Text("Log File: \(logger.getLogFilePath())")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(.bottom, 5)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(logger.logs)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("bottom")
                }
                .onChange(of: logger.logs) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .border(Color.gray.opacity(0.2))

            HStack {
                Button("Copy All") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logger.logs, forType: .string)
                }

                Spacer()

                Button("Clear Logs") {
                    logger.clear()
                }
            }
        }
        .padding()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("ocr_mode") private var ocrMode: String = "local"
    @AppStorage("api_model") private var apiModel: String = "PaddleOCR-VL-1.6"
    @AppStorage("siliconflow_model") private var siliconflowModel: String = "deepseek-ai/DeepSeek-OCR"

    @AppStorage("llm_base_url") private var llmBaseURL: String = "https://api.openai.com/v1"
    @AppStorage("llm_model") private var llmModel: String = "gpt-4o"
    @AppStorage("llm_headers") private var llmHeaders: String = ""
    @AppStorage("llm_system_prompt") private var llmSystemPrompt: String = OCRService.defaultLLMSystemPrompt

    @AppStorage("kimi_model") private var kimiModel: String = "kimi-k2.6"
    @AppStorage("kimi_system_prompt") private var kimiSystemPrompt: String = OCRService.defaultKimiSystemPrompt
    @AppStorage("user_prompt") private var userPrompt: String = OCRService.defaultUserPrompt
    @AppStorage("kimi_disable_thinking") private var kimiDisableThinking: Bool = true

    @AppStorage("local_pipeline_version") private var localPipelineVersion: String = "v1.6"
    @AppStorage("local_use_layout_detection") private var localUseLayoutDetection: Bool = true
    @AppStorage("local_use_chart_recognition") private var localUseChartRecognition: Bool = true
    @AppStorage("local_prettify_markdown") private var localPrettifyMarkdown: Bool = true

    @AppStorage("api_use_layout_detection") private var apiUseLayoutDetection: Bool = true
    @AppStorage("api_use_chart_recognition") private var apiUseChartRecognition: Bool = true
    @AppStorage("api_prettify_markdown") private var apiPrettifyMarkdown: Bool = true

    @AppStorage("HotKey_KeyCode") private var hotKeyKeyCode: Int = 0
    @AppStorage("HotKey_Modifiers") private var hotKeyModifiers: Int = 0

    @State private var isRecording = false
    @State private var displayString = "Cmd+Shift+A (Default)"
    @State private var launchAtLogin = false
    @State private var launchAtLoginStatus: String = ""

    @State private var apiToken: String = ""
    @State private var testStatus: String = ""
    @State private var isTesting: Bool = false

    @State private var siliconflowToken: String = ""
    @State private var sfTestStatus: String = ""
    @State private var isTestingSF: Bool = false

    @State private var llmToken: String = ""
    @State private var llmTestStatus: String = ""
    @State private var isTestingLLM: Bool = false

    @State private var kimiToken: String = ""
    @State private var kimiTestStatus: String = ""
    @State private var isTestingKimi: Bool = false

    private let apiModels = ["PaddleOCR-VL-1.6", "PaddleOCR-VL-1.5", "PaddleOCR-VL"]
    private let localPipelineVersions = ["v1.6", "v1.5", "v1"]
    private let siliconflowModels = ["deepseek-ai/DeepSeek-OCR", "PaddlePaddle/PaddleOCR-VL-1.5"]

    var body: some View {
        Form {
            Section(header: Text("OCR Engine")) {
                Picker("Mode", selection: $ocrMode) {
                    Text("Local (PaddleOCR-VL)").tag("local")
                    Text("Cloud API (PaddleOCR)").tag("api")
                    Text("SiliconFlow API").tag("siliconflow")
                    Text("OpenAI Compatible API").tag("llm")
                    Text("Kimi (Moonshot)").tag("kimi")
                }
                .pickerStyle(.radioGroup)

                if ocrMode == "api" {
                    SecureField("API Token", text: $apiToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: apiToken) { newValue in
                            CredentialsManager.save(key: "api_token", value: newValue)
                        }

                    Picker("Model", selection: $apiModel) {
                        ForEach(apiModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    Toggle("Layout Detection", isOn: $apiUseLayoutDetection)
                    Toggle("Chart Recognition", isOn: $apiUseChartRecognition)
                    Toggle("Prettify Markdown", isOn: $apiPrettifyMarkdown)

                    HStack {
                        Button(action: testConnection) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTesting || apiToken.isEmpty)

                        if !testStatus.isEmpty {
                            Text(testStatus)
                                .font(.caption)
                                .foregroundColor(testStatus.contains("Success") ? .green : .red)
                                .lineLimit(2)
                        }
                    }
                } else if ocrMode == "siliconflow" {
                    SecureField("API Token", text: $siliconflowToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: siliconflowToken) { newValue in
                            CredentialsManager.save(key: "siliconflow_token", value: newValue)
                        }

                    Picker("Model", selection: $siliconflowModel) {
                        ForEach(siliconflowModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    HStack {
                        Button(action: testSFConnection) {
                            if isTestingSF {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTestingSF || siliconflowToken.isEmpty)

                        if !sfTestStatus.isEmpty {
                            Text(sfTestStatus)
                                .font(.caption)
                                .foregroundColor(sfTestStatus.contains("Success") ? .green : .red)
                                .lineLimit(2)
                        }
                    }
                } else if ocrMode == "llm" {
                    SecureField("API Token", text: $llmToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: llmToken) { newValue in
                            CredentialsManager.save(key: "llm_token", value: newValue)
                        }

                    TextField("Base URL", text: $llmBaseURL, prompt: Text("https://api.openai.com/v1"))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    TextField("Model", text: $llmModel, prompt: Text("gpt-4o"))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Headers (one per line, Key: Value)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $llmHeaders)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 50, maxHeight: 80)
                            .border(Color.gray.opacity(0.2))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $llmSystemPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60, maxHeight: 100)
                            .border(Color.gray.opacity(0.2))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("User Prompt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $userPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 50, maxHeight: 80)
                            .border(Color.gray.opacity(0.2))
                    }

                    HStack {
                        Button(action: testLLMConnection) {
                            if isTestingLLM {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTestingLLM || llmToken.isEmpty)

                        if !llmTestStatus.isEmpty {
                            Text(llmTestStatus)
                                .font(.caption)
                                .foregroundColor(llmTestStatus.contains("Success") ? .green : .red)
                                .lineLimit(2)
                        }
                    }
                } else if ocrMode == "kimi" {
                    SecureField("API Token", text: $kimiToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: kimiToken) { newValue in
                            CredentialsManager.save(key: "kimi_token", value: newValue)
                        }

                    TextField("Model", text: $kimiModel, prompt: Text("kimi-k2.6"))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Toggle("Disable Thinking", isOn: $kimiDisableThinking)
                        .help("Turn off the reasoning pass for kimi-k2.x models (faster, cheaper). Non-reasoning models ignore this.")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $kimiSystemPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60, maxHeight: 100)
                            .border(Color.gray.opacity(0.2))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("User Prompt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $userPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 50, maxHeight: 80)
                            .border(Color.gray.opacity(0.2))
                    }

                    HStack {
                        Button(action: testKimiConnection) {
                            if isTestingKimi {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTestingKimi || kimiToken.isEmpty)

                        if !kimiTestStatus.isEmpty {
                            Text(kimiTestStatus)
                                .font(.caption)
                                .foregroundColor(kimiTestStatus.contains("Success") ? .green : .red)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Picker("Pipeline", selection: $localPipelineVersion) {
                        ForEach(localPipelineVersions, id: \.self) { v in
                            Text(v).tag(v)
                        }
                    }

                    Toggle("Layout Detection", isOn: $localUseLayoutDetection)
                    Toggle("Chart Recognition", isOn: $localUseChartRecognition)
                    Toggle("Prettify Markdown", isOn: $localPrettifyMarkdown)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Runs locally on CPU")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("Startup")) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                                launchAtLoginStatus = "Will launch at login"
                            } else {
                                try SMAppService.mainApp.unregister()
                                launchAtLoginStatus = ""
                            }
                        } catch {
                            launchAtLogin = !newValue
                            launchAtLoginStatus = "Failed: \(error.localizedDescription)"
                            Logger.shared.log("LaunchAtLogin error: \(error.localizedDescription)")
                        }
                    }

                if !launchAtLoginStatus.isEmpty {
                    Text(launchAtLoginStatus)
                        .font(.caption)
                        .foregroundColor(launchAtLogin == true ? .green : .red)
                }
            }

            Section(header: Text("Global Shortcut")) {
                HStack {
                    Text("Shortcut:")
                    Spacer()
                    Button(action: {
                        isRecording = true
                    }) {
                        Text(isRecording ? "Press keys..." : displayString)
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.bordered)

                    if hotKeyKeyCode != 0 {
                        Button("Reset") {
                            hotKeyKeyCode = 0
                            hotKeyModifiers = 0
                            updateDisplayString()
                            updateHotKey()
                        }
                    }
                }

                if isRecording {
                    Text("Press Esc to cancel")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
                launchAtLogin = SMAppService.mainApp.status == .enabled
                apiToken = CredentialsManager.load(key: "api_token") ?? ""
                siliconflowToken = CredentialsManager.load(key: "siliconflow_token") ?? ""
                llmToken = CredentialsManager.load(key: "llm_token") ?? ""
                kimiToken = CredentialsManager.load(key: "kimi_token") ?? ""
                updateDisplayString()
            }

            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
            }
        }
        .padding()
        .background(KeyRecorder(isRecording: $isRecording, onRecord: { code, mods in
            hotKeyKeyCode = Int(code)
            hotKeyModifiers = Int(mods)
            updateDisplayString()
            updateHotKey()
        }))
    }

    private func testConnection() {
        isTesting = true
        testStatus = "Testing..."
        Logger.shared.log("Testing API connection...")

        OCRService.shared.testAPIConnection(token: apiToken, model: apiModel) { error in
            DispatchQueue.main.async {
                isTesting = false
                if let error = error {
                    testStatus = "Failed: \(error)"
                } else {
                    testStatus = "Success!"
                }
            }
        }
    }

    private func testSFConnection() {
        isTestingSF = true
        sfTestStatus = "Testing..."
        Logger.shared.log("Testing SiliconFlow connection...")

        OCRService.shared.testSiliconFlowConnection(token: siliconflowToken, model: siliconflowModel) { error in
            DispatchQueue.main.async {
                isTestingSF = false
                if let error = error {
                    sfTestStatus = "Failed: \(error)"
                } else {
                    sfTestStatus = "Success!"
                }
            }
        }
    }

    private func testLLMConnection() {
        isTestingLLM = true
        llmTestStatus = "Testing..."
        Logger.shared.log("Testing OpenAI-compatible LLM connection...")

        OCRService.shared.testLLMConnection(
            baseURL: llmBaseURL,
            model: llmModel,
            token: llmToken,
            headersText: llmHeaders,
            systemPrompt: llmSystemPrompt
        ) { error in
            DispatchQueue.main.async {
                isTestingLLM = false
                if let error = error {
                    llmTestStatus = "Failed: \(error)"
                } else {
                    llmTestStatus = "Success!"
                }
            }
        }
    }

    private func testKimiConnection() {
        isTestingKimi = true
        kimiTestStatus = "Testing..."
        Logger.shared.log("Testing Kimi connection...")

        OCRService.shared.testKimiConnection(
            token: kimiToken,
            model: kimiModel,
            systemPrompt: kimiSystemPrompt,
            disableThinking: kimiDisableThinking
        ) { error in
            DispatchQueue.main.async {
                isTestingKimi = false
                if let error = error {
                    kimiTestStatus = "Failed: \(error)"
                } else {
                    kimiTestStatus = "Success!"
                }
            }
        }
    }

    private func updateDisplayString() {
        if hotKeyKeyCode == 0 && hotKeyModifiers == 0 {
            displayString = "Cmd+Shift+A (Default)"
            return
        }

        var parts: [String] = []
        if (hotKeyModifiers & Int(cmdKey)) != 0 { parts.append("Cmd") }
        if (hotKeyModifiers & Int(controlKey)) != 0 { parts.append("Ctrl") }
        if (hotKeyModifiers & Int(optionKey)) != 0 { parts.append("Opt") }
        if (hotKeyModifiers & Int(shiftKey)) != 0 { parts.append("Shift") }

        let keyStr = keyCodeToString(CGKeyCode(hotKeyKeyCode))
        parts.append(keyStr)

        displayString = parts.joined(separator: "+")
    }

    private func updateHotKey() {
        if hotKeyKeyCode == 0 {
            let defaultMods = HotKeyManager.carbonModifiers(from: [.command, .shift])
            HotKeyManager.shared.registerHotKey(keyCode: 0x00, modifiers: defaultMods)
        } else {
            HotKeyManager.shared.registerHotKey(keyCode: UInt32(hotKeyKeyCode), modifiers: UInt32(hotKeyModifiers))
        }
    }

    private func keyCodeToString(_ code: CGKeyCode) -> String {
        switch code {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x1F: return "O"
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x31: return "Space"
        case 0x24: return "Enter"
        case 0x30: return "Tab"
        default: return "Key(\(code))"
        }
    }
}

struct KeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onRecord: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.isRecording = $isRecording
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.isRecording = $isRecording
        nsView.onRecord = onRecord
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    class KeyView: NSView {
        var isRecording: Binding<Bool>?
        var onRecord: ((UInt32, UInt32) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard let isRec = isRecording, isRec.wrappedValue else {
                super.keyDown(with: event)
                return
            }

            if event.keyCode == 53 {
                isRec.wrappedValue = false
                return
            }

            let carbonMods = HotKeyManager.carbonModifiers(from: event.modifierFlags)
            onRecord?(UInt32(event.keyCode), carbonMods)
            isRec.wrappedValue = false
        }
    }
}
