import Foundation

enum MultiplayerShellDebugLog {
    private static let queue = DispatchQueue(label: "com.antigravity.gostop.multiplayer-shell-debug-log")
    private static let fileName = "debug_log_multiplayer.ndjson"
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var fileURL: URL {
        let fileManager = FileManager.default
        if let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            let directory = applicationSupport.appendingPathComponent("GoStop", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(fileName)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static var displayPath: String {
        fileURL.path
    }

    static func append(event: String, fields: [String: String?] = [:]) {
        let timestamp = formatter.string(from: .now)
        var payload: [String: String] = [
            "event": event,
            "ts": timestamp,
        ]
        for (key, value) in fields {
            guard let value, !value.isEmpty else { continue }
            payload[key] = value
        }
        let line = payload.keys.sorted().map { key in
            "\(key)=\(payload[key] ?? "")"
        }.joined(separator: " | ") + "\n"

        queue.async {
            let url = fileURL
            let fileManager = FileManager.default
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }

#if DEBUG
        print("[MultiplayerDebug] \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
#endif
    }
}
