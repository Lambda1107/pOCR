import SwiftUI
import UserNotifications

@main
struct pOCRAppStruct: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, HotKeyDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerDefaults()
        statusBarController = StatusBarController()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        HotKeyManager.shared.delegate = self

        loadHotKey()
    }

    private func registerDefaults() {
        let defaults: [String: Any] = [
            "ocr_mode": "local",
            "api_model": "PaddleOCR-VL-1.6",
        ]
        UserDefaults.standard.register(defaults: defaults)
    }

    func hotKeyTriggered() {
        statusBarController?.startOCR()
    }

    private func loadHotKey() {
        let keyCode = UInt32(UserDefaults.standard.integer(forKey: "HotKey_KeyCode"))
        let modifiers = UInt32(UserDefaults.standard.integer(forKey: "HotKey_Modifiers"))

        if keyCode == 0 && modifiers == 0 {
            let defaultMods = HotKeyManager.carbonModifiers(from: [.command, .shift])
            HotKeyManager.shared.registerHotKey(keyCode: 0x00, modifiers: defaultMods)
        } else {
            HotKeyManager.shared.registerHotKey(keyCode: keyCode, modifiers: modifiers)
        }
    }
}
