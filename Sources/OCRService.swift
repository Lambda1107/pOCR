import Foundation
import AppKit

enum OCRError: Error {
    case noImageInClipboard
    case failedToConvertImage
    case ocrError(String)
    case invalidResponse
    case ocrTimeout
}

class OCRService: ObservableObject {
    static let shared = OCRService()

    @Published var isProcessing = false
    @Published var lastResult: String?
    @Published var lastError: String?

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
            completion(.failure(.failedToConvertImage))
            return
        }

        Logger.shared.log("Image saved to \(imageURL.path)")

        guard let resourcesURL = Bundle.main.resourceURL else {
            Logger.shared.log("Error: Could not find app Resources")
            completion(.failure(.ocrError("App bundle is corrupt (no Resources)")))
            return
        }

        let scriptURL = resourcesURL.appendingPathComponent("run_paddleocr.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            Logger.shared.log("Error: run_paddleocr.sh not found at \(scriptURL.path)")
            completion(.failure(.ocrError("OCR engine not bundled. Reinstall the app.")))
            return
        }

        Logger.shared.log("Script path: \(scriptURL.path)")

        self.isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                DispatchQueue.main.async { self?.isProcessing = false }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [
                scriptURL.path,
                "doc_parser",
                "-i", imageURL.path,
                "--device", "cpu",
                "--save_path", tempDir.path,
            ]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Capture stderr asynchronously and feed to Logger
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

            do {
                Logger.shared.log("Running paddleocr...")
                try process.run()
                process.waitUntilExit()
                errorPipe.fileHandleForReading.readabilityHandler = nil
            } catch {
                errorPipe.fileHandleForReading.readabilityHandler = nil
                Logger.shared.log("Error running paddleocr: \(error.localizedDescription)")
                completion(.failure(.ocrError(error.localizedDescription)))
                return
            }

            let status = process.terminationStatus
            Logger.shared.log("paddleocr exit code: \(status)")

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
                    self?.lastResult = combined
                }

                completion(.success(combined))
            } catch {
                Logger.shared.log("Error parsing JSON: \(error.localizedDescription)")
                completion(.failure(.invalidResponse))
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func getClipboardImage() -> NSImage? {
        return NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
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

}
