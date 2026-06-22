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
    private let pythonBin: URL
    private let ocrLocalScript: URL
    private let ocrApiScript: URL

    static let defaultLLMSystemPrompt = "Extract all text from the provided image accurately and faithfully, preserving the original layout, reading order, and structure. Output the result as Markdown-formatted text only — use Markdown for headings, lists, tables, code blocks, and emphasis where appropriate, and add no explanations or commentary."
    static let defaultKimiSystemPrompt = "Extract all text from the provided image accurately and faithfully, preserving the original layout, reading order, and structure. Output the result as Markdown-formatted text only — use Markdown for headings, lists, tables, code blocks, and emphasis where appropriate, and add no explanations or commentary."
    private let ocrUserInstruction = "Extract all text from this image and return it as Markdown."

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        pocrDir = home.appendingPathComponent(".pocr")
        pythonBin = pocrDir.appendingPathComponent(".venv/bin/python3")
        ocrLocalScript = pocrDir.appendingPathComponent("ocr_local.py")
        ocrApiScript = pocrDir.appendingPathComponent("ocr_api.py")
    }

    // MARK: - Public API

    func performOCR(completion: @escaping (Result<String, OCRError>) -> Void) {
        Logger.shared.log("Starting OCR process...")

        guard let image = getClipboardImage() else {
            Logger.shared.log("Error: No image found in clipboard")
            completion(.failure(.noImageInClipboard))
            return
        }

        let paddedImage = padImage(image, horizontal: 30) ?? image

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
        guard saveImage(paddedImage, to: imageURL) else {
            Logger.shared.log("Error: Failed to save image")
            try? FileManager.default.removeItem(at: tempDir)
            completion(.failure(.failedToConvertImage))
            return
        }

        let mode = UserDefaults.standard.string(forKey: "ocr_mode") ?? "local"

        if mode == "api" {
            performOCRApi(imageURL: imageURL, tempDir: tempDir, completion: completion)
        } else if mode == "siliconflow" {
            performOCRSiliconFlow(imageURL: imageURL, tempDir: tempDir, completion: completion)
        } else if mode == "llm" {
            performOCRLLM(imageURL: imageURL, tempDir: tempDir, completion: completion)
        } else if mode == "kimi" {
            performOCRKimi(imageURL: imageURL, tempDir: tempDir, completion: completion)
        } else {
            performLocalOCR(imageURL: imageURL, tempDir: tempDir, completion: completion)
        }
    }

    func testAPIConnection(token: String, model: String, completion: @escaping (String?) -> Void) {
        Logger.shared.log("Testing API connection with model: \(model)")

        do {
            try ensureVenv()
        } catch {
            completion("Failed to init: \(error.localizedDescription)")
            return
        }

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

        let resultURL = tempDir.appendingPathComponent("test_result.json")

        let process = Process()
        process.executableURL = pythonBin
        process.arguments = [
            ocrApiScript.path,
            "--image", imageURL.path,
            "--output", resultURL.path,
            "--token", token,
            "--model", model,
            "--poll-timeout", "30",
            "--use-layout-detection", "false",
            "--use-chart-recognition", "false",
            "--prettify-markdown", "false",
        ]

        let errPipe = Pipe()
        process.standardOutput = Pipe()
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
            Logger.shared.log("Running: \(pythonBin.lastPathComponent) ocr_api.py --model \(model)")
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
            let detail = errBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = detail.isEmpty ? "exit code \(process.terminationStatus)" : detail
            Logger.shared.log("API test connection failed: \(msg)")
            completion(msg)
        }
    }

    func testSiliconFlowConnection(token: String, model: String, completion: @escaping (String?) -> Void) {
        Logger.shared.log("Testing SiliconFlow connection with model: \(model)")

        let testImage = createTestImage()
        guard let tiffData = testImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            completion("Failed to create test image")
            return
        }

        let base64Image = pngData.base64EncodedString()
        let dataURI = "data:image/png;base64,\(base64Image)"

        let url = URL(string: "https://api.siliconflow.cn/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": dataURI]],
                        ["type": "text", "text": "Extract text."],
                    ],
                ]
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(error.localizedDescription)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion("Invalid response")
                return
            }

            guard httpResponse.statusCode == 200 else {
                var msg = "HTTP \(httpResponse.statusCode)"
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    msg += ": \(str.prefix(200))"
                }
                completion(msg)
                return
            }

            guard let data = data else {
                completion("Empty response")
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion("Invalid JSON response")
                    return
                }

                if let errorObj = json["error"] as? [String: Any] {
                    completion(errorObj["message"] as? String ?? "API error")
                    return
                }

                if let code = json["code"] as? Int, code != 0 {
                    completion(json["message"] as? String ?? "API error (code \(code))")
                    return
                }

                guard let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let message = first["message"] as? [String: Any],
                      message["content"] as? String != nil else {
                    completion("Unexpected response format")
                    return
                }

                Logger.shared.log("SiliconFlow connection test successful")
                completion(nil)
            } catch {
                completion("Parse error: \(error.localizedDescription)")
            }
        }
        task.resume()
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
                try self?.runLocalOCR(imageURL: imageURL, tempDir: tempDir, completion: completion)
            } catch {
                Logger.shared.log("Error running OCR: \(error.localizedDescription)")
                completion(.failure(.ocrError(error.localizedDescription)))
            }
        }
    }

    private func ensureVenv() throws {
        guard !isInitializing else { return }

        isInitializing = true
        defer { isInitializing = false }

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

        for script in ["ocr_local.py", "ocr_api.py"] {
            let src = resources.appendingPathComponent(script)
            let dst = pocrDir.appendingPathComponent(script)
            if FileManager.default.fileExists(atPath: src.path) {
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: src, to: dst)
            }
        }

        if !FileManager.default.fileExists(atPath: pythonBin.path) {
            Logger.shared.log("Running uv sync (this may take a while on first run)...")
            try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                args: ["uv", "sync", "--directory", pocrDir.path, "--frozen"],
                workingDir: pocrDir
            )
        }
        Logger.shared.log("Venv and scripts ready")
    }

    private func runLocalOCR(imageURL: URL, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) throws {
        let useLayoutDetection = UserDefaults.standard.bool(forKey: "local_use_layout_detection")
        let useChartRecognition = UserDefaults.standard.bool(forKey: "local_use_chart_recognition")
        let formatBlockContent = UserDefaults.standard.bool(forKey: "local_prettify_markdown")
        let pipelineVersion = UserDefaults.standard.string(forKey: "local_pipeline_version") ?? "v1.6"

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

        Logger.shared.log("Running paddleocr via Python API...")
        try runProcess(
            executable: pythonBin,
            args: [
                ocrLocalScript.path,
                "--image", imageURL.path,
                "--output-dir", tempDir.path,
                "--device", "cpu",
                "--pipeline-version", pipelineVersion,
                "--use-layout-detection", useLayoutDetection ? "true" : "false",
                "--use-chart-recognition", useChartRecognition ? "true" : "false",
                "--format-block-content", formatBlockContent ? "true" : "false",
            ],
            workingDir: tempDir,
            errorPipe: errorPipe
        )
        errorPipe.fileHandleForReading.readabilityHandler = nil

        let resultURL = tempDir.appendingPathComponent("clipboard_res.json")
        guard let data = try? Data(contentsOf: resultURL) else {
            Logger.shared.log("Error: Result file not found at \(resultURL.path)")
            completion(.failure(.invalidResponse))
            return
        }

        parseAndCopyResult(data: data, tempDir: tempDir, completion: completion)
    }

    // MARK: - API OCR

    private func performOCRApi(imageURL: URL, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) {
        do {
            try ensureVenv()
        } catch {
            Logger.shared.log("Error initializing venv: \(error.localizedDescription)")
            completion(.failure(.ocrError("Failed to init: \(error.localizedDescription)")))
            return
        }

        guard let token = CredentialsManager.load(key: "api_token"), !token.isEmpty else {
            Logger.shared.log("Error: API token not configured")
            completion(.failure(.ocrError("API token not set. Configure it in Settings.")))
            return
        }

        let model = UserDefaults.standard.string(forKey: "api_model") ?? "PaddleOCR-VL-1.6"
        let useLayoutDetection = UserDefaults.standard.bool(forKey: "api_use_layout_detection")
        let useChartRecognition = UserDefaults.standard.bool(forKey: "api_use_chart_recognition")
        let prettifyMarkdown = UserDefaults.standard.bool(forKey: "api_prettify_markdown")
        let resultURL = tempDir.appendingPathComponent("api_result.json")

        self.isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async { self.isProcessing = false }
            }

            let process = Process()
            process.executableURL = self.pythonBin
            process.arguments = [
                self.ocrApiScript.path,
                "--image", imageURL.path,
                "--output", resultURL.path,
                "--token", token,
                "--model", model,
                "--poll-timeout", "120",
                "--use-layout-detection", useLayoutDetection ? "true" : "false",
                "--use-chart-recognition", useChartRecognition ? "true" : "false",
                "--prettify-markdown", prettifyMarkdown ? "true" : "false",
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
                Logger.shared.log("Submitting API OCR task via Python SDK...")
                try process.run()
                process.waitUntilExit()
                errPipe.fileHandleForReading.readabilityHandler = nil
            } catch {
                Logger.shared.log("Error running API OCR: \(error.localizedDescription)")
                completion(.failure(.ocrError(error.localizedDescription)))
                return
            }

            Logger.shared.log("API OCR exit code: \(process.terminationStatus)")

            guard process.terminationStatus == 0 else {
                let detail = errBuf.trimmingCharacters(in: .whitespacesAndNewlines)
                let msg = detail.isEmpty ? "API request failed (exit code \(process.terminationStatus))" : detail
                Logger.shared.log("API error: \(msg)")
                completion(.failure(.ocrError(msg)))
                return
            }

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

    // MARK: - SiliconFlow OCR

    private func performOCRSiliconFlow(imageURL: URL, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) {
        guard let token = CredentialsManager.load(key: "siliconflow_token"), !token.isEmpty else {
            Logger.shared.log("Error: SiliconFlow API token not configured")
            completion(.failure(.ocrError("SiliconFlow API token not set. Configure it in Settings.")))
            return
        }

        let model = UserDefaults.standard.string(forKey: "siliconflow_model") ?? "deepseek-ai/DeepSeek-OCR"

        guard let imageData = try? Data(contentsOf: imageURL) else {
            Logger.shared.log("Error: Failed to read image data")
            completion(.failure(.failedToConvertImage))
            return
        }

        let base64Image = imageData.base64EncodedString()
        let dataURI = "data:image/png;base64,\(base64Image)"

        self.isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async { self.isProcessing = false }
            }

            let url = URL(string: "https://api.siliconflow.cn/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 120

            let body: [String: Any] = [
                "model": model,
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["type": "image_url", "image_url": ["url": dataURI]],
                            ["type": "text", "text": "Please extract all text from this image."],
                        ],
                    ]
                ],
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                Logger.shared.log("Error serializing request: \(error.localizedDescription)")
                completion(.failure(.ocrError("Failed to create request")))
                return
            }

            Logger.shared.log("Sending request to SiliconFlow API...")

            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var responseError: Error?

            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                responseData = data
                responseError = error
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()

            if let error = responseError {
                Logger.shared.log("SiliconFlow API error: \(error.localizedDescription)")
                completion(.failure(.ocrError(error.localizedDescription)))
                return
            }

            guard let data = responseData else {
                Logger.shared.log("Error: No response from SiliconFlow API")
                completion(.failure(.invalidResponse))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    Logger.shared.log("Error: Invalid JSON from SiliconFlow API")
                    if let raw = String(data: data, encoding: .utf8) {
                        Logger.shared.log("Raw response: \(raw.prefix(500))")
                    }
                    completion(.failure(.invalidResponse))
                    return
                }

                if let errorObj = json["error"] as? [String: Any] {
                    let msg = errorObj["message"] as? String ?? "Unknown error"
                    Logger.shared.log("SiliconFlow API error: \(msg)")
                    completion(.failure(.ocrError(msg)))
                    return
                }

                if let code = json["code"] as? Int, code != 0 {
                    let msg = json["message"] as? String ?? "Unknown error"
                    Logger.shared.log("SiliconFlow API error: \(msg)")
                    completion(.failure(.ocrError(msg)))
                    return
                }

                guard let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let message = first["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    Logger.shared.log("Error: Unexpected response format")
                    if let raw = String(data: data, encoding: .utf8) {
                        Logger.shared.log("Raw response: \(raw.prefix(500))")
                    }
                    completion(.failure(.invalidResponse))
                    return
                }

                Logger.shared.log("SiliconFlow OCR Success. Chars: \(content.count)")

                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(content, forType: .string)
                    self.lastResult = content
                }

                completion(.success(content))
            } catch {
                Logger.shared.log("Error parsing SiliconFlow response: \(error.localizedDescription)")
                completion(.failure(.invalidResponse))
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - OpenAI Compatible LLM OCR

    private func performOCRLLM(imageURL: URL, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) {
        guard let token = CredentialsManager.load(key: "llm_token"), !token.isEmpty else {
            Logger.shared.log("Error: LLM API token not configured")
            completion(.failure(.ocrError("LLM API token not set. Configure it in Settings.")))
            return
        }

        let baseURL = UserDefaults.standard.string(forKey: "llm_base_url") ?? "https://api.openai.com/v1"
        let model = UserDefaults.standard.string(forKey: "llm_model") ?? "gpt-4o"
        let headersText = UserDefaults.standard.string(forKey: "llm_headers") ?? ""
        let systemPrompt = UserDefaults.standard.string(forKey: "llm_system_prompt") ?? OCRService.defaultLLMSystemPrompt

        performChatCompletionOCR(
            imageURL: imageURL,
            tempDir: tempDir,
            baseURL: baseURL,
            model: model,
            token: token,
            headersText: headersText,
            systemPrompt: systemPrompt,
            disableThinking: false,
            tag: "llm",
            completion: completion
        )
    }

    private func performOCRKimi(imageURL: URL, tempDir: URL, completion: @escaping (Result<String, OCRError>) -> Void) {
        guard let token = CredentialsManager.load(key: "kimi_token"), !token.isEmpty else {
            Logger.shared.log("Error: Kimi API token not configured")
            completion(.failure(.ocrError("Kimi API token not set. Configure it in Settings.")))
            return
        }

        let model = UserDefaults.standard.string(forKey: "kimi_model") ?? "kimi-k2.6"
        let systemPrompt = UserDefaults.standard.string(forKey: "kimi_system_prompt") ?? OCRService.defaultKimiSystemPrompt
        let disableThinking = UserDefaults.standard.object(forKey: "kimi_disable_thinking") as? Bool ?? true

        performChatCompletionOCR(
            imageURL: imageURL,
            tempDir: tempDir,
            baseURL: "https://api.moonshot.ai/v1",
            model: model,
            token: token,
            headersText: "",
            systemPrompt: systemPrompt,
            disableThinking: disableThinking,
            tag: "kimi",
            completion: completion
        )
    }

    /// Shared OpenAI-compatible chat-completions OCR engine. Used by both the
    /// generic LLM mode (configurable base URL / headers) and the Kimi mode
    /// (preset Moonshot endpoint). Sends the image as a vision `image_url`
    /// content part together with a system prompt and a short user instruction.
    private func performChatCompletionOCR(
        imageURL: URL,
        tempDir: URL,
        baseURL: String,
        model: String,
        token: String,
        headersText: String,
        systemPrompt: String,
        disableThinking: Bool,
        tag: String,
        completion: @escaping (Result<String, OCRError>) -> Void
    ) {
        guard let imageData = try? Data(contentsOf: imageURL) else {
            Logger.shared.log("Error: Failed to read image data")
            completion(.failure(.failedToConvertImage))
            return
        }

        let base64Image = imageData.base64EncodedString()
        let dataURI = "data:image/png;base64,\(base64Image)"

        guard let request = buildChatCompletionRequest(
            baseURL: baseURL,
            model: model,
            token: token,
            headersText: headersText,
            systemPrompt: systemPrompt,
            disableThinking: disableThinking,
            dataURI: dataURI
        ) else {
            Logger.shared.log("Error: Invalid base URL for \(tag)")
            completion(.failure(.ocrError("Invalid API base URL")))
            return
        }

        self.isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async { self.isProcessing = false }
            }

            Logger.shared.log("Sending request to \(tag) API (model: \(model))...")

            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var responseError: Error?

            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                responseData = data
                responseError = error
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()

            if let error = responseError {
                Logger.shared.log("\(tag) API error: \(error.localizedDescription)")
                completion(.failure(.ocrError(error.localizedDescription)))
                return
            }

            guard let data = responseData else {
                Logger.shared.log("Error: No response from \(tag) API")
                completion(.failure(.invalidResponse))
                return
            }

            let content = self.parseChatCompletionContent(data: data, tag: tag)
            switch content {
            case .success(let text):
                Logger.shared.log("\(tag) OCR Success. Chars: \(text.count)")
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    self.lastResult = text
                }
                completion(.success(text))
            case .failure(let err):
                completion(.failure(err))
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testLLMConnection(baseURL: String, model: String, token: String, headersText: String, systemPrompt: String, completion: @escaping (String?) -> Void) {
        testChatCompletionConnection(
            baseURL: baseURL, model: model, token: token,
            headersText: headersText, systemPrompt: systemPrompt,
            disableThinking: false,
            tag: "llm", completion: completion
        )
    }

    func testKimiConnection(token: String, model: String, systemPrompt: String, disableThinking: Bool, completion: @escaping (String?) -> Void) {
        testChatCompletionConnection(
            baseURL: "https://api.moonshot.ai/v1", model: model, token: token,
            headersText: "", systemPrompt: systemPrompt,
            disableThinking: disableThinking,
            tag: "kimi", completion: completion
        )
    }

    private func testChatCompletionConnection(
        baseURL: String,
        model: String,
        token: String,
        headersText: String,
        systemPrompt: String,
        disableThinking: Bool,
        tag: String,
        completion: @escaping (String?) -> Void
    ) {
        Logger.shared.log("Testing \(tag) connection with model: \(model)")

        let testImage = createTestImage()
        guard let tiffData = testImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            completion("Failed to create test image")
            return
        }
        let dataURI = "data:image/png;base64,\(pngData.base64EncodedString())"

        guard var request = buildChatCompletionRequest(
            baseURL: baseURL, model: model, token: token,
            headersText: headersText, systemPrompt: systemPrompt,
            disableThinking: disableThinking,
            dataURI: dataURI
        ) else {
            completion("Invalid API base URL")
            return
        }
        request.timeoutInterval = 30

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(error.localizedDescription)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion("Invalid response")
                return
            }
            guard httpResponse.statusCode == 200 else {
                var msg = "HTTP \(httpResponse.statusCode)"
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    msg += ": \(str.prefix(200))"
                }
                completion(msg)
                return
            }
            guard let data = data else {
                completion("Empty response")
                return
            }

            switch self.parseChatCompletionContent(data: data, tag: tag) {
            case .success:
                Logger.shared.log("\(tag) connection test successful")
                completion(nil)
            case .failure(let err):
                completion(err.localizedDescription)
            }
        }
        task.resume()
    }

    // MARK: - Chat completion helpers

    /// Resolves a user-supplied base URL to a full `/chat/completions` endpoint.
    /// Accepts a bare host, a `.../v1` prefix, or a full endpoint URL.
    private func resolveChatCompletionsURL(_ base: String) -> String? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") { return trimmed }
        if trimmed.hasSuffix("/v1") { return trimmed + "/chat/completions" }
        return trimmed + "/v1/chat/completions"
    }

    /// Parses a `Key: Value`-per-line block of custom HTTP headers.
    private func parseCustomHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let idx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    private func buildChatCompletionRequest(
        baseURL: String,
        model: String,
        token: String,
        headersText: String,
        systemPrompt: String,
        disableThinking: Bool,
        dataURI: String
    ) -> URLRequest? {
        guard let endpoint = resolveChatCompletionsURL(baseURL),
              let url = URL(string: endpoint) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Custom headers are applied last so they can override the defaults
        // (e.g. a non-Bearer Authorization scheme).
        for (key, value) in parseCustomHeaders(headersText) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 120

        var messages: [[String: Any]] = []
        let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            messages.append(["role": "system", "content": trimmedSystem])
        }
        messages.append([
            "role": "user",
            "content": [
                ["type": "image_url", "image_url": ["url": dataURI]],
                ["type": "text", "text": ocrUserInstruction],
            ],
        ])

        var body: [String: Any] = ["model": model, "messages": messages]
        // Disable the reasoning/thinking pass for Moonshot reasoning models
        // (e.g. kimi-k2.6). Faster, cheaper, and irrelevant to plain text OCR.
        // Non-reasoning models silently ignore this field. Only injected when
        // requested so the generic LLM mode stays OpenAI-compatible.
        if disableThinking {
            body["thinking"] = ["type": "disabled"]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private enum ContentParseResult {
        case success(String)
        case failure(OCRError)
    }

    /// Extracts the assistant text from an OpenAI-compatible chat-completion
    /// response. Handles `content` as both a plain string and an array of
    /// content parts (some providers return the array form).
    private func parseChatCompletionContent(data: Data, tag: String) -> ContentParseResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.shared.log("Error: Invalid JSON from \(tag) API")
            if let raw = String(data: data, encoding: .utf8) {
                Logger.shared.log("Raw response: \(raw.prefix(500))")
            }
            return .failure(.invalidResponse)
        }

        if let errorObj = json["error"] as? [String: Any] {
            let msg = errorObj["message"] as? String ?? "Unknown error"
            Logger.shared.log("\(tag) API error: \(msg)")
            return .failure(.ocrError(msg))
        }
        if let code = json["code"] as? Int, code != 0 {
            let msg = json["message"] as? String ?? "Unknown error"
            Logger.shared.log("\(tag) API error: \(msg)")
            return .failure(.ocrError(msg))
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            Logger.shared.log("Error: Unexpected response format from \(tag)")
            if let raw = String(data: data, encoding: .utf8) {
                Logger.shared.log("Raw response: \(raw.prefix(500))")
            }
            return .failure(.invalidResponse)
        }

        if let s = message["content"] as? String {
            return .success(s)
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty {
                return .success(text)
            }
        }
        if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty {
            // Some models put output under reasoning_content; treat as fallback.
            return .success(reasoning)
        }

        Logger.shared.log("Error: No text content in \(tag) response")
        return .failure(.invalidResponse)
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
        Logger.shared.log("NSImage size: \(image.size.width)x\(image.size.height) pts, reps: \(image.representations.count)")

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return false
        }

        let pxW = bitmap.pixelsWide
        let pxH = bitmap.pixelsHigh
        Logger.shared.log("Bitmap size: \(pxW)x\(pxH) px")

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try pngData.write(to: url)
            Logger.shared.log("Saved PNG: \(pngData.count) bytes")
            return true
        } catch {
            Logger.shared.log("Error writing image: \(error.localizedDescription)")
            return false
        }
    }

    private func padImage(_ image: NSImage, horizontal padding: CGFloat) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let newW = Int(CGFloat(bitmap.pixelsWide) + padding * 2)
        let newH = bitmap.pixelsHigh
        let newImage = NSImage(size: NSSize(width: CGFloat(newW), height: CGFloat(newH)))

        newImage.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: newImage.size).fill()
        bitmap.draw(in: NSRect(x: padding, y: 0, width: CGFloat(bitmap.pixelsWide), height: CGFloat(bitmap.pixelsHigh)),
                    from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: false, hints: nil)
        newImage.unlockFocus()

        return newImage
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
