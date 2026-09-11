import Cocoa
import SwiftUI
if CommandLine.arguments.contains("--preview-notification") {
    MainActor.assumeIsolated {
        let _ = NSApplication.shared
        let card = NotificationCard(activity: "Splitting the Python file", title: "Resolve Code Review Issues", subtitle: "Fixing portability and state-handling issues", isError: false, fontSize: 13, opacity: 0.9, dismiss: {}, open: {})
            .padding(16).frame(width: 366).background(Color(white: 0.035)).preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "build/notification-preview.png"))
        }
    }
} else if CommandLine.arguments.contains("--test-codex-summary") {
    Task {
        let writer = IntentionWriter()
        let result = try? await writer.title(for: "Synthetic test: I will change a fictional button from blue to green.", provider: .codex)
        print(result.map { "Codex summary: " + $0 } ?? "FAILED: Codex summary unavailable")
        exit(result == nil ? 1 : 0)
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--check") {
    do {
        guard let index = CommandLine.arguments.firstIndex(of: "--check"), CommandLine.arguments.count > index + 1 else { print("Usage: Sideglance --check TASK_ID"); exit(1) }
        let id = CommandLine.arguments[index + 1]
        let selected = currentLog(id: id)
        print("Source: \(selected.lastPathComponent)")
        let updates = try LogReader(selected).read().0
        print("Target: \(id)\nReadable entries in recent log: \(updates.compactMap(\.entry).count)")
        print(Dictionary(grouping: updates.compactMap(\.entry), by: \.kind).mapValues(\.count))
        print("Last recorded state: \(updates.compactMap(\.state).last?.rawValue ?? "unknown")")
    } catch { print("Read failed: \(error)"); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
}
