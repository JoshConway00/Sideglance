import Cocoa
import SQLite3
import CryptoKit
enum EntryKind: String { case summary = "Summary", error = "Error", activity = "Activity", progress = "Progress", answer = "Answer" }
enum TaskState: String { case connecting = "Connecting", watching = "Watching", working = "Working", finished = "Finished", stopped = "Stopped", unselected = "Choose a task" }
enum SourceConnection: String { case reading = "Reading local activity", connected = "Connected · checks every 250 ms", disconnected = "Disconnected · retrying", unselected = "Select a task from the menu" }


enum CodexPaths {
    static var home: URL {
        if let value = getenv("CODEX_HOME"), let path = String(validatingUTF8: value), path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }
    static var database: String {
        let files = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        let states = files.compactMap { url -> (Int, URL)? in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "sqlite", name.hasPrefix("state_"), let version = Int(name.dropFirst(6)) else { return nil }
            return (version, url)
        }
        return states.max(by: { $0.0 < $1.0 })?.1.path ?? home.appendingPathComponent("state_5.sqlite").path
    }
}

func currentLog(id: String) -> URL {
    let root = CodexPaths.home.appendingPathComponent("sessions")
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return CodexPaths.home.appendingPathComponent("missing-\(id).jsonl") }
    var latest = CodexPaths.home.appendingPathComponent("missing-\(id).jsonl")
    var date = Date.distantPast
    for case let url as URL in files where url.pathExtension == "jsonl" && url.lastPathComponent.contains(id) {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if modified > date { latest = url; date = modified }
    }
    return latest
}
final class SourceReader: @unchecked Sendable {
    private let id: String
    private var reader: LogReader
    init(id: String) { self.id = id; reader = LogReader(FileManager.default.temporaryDirectory.appendingPathComponent("unresolved-sideglance-log")) }
    private var checked = Date.distantPast
    func read() throws -> ([Decoded], Bool) {
        var changed = false
        if Date().timeIntervalSince(checked) > 2 {
            let url = currentLog(id: id)
            if url != reader.url { reader = LogReader(url); changed = true }
            checked = Date()
        }
        let (updates, reset) = try reader.read()
        return (updates, changed || reset)
    }
}



struct WatchedTask: Identifiable {
    static let unselected = WatchedTask(id: "", title: "Choose a task", project: "")
    static func restored(savedID: String?, tasks: [WatchedTask]) -> WatchedTask {
        tasks.first { $0.id == savedID } ?? .unselected
    }
    let id: String
    let title: String
    let project: String
}
func taskCatalog(path: String = CodexPaths.database) -> [WatchedTask] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { if db != nil { sqlite3_close(db) }; return [] }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 200)
    var statement: OpaquePointer?
    var schema: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &schema, nil) == SQLITE_OK else { return [] }
    var columns: Set<String> = []
    while sqlite3_step(schema) == SQLITE_ROW {
        if let value = sqlite3_column_text(schema, 1) { columns.insert(String(cString: value)) }
    }
    sqlite3_finalize(schema)
    guard columns.contains("id"), columns.contains("title") || columns.contains("name") else { return [] }
    let title = columns.contains("name") && columns.contains("title") ? "COALESCE(NULLIF(name,''),title)" : (columns.contains("title") ? "title" : "name")
    let cwd = columns.contains("cwd") ? "cwd" : "''"
    var predicates: [String] = []
    if columns.contains("archived") { predicates.append("archived=0") }
    if columns.contains("thread_source") { predicates.append("thread_source IN ('user','chatgpt_handoff','cli','vscode','appServer')") }
    let filter = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
    let sort = columns.contains("updated_at") ? " ORDER BY updated_at DESC" : ""
    let sql = "SELECT id, \(title), \(cwd) FROM threads" + filter + sort + " LIMIT 100"
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    var tasks: [WatchedTask] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        func field(_ index: Int32) -> String { sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
        tasks.append(WatchedTask(id: field(0), title: field(1), project: URL(fileURLWithPath: field(2)).lastPathComponent))
    }
    return tasks
}

struct LiveActivityStatus {
    let entryID: String
    let kind: EntryKind
    let text: String
}

