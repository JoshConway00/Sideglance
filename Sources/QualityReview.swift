import Cocoa
import SwiftUI
import Combine

typealias QualityFields = [String: String]

struct QualityVersion: Identifiable {
    let id: String
    let presentation: QualityFields
    let headingTrace: QualityFields?
    let activityTrace: QualityFields?
    let headingSource: String
    let activitySource: String
    var time: String { presentation["timestamp"] ?? "Unknown time" }
    var hasModel: Bool {
        headingTrace != nil || activityTrace != nil ||
        (presentation["heading_origin"] ?? "").hasPrefix("generated") ||
        (presentation["label_origin"] ?? "").hasPrefix("generated")
    }
    var needsReview: Bool {
        [headingTrace, activityTrace].compactMap { $0 }.contains { ["failed", "cancelled", "failed_or_cancelled"].contains($0["outcome"] ?? "") } ||
        ((presentation["label_origin"] ?? "").hasPrefix("generated") && activityTrace == nil) ||
        ((presentation["heading_origin"] ?? "").hasPrefix("generated") && headingTrace == nil)
    }
}
struct QualityCard: Identifiable {
    let id: String
    var versions: [QualityVersion]
    var latest: QualityVersion { versions.last! }
    var title: String { latest.presentation["display_heading"] ?? "Notification" }
    var searchableText: String {
        versions.map { [$0.headingSource, $0.activitySource, $0.presentation.values.joined(separator: " "), $0.headingTrace?.values.joined(separator: " ") ?? "", $0.activityTrace?.values.joined(separator: " ") ?? ""].joined(separator: " ") }.joined(separator: " ")
    }
}
struct QualityReviewResult {
    let cards: [QualityCard]
    let skipped: Int
}

enum QualityReviewParser {
    static func parse(_ rows: [QualityFields]) -> [QualityCard] {
        var requests: [String: QualityFields] = [:]
        var attempts: [String: QualityFields] = [:]
        var sources: [String: String] = [:]
        var cards: [String: QualityCard] = [:]
        var order: [String] = []
        func key(_ task: String, _ source: String, _ role: String = "") -> String { task + "\u{1f}" + source + "\u{1f}" + role }
        for row in rows {
            let task = row["task_id"] ?? ""
            switch row["event"] {
            case "source_prompt":
                sources[key(task, row["source_key"] ?? "", "task_heading")] = row["original_text"]
            case "source_message":
                sources[key(task, row["entry_id"] ?? "", "activity_label")] = row["original_text"]
            case "model_request", "model_response", "summary_result":
                guard let id = row["request_id"] else { continue }
                let trace = (requests[id] ?? [:]).merging(row, uniquingKeysWith: { _, new in new })
                requests[id] = trace
                if row["event"] == "summary_result", let source = row["source_key"], !source.isEmpty {
                    attempts[key(task, source, row["role"] ?? "")] = trace
                }
            case "notification_presented":
                guard let entry = row["entry_id"] else { continue }
                let id = key(task, entry)
                let heading = attempts[key(task, row["prompt_key"] ?? "", "task_heading")]
                let activity = attempts[key(task, row["source_key"] ?? "", "activity_label")]
                let headingSource = sources[key(task, row["prompt_key"] ?? "", "task_heading")] ?? heading?["original_source"] ?? "Original request is not retained in these logs."
                let localSource = sources[key(task, row["source_key"] ?? "", "activity_label")] ?? row["original_text"] ?? "Source text is not retained."
                let activitySource = (row["label_origin"] ?? "").hasPrefix("generated") ? (activity?["original_source"] ?? localSource) : localSource
                let encoded = (try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])) ?? Data()
                let version = QualityVersion(id: errorFingerprint(String(decoding: encoded, as: UTF8.self)), presentation: row, headingTrace: heading, activityTrace: activity, headingSource: headingSource, activitySource: activitySource)
                if cards[id] == nil { cards[id] = QualityCard(id: id, versions: []) }
                if cards[id]?.versions.last?.id != version.id { cards[id]?.versions.append(version) }
                order.removeAll { $0 == id }; order.append(id)
            default: break
            }
        }
        return order.reversed().compactMap { cards[$0] }
    }
    static func decode(_ contents: [Data]) -> QualityReviewResult {
        var rows: [QualityFields] = []
        var skipped = 0
        for data in contents {
            for line in data.split(separator: 10) {
                if let row = try? JSONSerialization.jsonObject(with: Data(line)) as? QualityFields { rows.append(row) }
                else { skipped += 1 }
            }
        }
        return QualityReviewResult(cards: parse(rows), skipped: skipped)
    }

}

