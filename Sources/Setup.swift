import Cocoa
import SwiftUI

@MainActor final class SetupOptions: ObservableObject {
    @Published var width: Double
    @Published var fontSize: Double
    @Published var opacity: Double
    @Published var lifetime: Double
    @Published var provider: SummaryProvider
    @Published var aiEnabled: Bool
    @Published var model: String
    @Published var tasks: [WatchedTask] = []
    @Published var startingTaskID = ""
    var startingTask: WatchedTask { tasks.first { $0.id == startingTaskID } ?? .unselected }
    func refreshTasks() {
        tasks = taskCatalog()
        if !tasks.contains(where: { $0.id == startingTaskID }) { startingTaskID = "" }
    }
    @Published var playing = true
    @Published var screenIndex = 0
    @Published var corner = "Bottom right"
    init(feed: Feed, width: Double) {
        self.width = min(520, max(280, width))
        fontSize = feed.fontSize; opacity = feed.opacity; lifetime = feed.lifetime
        provider = feed.summaryProvider; aiEnabled = feed.intentionTitles
        model = UserDefaults.standard.string(forKey: "codexSummaryModel") ?? ""
        tasks = taskCatalog()
        startingTaskID = tasks.contains(where: { $0.id == feed.task.id }) ? feed.task.id : ""
    }
}

