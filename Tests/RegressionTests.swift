import Cocoa
import SQLite3
func runRegressionTests() {
    func line(_ item: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: ["type": "event_msg", "payload": ["type": "item_completed", "item": item]]) }
    assert(decode(line(["type": "Reasoning", "summary_text": ["Visible summary"], "raw_content": "PRIVATE"])).entry?.text == "Visible summary")
    assert(decode(line(["type": "Reasoning", "raw_content": "PRIVATE"])).entry == nil)
    assert(decode(line(["type": "AgentMessage", "content": "Working", "phase": "commentary"])).entry?.kind == .progress)
    assert(decode(line(["type": "AgentMessage", "content": [["type": "Text", "text": "Live content"]]])).entry?.text == "Live content")
    assert(decode(Data("broken".utf8)).entry == nil)
    let parts = decode(line(["type": "Reasoning", "id": "same", "summary_text": ["First status", "Second status"]])).messages
    assert(parts.count == 2 && parts[0].id != parts[1].id)
    var tracker = RevisionTracker()
    let received = Date()
    let first = tracker.accept(parts[0], receivedAt: received)!
    assert(tracker.accept(parts[0], receivedAt: received) == nil)
    let changed = Entry(id: parts[0].id, kind: .summary, text: "Changed status", time: "")
    let next = tracker.accept(changed, receivedAt: received.addingTimeInterval(5))!
    assert(first.id != next.id && next.text == "Changed status")
    assert(eventDate(next.time)!.timeIntervalSince(received) > 4)
    print("PASS: separate status lines, changed text becomes a new message, duplicates ignored, fresh timer")
    assert(validFeatureEmail("features@example.com") && !validFeatureEmail("a@example.com\nBcc: injected@example.com"))
    assert(validFeatureProject("/private/tmp"))
    assert(!validFeatureProject("relative/path"))
    let requestText = "Add A&B + \"quotes\"\nSecond line 🟢"
    let requestURL = featureTaskURL(details: requestText, projectPath: "/private/tmp/Sideglance")!
    let requestPrompt = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
    assert(requestPrompt.contains(requestText) && requestPrompt.contains("Do not create a PR, push, or merge"))
    print("PASS: feature destinations, URL escaping and branch-and-commit handoff")
    assert(cleanIntentionTitle("Updating the feature request workflow") != nil)
    assert(cleanIntentionTitle("Here is a title:\nUpdating things") == nil)
    assert(cleanIntentionTitle(String(repeating: "long ", count: 30)) == nil)
    let user = decode(line(["type": "UserMessage", "content": [["type": "Text", "text": "## My request:\nClean up the menu"]]]))
    assert(user.userPrompt == "Clean up the menu")
    assert(user.messages.isEmpty)
    print("PASS: prompt extraction and separate user-message handling")
    assert(cleanIntentionTitle("Remove Personal Information, Ensure macOS Portability") == nil)
    assert(notificationPlainText("**Preparing environment-aware home resolution**") == "Preparing environment-aware home resolution")
    print("PASS: intention title output validation")
    let bodyFixture = [Entry(id: "p", kind: .progress, text: "Written progress", time: ""), Entry(id: "s", kind: .summary, text: "Adding accuracy metrics", time: ""), Entry(id: "t", kind: .activity, text: "Running command", time: ""), Entry(id: "a", kind: .answer, text: "Finished prose", time: "")]
    assert(activityBodyEntries(bodyFixture, includeTools: true).map(\.id) == ["s", "t"])
    assert(activityBodyEntries(bodyFixture, includeTools: false).map(\.id) == ["s"])
    let startData = try! JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": ["type": "function_call", "name": "exec_command", "call_id": "t1"]])
    assert(decode(startData).entry?.text == "Running command")
    print("PASS: activity-only body and saved tool-start events")
    let contextual = contextualPrompt("Proceed with recommendations", previousResponse: "Clarify advertising allocation and separate campaign performance.")
    assert(contextual.contains("Clarify advertising allocation"))
    assert(contextualPrompt("Make the font bigger", previousResponse: "Unrelated recommendation") == "Make the font bigger")
    assert(contextualPrompt("proceed", previousResponse: nil) == "proceed")
    assert(contextualPrompt("try that", previousResponse: String(repeating: "x", count: 9000)).count < 2500)
    print("PASS: contextual follow-ups, standalone requests, absent context and input bounds")
    let expiryEntry = Entry(id: "expiry", kind: .progress, text: "test", time: "2026-09-11T00:00:00Z")
    let base = eventDate(expiryEntry.time)!
    assert(isRecent(expiryEntry, now: base.addingTimeInterval(19), lifetime: 20))
    assert(!isRecent(expiryEntry, now: base.addingTimeInterval(20), lifetime: 20))
    assert(!isRecent(expiryEntry, now: base.addingTimeInterval(3600), lifetime: 20))
    assert(decode(line(["type": "AgentMessage", "content": "Please choose", "questions": [["id": "choice"]]])).inputRequested == true)
    assert(decode(line(["type": "UserMessage"])).inputRequested == false)
    assert(decode(line(["type": "AgentMessage", "content": "Working"])).inputRequested == nil)
    assert(taskCatalog(path: "/private/tmp/no-sideglance-test-db").isEmpty)
    assert(WatchedTask.restored(savedID: "missing", tasks: []).id.isEmpty)
    assert(currentLog(id: "nonexistent-test-id").lastPathComponent == "missing-nonexistent-test-id.jsonl")
    print("PASS: input request markers, user reply clears marker, task catalog, missing task isolation")
    let long = Entry(id: "long", kind: .progress, text: String(repeating: "word ", count: 90), time: expiryEntry.time)
    assert(displayLifetime(long, base: 20, adaptive: true) > 20)
    assert(displayLifetime(long, base: 20, adaptive: false) == 20)
    assert(displayLifetime(long, base: 120, adaptive: true) == 120)
    let e1 = Entry(id: "e1", kind: .error, text: "Failure", time: "2026-09-11T00:00:00Z", errorKey: "command-a")
    let e2 = Entry(id: "e2", kind: .error, text: "Failure", time: "2026-09-11T00:00:30Z", errorKey: "command-a")
    let e3 = Entry(id: "e3", kind: .error, text: "Failure", time: "2026-09-11T00:00:31Z", errorKey: "command-b")
    assert(groupedErrors([e1,e2]).count == 1 && groupedErrors([e1,e2])[0].repetitions == 2)
    assert(groupedErrors([e1,e2,e3]).count == 2)
    assert(!shouldPlayInputSound(enabled: true, live: false, wasRequested: false, requested: true))
    assert(!shouldPlayInputSound(enabled: true, live: true, wasRequested: true, requested: true))
    assert(!shouldPlayInputSound(enabled: false, live: true, wasRequested: false, requested: true))
    assert(shouldPlayInputSound(enabled: true, live: true, wasRequested: false, requested: true))
    let bounds = NSRect(x: -1440, y: 0, width: 1440, height: 900)
    let fitted = fittedFrame(NSRect(x: 2000, y: -300, width: 340, height: 300), within: bounds)
    assert(bounds.contains(fitted))
    assert(fittedFrame(NSRect(x: 0, y: 0, width: 3000, height: 2000), within: bounds) == bounds)
    print("PASS: adaptive timing, error grouping isolation, sound gating, disconnected-screen clamping")
    print("PASS: timed expiry and old history stays hidden")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let data = line(["type": "AgentMessage", "content": "Test", "id": "one"])
    try! data.write(to: url)
    let reader = LogReader(url)
    assert(try! reader.read().0.isEmpty)
    let handle = try! FileHandle(forWritingTo: url); try! handle.seekToEnd(); try! handle.write(contentsOf: Data([10])); try! handle.close()
    assert(try! reader.read().0.compactMap(\.entry).count == 1)
    assert(try! reader.read().0.isEmpty)
    try! Data("\n".utf8).write(to: url)
    assert(try! reader.read().1)
    try! FileManager.default.removeItem(at: url)
    print("PASS: summaries only, messages, malformed records, partial lines, incremental reads, truncation")
}


