import AppKit
import Combine
import PasterCore

final class AppModel: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published var message: String?
    @Published var shortcutAvailable = true

    let settings: SettingsStore
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let pasteController = QuickPasteController()
    private let imageCache = NSCache<NSString, NSImage>()
    var targetApplication: NSRunningApplication?
    var onRequestHidePanel: (() -> Void)?
    var onRequestShowPanel: (() -> Void)?

    init() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paster", isDirectory: true)
        settings = SettingsStore()
        store = try HistoryStore(directory: support)
        monitor = ClipboardMonitor(settings: settings)
        imageCache.countLimit = 100
        monitor.onCapture = { [weak self] payload, bundleID in
            guard let self else { return }
            do {
                _ = try self.store.save(payload, sourceBundleID: bundleID, retentionDays: self.settings.retentionDays)
                try self.refresh()
            } catch { self.message = "保存失败：\(error.localizedDescription)" }
        }
        settings.onCapturePolicyChanged = { [weak self] in
            self?.monitor.resetBaseline()
            try? self?.refresh()
        }
        try refresh()
    }

    func start() { monitor.start() }
    func stop() { monitor.stop() }

    func refresh() throws {
        try store.cleanup(retentionDays: settings.retentionDays)
        items = try store.items()
    }

    func filteredItems(_ search: String) -> [ClipItem] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return items }
        return items.filter { $0.text?.localizedCaseInsensitiveContains(term) == true }
    }

    func image(for item: ClipItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard case .image(let data) = try? store.payload(for: item) else { return nil }
        guard let image = NSImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    func togglePin(_ item: ClipItem) {
        do { try store.setPinned(!item.isPinned, id: item.id); try refresh() }
        catch { message = "固定失败：\(error.localizedDescription)" }
    }

    func delete(_ item: ClipItem) {
        do { try store.delete(id: item.id); imageCache.removeObject(forKey: item.id.uuidString as NSString); try refresh() }
        catch { message = "删除失败：\(error.localizedDescription)" }
    }

    func clearAll() {
        do { try store.clearAll(); imageCache.removeAllObjects(); try refresh(); message = "历史已清空" }
        catch { message = "清空失败：\(error.localizedDescription)" }
    }

    func use(_ item: ClipItem, automaticPaste: Bool) {
        do {
            let payload = try store.payload(for: item)
            guard pasteController.copy(payload) else { message = "无法写入系统剪贴板"; return }
            monitor.markSelfWrite()
            try store.touch(id: item.id)
            try refresh()
            if automaticPaste {
                guard settings.autoPasteEnabled else {
                    message = "内容已复制。请先在设置中启用自动粘贴，或手动粘贴。"
                    return
                }
                guard let targetApplication, !targetApplication.isTerminated else {
                    message = "内容已复制。目标应用不可用，请手动粘贴。"
                    return
                }
                onRequestHidePanel?()
                pasteController.paste(to: targetApplication) { [weak self] result in
                    switch result {
                    case .copied: self?.message = "内容已复制"
                    case .attemptedPaste: self?.message = "已尝试粘贴"
                    case .manualPasteRequired(let detail):
                        self?.message = detail
                        self?.onRequestShowPanel?()
                    }
                }
            } else {
                message = "已复制到剪贴板"
                onRequestHidePanel?()
            }
        } catch { message = "操作失败：\(error.localizedDescription)" }
    }
}