struct SetupView: View {
    @ObservedObject var options: SetupOptions
    let screens: [String]
    var changed: () -> Void
    var position: () -> Void
    var replay: () -> Void
    var finish: () -> Void
    var cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Make Sideglance yours").font(.system(size: 25, weight: .semibold))
                Text("The floating notification is a live sample. Drag it anywhere, or use the controls below.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            GroupBox("Starting chat") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("Chat", selection: $options.startingTaskID) {
                            Text("Choose later").tag("")
                            ForEach(options.tasks) { task in
                                Text(task.project.isEmpty ? task.title : "\(task.title) — \(task.project)").tag(task.id)
                            }
                        }
                        Button("Refresh") { options.refreshTasks() }
                    }
                    Text(options.tasks.isEmpty ? "No local Codex chats found. Open a chat in Codex, then refresh." : "Monitoring starts after Save & finish. The preview stays simulated.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            GroupBox("Position & appearance") {
                VStack(spacing: 12) {
                    HStack {
                        Picker("Display", selection: $options.screenIndex) {
                            ForEach(screens.indices, id: \.self) { Text(screens[$0]).tag($0) }
                        }
                        Picker("Position", selection: $options.corner) {
                            ForEach(["Top right", "Bottom right", "Top left", "Bottom left", "Custom"], id: \.self) { Text($0) }
                        }
                    }
                    setting("Width", value: $options.width, range: 280...520, step: 10, label: "\(Int(options.width)) pt")
                    setting("Text size", value: $options.fontSize, range: 10...20, step: 1, label: "\(Int(options.fontSize)) pt")
                    setting("Background", value: $options.opacity, range: 0.1...1, step: 0.05, label: "\(Int((options.opacity * 100).rounded()))%")
                    Text("One notification stays visible until dismissed and updates as the task progresses.").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("AI summaries") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Summarise the request and current intention", isOn: $options.aiEnabled)
                    Picker("Provider", selection: $options.provider) {
                        ForEach(SummaryProvider.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.disabled(!options.aiEnabled)
                    if options.provider == .codex && options.aiEnabled {
                        TextField("Automatic (Codex default)", text: $options.model)
                        Text("Uses your existing Codex ChatGPT sign-in and allowance. Task text is sent to OpenAI. Leave the model blank to use your Codex default.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else if options.aiEnabled {
                        Text(intelligenceAvailability()).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(8)
            }
            HStack {
                Image(systemName: "play.rectangle").foregroundStyle(.mint)
                Text("Simulated feed · no AI requests or usage").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(options.playing ? "Pause" : "Play") { options.playing.toggle() }
                Button("Replay", action: replay)
            }
            Divider()
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Text("You can reopen setup from the menu.").font(.caption).foregroundStyle(.secondary)
                Button("Save & finish", action: finish).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 580)
        .onChange(of: options.width) { changed() }
        .onChange(of: options.fontSize) { changed() }
        .onChange(of: options.opacity) { changed() }
        .onChange(of: options.lifetime) { changed() }
        .onChange(of: options.aiEnabled) { changed() }
        .onChange(of: options.screenIndex) { position() }
        .onChange(of: options.corner) { position() }
    }
    private func setting(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, label: String) -> some View {
        HStack {
            Text(name).frame(width: 115, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(label).monospacedDigit().foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
        }
    }
}

@MainActor final class SetupController: NSObject, NSWindowDelegate {
    let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let options: SetupOptions
    let preview = Feed(task: WatchedTask(id: "setup-preview", title: "Build a sample dashboard", project: "Demo"))
    let panel: FloatingPanel
    let originalFrame: NSRect
    let originalVisible: Bool
    var timer: Timer?
    var sequence = 0
    var ticks = 0
    var didClose = false
    private var placingPreview = false
    let complete: (Bool, SetupOptions) -> Void
    let screens: [NSScreen]
    init(feed: Feed, panel: FloatingPanel, controlsChanged: @escaping ([CGRect]) -> Void, complete: @escaping (Bool, SetupOptions) -> Void) {
        self.panel = panel; self.complete = complete
        originalFrame = panel.frame; originalVisible = panel.isVisible
        screens = NSScreen.screens
        options = SetupOptions(feed: feed, width: panel.frame.width)
        super.init()
        options.screenIndex = screens.firstIndex { $0 == panel.screen } ?? 0
        options.corner = matchingCorner()
        preview.paused = true; preview.intentionTitles = true; preview.keepLatest = false
        panel.contentView = NSHostingView(rootView: Overlay(feed: preview, openTask: { [weak self] in self?.window.makeKeyAndOrderFront(nil) }, controlsChanged: controlsChanged))
        window.title = "Set up Sideglance"; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView: SetupView(options: options, screens: screens.map(\.localizedName), changed: { [weak self] in self?.update() }, position: { [weak self] in self?.position() }, replay: { [weak self] in self?.replay() }, finish: { [weak self] in self?.close(save: true) }, cancel: { [weak self] in self?.close(save: false) }))
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        update(); replay(); panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.options.playing else { return }
                self.preview.now = Date(); self.ticks += 1
                if self.ticks % 5 == 0 { self.nextMessage() }
            }
        }
    }
    private func cornerOrigin(_ corner: String, bounds: NSRect) -> NSPoint {
        NSPoint(x: corner.contains("right") ? bounds.maxX - panel.frame.width - 16 : bounds.minX + 16,
                y: corner.contains("Top") ? bounds.maxY - panel.frame.height - 16 : bounds.minY + 16)
    }
    private func matchingCorner() -> String {
        guard let screen = panel.screen else { return "Custom" }
        return ["Top right", "Bottom right", "Top left", "Bottom left"].first {
            let expected = cornerOrigin($0, bounds: screen.visibleFrame)
            return abs(panel.frame.minX - expected.x) < 3 && abs(panel.frame.minY - expected.y) < 3
        } ?? "Custom"
    }
    func previewDidMove() {
        guard !placingPreview, NSEvent.pressedMouseButtons != 0 else { return }
        if matchingCorner() != options.corner { options.corner = "Custom" }
        if let screen = panel.screen, let index = screens.firstIndex(of: screen), index != options.screenIndex {
            options.corner = "Custom"
            options.screenIndex = index
        }
    }
    func update() {
        placingPreview = true
        defer { placingPreview = false }
        preview.fontSize = options.fontSize; preview.opacity = options.opacity
        preview.lifetime = options.lifetime; preview.intentionTitles = options.aiEnabled
        let frame = panel.frame
        let desired = NSRect(x: frame.maxX - options.width, y: frame.minY, width: options.width, height: 260)
        panel.setFrame(panel.screen.map { fittedFrame(desired, within: $0.visibleFrame) } ?? desired, display: true)
        if options.corner != "Custom" { position() }
    }
    func position() {
        guard options.corner != "Custom", screens.indices.contains(options.screenIndex) else { return }
        let wasPlacing = placingPreview
        placingPreview = true
        defer { placingPreview = wasPlacing }
        panel.setFrameOrigin(cornerOrigin(options.corner, bounds: screens[options.screenIndex].visibleFrame))
    }
    func replay() {
        preview.resetTitles(); preview.entries = []; sequence = 0; ticks = 0; preview.now = Date()
        nextMessage()
    }
    func nextMessage() {
        let examples = [
            ("Planning the layout", "Planning a clear dashboard layout", false),
            ("Building the activity cards", "Adding compact progress notifications", false),
            ("Checking the connection", "Retrying a sample connection", true),
            ("Reviewing the finishing touches", "Checking spacing and readability", false)
        ]
        let example = examples[sequence % examples.count], key = "sample-\(sequence)"
        let entry = Entry(id: key, kind: example.2 ? .error : .summary, text: example.0, time: ISO8601DateFormatter().string(from: Date()), intentionKey: key, promptKey: "sample-request")
        preview.entries.append(entry); preview.appendNotification(entry); preview.titles[key] = example.1
        preview.promptTitles["sample-request"] = "Build a sample dashboard"
        preview.status = .working; preview.connection = .connected
        preview.trimHistory(); sequence += 1
    }
    func close(save: Bool) {
        guard !didClose else { return }
        if save && !options.startingTaskID.isEmpty && !taskCatalog().contains(where: { $0.id == options.startingTaskID }) {
            options.refreshTasks()
            let alert = NSAlert(); alert.messageText = "That chat is no longer available"
            alert.informativeText = "Choose another chat or choose later, then save again."
            alert.runModal()
            return
        }
        didClose = true
        timer?.invalidate(); timer = nil
        if !save { panel.setFrame(originalFrame, display: true) }
        complete(save, options)
        window.orderOut(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { close(save: false); return true }
}
