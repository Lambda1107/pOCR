import AppKit
import SwiftUI
import UserNotifications

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var animationTimer: Timer?
    private var animationAngle: Double = 0
    private var isAnimating = false

    private var settingsWindow: NSWindow?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        setupMenu()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "pOCR")
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupMenu() {
        let runItem = NSMenuItem(title: "Run OCR from Clipboard", action: #selector(startOCR), keyEquivalent: "o")
        runItem.target = self
        menu.addItem(runItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else if event.type == .leftMouseUp {
            startOCR()
        }
    }

    @objc func startOCR() {
        if isAnimating { return }

        startAnimation()

        OCRService.shared.performOCR { [weak self] result in
            DispatchQueue.main.async {
                self?.stopAnimation()
                self?.handleResult(result)
            }
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.center()
            window.title = "pOCR Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func handleResult(_ result: Result<String, OCRError>) {
        switch result {
        case .success(let text):
            sendNotification(title: "pOCR Success", body: "Text copied to clipboard: \(text.prefix(50))...")
        case .failure(let error):
            let msg = {
                switch error {
                case .noImageInClipboard: return "No image in clipboard"
                case .failedToConvertImage: return "Failed to process image"
                case .ocrError(let m): return "OCR Error: \(m)"
                case .invalidResponse: return "Invalid response from model"
                case .ocrTimeout: return "OCR timed out"
                }
            }()
            sendNotification(title: "pOCR Failed", body: msg)
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Animation

    private func startAnimation() {
        if isAnimating { return }
        isAnimating = true
        animationAngle = 0

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateLoadingIcon()
        }
    }

    private func stopAnimation() {
        isAnimating = false
        animationTimer?.invalidate()
        animationTimer = nil

        DispatchQueue.main.async {
            self.statusItem.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "pOCR")
        }
    }

    private func updateLoadingIcon() {
        animationAngle += 30
        if animationAngle >= 360 { animationAngle = 0 }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let baseImage = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Loading")?.withSymbolConfiguration(config) {
            let rotated = rotateImage(baseImage, by: CGFloat(animationAngle))
            DispatchQueue.main.async {
                self.statusItem.button?.image = rotated
            }
        }
    }

    private func rotateImage(_ image: NSImage, by degrees: CGFloat) -> NSImage {
        let newSize = image.size
        let rotatedImage = NSImage(size: newSize)

        rotatedImage.lockFocus()
        let ctx = NSGraphicsContext.current
        ctx?.imageInterpolation = .high

        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byDegrees: -degrees)
        transform.translateX(by: -newSize.width / 2, yBy: -newSize.height / 2)
        transform.concat()

        image.draw(at: .zero, from: NSRect(origin: .zero, size: newSize), operation: .copy, fraction: 1.0)

        rotatedImage.unlockFocus()
        rotatedImage.isTemplate = true
        return rotatedImage
    }
}
