import Foundation
import AppKit

enum OCRError: Error, LocalizedError {
    case noImageInClipboard
    case failedToConvertImage
    case ocrError(String)
    case invalidResponse
    case ocrTimeout

    var errorDescription: String? {
        switch self {
        case .noImageInClipboard: return "No image in clipboard"
        case .failedToConvertImage: return "Failed to process image"
        case .ocrError(let m): return m
        case .invalidResponse: return "Invalid response from model"
        case .ocrTimeout: return "OCR timed out"
        }
    }
}

class OCRService: ObservableObject {
    static let shared = OCRService()

    @Published var isProcessing = false
    @Published var isInitializing = false
    @Published var lastResult: String?
    @Published var lastError: String?

    private let pocrDir: URL
    private let venvPaddle: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        pocrDir = home.appendingPathComponent(".pocr")
        venvPaddle = pocrDir.appendingPathComponent(".venv/bin/paddleocr")
    }

    // MARK: - Public API

    func performOCR(completion: @escaping (Result<String, OCRError>) -> Void) {
        Logger.shared.log("Starting OCR process...")

        guard let image = getClipboardImage() else {
            Logger.shared.log("Error: No image found in clipboard")
            completion(.failure(.noImageInClipboard))
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocr_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            Logger.shared.log("Error creating temp dir: \(error.localizedDescription)")
            completion(.failure(.failedToConvertImage))
            return
        }

        let imageURL = tempDir.appendingPathComponent("clipboard.png")
        guard saveImage(image, to: imageURL) else {
            Logger.shared.log("Error: Failed to save image")
            try? FileManager.default.removeItem(at: tempDir)
            completion(.failure(.failedToConvertImage))
            return
        }

        let mode = UserDefaults.standard.string(forKey: "ocr_mode") ?? "local"

        if mode == "api" {
            performOCRApi(imageURL: imageURL, tempDir: tempDir, completion: completion)
        } else {
            performLocalOCR(imageURL: imageURL, tempDir: tempDir, completion: completion)
        }
    }

    func testAPIConnection(token: String, model: String, completion: @escaping (String?) -> Void) {
        Logger.shared.log("Testing API connection with model: \(model)")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocr_test_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            completion("Failed to create temp dir: \(error.localizedDescription)")
            return
        }

        let imageURL = tempDir.appendingPathComponent("test.png")
        let testImage = createTestImage()
        guard saveImage(testImage, to: imageURL) else {
            try? FileManager.default.removeItem(at: tempDir)
            completion("Failed to create test image")
            return
        }

        let process = Process()
        process.executableURL = venvPaddle
        process.arguments = [
            "api",
            "--model_type", "doc_parsing",
            "--model", model,
            "--file_path", imageURL.path,
            "--token", token,
            "--poll_timeout", "30",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var errBuf = ""
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8) {
                errBuf += chunk
                for line in errBuf.components(separatedBy: "\n").dropLast() {
                    Logger.shared.log("[api] \(line)")
                }
                errBuf = errBuf.components(separatedBy: "\n").last ?? ""
            }
        }

        do {
            Logger.shared.log("Running: paddleocr api --model \(model)")
            try process.run()
            process.waitUntilExit()
            errPipe.fileHandleForReading.readabilityHandler = nil
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            completion("Failed to run: \(error.localizedDescription)")
            return
        }

        try? FileManager.default.removeItem(at: tempDir)

        if process.terminationStatus == 0 {
            Logger.shared.log("API test connection successful")
            completion(nil)
        } else {
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            if let outStr = String(data: outData, encoding: .utf8), !outStr.isEmpty {
                Logger.shared.log("[api] stdout: \(outStr)")
            }
            let detail = errBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = detail.isEmpty ? "exit code \(process.terminationStatus)" : detail
            Logger.shared.log("API test connection failed: \(msg)")
            completion(msg)
        }
    }

    // MARK: - Local OCR

    private func performLocalOCR(imageURL: URL, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) {
        do {
            try ensureVenv()
        } catch {
            Logger.shared.log("Error initializing venv: \(error.localizedDescription)")
            completion(.failure(.ocrError("Failed to initialize OCR engine: \(error.localizedDescription)")))
            return
        }

        self.isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                DispatchQueue.main.async { self?.isProcessing = false }
            }

            do {
                try self?.runPaddleOCR(imageURL: imageURL, tempDir: tempDir, completion: completion)
            } catch {
                Logger.shared.log("Error running OCR: \(error.localizedDescription)")
                completion(.failure(.ocrError(error.localizedDescription)))
            }
        }
    }

    private func ensureVenv() throws {
        guard !isInitializing else { return }

        if FileManager.default.fileExists(atPath: venvPaddle.path) {
            return
        }

        isInitializing = true
        defer { isInitializing = false }
        Logger.shared.log("Initializing Python venv in \(pocrDir.path)...")

        try FileManager.default.createDirectory(at: pocrDir, withIntermediateDirectories: true)

        guard let resources = Bundle.main.resourceURL else {
            throw OCRError.ocrError("App bundle is corrupt (no Resources)")
        }

        for file in ["pyproject.toml", "uv.lock"] {
            let src = resources.appendingPathComponent(file)
            let dst = pocrDir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: src.path) && !FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.copyItem(at: src, to: dst)
            }
        }

        Logger.shared.log("Running uv sync (this may take a while on first run)...")
        try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            args: ["uv", "sync", "--directory", pocrDir.path, "--frozen"],
            workingDir: pocrDir
        )
        Logger.shared.log("Venv initialized successfully")
    }

    private func runPaddleOCR(imageURL: URL, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) throws {
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        var stderrBuf = ""
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8) {
                stderrBuf += chunk
                for line in stderrBuf.components(separatedBy: "\n").dropLast() {
                    Logger.shared.log("[paddleocr] \(line)")
                }
                stderrBuf = stderrBuf.components(separatedBy: "\n").last ?? ""
            }
        }

        Logger.shared.log("Running paddleocr...")
        try runProcess(
            executable: venvPaddle,
            args: [
                "doc_parser",
                "-i", imageURL.path,
                "--device", "cpu",
                "--save_path", tempDir.path,
            ],
            workingDir: tempDir,
            outputPipe: outputPipe,
            errorPipe: errorPipe
        )
        errorPipe.fileHandleForReading.readabilityHandler = nil

        let resultURL = tempDir.appendingPathComponent("clipboard_res.json")
        guard let data = try? Data(contentsOf: resultURL) else {
            Logger.shared.log("Error: Result file not found at \(resultURL.path)")
            let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let outStr = String(data: outData, encoding: .utf8) {
                Logger.shared.log("stdout: \(outStr)")
            }
            completion(.failure(.invalidResponse))
            return
        }

        parseAndCopyResult(data: data, tempDir: tempDir, completion: completion)
    }

    // MARK: - API OCR

    private func performOCRApi(imageURL: URL, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) {
        guard let token = KeychainManager.load(key: "api_token"), !token.isEmpty else {
            Logger.shared.log("Error: API token not configured")
            completion(.failure(.ocrError("API token not set. Configure it in Settings.")))
            return
        }

        let model = UserDefaults.standard.string(forKey: "api_model") ?? "PaddleOCR-VL-1.6"
        let resultURL = tempDir.appendingPathComponent("api_result.json")

        self.isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async { self.isProcessing = false }
            }

            let process = Process()
            process.executableURL = self.venvPaddle
            process.arguments = [
                "api",
                "--model_type", "doc_parsing",
                "--model", model,
                "--file_path", imageURL.path,
                "--token", token,
                "--poll_timeout", "120",
                "--output", resultURL.path,
            ]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            var errBuf = ""
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let chunk = String(data: data, encoding: .utf8) {
                    errBuf += chunk
                    for line in errBuf.components(separatedBy: "\n").dropLast() {
                        Logger.shared.log("[api] \(line)")
                    }
                    errBuf = errBuf.components(separatedBy: "\n").last ?? ""
                }
            }

            do {
                Logger.shared.log("Submitting API OCR task...")
                try process.run()
                process.waitUntilExit()
                errPipe.fileHandleForReading.readabilityHandler = nil
            } catch {
                Logger.shared.log("Error running API OCR: \(error.localizedDescription)")
                completion(.failure(.ocrError(error.localizedDescription)))
                return
            }

            Logger.shared.log("API OCR exit code: \(process.terminationStatus)")

            guard let data = try? Data(contentsOf: resultURL) else {
                Logger.shared.log("Error: API result file not found")
                completion(.failure(.invalidResponse))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    Logger.shared.log("Error: Invalid JSON from API")
                    completion(.failure(.invalidResponse))
                    return
                }

                if let errorMsg = json["error"] as? String {
                    Logger.shared.log("API error: \(errorMsg)")
                    completion(.failure(.ocrError(errorMsg)))
                    return
                }

                guard let pages = json["pages"] as? [[String: Any]] else {
                    Logger.shared.log("Error: No pages in API response")
                    if let raw = String(data: data, encoding: .utf8) {
                        Logger.shared.log("Raw API response: \(raw.prefix(500))")
                    }
                    completion(.failure(.invalidResponse))
                    return
                }

                let texts = pages.compactMap { $0["markdownText"] as? String }
                let combined = texts.joined(separator: "\n\n")

                Logger.shared.log("API OCR Success. Pages: \(pages.count), chars: \(combined.count)")

                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(combined, forType: .string)
                    self.lastResult = combined
                }

                completion(.success(combined))
            } catch {
                Logger.shared.log("Error parsing API response: \(error.localizedDescription)")
                completion(.failure(.invalidResponse))
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Utilities

    private func parseAndCopyResult(data: Data, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) {
        Logger.shared.log("Result file size: \(data.count) bytes")

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsingList = json["parsing_res_list"] as? [[String: Any]] else {
                Logger.shared.log("Error: Invalid JSON structure")
                completion(.failure(.invalidResponse))
                return
            }

            let texts = parsingList.compactMap { $0["block_content"] as? String }
            let combined = texts.joined(separator: "\n")

            Logger.shared.log("OCR Success. Length: \(combined.count) chars")

            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(combined, forType: .string)
                self.lastResult = combined
            }

            completion(.success(combined))
        } catch {
            Logger.shared.log("Error parsing JSON: \(error.localizedDescription)")
            completion(.failure(.invalidResponse))
        }

        try? FileManager.default.removeItem(at: tempDir)
    }

    private func runProcess(executable: URL, args: [String], workingDir: URL, outputPipe: Pipe? = nil, errorPipe: Pipe? = nil) throws {
        let process = Process()
        process.currentDirectoryURL = workingDir
        process.executableURL = executable
        process.arguments = args

        let outPipe = outputPipe ?? Pipe()
        let errPipe = errorPipe ?? Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        if outputPipe == nil {
            var errBuf = ""
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let chunk = String(data: data, encoding: .utf8) {
                    errBuf += chunk
                    for line in errBuf.components(separatedBy: "\n").dropLast() {
                        Logger.shared.log(line)
                    }
                    errBuf = errBuf.components(separatedBy: "\n").last ?? ""
                }
            }
        }

        try process.run()
        process.waitUntilExit()
        errPipe.fileHandleForReading.readabilityHandler = nil

        let status = process.terminationStatus
        Logger.shared.log("Process exit code: \(status) (\(executable.lastPathComponent))")

        if status != 0 && outputPipe == nil {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                Logger.shared.log("stderr: \(errStr)")
            }
        }
    }

    private func getClipboardImage() -> NSImage? {
        NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
    }

    private func saveImage(_ image: NSImage, to url: URL) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return false
        }
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try pngData.write(to: url)
            return true
        } catch {
            Logger.shared.log("Error writing image: \(error.localizedDescription)")
            return false
        }
    }

    private func createTestImage() -> NSImage {
        let size = NSSize(width: 100, height: 30)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        "Test".draw(at: NSPoint(x: 10, y: 8), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black,
        ])
        image.unlockFocus()
        return image
    }

}
