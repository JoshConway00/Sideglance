import Cocoa

// Content logging is deliberately separate from the text-free diagnostic history.
final class QualityLog: @unchecked Sendable {
    static let shared = QualityLog()
    let directory: URL
    private let defaults: UserDefaults
    private let lock = NSLock()
    private let limit: Int
    private let preferenceKey: String
    private var lastError: String?
    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Sideglance"), defaults: UserDefaults = .standard, limit: Int = 5_000_000, preferenceKey: String = "qualityLogging") {
        self.directory = directory; self.defaults = defaults; self.limit = limit; self.preferenceKey = preferenceKey
    }
    var enabled: Bool { defaults.bool(forKey: preferenceKey) }
    var error: String? { lock.lock(); defer { lock.unlock() }; return lastError }
    func setEnabled(_ value: Bool) { defaults.set(value, forKey: preferenceKey) }
    func record(_ event: String, _ fields: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            var row = fields
            row["event"] = event; row["timestamp"] = ISO8601DateFormatter().string(from: Date()); row["schema"] = "1"
            let bytes = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([10])
            guard bytes.count <= limit else { throw CocoaError(.fileWriteUnknown) }
            let file = directory.appendingPathComponent("quality.jsonl")
            let previous = directory.appendingPathComponent("quality-previous.jsonl")
            let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            if size + bytes.count > limit {
                if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
                if fm.fileExists(atPath: file.path) { try fm.moveItem(at: file, to: previous) }
            }
            if !fm.fileExists(atPath: file.path) { guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) } }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: bytes)
            lastError = nil
        } catch { lastError = "Quality log could not be written" }
    }
    func snapshotData() throws -> [Data] {
        lock.lock(); defer { lock.unlock() }
        return try ["quality-previous.jsonl", "quality.jsonl"].compactMap { name in
            let file = directory.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        }
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        do {
            for name in ["quality.jsonl", "quality-previous.jsonl"] {
                let file = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            }
            lastError = nil
        } catch { lastError = "Quality log could not be cleared" }
    }
}
