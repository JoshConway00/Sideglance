import Cocoa
import SwiftUI
import ServiceManagement
func featureTaskURL(details: String, projectPath: String) -> URL? {
    var components = URLComponents()
    components.scheme = "codex"; components.host = "threads"; components.path = "/new"
    let prompt = """
    Implement this feature request for Sideglance in the local project at \(projectPath).
    Read repository guidance and inspect the working tree first. Preserve unrelated changes. Create a new feature branch, implement the request, run relevant checks, self-review the diff and fix issues, then commit only the feature changes so they are ready for a later PR. If the project is not a Git repository yet, initialize it locally with an appropriate .gitignore that excludes local chats, settings, secrets and build output. Do not create a PR, push, or merge. Report the branch, commit, changes, checks and any blockers.

    Feature request:
    \(details)
    """
    components.queryItems = [URLQueryItem(name: "prompt", value: prompt), URLQueryItem(name: "path", value: projectPath)]
    return components.url
}
func validFeatureProject(_ path: String) -> Bool {
    var directory: ObjCBool = false
    return path.hasPrefix("/") && FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
}
func validFeatureEmail(_ text: String) -> Bool {
    text.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
}

final class FloatingPanel: NSPanel { override var canBecomeKey: Bool { true } }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    var panel: FloatingPanel!
    var item: NSStatusItem!
    let feed = Feed()
    let taskMenu = NSMenu()
    var heading = NSMenuItem()
    var activityItem = NSMenuItem()
    var stateItem = NSMenuItem()
    var historyPanel: NSPanel?
    var qualityReviewWindow: NSWindow?
    var statusTimer: Timer?
    var positioningItem = NSMenuItem()
    var visibilityItem = NSMenuItem()
    var pauseItem = NSMenuItem()
    var loginItem = NSMenuItem()
    var intelligenceItem = NSMenuItem()
    var restoringFrame = false
    var notificationControls: [CGRect] = []
    var hoverTimer: Timer?
    var setupController: SetupController?
    var setupWasPaused = false
    var setupWasEditing = false
    func updatePointerInteraction() {
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        panel.ignoresMouseEvents = setupController == nil && !feed.editing && !notificationControls.contains { $0.insetBy(dx: -4, dy: -4).contains(point) }
    }
    var screenObserver: NSObjectProtocol?
    func screenKey(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let number, let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return screen.localizedName }
        return CFUUIDCreateString(nil, uuid) as String
    }
    func savePosition() {
        guard setupController == nil, !restoringFrame, let screen = panel.screen else { return }
        let key = screenKey(screen), bounds = screen.visibleFrame, frame = panel.frame
        let relative = NSRect(x: (frame.minX - bounds.minX) / bounds.width, y: (frame.minY - bounds.minY) / bounds.height, width: frame.width, height: frame.height)
        var positions = UserDefaults.standard.dictionary(forKey: "monitorPositions") as? [String: String] ?? [:]
        positions[key] = NSStringFromRect(relative)
        UserDefaults.standard.set(positions, forKey: "monitorPositions")
        UserDefaults.standard.set(key, forKey: "preferredMonitor")
    }
    func restorePosition() {
        let preferred = UserDefaults.standard.string(forKey: "preferredMonitor")
        guard let screen = NSScreen.screens.first(where: { screenKey($0) == preferred }) ?? NSScreen.main else { return }
        let positions = UserDefaults.standard.dictionary(forKey: "monitorPositions") as? [String: String] ?? [:]
        let bounds = screen.visibleFrame
        let proposed: NSRect
        if let saved = positions[screenKey(screen)] {
            let relative = NSRectFromString(saved)
            proposed = NSRect(x: bounds.minX + relative.minX * bounds.width, y: bounds.minY + relative.minY * bounds.height, width: relative.width, height: relative.height)
        } else {
            proposed = NSRect(x: bounds.maxX - panel.frame.width - 20, y: bounds.minY + 35, width: panel.frame.width, height: panel.frame.height)
        }
        restoringFrame = true
        panel.setFrame(fittedFrame(proposed, within: bounds), display: true)
        restoringFrame = false
    }
    func windowDidMove(_ notification: Notification) {
        setupController?.previewDidMove()
        if feed.editing && NSEvent.pressedMouseButtons != 0 { savePosition() }
    }
    func windowDidResize(_ notification: Notification) { if feed.editing && NSEvent.pressedMouseButtons != 0 { savePosition() } }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let localSource = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourcePath = FileManager.default.fileExists(atPath: localSource.appendingPathComponent("Sources/main.swift").path) ? localSource.path : ""
        UserDefaults.standard.register(defaults: ["featureEmail": "", "featureProjectPath": sourcePath])
        panel = FloatingPanel(contentRect: NSRect(x: 100, y: 100, width: 350, height: 260), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Sideglance"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 280, height: 150)
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: Overlay(feed: feed, openTask: { [weak self] in self?.openTask() }, controlsChanged: { [weak self] bounds in self?.notificationControls = bounds }))
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointerInteraction() }
        }
        if UserDefaults.standard.dictionary(forKey: "monitorPositions") == nil {
            // One-time migration from the older single-window setting.
            if !panel.setFrameUsingName("SideglanceQuietOverlay"), let screen = NSScreen.main {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 360, y: screen.visibleFrame.minY + 35))
            }
            savePosition()
        }
        restorePosition()
        if !UserDefaults.standard.bool(forKey: "notificationCardCompactV2") {
            let frame = panel.frame
            panel.setFrame(NSRect(x: frame.maxX - 350, y: frame.maxY - 260, width: 350, height: 260), display: true)
            savePosition()
            UserDefaults.standard.set(true, forKey: "notificationCardCompactV2")
        }
        panel.delegate = self
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.restorePosition() }
        }
        panel.orderFrontRegardless()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Sideglance")
        let menu = NSMenu()
        menu.delegate = self
        func action(_ title: String, _ selector: Selector, in parent: NSMenu, checked: Bool = false) -> NSMenuItem {
            let option = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            option.target = self; option.state = checked ? .on : .off; parent.addItem(option)
            return option
        }
        func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
            let child = NSMenu()
            let option = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            option.submenu = child; parent.addItem(option)
            return child
        }
        heading = action(feed.task.title, #selector(openTask), in: menu)
        heading.toolTip = "Open this task in Codex"
        stateItem.isEnabled = false; menu.addItem(stateItem)
        menu.addItem(.separator())
        let picker = NSMenuItem(title: "Switch task", action: nil, keyEquivalent: "")
        picker.submenu = taskMenu; menu.addItem(picker)
        _ = action("Recent updates…", #selector(showHistory), in: menu)
        let overlayMenu = submenu("Overlay", in: menu)
        visibilityItem = action("Hide overlay", #selector(toggleVisibility), in: overlayMenu)
        positioningItem = action("Move / resize…", #selector(togglePositioning), in: overlayMenu)
        pauseItem = action("Pause updates", #selector(togglePause(_:)), in: overlayMenu, checked: feed.paused)

        _ = action("Set up Sideglance…", #selector(showSetup), in: menu)
        _ = action("Review output quality…", #selector(showQualityReview), in: menu)
        let settings = submenu("Settings", in: menu)
        let quality = submenu("Output quality logging", in: settings)
        _ = action("Record original text and labels locally", #selector(toggleQualityLogging(_:)), in: quality, checked: QualityLog.shared.enabled)
        _ = action("Review original and displayed text…", #selector(showQualityReview), in: quality)
        _ = action("Open quality logs…", #selector(openQualityLogs), in: quality)
        _ = action("Stop and clear quality logs", #selector(clearQualityLogs), in: quality)
        let appearance = submenu("Appearance", in: settings)
        let background = submenu("Background opacity", in: appearance)
        for percent in [0, 15, 25, 50, 80] {
            let option = action("\(percent)%", #selector(setOpacity(_:)), in: background, checked: Int((feed.opacity * 100).rounded()) == percent)
            option.tag = percent
        }
        _ = action("Larger text", #selector(larger), in: appearance)
        _ = action("Smaller text", #selector(smaller), in: appearance)

        let updates = submenu("Messages", in: settings)
        _ = action("Group repeated errors", #selector(toggleGrouping(_:)), in: updates, checked: feed.groupErrors)
        _ = action("Show tool activity", #selector(toggleTools(_:)), in: updates, checked: feed.showActivity)

        let intelligence = submenu("Summary provider", in: settings)
        for provider in SummaryProvider.allCases {
            let option = action(provider.label, #selector(selectSummaryProvider(_:)), in: intelligence, checked: feed.summaryProvider == provider)
            option.representedObject = provider.rawValue
        }
        let privacyNote = NSMenuItem(title: "Codex sends label text to OpenAI", action: nil, keyEquivalent: "")
        privacyNote.isEnabled = false
        intelligence.addItem(privacyNote)
        intelligence.addItem(.separator())
        _ = action("Intention titles", #selector(toggleIntentionTitles(_:)), in: intelligence, checked: feed.intentionTitles)
        _ = action("Retry summaries · uses selected provider", #selector(retrySummaries), in: intelligence)
        intelligenceItem.isEnabled = false; intelligence.addItem(intelligenceItem)
        settings.addItem(.separator())
        _ = action("Sound when input is requested", #selector(toggleSound(_:)), in: settings, checked: feed.inputSound)
        loginItem = action("Launch at login", #selector(toggleLogin), in: settings)
        _ = action("Feature request settings…", #selector(featureSettings), in: settings)
        menu.addItem(.separator())
        _ = action("Feature request", #selector(featureRequest), in: menu)
        _ = action("Quit Sideglance", #selector(quit), in: menu)
        item.button?.toolTip = feed.task.title
        item.menu = menu
        feed.start()
        if !UserDefaults.standard.bool(forKey: "setupCompleted") || CommandLine.arguments.contains("--setup") { showSetup() }
        if CommandLine.arguments.contains("--review-quality") { showQualityReview() }
        refreshMenu()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }
    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }
    func refreshStatus() {
        intelligenceItem.title = feed.intentionTitles ? feed.titleStatus : "Intention titles off"
        heading.title = feed.task.title
        stateItem.title = feed.paused ? "Updates paused" : "\(feed.displayStatus) · \(feed.freshness)"
        stateItem.toolTip = "\(feed.task.project) · \(feed.connection.rawValue)"
        visibilityItem.title = panel.isVisible ? "Hide overlay" : "Show overlay"
        positioningItem.title = feed.editing ? "Finish positioning" : "Move / resize…"
        pauseItem.title = feed.paused ? "Resume updates" : "Pause updates"
        pauseItem.state = .off
        activityItem.title = "\(feed.freshness) · \(feed.connection == .disconnected ? "Disconnected" : "Reading local log")"
        item.button?.toolTip = "\(feed.task.title) · \(feed.displayStatus) · \(feed.freshness)"
        let symbol = feed.connection == .disconnected ? "wifi.slash" : (feed.inputRequested ? "questionmark.circle" : (feed.status == .finished ? "checkmark.circle" : (feed.status == .stopped ? "stop.circle" : "waveform.path")))
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sideglance · \(feed.displayStatus)")
    }
    func refreshMenu() {
        refreshStatus()
        let loginStatus = SMAppService.mainApp.status
        loginItem.state = loginStatus == .enabled ? .on : (loginStatus == .requiresApproval ? .mixed : .off)
        loginItem.title = loginStatus == .requiresApproval ? "Launch at login · approval needed…" : "Launch at login"
        taskMenu.removeAllItems()
        for task in taskCatalog() {
            let option = NSMenuItem(title: "\(task.title) — \(task.project)", action: #selector(selectTask(_:)), keyEquivalent: "")
            option.target = self; option.representedObject = task.id
            option.state = task.id == feed.task.id ? .on : .off
            taskMenu.addItem(option)
        }
        if taskMenu.items.isEmpty { taskMenu.addItem(withTitle: "No local tasks available", action: nil, keyEquivalent: "") }
    }
    @objc func selectTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let task = taskCatalog().first(where: { $0.id == id }) else { return }
        feed.select(task); refreshMenu()
    }
    @objc func showSetup() {
        if let setupController { setupController.window.makeKeyAndOrderFront(nil); return }
        setupWasPaused = feed.paused; setupWasEditing = feed.editing
        feed.paused = true; feed.suspendSummariesForSetup()
        setupController = SetupController(feed: feed, panel: panel, controlsChanged: { [weak self] in self?.notificationControls = $0 }) { [weak self] save, options in
            guard let self else { return }
            let wasVisible = self.setupController?.originalVisible ?? true
            self.setupController = nil
            if save {
                self.feed.fontSize = options.fontSize; self.feed.opacity = options.opacity; self.feed.lifetime = options.lifetime
                self.feed.intentionTitles = options.aiEnabled
                let defaults = UserDefaults.standard
                defaults.set(options.fontSize, forKey: "quietFontSize"); defaults.set(options.opacity, forKey: "quietOpacity")
                defaults.set(options.lifetime, forKey: "lifetime"); defaults.set(options.aiEnabled, forKey: "intentionTitles")
                defaults.set(options.model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "codexSummaryModel")
                defaults.set(true, forKey: "setupCompleted")
                self.feed.select(options.startingTask)
                self.feed.setSummaryProvider(options.provider)
                self.savePosition()
            }
            self.feed.editing = self.setupWasEditing; self.feed.paused = self.setupWasPaused
            self.feed.setupActive = false
            self.panel.contentView = NSHostingView(rootView: Overlay(feed: self.feed, openTask: { [weak self] in self?.openTask() }, controlsChanged: { [weak self] in self?.notificationControls = $0 }))
            if !wasVisible { self.panel.orderOut(nil) }
            self.updatePointerInteraction(); self.refreshMenu()
        }
        updatePointerInteraction()
    }
    @objc func openTask() {
        guard let url = URL(string: "codex://threads/" + feed.task.id) else { return }
        guard !feed.task.id.isEmpty else { return }
        if !CodexInstallation.open(url) { featureNotice("No application is registered to open Codex tasks. Install Codex, then try again.") }
    }
    func featureNotice(_ text: String) {
        let alert = NSAlert(); alert.messageText = text; alert.runModal()
    }
    @objc func toggleQualityLogging(_ sender: NSMenuItem) {
        QualityLog.shared.setEnabled(!QualityLog.shared.enabled)
        sender.state = QualityLog.shared.enabled ? .on : .off
        QualityLog.shared.record("logging_enabled", ["notice": "Contains actual message text; local quality review only"])
    }
    @objc func showQualityReview() {
        if qualityReviewWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Sideglance · Output quality"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: QualityReviewView())
            window.center(); qualityReviewWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        qualityReviewWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func openQualityLogs() {
        if let error = QualityLog.shared.error { let alert = NSAlert(); alert.messageText = error; alert.runModal(); return }
        NSWorkspace.shared.open(QualityLog.shared.directory)
    }
    @objc func clearQualityLogs() {
        QualityLog.shared.setEnabled(false); QualityLog.shared.clear()
        if let menu = item.menu {
            for parent in menu.items { for child in parent.submenu?.items ?? [] { for option in child.submenu?.items ?? [] where option.action == #selector(toggleQualityLogging(_:)) { option.state = .off } } }
        }
    }
    @objc func featureSettings() { _ = configureFeatureDestinations() }
    @discardableResult func configureFeatureDestinations() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Feature request settings"
        alert.informativeText = "Set your feature-request email recipient and local source folder."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 112))
        let email = NSTextField(frame: NSRect(x: 0, y:  60, width: 420, height: 24))
        email.stringValue = UserDefaults.standard.string(forKey: "featureEmail") ?? ""
        email.placeholderString = "features@example.com"
        let repo = NSTextField(frame: NSRect(x: 0, y: 4, width: 420, height: 24))
        repo.stringValue = UserDefaults.standard.string(forKey: "featureProjectPath") ?? ""
        repo.placeholderString = "/path/to/Sideglance"
        for (title, y) in [("Email recipient", 88.0), ("Local project folder", 32.0)] {
            let label = NSTextField(labelWithString: title); label.frame = NSRect(x: 0, y: y, width: 420, height: 20); container.addSubview(label)
        }
        container.addSubview(email); container.addSubview(repo); alert.accessoryView = container
        while alert.runModal() == .alertFirstButtonReturn {
            let recipient = email.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let repository = repo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard recipient.isEmpty || validFeatureEmail(recipient) else { featureNotice("Enter a valid email address."); continue }
            guard repository.isEmpty || validFeatureProject(repository) else { featureNotice("Enter an existing absolute project folder path."); continue }
            UserDefaults.standard.set(recipient, forKey: "featureEmail")
            UserDefaults.standard.set(repository, forKey: "featureProjectPath")
            return true
        }
        return false
    }
    @objc func featureRequest() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Feature request"
        alert.informativeText = "What would you like Sideglance to do? Describe the change and how it would help you."
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 190))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let editor = NSTextView(frame: scroll.bounds)
        editor.isRichText = false; editor.font = .systemFont(ofSize: 13)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.autoresizingMask = [.width]; editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.string = UserDefaults.standard.string(forKey: "featureDraft") ?? ""
        scroll.documentView = editor; alert.accessoryView = scroll
        alert.window.initialFirstResponder = editor
        var details = ""
        while true {
            let result = alert.runModal()
            details = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(details, forKey: "featureDraft")
            guard result == .alertFirstButtonReturn else { return }
            if details.isEmpty { featureNotice("Please describe your feature request."); continue }
            if details.count > 6000 { featureNotice("Please keep the request under 6,000 characters."); continue }
            break
        }
        let choice = NSAlert(); choice.messageText = "How would you like to proceed?"
        choice.informativeText = "Email opens a draft for you to review and send. Codex opens a prepared task asking it to create a branch, implement the feature, test and self-review it, then commit ready for a later PR. It will not create a PR, push or merge. Your feature details are included; chat history is not attached."
        choice.addButton(withTitle: "Email feature request")
        choice.addButton(withTitle: "Ask Codex to build + commit")
        choice.addButton(withTitle: "Cancel")
        let route = choice.runModal()
        if route == .alertFirstButtonReturn {
            if (UserDefaults.standard.string(forKey: "featureEmail") ?? "").isEmpty {
                guard configureFeatureDestinations() else { return }
            }
            guard let recipient = UserDefaults.standard.string(forKey: "featureEmail"), validFeatureEmail(recipient) else { featureNotice("Set an email recipient in Feature request settings first."); return }
            guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [details]) else { featureNotice("No email composer is available. Your request has been saved; open Feature request to try again."); return }
            service.recipients = [recipient]; service.subject = "Sideglance feature request"
            service.perform(withItems: [details])
        } else if route == .alertSecondButtonReturn {
            if (UserDefaults.standard.string(forKey: "featureProjectPath") ?? "").isEmpty {
                guard configureFeatureDestinations() else { return }
            }
            guard let repo = UserDefaults.standard.string(forKey: "featureProjectPath"), validFeatureProject(repo), let url = featureTaskURL(details: details, projectPath: repo) else { featureNotice("Set an existing local project folder in Feature request settings first."); return }
            if !CodexInstallation.open(url) { featureNotice("No application is registered to open Codex tasks. Install Codex, then try again. Your request has been saved.") }
        }
    }
    @objc func showHistory() {
        if historyPanel == nil {
            let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 460, height: 540), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Sideglance · Recent updates"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView(feed: feed))
            window.center(); historyPanel = window
        }
        historyPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggleVisibility() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        refreshStatus()
    }
    @objc func togglePositioning() {
        if feed.editing { clickThrough() } else { show() }
        refreshStatus()
    }
    @objc func show() { feed.editing = true; panel.ignoresMouseEvents = false; panel.orderFrontRegardless() }
    @objc func clickThrough() { savePosition(); feed.editing = false; panel.ignoresMouseEvents = true; panel.orderFrontRegardless() }
    @objc func setLifetime(_ sender: NSMenuItem) {
        feed.lifetime = Double(sender.tag); UserDefaults.standard.set(feed.lifetime, forKey: "lifetime")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    @objc func setOpacity(_ sender: NSMenuItem) {
        feed.opacity = Double(sender.tag) / 100; UserDefaults.standard.set(feed.opacity, forKey: "quietOpacity")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    @objc func larger() { feed.fontSize = min(22, feed.fontSize + 1); UserDefaults.standard.set(feed.fontSize, forKey: "quietFontSize") }
    @objc func smaller() { feed.fontSize = max(10, feed.fontSize - 1); UserDefaults.standard.set(feed.fontSize, forKey: "quietFontSize") }
    @objc func togglePause(_ sender: NSMenuItem) { feed.paused.toggle(); sender.state = feed.paused ? .on : .off }
    @objc func toggleTools(_ sender: NSMenuItem) { feed.showActivity.toggle(); sender.state = feed.showActivity ? .on : .off }
    @objc func toggleKeepLatest(_ sender: NSMenuItem) {
        feed.keepLatest.toggle()
        UserDefaults.standard.set(feed.keepLatest, forKey: "keepLatestWhileWorking")
        sender.state = feed.keepLatest ? .on : .off
    }
    @objc func retrySummaries() { feed.retryIntentionTitle() }
    @objc func selectSummaryProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = SummaryProvider(rawValue: raw) else { return }
        feed.setSummaryProvider(provider)
        for item in sender.menu?.items ?? [] {
            if let value = item.representedObject as? String { item.state = value == raw ? .on : .off }
        }
        refreshStatus()
    }
    @objc func toggleIntentionTitles(_ sender: NSMenuItem) {
        feed.intentionTitles.toggle(); UserDefaults.standard.set(feed.intentionTitles, forKey: "intentionTitles")
        sender.state = feed.intentionTitles ? .on : .off
        if !feed.intentionTitles { feed.setSummaryProvider(feed.summaryProvider) }
        if feed.intentionTitles { feed.refreshIntentionTitle() }
    }
    @objc func toggleAdaptive(_ sender: NSMenuItem) {
        feed.adaptiveTiming.toggle(); UserDefaults.standard.set(feed.adaptiveTiming, forKey: "adaptiveTiming"); sender.state = feed.adaptiveTiming ? .on : .off
    }
    @objc func toggleGrouping(_ sender: NSMenuItem) {
        feed.groupErrors.toggle(); UserDefaults.standard.set(feed.groupErrors, forKey: "groupErrors"); sender.state = feed.groupErrors ? .on : .off
    }
    @objc func toggleSound(_ sender: NSMenuItem) {
        feed.inputSound.toggle(); UserDefaults.standard.set(feed.inputSound, forKey: "inputSound"); sender.state = feed.inputSound ? .on : .off
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "Could not update launch at login"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
        refreshMenu()
    }
    @objc func quit() { NSApp.terminate(nil) }
}
