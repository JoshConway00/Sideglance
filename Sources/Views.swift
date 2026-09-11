import SwiftUI
struct NotificationControlsBounds: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

func notificationPlainText(_ text: String) -> String {
    let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    return (parsed.map { String($0.characters) } ?? text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

struct NotificationCard: View {
    let activity: String
    let title: String
    let subtitle: String
    let isError: Bool
    let fontSize: Double
    let opacity: Double
    var dismiss: () -> Void
    var open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(isError ? Color.orange : Color(red: 0, green: 0.83, blue: 0.68))
                        .frame(width: 6, height: 6)
                    Text("Codex · " + notificationPlainText(activity))
                        .font(.system(size: fontSize - 3, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(notificationPlainText(title)).font(.system(size: fontSize + 1, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96)).lineLimit(2)
                    if !subtitle.isEmpty {
                        Text(notificationPlainText(subtitle)).font(.system(size: fontSize - 1, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66)).lineLimit(2)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).frame(width: 22, height: 22) }
                    .help("Dismiss notification").accessibilityLabel("Dismiss notification")
                Button(action: open) { Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).frame(width: 22, height: 22) }
                    .help("Open Codex task").accessibilityLabel("Open Codex task")
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
            .background(GeometryReader { geometry in
                Color.clear.preference(key: NotificationControlsBounds.self, value: [geometry.frame(in: .named("overlay"))])
            })
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.065).opacity(opacity)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}

struct Overlay: View {
    @ObservedObject var feed: Feed
    var openTask: () -> Void = {}
    var controlsChanged: ([CGRect]) -> Void = { _ in }
    private func recordPresentation(_ entry: Entry) {
        let heading = feed.promptTitle(for: entry).flatMap { $0 == "Current request" ? nil : $0 } ?? feed.task.title
        let label = feed.notificationLabel(for: entry)
        QualityLog.shared.record("notification_presented", [
            "task_id": feed.task.id, "entry_id": entry.id, "source_key": entry.intentionKey ?? "", "prompt_key": entry.promptKey ?? "",
            "live_activity_entry_id": entry.liveStatus?.entryID ?? entry.id, "live_activity_source_text": entry.liveStatus?.text ?? entry.text,
            "original_text": entry.text, "heading_before_display_cleanup": heading, "label_before_display_cleanup": label,
            "display_status": "Codex · " + liveActivityLabel(entry),
            "display_heading": notificationPlainText(heading), "display_label": notificationPlainText(label),
            "heading_origin": feed.promptTitle(for: entry).map { $0 == "Current request" ? "task_title_fallback" : "generated_summary" } ?? "task_title_fallback",
            "label_origin": feed.labelOrigin(for: entry),
            "display_transform": "Markdown to plain text; collapse whitespace; status 1 line; heading and label 2 lines with tail truncation",
            "font_size": String(feed.fontSize), "presentation_scope": "Text supplied to mounted card; clipping depends on window width. Not a pixel capture."
        ])
    }
    var body: some View {
        let visible = feed.visible
        VStack(alignment: .trailing, spacing: 10) {
            if feed.editing {
                Text("Drag to position · Finish from menu bar")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
            ForEach(Array(visible.reversed())) { entry in
                NotificationCard(activity: liveActivityLabel(entry),
                    title: feed.promptTitle(for: entry).flatMap { $0 == "Current request" ? nil : $0 } ?? feed.task.title,
                    subtitle: feed.notificationLabel(for: entry),
                    isError: entry.kind == .error, fontSize: feed.fontSize, opacity: feed.opacity,
                    dismiss: { feed.dismiss(entry) }, open: openTask)
                    .onAppear { recordPresentation(entry) }
                    .onChange(of: [feed.promptTitle(for: entry) ?? "", feed.title(for: entry) ?? "", entry.text, entry.liveStatus?.entryID ?? "", liveActivityLabel(entry), feed.task.title, String(feed.fontSize)]) { recordPresentation(entry) }
                    .opacity(entry.id == visible.last?.id ? 1 : 0.65)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if feed.task.id.isEmpty || feed.showCompletionBadge || feed.status == .stopped || feed.inputRequested || feed.editing || feed.connection == .disconnected {
                HStack(spacing: 5) {
                    Image(systemName: feed.connection == .disconnected ? "wifi.slash" : (feed.status == .finished ? "checkmark.circle.fill" : (feed.inputRequested ? "questionmark.circle.fill" : "waveform.path")))
                        .foregroundStyle(feed.connection == .disconnected || feed.inputRequested ? .orange : .mint.opacity(0.7))
                    Text(feed.connection == .disconnected ? "Disconnected" : feed.displayStatus)
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.22))).help(feed.task.title)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .coordinateSpace(name: "overlay")
        .onPreferenceChange(NotificationControlsBounds.self, perform: controlsChanged)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(feed.editing ? 0.18 : 0)))
        .animation(.easeOut(duration: 0.4), value: visible.map(\.id))
        .animation(.easeOut(duration: 0.5), value: feed.showCompletionBadge)
        .preferredColorScheme(.dark)
    }
}
struct HistoryView: View {
    @ObservedObject var feed: Feed
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(feed.task.title).font(.headline)
            Text("\(feed.displayStatus) · \(feed.freshness)").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(feed.entries.filter { feed.showActivity || $0.kind != .activity }.reversed())) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            if let title = feed.promptTitle(for: entry) { Text(notificationPlainText(title)).font(.headline) }
                            HStack {
                                Text(feed.subtitle(for: entry)).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if let date = entry.date { Text(date, style: .time).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text((try? AttributedString(markdown: entry.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(entry.text)).textSelection(.enabled)
                        }
                        Divider()
                    }
                }
            }
        }.padding(18).frame(minWidth: 340, minHeight: 300)
    }
}