struct Entry: Identifiable {
    let id: String
    let kind: EntryKind
    let text: String
    let time: String
    let date: Date?
    var liveStatus: LiveActivityStatus? = nil
    var errorKey: String? = nil
    var repetitions: Int = 1
    var intentionKey: String? = nil
    var promptKey: String? = nil
    init(id: String, kind: EntryKind, text: String, time: String, errorKey: String? = nil, repetitions: Int = 1, intentionKey: String? = nil, promptKey: String? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.time = time; self.date = eventDate(time)
        self.errorKey = errorKey; self.repetitions = repetitions; self.intentionKey = intentionKey; self.promptKey = promptKey
    }
}
func errorFingerprint(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}
func displayLifetime(_ entry: Entry, base: Double, adaptive: Bool) -> Double {
    guard adaptive else { return base }
    // The overlay shows a short excerpt; full messages remain in History.
    let words = String(entry.text.prefix(450)).split { $0.isWhitespace }.count
    return max(base, min(60, Double(words) / 3 + 3))
}
func activityBodyEntries(_ entries: [Entry], includeTools: Bool) -> [Entry] {
    entries.filter { $0.kind == .summary || $0.kind == .progress || $0.kind == .answer || $0.kind == .error || (includeTools && $0.kind == .activity) }
}
func groupedErrors(_ entries: [Entry]) -> [Entry] {
    var result: [Entry] = []
    for entry in entries {
        if let previous = result.last, entry.kind == .error, previous.kind == .error,
           let key = entry.errorKey, key == previous.errorKey, entry.promptKey == previous.promptKey,
           let time = entry.date, let before = previous.date,
           time.timeIntervalSince(before) >= 0, time.timeIntervalSince(before) <= 120 {
            var merged = entry
            merged.repetitions = previous.repetitions + 1
            result[result.count - 1] = merged
        } else { result.append(entry) }
    }
    return result
}
func shouldPlayInputSound(enabled: Bool, live: Bool, wasRequested: Bool, requested: Bool) -> Bool {
    enabled && live && !wasRequested && requested
}
func fittedFrame(_ proposed: NSRect, within bounds: NSRect) -> NSRect {
    let width = min(proposed.width, bounds.width), height = min(proposed.height, bounds.height)
    return NSRect(x: min(max(proposed.minX, bounds.minX), bounds.maxX - width),
                  y: min(max(proposed.minY, bounds.minY), bounds.maxY - height), width: width, height: height)
}
func eventDate(_ text: String) -> Date? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}
func isRecent(_ entry: Entry, now: Date, lifetime: Double) -> Bool {
    guard let date = entry.date else { return false }
    return now.timeIntervalSince(date) < lifetime
}
func extractUserRequest(_ content: String) -> String {
    for marker in ["## My request:", "# My request:"] {
        if let range = content.range(of: marker) { return String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}
func contextualPrompt(_ request: String, previousResponse: String?) -> String {
    let lower = request.lowercased()
    let isFollowUp = request.split { $0.isWhitespace }.count <= 30 && lower.range(of: #"\b(proceed|go ahead|yes|yep|agreed|recommendations?|try that|do that|do it|all of them|those|that one)\b"#, options: .regularExpression) != nil
    guard isFollowUp, let previousResponse, !previousResponse.isEmpty else { return request }
    return "User follow-up:\n" + String(request.prefix(500)) + "\n\nPreceding proposed work accepted or referred to by the follow-up (use its concrete topic for the title):\n" + String(previousResponse.prefix(1800))
}
struct Decoded {
    var entry: Entry? = nil
    var state: TaskState? = nil
    var completedAt: Date? = nil
    var additional: [Entry] = []
    var inputRequested: Bool? = nil
    var userPrompt: String? = nil
    var messages: [Entry] { (entry.map { [$0] } ?? []) + additional }
}
struct RevisionTracker {
    private var latest: [String: String] = [:]
    private var order: [String] = []
    let capacity = 1000
    var retainedCount: Int { latest.count }
    mutating func accept(_ entry: Entry, receivedAt: Date?) -> Entry? {
        let digest = errorFingerprint(entry.text)
        guard latest[entry.id] != digest else { return nil }
        if latest[entry.id] == nil {
            order.append(entry.id)
            if order.count > capacity { latest.removeValue(forKey: order.removeFirst()) }
        }
        latest[entry.id] = digest
        let stamp = receivedAt.map { ISO8601DateFormatter().string(from: $0) } ?? entry.time
        return Entry(id: UUID().uuidString, kind: entry.kind, text: entry.text, time: stamp, errorKey: entry.errorKey)
    }
}
// Only read the display title from known UI tools; never display code or other arguments.
func toolDisplayTitle(_ arguments: Any?, tool: String, server: String) -> String? {
    guard tool == "js", server.contains("cua_repl") else { return nil }
    let fields: [String: Any]?
    if let raw = arguments as? String, let data = raw.data(using: .utf8) {
        fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    } else { fields = arguments as? [String: Any] }
    guard let raw = fields?["title"] as? String else { return nil }
    let title = notificationPlainText(raw)
    guard !title.isEmpty, title.count <= 160 else { return nil }
    return title
}

func decode(_ line: Data) -> Decoded {
    guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let payload = root["payload"] as? [String: Any] else { return Decoded() }
    let type = payload["type"] as? String ?? ""
    if root["type"] as? String == "response_item", ["function_call", "custom_tool_call"].contains(type) {
        let name = payload["name"] as? String ?? ""
        var label: String
        switch name {
        case "exec_command": label = "Running command"
        case "exec": label = "Running tools"
        case "js": label = "Using app or browser"
        case "imagegen": label = "Generating image"
        default: label = "Using tool · " + name
        }
        if let title = toolDisplayTitle(payload["arguments"], tool: name, server: payload["namespace"] as? String ?? "") { label = title }
        return Decoded(entry: Entry(id: "started:" + (payload["call_id"] as? String ?? UUID().uuidString), kind: .activity, text: label, time: root["timestamp"] as? String ?? ""))
    }
    guard root["type"] as? String == "event_msg" else { return Decoded() }
    if type == "task_started" { return Decoded(state: .working) }
    if type == "task_complete" { return Decoded(state: .finished, completedAt: eventDate(root["timestamp"] as? String ?? "")) }
    if type == "turn_aborted" { return Decoded(state: .stopped) }
    guard type == "item_completed", let item = payload["item"] as? [String: Any] else { return Decoded() }
    let itemType = item["type"] as? String ?? ""
    if itemType == "UserMessage" {
        let content = item["content"] as? String ?? (item["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        return Decoded(inputRequested: false, userPrompt: extractUserRequest(content))
    }
    let asksInput = !(item["questions"] as? [Any] ?? []).isEmpty
    var kind: EntryKind = .activity
    var text = ""
    var errorKey: String?
    switch itemType {
    case "AgentMessage":
        kind = item["phase"] as? String == "final_answer" ? .answer : .progress
        text = item["content"] as? String ?? (item["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    case "Reasoning":
        kind = .summary
        let summaries = item["summary_text"] as? [String] ?? [item["summary_text"] as? String ?? ""]
        let baseID = item["id"] as? String ?? UUID().uuidString
        let messages = summaries.enumerated().compactMap { index, summary -> Entry? in
            guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Entry(id: baseID + ":summary:\(index)", kind: .summary, text: summary, time: root["timestamp"] as? String ?? "")
        }
        return Decoded(entry: messages.first, additional: Array(messages.dropFirst()))
    case "CommandExecution":
        kind = (item["exit_code"] as? Int ?? 0) == 0 ? .activity : .error
        if kind == .error, let command = item["command"] { errorKey = errorFingerprint(String(describing: command)) }
        text = kind == .error ? "A command exited with an error. Check the task for details." : "Command completed"
    case "McpToolCall":
        kind = item["status"] as? String == "failed" ? .error : .activity
        if kind == .error { errorKey = errorFingerprint("\(item["server"] ?? "")/\(item["tool"] ?? "")") }
        let title = toolDisplayTitle(item["arguments"], tool: item["tool"] as? String ?? "", server: item["server"] as? String ?? "")
        text = (title ?? item["actionName"] as? String ?? item["tool"] as? String ?? "Tool") + " · " + (item["status"] as? String ?? "completed")
    case "FileChange": kind = .activity; text = "File changes · " + (item["status"] as? String ?? "completed")
    default: break
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Decoded(inputRequested: asksInput ? true : nil) }
    return Decoded(entry: Entry(id: item["id"] as? String ?? UUID().uuidString, kind: kind, text: text, time: root["timestamp"] as? String ?? "", errorKey: errorKey), inputRequested: asksInput ? true : nil)
}

// Reads only complete JSONL records. The first read is bounded; later reads are incremental.
// Mutable reader state is confined to the serial reader queue.
final class LogReader: @unchecked Sendable {
    let url: URL
    var offset: UInt64 = 0
    var pending = Data()
    var initialized = false
    var identity: UInt64 = 0
    init(_ url: URL) { self.url = url }
    func read() throws -> ([Decoded], Bool) {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let reset = initialized && (size < offset || identity != inode)
        if reset { offset = 0; pending.removeAll(); initialized = false }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var skipFirst = false
        if !initialized {
            offset = size > 16_000_000 ? size - 16_000_000 : 0
            skipFirst = offset > 0
            initialized = true
            identity = inode
        }
        try file.seek(toOffset: offset)
        let bytes = try file.read(upToCount: 16_000_000) ?? Data()
        offset += UInt64(bytes.count)
        pending.append(bytes)
        var records: [Decoded] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if skipFirst { skipFirst = false; continue }
            records.append(decode(line))
        }
        if pending.count > 16_000_000 { throw NSError(domain: "Oversized activity record", code: 1) }
        return (records, reset)
    }
}
