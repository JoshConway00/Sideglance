import Cocoa
import SwiftUI
@MainActor final class Feed: ObservableObject {
    @Published var task: WatchedTask
    private let defaults: UserDefaults
    init(task: WatchedTask? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.task = task ?? WatchedTask.restored(savedID: defaults.string(forKey: "watchedTask"), tasks: taskCatalog())
    }
    @Published var entries: [Entry] = []
    @Published private var notificationCards: [Entry] = []
    @Published private var latestLiveStatus: LiveActivityStatus?
    @Published var intentionTitles = UserDefaults.standard.object(forKey: "intentionTitles") as? Bool ?? true
    @Published var summaryProvider = SummaryProvider(rawValue: UserDefaults.standard.string(forKey: "summaryProvider") ?? "apple") ?? .apple
    func setSummaryProvider(_ provider: SummaryProvider) {
        invalidateTitles()
        summaryProvider = provider
        defaults.set(provider.rawValue, forKey: "summaryProvider")
        refreshIntentionTitle()
    }
    @Published var titles: [String: String] = [:]
    @Published var promptTitles: [String: String] = [:]
    private var promptKey: String?
    private var promptSource: String?
    private var precedingResponse: String?
    func promptTitle(for entry: Entry) -> String? {
        guard intentionTitles, let key = entry.promptKey else { return nil }
        return promptTitles[key] ?? "Current request"
    }
    func subtitle(for entry: Entry) -> String {
        let label = title(for: entry) ?? entry.kind.rawValue
        if entry.kind == .error { return "\(label) · Error" + (entry.repetitions > 1 ? " ×\(entry.repetitions)" : "") }
        return label
    }
    @Published var titleStatus = intelligenceAvailability()
    @Published var summaryAvailabilityNotice: String?
    private var lastUnavailableSummaryState: String?
    private var intentionKey: String?
    private var narrativeBatch = NarrativeBatch()
    private var lastGroup: NarrativeGroup?
    @Published private var directTitles: [String: String] = [:]
    private let titleWriter = IntentionWriter()
    var setupActive = false
    func suspendSummariesForSetup() {
        setupActive = true
        titleJob?.cancel(); titleJob = nil; titleGeneration = UUID(); attemptedTitle = nil
    }
    private var titleJob: Task<Void, Never>?
    private var titleGeneration = UUID()
    private var attemptedTitle: String?
    private func invalidateTitles() {
        titleJob?.cancel(); titleJob = nil; titleGeneration = UUID()
        titles = [:]; promptTitles = [:]; attemptedTitle = nil
        summaryAvailabilityNotice = nil; lastUnavailableSummaryState = nil
    }
    func resetTitles() {
        invalidateTitles()
        dismissed = []
        notificationCards = []
        latestLiveStatus = nil
        intentionKey = nil; narrativeBatch = NarrativeBatch(); lastGroup = nil
        promptKey = nil; promptSource = nil; precedingResponse = nil
        directTitles = [:]
    }
    func trimHistory() {
        entries = Array(entries.suffix(250))
        dismissed.formIntersection(Set(entries.map(\.id) + notificationCards.map(\.id)))
        let intentionKeys = Set(entries.compactMap(\.intentionKey) + [intentionKey].compactMap { $0 })
        let promptKeys = Set(entries.compactMap(\.promptKey) + [promptKey].compactMap { $0 })
        titles = titles.filter { intentionKeys.contains($0.key) }
        directTitles = directTitles.filter { intentionKeys.contains($0.key) }
        promptTitles = promptTitles.filter { promptKeys.contains($0.key) }
    }
    func title(for entry: Entry) -> String? {
        guard intentionTitles, let key = entry.intentionKey else { return nil }
        if let summary = titles[key] { return summary }
        return directTitles[key].map { _ in summaryAvailabilityNotice == nil ? "Preparing summary" : "Summary unavailable" }
    }
    func notificationLabel(for entry: Entry) -> String {
        if let label = title(for: entry) { return label }
        return entry.kind == .activity ? "" : entry.text
    }
    func labelOrigin(for entry: Entry) -> String {
        guard intentionTitles, let key = entry.intentionKey else { return entry.kind == .activity ? "status_only_no_model" : "original_text_fallback" }
        if titles[key] != nil { return "generated_group_summary" }
        return directTitles[key] == nil ? "original_text_fallback" : "summary_status_no_model"
    }
    private var lastRetry = Date.distantPast
    func retryIntentionTitle() {
        guard Date().timeIntervalSince(lastRetry) >= 5 else { return }
        lastRetry = Date(); attemptedTitle = nil; refreshIntentionTitle(force: true)
    }
    var hasRecentSummarySource: Bool {
        activityBodyEntries(entries, includeTools: showActivity).contains {
            isRecent($0, now: now, lifetime: displayLifetime($0, base: lifetime, adaptive: adaptiveTiming)) &&
            ((promptKey != nil && $0.promptKey == promptKey) || (intentionKey != nil && $0.intentionKey == intentionKey))
        }
    }
    func refreshIntentionTitle(force: Bool = false) {
        guard !setupActive, intentionTitles, titleJob == nil else { return }
        guard force || hasRecentSummarySource else { return }
        let readyGroup = narrativeBatch.ready(now: Date(), force: force)
        let group = readyGroup ?? ((force || lastGroup?.key == intentionKey) ? lastGroup : nil)
        let key = group?.key, source = group?.source
        let requestKey = promptKey, requestSource = promptSource
        guard key != nil || requestKey != nil else { return }
        let jobKey = (requestKey ?? "") + ":" + (key ?? "")
        guard attemptedTitle != jobKey else { return }
        let provider = summaryProvider
        titleStatus = provider == .apple ? intelligenceAvailability() : (CodexSummary.executable == nil ? "Install Codex and sign in with ChatGPT" : "Summarising with Codex · uses allowance")
        guard provider == .codex ? CodexSummary.executable != nil : titleStatus == "On-device model ready" else {
            summaryAvailabilityNotice = titleStatus
            if lastUnavailableSummaryState != titleStatus {
                QualityLog.shared.record("summary_unavailable", ["task_id": task.id, "provider": provider.rawValue, "reason": titleStatus, "fallback": "summary unavailable status; no model request made"])
                lastUnavailableSummaryState = titleStatus
            }
            // Do not mark this work attempted: retry availability on later polls.
            return
        }
        summaryAvailabilityNotice = nil; lastUnavailableSummaryState = nil
        attemptedTitle = jobKey
        if let readyGroup { lastGroup = readyGroup; narrativeBatch.consume() }
        let generation = titleGeneration
        titleJob = Task { [weak self] in
            guard let self else { return }
            var failures: [SummaryFailure] = []
            if let requestKey, let requestSource, promptTitles[requestKey] == nil {
                do {
                    let heading = try await titleWriter.title(for: requestSource, isPrompt: true, provider: provider, trace: ["task_id": task.id, "source_key": requestKey])
                    guard !Task.isCancelled, titleGeneration == generation else { return }
                    promptTitles[requestKey] = heading
                } catch {
                    guard !Task.isCancelled, titleGeneration == generation else { return }
                    failures.append(error as? SummaryFailure ?? (provider == .apple ? .localGeneration : .process))
                }
            }
            if let key, let source, titles[key] == nil {
                do {
                    let result = try await titleWriter.title(for: source, provider: provider, trace: ["task_id": task.id, "source_key": key, "group_entry_ids": group?.entryIDs.joined(separator: ",") ?? "", "strategy": "group_distinct_narrative_updates"])
                    guard !Task.isCancelled, titleGeneration == generation else { return }
                    titles[key] = result
                } catch {
                    guard !Task.isCancelled, titleGeneration == generation else { return }
                    failures.append(error as? SummaryFailure ?? (provider == .apple ? .localGeneration : .process))
                }
            }
            if let failure = failures.first {
                let partial = requestKey.flatMap { self.promptTitles[$0] } != nil || key.flatMap { self.titles[$0] } != nil
                summaryAvailabilityNotice = failure.message
                titleStatus = (partial ? "Some labels unavailable · " : "") + failure.message
                // Store only safe categories and time; never process output, input text or tokens.
                var diagnostics = defaults.stringArray(forKey: "summaryDiagnostics") ?? []
                diagnostics.append(ISO8601DateFormatter().string(from: Date()) + " " + failure.message)
                defaults.set(Array(diagnostics.suffix(20)), forKey: "summaryDiagnostics")
            } else {
                titleStatus = provider == .apple ? "Summaries · on device" : "Temporary Codex summaries · uses allowance"
            }
            trimHistory()
            titleJob = nil
            refreshIntentionTitle()
        }
    }