@MainActor final class QualityReviewModel: ObservableObject {
    @Published var cards: [QualityCard] = []
    @Published var loading = false
    @Published var error: String?
    @Published var skipped = 0
    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            do {
                let result = try await Task.detached(priority: .utility) { QualityReviewParser.decode(try QualityLog.shared.snapshotData()) }.value
                cards = result.cards; skipped = result.skipped; error = nil
            } catch { self.error = "Could not read the quality logs. Try refreshing or open the log folder." }
            loading = false
        }
    }
}

private enum QualityPart: String, CaseIterable { case activity = "Activity summary", heading = "Task heading", status = "Live status" }
private enum QualityFilter: String, CaseIterable { case all = "All notifications", models = "Model attempts", local = "Local only", issues = "Missing or failed output" }

struct QualityReviewView: View {
    @StateObject private var model = QualityReviewModel()
    @State private var search = ""
    @State private var selection: String?
    @State private var versionID: String?
    @State private var part: QualityPart = .activity
    @State private var filter: QualityFilter = .all
    @State private var live = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private var filtered: [QualityCard] {
        model.cards.filter { card in
            let matches = search.isEmpty || card.searchableText.localizedCaseInsensitiveContains(search)
            switch filter {
            case .all: return matches
            case .models: return matches && card.versions.contains { $0.hasModel }
            case .local: return matches && !card.versions.contains { $0.hasModel }
            case .issues: return matches && card.versions.contains { $0.needsReview }
            }
        }
    }
    private var selected: QualityCard? { filtered.first { $0.id == selection } }
    private func move(_ offset: Int) {
        guard !filtered.isEmpty else { return }
        let index = filtered.firstIndex { $0.id == selection } ?? 0
        selection = filtered[min(max(index + offset, 0), filtered.count - 1)].id
        versionID = nil
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Output quality").font(.title2.bold())
                Spacer()
                Toggle("Live refresh", isOn: $live).toggleStyle(.checkbox)
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.keyboardShortcut("r", modifiers: .command).disabled(model.loading)
                Button("Log folder") { NSWorkspace.shared.open(QualityLog.shared.directory) }
            }.padding()
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search original or displayed text", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Filter", selection: $filter) { ForEach(QualityFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                    Text("\(filtered.count) notifications · newest first").font(.caption).foregroundStyle(.secondary)
                    List(selection: $selection) {
                        ForEach(filtered) { card in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(card.title).font(.headline).lineLimit(2)
                                Text(card.latest.presentation["display_label"].flatMap { $0.isEmpty ? nil : $0 } ?? card.latest.presentation["display_status"] ?? "").lineLimit(2).foregroundStyle(.secondary)
                                HStack {
                                    Text(shortTime(card.latest.time))
                                    Spacer()
                                    Text("\(card.versions.count) updates")
                                    if card.versions.contains(where: \.needsReview) { Image(systemName: "exclamationmark.circle").help("A failed attempt or missing trace was recorded") }
                                }.font(.caption2).foregroundStyle(.secondary)
                            }.padding(.vertical, 5).tag(card.id)
                        }
                    }.listStyle(.sidebar)
                }.padding(12).frame(minWidth: 240, idealWidth: 290, maxWidth: 360)
                VStack(spacing: 0) {
                    if let card = selected {
                        let version = card.versions.first { $0.id == versionID } ?? card.latest
                        HStack {
                            Button { move(-1) } label: { Label("Newer", systemImage: "chevron.up") }.keyboardShortcut(.upArrow, modifiers: .command)
                            Button { move(1) } label: { Label("Older", systemImage: "chevron.down") }.keyboardShortcut(.downArrow, modifiers: .command)
                            Spacer()
                            Picker("Update", selection: Binding(get: { version.id }, set: { versionID = $0 })) {
                                ForEach(Array(card.versions.enumerated()), id: \.element.id) { index, item in
                                    Text("\(index + 1) of \(card.versions.count) · \(shortTime(item.time))").tag(item.id)
                                }
                            }.frame(maxWidth: 250)
                        }.padding()
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                Text(card.title).font(.title2.bold()).textSelection(.enabled)
                                Text(version.time).font(.caption).foregroundStyle(.secondary)
                                Picker("Text section", selection: $part) { ForEach(QualityPart.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                                comparison(version)
                                Divider()
                                Text("Notification text").font(.headline)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(version.presentation["display_status"] ?? "").font(.caption).foregroundStyle(.secondary)
                                    Text(version.presentation["display_heading"] ?? "").font(.headline)
                                    Text(version.presentation["display_label"] ?? "").foregroundStyle(.secondary)
                                }.textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                Text("Recorded text before on-screen clipping. This is not a screenshot.").font(.caption).foregroundStyle(.secondary)
                            }.padding(20)
                        }
                    } else {
                        ContentUnavailableView(model.cards.isEmpty ? "No recorded notifications" : "Select a notification", systemImage: "text.magnifyingglass", description: Text(model.cards.isEmpty ? "Enable Output quality logging in Settings, let notifications appear, then refresh. Older model responses cannot be recovered if logging was off." : "Choose an item on the left, or change your search and filter."))
                    }
                }.frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                if model.loading { ProgressView().controlSize(.small); Text("Reading logs…") }
                else { Text(QualityLog.shared.enabled ? "Recording locally" : "Logging is off") }
                Spacer()
                if let error = model.error { Text(error).foregroundStyle(.orange) }
                else if model.skipped > 0 { Text("\(model.skipped) incomplete or unreadable records skipped").foregroundStyle(.orange) }
                else { Text("Private local text · rotated logs may have gaps") }
            }.font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .onAppear { model.refresh() }
        .onReceive(timer) { _ in if live { model.refresh() } }
        .onChange(of: selection) { versionID = nil }
        .onChange(of: filtered.map(\.id)) {
            if selection == nil || !filtered.contains(where: { $0.id == selection }) { selection = filtered.first?.id }
        }
        .frame(minWidth: 850, minHeight: 570)
    }
    @ViewBuilder private func comparison(_ version: QualityVersion) -> some View {
        let trace = part == .heading ? version.headingTrace : (part == .activity ? version.activityTrace : nil)
        let original = part == .heading ? version.headingSource : (part == .activity ? version.activitySource : version.presentation["live_activity_source_text"] ?? version.presentation["original_text"] ?? "Not retained")
        let shown = version.presentation[part == .heading ? "display_heading" : (part == .activity ? "display_label" : "display_status")] ?? ""
        HStack(alignment: .top, spacing: 16) {
            textBox("Original text", original)
            textBox("What was shown", shown.isEmpty ? "No secondary text was shown for this update." : shown)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("How it changed").font(.headline)
            let origin = version.presentation[part == .heading ? "heading_origin" : "label_origin"] ?? ""
            if part != .status {
                Text(origin.hasPrefix("generated") ? "Displayed a generated label." : (part == .heading ? "Displayed the existing task title, not a model response." : "Displayed local text or an excerpt, not a model response."))
            }
            if let trace {
                Text(providerName(trace)).font(.subheadline.bold())
                if let milliseconds = trace["elapsed_ms"].flatMap(Double.init) { Text(String(format: "%.2f seconds · %@", milliseconds / 1000, trace["outcome"] ?? "unknown result")).foregroundStyle(.secondary) }
                if let ids = trace["group_entry_ids"], !ids.isEmpty { Text("Combined \(ids.split(separator: ",").count) related progress updates.") }
                if let failure = trace["failure"] { Text(failure).foregroundStyle(.orange) }
                if let label = trace["accepted_label"] { textBox("Accepted label before display cleanup", label) }
                Text(trace["validation"] ?? "No validation details retained for this attempt.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Model input, instructions and raw response") {
                    VStack(alignment: .leading, spacing: 12) {
                        textBox("Input sent to model", trace["bounded_source"] ?? "Not retained")
                        if let instructions = trace["instructions"] { textBox("Instructions", instructions) }
                        textBox("Full request", trace["exact_prompt"] ?? "Not retained (for example, a cached result)")
                        textBox("Raw response", trace["raw_output"] ?? "Not retained (for example, a cached result)")
                        Text("Prompt version: " + (trace["prompt_version"] ?? "Unknown")).font(.caption)
                    }.padding(.top, 10)
                }
            } else {
                let origin = version.presentation[part == .heading ? "heading_origin" : "label_origin"] ?? ""
                if part == .status { Text("Local status formatting · no model. Uses the source activity, removes Markdown and limits the small status line to 48 characters.") }
                else if origin.hasPrefix("generated") { Text("This label was generated, but its model trace is no longer in the retained logs.").foregroundStyle(.orange) }
                else if part == .heading { Text("Used the existing task title; no generated heading was available.") }
                else { Text("Used a local excerpt or original text. No activity-summary model response was available for this update.") }
            }
            Text(version.presentation["display_transform"] ?? "Display transformation details were not recorded.").font(.caption).foregroundStyle(.secondary)
        }.textSelection(.enabled)
    }
    private func textBox(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).frame(maxWidth: .infinity, alignment: .topLeading).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
    private func shortTime(_ value: String) -> String {
        eventDate(value).map { $0.formatted(date: .abbreviated, time: .standard) } ?? value
    }
    private func providerName(_ trace: QualityFields) -> String {
        if trace["provider"] == "apple" { return "Apple Intelligence · on device" }
        let model = trace["requested_model"] ?? "Unknown model"
        let name = model == "gpt-5.6-luna" ? "Codex Luna" : (model == "gpt-5.3-codex-spark" ? "Codex Spark" : model)
        return name + " · " + (trace["reasoning"] ?? "unknown reasoning").capitalized
    }
}
