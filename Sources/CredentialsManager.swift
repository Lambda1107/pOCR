import Foundation

class CredentialsManager {
    private static let configDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pocr")
    }()
    private static let credFile = configDir.appendingPathComponent("credentials.json")

    private static func ensureDir() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }

    private static func readAll() -> [String: String] {
        guard let data = try? Data(contentsOf: credFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }

    private static func writeAll(_ dict: [String: String]) {
        ensureDir()
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: credFile, options: .atomic)
    }

    static func save(key: String, value: String) {
        var dict = readAll()
        dict[key] = value
        writeAll(dict)
    }

    static func load(key: String) -> String? {
        return readAll()[key]
    }

    static func delete(key: String) {
        var dict = readAll()
        dict.removeValue(forKey: key)
        writeAll(dict)
    }
}