    @Published var inputRequested = false
    @Published var lastActivity: Date?
    @Published var completedAt: Date?
    var showCompletionBadge: Bool {
        status == .finished && completedAt.map { now.timeIntervalSince($0) < 10 } == true
    }
    var displayStatus: String { inputRequested ? "Input requested" : (status == .finished ? "Complete" : status.rawValue) }
    var freshness: String {
        guard let date = lastActivity else { return "No recorded activity yet" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return seconds < 60 ? "Last activity \(seconds)s ago" : "Last activity \(seconds / 60)m ago"
    }
    func select(_ task: WatchedTask) {
        readerGeneration = UUID()
        resetTitles()
        self.task = task; defaults.set(task.id, forKey: "watchedTask")
        entries = []; revisions = RevisionTracker(); loaded = false; inputRequested = false
        status = .connecting; connection = .reading; lastActivity = nil; completedAt = nil
        reader = SourceReader(id: task.id)
        poll()
    }
    @Published var status: TaskState = .connecting
    @Published var connection: SourceConnection = .reading
    @Published var paused = false
    @Published var showActivity = false
    @Published var adaptiveTiming = UserDefaults.standard.object(forKey: "adaptiveTiming") as? Bool ?? true
    @Published var groupErrors = UserDefaults.standard.object(forKey: "groupErrors") as? Bool ?? true
    @Published var inputSound = UserDefaults.standard.bool(forKey: "inputSound")
    @Published var keepLatest = UserDefaults.standard.object(forKey: "keepLatestWhileWorking") as? Bool ?? true
    @Published var now = Date()
    @Published var editing = false
    @Published var lifetime = UserDefaults.standard.object(forKey: "lifetime") as? Double ?? 20
    @Published var opacity = UserDefaults.standard.object(forKey: "quietOpacity") as? Double ?? 0.9
    @Published var fontSize = UserDefaults.standard.object(forKey: "quietFontSize") as? Double ?? 13
    private var revisions = RevisionTracker()
    private var loaded = false
    private var reader: SourceReader?
    private let queue = DispatchQueue(label: "app.sideglance.reader")
    private var timer: Timer?
    private var busy = false
    private(set) var readerGeneration = UUID()
    private var dismissed: Set<String> = []
    func dismiss(_ entry: Entry) { dismissed.formUnion(notificationCards.map(\.id)) }
    var currentActivityNeedsAttention: Bool { inputRequested || latestLiveStatus?.kind == .error }
    var currentActivityLabel: String {
        if inputRequested { return "Input requested" }
        if status == .finished { return "Complete" }
        guard let live = latestLiveStatus else { return displayStatus }
        if live.kind == .summary || live.kind == .progress {
            let label = notificationPlainText(live.text)
            if !label.isEmpty && label.count <= 96 && !label.contains("…") && !label.contains("...") { return label }
            return displayStatus
        }
        if live.kind == .answer { return displayStatus }
        return liveActivityLabel(Entry(id: live.entryID, kind: live.kind, text: live.text, time: ""))
    }
    func appendNotification(_ entry: Entry) {
        latestLiveStatus = LiveActivityStatus(entryID: entry.id, kind: entry.kind, text: entry.text)
        if entry.kind != .error { notificationCards.removeAll { $0.kind == .error } }
        if !activityBodyEntries([entry], includeTools: true).isEmpty { appendNotificationCard(entry, to: &notificationCards) }
    }
    var visible: [Entry] {
        let filtered = activityBodyEntries(notificationCards, includeTools: showActivity).filter { !dismissed.contains($0.id) }.map { entry in
            var card = entry
            if showActivity { card.liveStatus = latestLiveStatus ?? card.liveStatus }
            else { card.liveStatus = nil }
            return card
        }
        // Keep a completed summary in place while its successor is being generated.
        let stable = filtered.filter { entry in
            guard intentionTitles, entry.kind != .error,
                  entry.intentionKey.flatMap({ titles[$0] }) == nil else { return true }
            return !filtered.contains { prior in
                prior.promptKey == entry.promptKey && prior.intentionKey.flatMap({ titles[$0] }) != nil
            }
        }
        let candidates = groupErrors ? groupedErrors(stable) : stable
        return Array(candidates.suffix(1))
    }
    func start() {
        poll()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date(); self?.poll() }
        }
    }
    func poll() {
        guard !task.id.isEmpty else { status = .unselected; connection = .unselected; return }
        guard !paused, !busy else { return }
        busy = true
        if reader == nil { reader = SourceReader(id: task.id) }
        let logReader = reader!
        let requestedTask = task.id
        let requestedGeneration = readerGeneration
        queue.async { [self] in
            let result = Result { try logReader.read() }
            DispatchQueue.main.async { [self] in
                applyRead(result, taskID: requestedTask, generation: requestedGeneration)

            }
        }
    }
    func applyRead(_ result: Result<([Decoded], Bool), Error>, taskID: String, generation: UUID) {
        busy = false
        guard task.id == taskID && readerGeneration == generation else { poll(); return }
        switch result {
        case .success(let (updates, reset)):
            connection = .connected
            if reset { resetTitles(); entries = []; revisions = RevisionTracker(); loaded = false; status = .watching; inputRequested = false; lastActivity = nil; completedAt = nil }
            for update in updates {
                if let state = update.state {
                    status = state
                    latestLiveStatus = LiveActivityStatus(entryID: "state:" + UUID().uuidString, kind: .activity, text: state.rawValue)
                    completedAt = state == .finished ? (loaded ? Date() : update.completedAt) : nil
                    if state == .working { intentionKey = nil; narrativeBatch = NarrativeBatch(); lastGroup = nil }
                }
                if let prompt = update.userPrompt, !prompt.isEmpty {
                    latestLiveStatus = LiveActivityStatus(entryID: "request:" + UUID().uuidString, kind: .activity, text: "Working")
                    promptKey = UUID().uuidString; promptSource = contextualPrompt(prompt, previousResponse: precedingResponse)
                    QualityLog.shared.record("source_prompt", ["task_id": task.id, "source_key": promptKey!, "original_text": prompt, "contextual_input": promptSource ?? ""])
                    intentionKey = nil; narrativeBatch = NarrativeBatch(); lastGroup = nil
                }
                if let requested = update.inputRequested {
                    if shouldPlayInputSound(enabled: inputSound, live: loaded, wasRequested: inputRequested, requested: requested) {
                        let sound = NSSound(named: "Tink"); sound?.volume = 0.35; sound?.play()
                    }
                    inputRequested = requested
                }
                for candidate in update.messages {
                    if var entry = revisions.accept(candidate, receivedAt: loaded ? Date() : nil) {
                        if [.progress, .answer].contains(entry.kind) { precedingResponse = entry.text }
                        if narrativeBatch.add(entry, now: Date()) {
                            intentionKey = entry.id
                            directTitles[entry.id] = "Preparing summary"
                            QualityLog.shared.record("label_decision", ["task_id": task.id, "entry_id": entry.id, "source_key": entry.id, "strategy": "summary_pending_debounced_narrative", "display_label": directTitles[entry.id] ?? "", "model_used": "none"])
                        } else if entry.kind == .activity || entry.kind == .error {
                            QualityLog.shared.record("label_decision", ["task_id": task.id, "entry_id": entry.id, "strategy": "deterministic_live_status", "display_status": liveActivityLabel(entry), "model_used": "none"])
                        }
                        if [.progress, .activity, .error, .summary, .answer].contains(entry.kind) { entry.intentionKey = intentionKey }
                        entry.promptKey = promptKey
                        QualityLog.shared.record("source_message", ["task_id": task.id, "entry_id": entry.id, "source_key": entry.intentionKey ?? "", "prompt_key": entry.promptKey ?? "", "kind": entry.kind.rawValue, "original_text": entry.text, "source_timestamp": entry.date.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"])
                        entries.append(entry); lastActivity = entry.date
                        appendNotification(entry)
                    }
                }
            }
            loaded = true
            trimHistory()
            refreshIntentionTitle()
            if status == .connecting { status = .watching }
        case .failure:
            connection = .disconnected
        }
    }
}