@MainActor func runStateRegressionTests() {
    let suite = "SideglanceTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let a = WatchedTask(id: "synthetic-a", title: "A", project: "Test")
    let b = WatchedTask(id: "synthetic-b", title: "B", project: "Test")
    let feed = Feed(task: a, defaults: defaults)
    feed.paused = true; feed.intentionTitles = false; feed.inputSound = false
    let staleGeneration = feed.readerGeneration
    feed.select(b); feed.select(a)
    let old = Entry(id: "old", kind: .summary, text: "Old synthetic activity", time: "2020-01-01T00:00:00Z")
    let oldRead: Result<([Decoded], Bool), Error> = .success(([Decoded(entry: old, state: .finished)], false))
    feed.applyRead(oldRead, taskID: a.id, generation: staleGeneration)
    assert(feed.entries.isEmpty && feed.status == .connecting)
    feed.applyRead(oldRead, taskID: a.id, generation: feed.readerGeneration)
    assert(feed.entries.count == 1 && feed.status == .finished)
    assert(!feed.hasRecentSummarySource)
    let generation = feed.readerGeneration
    let recent = Entry(id: "recent", kind: .summary, text: "Synthetic update", time: ISO8601DateFormatter().string(from: Date()))
    feed.applyRead(.success(([Decoded(userPrompt: "Synthetic request"), Decoded(entry: recent)], false)), taskID: a.id, generation: generation)
    assert(feed.hasRecentSummarySource)
    feed.now = Date().addingTimeInterval(3600)
    assert(!feed.hasRecentSummarySource)
    feed.entries = (0..<2000).map { Entry(id: "e\($0)", kind: .summary, text: "Synthetic", time: "", intentionKey: "i\($0)", promptKey: "p\($0)") }
    feed.titles = Dictionary(uniqueKeysWithValues: (0..<2000).map { ("i\($0)", "Test title") })
    feed.promptTitles = Dictionary(uniqueKeysWithValues: (0..<2000).map { ("p\($0)", "Test prompt") })
    feed.trimHistory()
    assert(feed.entries.count == 250 && feed.titles.count == 250 && feed.promptTitles.count == 250)
    var tracker = RevisionTracker()
    for index in 0..<5000 { _ = tracker.accept(Entry(id: "r\(index)", kind: .summary, text: "Synthetic large text \(index)", time: ""), receivedAt: nil) }
    assert(tracker.retainedCount == 1000)
    assert(tracker.accept(Entry(id: "r4999", kind: .summary, text: "Synthetic large text 4999", time: ""), receivedAt: nil) == nil)
    assert(tracker.accept(Entry(id: "r4999", kind: .summary, text: "Changed", time: ""), receivedAt: nil) != nil)
    let empty = Feed(task: .unselected, defaults: defaults)
    empty.poll()
    assert(empty.status == .unselected && empty.connection == .unselected)
    assert(WatchedTask.restored(savedID: a.id, tasks: [a,b]).id == a.id)
    assert(WatchedTask.restored(savedID: "removed", tasks: [a,b]).id.isEmpty)
    print("PASS: stale A-B-A reads rejected, bounded history/revisions, expired summaries skipped, portable startup")
}

