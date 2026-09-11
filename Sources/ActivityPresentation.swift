import Foundation

func compactActivityText(_ text: String, limit: Int = 48) -> String {
    let plain = notificationPlainText(text)
    guard plain.count > limit || plain.contains("…") || plain.contains("...") else { return plain }
    return "Activity update"
}

func liveActivityLabel(_ entry: Entry) -> String {
    let text = notificationPlainText(entry.liveStatus?.text ?? entry.text)
    if text == "Command completed" { return "Ran command" }
    if (entry.liveStatus?.kind ?? entry.kind) == .error { return text.lowercased().contains("command") ? "Command error" : "Tool error" }
    return compactActivityText(text, limit: 180)
}

struct NarrativeGroup {
    let key: String
    let source: String
    let entryIDs: [String]
}

// Routine tools update the card immediately. Only distinct narrative updates enter AI batches.
struct NarrativeBatch {
    private var members: [Entry] = []
    private var recentText: [String] = []
    private var readyAt: Date?
    private var groupedAt: Date?
    static func isNarrative(_ entry: Entry) -> Bool {
        guard entry.kind == .progress || entry.kind == .summary || entry.kind == .answer else { return false }
        let text = notificationPlainText(entry.text).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        return !text.isEmpty && !["running command", "ran command", "command completed", "running tools", "tool completed", "reading file", "reading files", "updating file", "using app or browser"].contains(text)
    }
    @discardableResult mutating func add(_ entry: Entry, now: Date) -> Bool {
        guard Self.isNarrative(entry) else { return false }
        let text = notificationPlainText(entry.text).lowercased()
        guard !recentText.contains(text) else { return false }
        recentText.append(text); recentText = Array(recentText.suffix(20))
        members.append(entry); members = Array(members.suffix(3))
        if !members.isEmpty {
            if groupedAt == nil { groupedAt = now }
            readyAt = min(now.addingTimeInterval(2), groupedAt!.addingTimeInterval(6))
        }
        return true
    }
    func ready(now: Date, force: Bool = false) -> NarrativeGroup? {
        guard !members.isEmpty, let readyAt, force || now >= readyAt, let last = members.last else { return nil }
        // Debounce bursts, but summarize only the latest update so older facts cannot win.
        let source = String(last.text.prefix(2400))
        return NarrativeGroup(key: last.id, source: source, entryIDs: [last.id])
    }
    mutating func consume() { members = []; readyAt = nil; groupedAt = nil }
}

// Keep the card identity/body while routine events replace only its live status.
func appendNotificationCard(_ entry: Entry, to cards: inout [Entry]) {
    if let last = cards.last, entry.kind == .activity, last.kind != .error,
       last.promptKey == entry.promptKey, last.intentionKey == entry.intentionKey {
        var updated = Entry(id: last.id, kind: last.kind, text: last.text, time: entry.time,
                            errorKey: last.errorKey, repetitions: last.repetitions,
                            intentionKey: last.intentionKey, promptKey: last.promptKey)
        updated.liveStatus = LiveActivityStatus(entryID: entry.id, kind: entry.kind, text: entry.text)
        cards[cards.count - 1] = updated
    } else {
        cards.append(entry)
    }
    cards = Array(cards.suffix(250))
}
