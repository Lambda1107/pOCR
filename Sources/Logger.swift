import Foundation

class Logger: ObservableObject {
    static let shared = Logger()

    @Published var logs: String = ""
    private let logFileURL: URL

    init() {
        let tempDir = FileManager.default.temporaryDirectory
        logFileURL = tempDir.appendingPathComponent("pocr.log")

        if let content = try? String(contentsOf: logFileURL, encoding: .utf8) {
            logs = content
        } else {
            log("Logger initialized. Log file: \(logFileURL.path)")
        }
    }

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"

        DispatchQueue.main.async {
            self.logs.append(logLine)
        }

        DispatchQueue.global(qos: .background).async {
            if let data = logLine.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? logLine.write(to: self.logFileURL, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    func clear() {
        logs = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("Logs cleared.")
    }

    func getLogFilePath() -> String {
        return logFileURL.path
    }
}
