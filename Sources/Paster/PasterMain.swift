import AppKit
import SwiftUI
import PasterCore

@main
struct PasterMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            runPasteboardSelfTest()
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = PasterAppDelegate()
        app.delegate = delegate
        app.run()
    }

    private static func runPasteboardSelfTest() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PasterSelfTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try! HistoryStore(directory: directory)
        let suite = "com.temptrip.paster.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        precondition(!settings.recordingEnabled)
        settings.recordingEnabled = true
        settings.excludedBundleIDs = ["com.example.private"]
        let restoredSettings = SettingsStore(defaults: defaults)
        precondition(restoredSettings.recordingEnabled)
        precondition(restoredSettings.excludedBundleIDs == ["com.example.private"])

        let board = NSPasteboard(name: NSPasteboard.Name("com.temptrip.paster.selftest.\(UUID().uuidString)"))
        let controller = QuickPasteController(pasteboard: board)
        let monitor = ClipboardMonitor(pasteboard: board, settings: settings)
        var captured: [ClipPayload] = []
        monitor.onCapture = { payload, source in
            captured.append(payload)
            _ = try! store.save(payload, sourceBundleID: source)
        }
        monitor.poll()
        precondition(captured.isEmpty)
        precondition(controller.copy(.text("Paster self-test")))
        precondition(ClipboardMonitor.readPayload(from: board) == .text("Paster self-test"))
        monitor.poll()
        precondition(captured == [.text("Paster self-test")])
        precondition(controller.copy(.url("https://example.com")))
        precondition(ClipboardMonitor.readPayload(from: board) == .url("https://example.com"))
        monitor.markSelfWrite()
        monitor.poll()
        precondition(captured.count == 1)
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4,
                                     bitsPerPixel: 32)!
        let png = image.representation(using: .png, properties: [:])!
        precondition(controller.copy(.image(png)))
        precondition(ClipboardMonitor.readPayload(from: board) == .image(png))
        monitor.poll()
        precondition(captured.count == 2)
        let reopened = try! HistoryStore(directory: directory)
        precondition(try! reopened.items().count == 2)
        precondition(try! reopened.items().contains { $0.kind == .image })
        precondition(controller.copy(.image(Data(count: 20 * 1_024 * 1_024 + 1))))
        precondition(ClipboardMonitor.readPayload(from: board) == nil)
        var fallback: PasteResult?
        controller.paste(to: nil) { fallback = $0 }
        guard case .manualPasteRequired = fallback else { preconditionFailure("Missing paste fallback") }
        let deniedController = QuickPasteController(pasteboard: board, isAccessibilityTrusted: { false })
        var permissionFallback: PasteResult?
        deniedController.paste(to: NSWorkspace.shared.frontmostApplication) { permissionFallback = $0 }
        guard case .manualPasteRequired = permissionFallback else { preconditionFailure("Missing permission fallback") }
        _ = NSApplication.shared
        var hotkeyConflictVerified = false
        for choice in HotkeyChoice.allCases {
            let first = HotkeyService()
            if first.register(choice) {
                let second = HotkeyService()
                precondition(!second.register(choice))
                hotkeyConflictVerified = true
                break
            }
        }
        board.clearContents()
        print("Paster app self-test: settings, capture, self-write, text, URL, image, restart, paste fallback passed")
        print(hotkeyConflictVerified ? "Hotkey registration conflict: passed" : "Hotkey registration conflict: skipped (all choices occupied)")
    }
}

final class PasterAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var model: AppModel?
    private let hotkey = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let model = try AppModel()
            self.model = model
            model.onRequestHidePanel = { [weak self] in self?.panel?.orderOut(nil) }
            model.onRequestShowPanel = { [weak self] in self?.showPanel(nil) }
            model.settings.onHotkeyChanged = { [weak self] in
                guard let self, let model = self.model else { return }
                model.shortcutAvailable = self.hotkey.register(model.settings.hotkeyChoice)
            }
            model.shortcutAvailable = hotkey.register(model.settings.hotkeyChoice)
            hotkey.onPressed = { [weak self] in self?.showPanel(nil) }
            model.start()
            setupMenuBar()
            if !model.settings.recordingEnabled { showPanel(nil) }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Paster 无法启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model?.stop() }

    private func setupMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paster") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else { statusItem.button?.title = "P" }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "打开剪贴板历史", action: #selector(showPanel(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if let settings = model?.settings {
            let record = NSMenuItem(title: settings.recordingEnabled ? "停止记录" : "启用记录",
                                    action: #selector(toggleRecording(_:)), keyEquivalent: "")
            record.target = self
            menu.addItem(record)
            if settings.recordingEnabled {
                let pause = NSMenuItem(title: settings.paused ? "继续记录" : "暂停记录",
                                       action: #selector(togglePause(_:)), keyEquivalent: "")
                pause.target = self
                menu.addItem(pause)
            }
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Paster", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleRecording(_ sender: Any?) {
        guard let settings = model?.settings else { return }
        settings.recordingEnabled.toggle()
    }

    @objc private func togglePause(_ sender: Any?) {
        guard let settings = model?.settings else { return }
        settings.paused.toggle()
    }

    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }

    @objc private func showPanel(_ sender: Any?) {
        guard let model else { return }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            model.targetApplication = NSWorkspace.shared.frontmostApplication
        }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 570, height: 590),
                                styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered,
                                defer: false)
            panel.title = "Paster"
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.contentView = NSHostingView(rootView: PasterView(model: model))
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