func runProcessRegressionTests() async {
    let candidates = CodexInstallation.candidates(home: "/synthetic/home", path: "/synthetic/bin:/usr/local/bin", application: URL(fileURLWithPath: "/synthetic/Registered.app"))
    assert(candidates.first == "/synthetic/Registered.app/Contents/Resources/codex")
    assert(candidates.contains("/synthetic/home/.local/bin/codex") && candidates.contains("/synthetic/bin/codex"))
    assert(candidates.count == Set(candidates).count)
    assert(SummaryFailure.classify("401 unauthorized secret") == .authentication)
    assert(SummaryFailure.classify("429 rate limit") == .allowance)
    assert(SummaryFailure.classify("unexpected argument --ephemeral") == .compatibility)
    assert(SummaryFailure.classify("generic error") == .process)
    do {
        let result = try await SummaryProcess.run(executable: "/bin/echo", arguments: ["Synthetic title"])
        assert(result.status == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "Synthetic title")
        do {
            _ = try await SummaryProcess.run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.2)
            assertionFailure("Expected timeout")
        } catch { assert(error as? SummaryFailure == .timeout) }
        let pending = Task { try await SummaryProcess.run(executable: "/bin/sleep", arguments: ["10"]) }
        try await Task.sleep(nanoseconds: 200_000_000)
        pending.cancel()
        do { _ = try await pending.value; assertionFailure("Expected cancellation") }
        catch { assert(error is CancellationError) }
        print("PASS: Codex discovery, safe failure categories, process output, timeout and cancellation")
    } catch { assertionFailure("Process regression failed: \(error)") }
}


func runPortabilityTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sideglance-fixture-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let oldHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
    setenv("CODEX_HOME", root.path, 1)
    defer {
        if let oldHome { setenv("CODEX_HOME", oldHome, 1) } else { unsetenv("CODEX_HOME") }
    }
    var db: OpaquePointer?
    let path = root.appendingPathComponent("state_99.sqlite").path
    assert(sqlite3_open(path, &db) == SQLITE_OK)
    assert(sqlite3_exec(db, "CREATE TABLE threads(id TEXT, title TEXT); INSERT INTO threads VALUES('fixture','Sample chat');", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    assert(CodexPaths.home.resolvingSymlinksInPath() == root.resolvingSymlinksInPath())
    assert(URL(fileURLWithPath: CodexPaths.database).resolvingSymlinksInPath() == URL(fileURLWithPath: path).resolvingSymlinksInPath())
    let minimal = taskCatalog()
    assert(minimal.count == 1 && minimal.first?.title == "Sample chat")
    assert(sqlite3_open(path, &db) == SQLITE_OK)
    assert(sqlite3_exec(db, "ALTER TABLE threads ADD COLUMN name TEXT; ALTER TABLE threads ADD COLUMN archived INTEGER DEFAULT 0; ALTER TABLE threads ADD COLUMN thread_source TEXT DEFAULT 'cli'; UPDATE threads SET name='Renamed sample'; INSERT INTO threads(id,title,archived) VALUES('hidden','Archived sample',1);", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    assert(taskCatalog().map(\.title) == ["Renamed sample"])
    let sessions = root.appendingPathComponent("sessions")
    try! FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let log = sessions.appendingPathComponent("rollout-fixture.jsonl")
    try! Data("{}\n".utf8).write(to: log)
    assert(currentLog(id: "fixture").resolvingSymlinksInPath() == log.resolvingSymlinksInPath())
    print("PASS: custom Codex home, versioned database discovery, optional columns, CLI tasks and archive filtering")
}

func runQualityLogTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sideglance-quality-test-" + UUID().uuidString)
    let suite = "sideglance-quality-test-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let logger = QualityLog(directory: root, defaults: defaults, limit: 800, preferenceKey: "testQualityLogging")
    logger.record("disabled", ["text": "must not be written"])
    assert(!FileManager.default.fileExists(atPath: root.path))
    logger.setEnabled(true)
    logger.record("sample", ["request_id": "synthetic", "text": "Quoted \"label\"\nSecond line"])
    let file = root.appendingPathComponent("quality.jsonl")
    let data = try! Data(contentsOf: file)
    let row = try! JSONSerialization.jsonObject(with: data) as! [String: String]
    assert(row["text"] == "Quoted \"label\"\nSecond line" && row["request_id"] == "synthetic")
    let permissions = try! FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
    assert(permissions.intValue == 0o600)
    for index in 0..<12 { logger.record("rotation", ["index": String(index), "text": String(repeating: "x", count: 120)]) }
    assert(FileManager.default.fileExists(atPath: root.appendingPathComponent("quality-previous.jsonl").path))
    for name in ["quality.jsonl", "quality-previous.jsonl"] { assert((try! Data(contentsOf: root.appendingPathComponent(name))).count <= 800) }
    logger.setEnabled(false); logger.clear()
    assert(!FileManager.default.fileExists(atPath: file.path) && logger.error == nil)
    print("PASS: quality log opt-in, exact text round-trip, private permissions, bounded rotation and clear")
}

func runNarrativeBatchTests() {
    let now = Date(timeIntervalSince1970: 1000)
    func entry(_ id: String, _ kind: EntryKind, _ text: String) -> Entry { Entry(id: id, kind: kind, text: text, time: "") }
    var batch = NarrativeBatch()
    for index in 0..<20 { assert(!batch.add(entry("tool\(index)", .activity, "Running command"), now: now)) }
    assert(batch.ready(now: now.addingTimeInterval(10), force: true) == nil)
    assert(!batch.add(entry("routine", .summary, "Running command"), now: now))
    let first = entry("first", .progress, "Checking notification spacing")
    assert(batch.add(first, now: now))
    assert(batch.ready(now: now.addingTimeInterval(10), force: true) == nil)
    assert(!batch.add(entry("duplicate", .summary, "**Checking notification spacing**"), now: now))
    let second = entry("second", .summary, "Adjusting notification padding")
    assert(batch.add(second, now: now))
    assert(batch.ready(now: now.addingTimeInterval(1)) == nil)
    assert(batch.ready(now: now.addingTimeInterval(2))?.entryIDs == ["first", "second"])
    assert(batch.ready(now: now.addingTimeInterval(2))?.source.contains("Adjusting notification padding") == true)
    batch.consume()
    assert(batch.ready(now: now.addingTimeInterval(10), force: true) == nil)
    assert(!batch.add(first, now: now))
    assert(batch.add(entry("third", .progress, "Checking notification controls"), now: now))
    assert(batch.ready(now: now.addingTimeInterval(10), force: true) == nil)
    var bounded = NarrativeBatch()
    for index in 0..<8 { assert(bounded.add(entry("long\(index)", .summary, "Step \(index) " + String(repeating: "x", count: 2000)), now: now)) }
    let group = bounded.ready(now: now.addingTimeInterval(2))!
    assert(group.entryIDs == ["long5", "long6", "long7"] && group.source.count < 2500)
    assert(group.source.contains("Step 7"))
    var continuous = NarrativeBatch()
    for index in 0..<9 { continuous.add(entry("continuous\(index)", .summary, "Checking part \(index)"), now: now.addingTimeInterval(Double(index))) }
    assert(continuous.ready(now: now.addingTimeInterval(8)) != nil)
    assert(liveActivityLabel(entry("run", .activity, "Running command")) == "Running command")
    assert(liveActivityLabel(entry("done", .activity, "Command completed")) == "Ran command")
    assert(liveActivityLabel(entry("format", .summary, "**Checking notification spacing**")) == "Checking notification spacing")
    assert(liveActivityLabel(entry("long", .summary, String(repeating: "word ", count: 50))).count <= 48)
    print("PASS: routine status bypasses AI, distinct narratives batch after delay, duplicates ignored, bounded context and live status")
}

@MainActor func runNotificationUpdateTests() {
    let suite = "SideglanceCardTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let task = WatchedTask(id: "card-fixture", title: "Test notifications", project: "Test")
    let feed = Feed(task: task, defaults: defaults)
    feed.paused = true; feed.intentionTitles = false
    let stamp = ISO8601DateFormatter().string(from: Date())
    func entry(_ id: String, _ kind: EntryKind, _ text: String) -> Entry { Entry(id: id, kind: kind, text: text, time: stamp) }
    func apply(_ updates: [Decoded]) { feed.applyRead(.success((updates, false)), taskID: task.id, generation: feed.readerGeneration) }
    apply([Decoded(userPrompt: "Check notifications"), Decoded(entry: entry("start", .activity, "Running command"))])
    let originalID = feed.visible[0].id
    apply([Decoded(entry: entry("done", .activity, "Command completed"))])
    assert(feed.visible.count == 1 && feed.visible[0].id == originalID)
    assert(liveActivityLabel(feed.visible[0]) == "Ran command" && feed.visible[0].liveStatus?.entryID == feed.entries.last?.id)
    assert(feed.entries.count == 2)
    feed.dismiss(feed.visible[0])
    apply([Decoded(entry: entry("more", .activity, "Running tools"))])
    assert(feed.visible.isEmpty)
    apply([Decoded(entry: entry("narrative", .summary, "Checking card grouping"))])
    let narrativeID = feed.entries.last!.id
    assert(feed.visible.count == 1 && feed.visible[0].id == narrativeID)
    apply([Decoded(entry: entry("tool", .activity, "Running command"))])
    assert(feed.visible.count == 1 && feed.visible[0].id == narrativeID)
    assert(liveActivityLabel(feed.visible[0]) == "Running command")
    feed.showActivity = false
    assert(liveActivityLabel(feed.visible[0]) == "Checking card grouping")
    feed.showActivity = true
    apply([Decoded(entry: entry("error", .error, "A command exited with an error."))])
    assert(feed.visible.count == 2 && feed.visible.last?.id == feed.entries.last?.id)
    apply([Decoded(userPrompt: "Check another task"), Decoded(entry: entry("new-request", .activity, "Running command"))])
    assert(feed.visible.last?.id == feed.entries.last?.id)
    print("PASS: status updates keep card identity, preserve source history and dismissal, and respect narrative/error/request boundaries")
}

func runQualityReviewTests() {
    func presentation(_ status: String, task: String = "t", generated: Bool = false) -> QualityFields {
        ["event": "notification_presented", "task_id": task, "entry_id": "card", "source_key": "s", "prompt_key": "p", "display_status": status, "display_label": generated ? "Checking spacing" : "Original progress", "label_origin": generated ? "generated_group_summary" : "local_excerpt_no_model", "original_text": "Original progress"]
    }
    let rows: [QualityFields] = [
        ["event": "source_prompt", "task_id": "t", "source_key": "p", "original_text": "Check the spacing"],
        ["event": "source_message", "task_id": "t", "entry_id": "s", "original_text": "Original source"],
        presentation("Running command"),
        ["event": "model_request", "task_id": "t", "source_key": "s", "request_id": "r1", "role": "activity_label", "provider": "codex", "requested_model": "gpt-5.6-luna", "exact_prompt": "Label the source", "original_source": "Grouped source"],
        ["event": "model_response", "request_id": "r1", "raw_output": "Checking spacing"],
        ["event": "summary_result", "task_id": "t", "source_key": "s", "request_id": "r1", "role": "activity_label", "outcome": "accepted", "accepted_label": "Checking spacing"],
        presentation("Ran command", generated: true),
        ["event": "summary_result", "task_id": "t", "source_key": "s", "request_id": "r2", "role": "activity_label", "provider": "apple", "outcome": "failed", "failure": "Invalid output"],
        presentation("Running tools"),
        presentation("Other task", task: "other", generated: true)
    ]
    let cards = QualityReviewParser.parse(rows)
    assert(cards.count == 2 && cards[0].latest.needsReview && cards[0].latest.hasModel)
    let versions = cards[1].versions
    assert(versions.count == 3)
    assert(versions[0].activityTrace == nil && versions[0].activitySource == "Original source")
    assert(versions[1].activityTrace?["provider"] == "codex" && versions[1].activityTrace?["raw_output"] == "Checking spacing")
    assert(versions[1].activitySource == "Grouped source" && versions[1].headingSource == "Check the spacing")
    assert(versions[2].activityTrace?["provider"] == "apple" && versions[2].needsReview)
    assert(versions[2].activitySource == "Original source")
    let encoded = try! JSONSerialization.data(withJSONObject: rows[0])
    let result = QualityReviewParser.decode([encoded + Data([10]), try! JSONSerialization.data(withJSONObject: rows.last!) + Data("\n{incomplete".utf8)])
    assert(result.skipped == 1 && result.cards.count == 1)
    assert(QualityReviewParser.parse([]).isEmpty)
    print("PASS: quality viewer preserves historical provenance, groups card updates, separates tasks, and handles missing or incomplete traces")
}
