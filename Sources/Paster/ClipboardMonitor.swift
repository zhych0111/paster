import AppKit
import PasterCore

final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let settings: SettingsStore
    private var gate: CaptureGate
    private var timer: Timer?
    var onCapture: ((ClipPayload, String?) -> Void)?

    init(pasteboard: NSPasteboard = .general, settings: SettingsStore) {
        self.pasteboard = pasteboard
        self.settings = settings
        self.gate = CaptureGate(initialChangeCount: pasteboard.changeCount)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() { timer?.invalidate(); timer = nil }
    func resetBaseline() { gate.reset(to: pasteboard.changeCount) }
    func markSelfWrite() { gate.markSelfWrite(pasteboard.changeCount) }

    func poll() {
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard gate.shouldCapture(changeCount: pasteboard.changeCount, recordingEnabled: settings.recordingEnabled,
                                 paused: settings.paused, sourceBundleID: source,
                                 excludedBundleIDs: Set(settings.excludedBundleIDs)) else { return }
        guard let payload = Self.readPayload(from: pasteboard) else { return }
        onCapture?(payload, source)
    }

    static func readPayload(from pasteboard: NSPasteboard) -> ClipPayload? {
        if let data = pasteboard.data(forType: .png) {
            guard !data.isEmpty, data.count <= 20 * 1_024 * 1_024 else { return nil }
            return .image(data)
        }
        if let data = pasteboard.data(forType: .tiff) {
            guard !data.isEmpty, data.count <= 20 * 1_024 * 1_024,
                  let image = NSBitmapImageRep(data: data),
                  let png = image.representation(using: .png, properties: [:]),
                  !png.isEmpty, png.count <= 20 * 1_024 * 1_024 else { return nil }
            return .image(png)
        }
        if let url = pasteboard.string(forType: .URL), let payload = ClipPayload.normalizedText(url) {
            return payload
        }
        if let text = pasteboard.string(forType: .string) { return ClipPayload.normalizedText(text) }
        return nil
    }
}
