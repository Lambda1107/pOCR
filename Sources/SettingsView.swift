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
        .frame(width: 500, height: 300)
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
    @AppStorage("HotKey_KeyCode") private var hotKeyKeyCode: Int = 0
    @AppStorage("HotKey_Modifiers") private var hotKeyModifiers: Int = 0

    @State private var isRecording = false
    @State private var displayString = "Cmd+Shift+A (Default)"
    @State private var launchAtLogin = false
    @State private var launchAtLoginStatus: String = ""

    var body: some View {
        Form {
            Section(header: Text("OCR Engine")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PaddleOCR-VL-1.6 (Local)")
                        .font(.body)
                    Text("Model: PaddleOCR-VL-1.6-0.9B")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Device: CPU")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
