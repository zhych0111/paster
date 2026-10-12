import AppKit
import SwiftUI

private struct ScrollingPreviewView: View {
    let image: NSImage
    let onPin: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("滚动截图预览").font(.headline)
                Spacer()
                Button("贴在桌面") { onPin() }
                Button("复制") { onCopy() }
                Button("保存 PNG") { onSave() }
                Button("关闭") { onDismiss() }
            }
            .padding(10)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 650)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 450, minHeight: 350)
    }
}

final class ScreenshotCommandController: NSObject {
    private let regionCapture = ScreenshotCaptureService()
    private let overlay = ScrollSelectionOverlay()
    private let pins = PinnedImageManager()
    private var scrolling: ScrollingCaptureSession?
    private var preview: NSPanel?
    private var progressPanel: NSPanel?
    private var progressLabel: NSTextField?
    private var hiddenPins: [NSPanel] = []
    private var historyWasVisible = false
    private var previewWasVisible = false
    private var selecting = false
    private var waitingForRegion = false
    private var shuttingDown = false
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private(set) var status: String?
    var onStatusChange: (() -> Void)?
    var onHideHistory: (() -> Bool)?
    var onRestoreHistory: (() -> Void)?
    var onCopy: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        super.init()
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier { lastExternalApplication = front }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.lastExternalApplication = app
        }
        pins.onCopy = { [weak self] data in self?.onCopy?(data) }
        pins.onError = { [weak self] message in self?.onError?(message) }
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    var isBusy: Bool { regionCapture.isCapturing || waitingForRegion || selecting || scrolling != nil }
    var isScrolling: Bool { scrolling != nil }

    func captureRegion() {
        guard !isBusy, !shuttingDown else { return }
        hideExistingWindows()
        waitingForRegion = true
        status = "选择截图区域中"
        onStatusChange?()
        waitForShortcutRelease { [weak self] in
            guard let self else { return }
            self.waitingForRegion = false
            self.regionCapture.captureRegion { [weak self] result in
                guard let self, !self.shuttingDown else { return }
                self.restoreExistingWindows()
                self.status = nil
                self.onStatusChange?()
                switch result {
                case .image(let data): self.pins.add(data)
                case .cancelled: break
                case .copiedToClipboard: self.onError?("系统已将截图复制到剪贴板；若要贴图，请重试并松开 Control")
                case .failed(let message): self.onError?(message)
                }
            }
        }
    }

    func captureScrolling() {
        guard !isBusy, !shuttingDown else { return }
        let front = NSWorkspace.shared.frontmostApplication
        guard let target = (front?.bundleIdentifier == Bundle.main.bundleIdentifier ? lastExternalApplication : front),
              !target.isTerminated else {
            onError?("请先切换到要截图的应用，再从菜单栏启动滚动截图")
            return
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { onError?("无法识别显示器"); return }
        hideExistingWindows()
        selecting = true
        status = "拖出滚动内容区域 · Esc 取消"
        onStatusChange?()
        overlay.select(on: screen) { [weak self] region in
            guard let self, !self.shuttingDown else { return }
            self.selecting = false
            guard let region else {
                self.restoreExistingWindows()
                self.status = nil
                self.onStatusChange?()
                return
            }
            guard target.activate(options: [.activateIgnoringOtherApps]) else {
                self.restoreExistingWindows()
                self.status = nil
                self.onStatusChange?()
                self.onError?("无法切回要截图的应用，请重试")
                return
            }
            let session = ScrollingCaptureSession(target: target, screen: screen, region: region)
            self.scrolling = session
            self.showProgressPanel(on: screen, outside: region)
            session.onStatus = { [weak self] message in
                self?.status = message
                self?.progressLabel?.stringValue = message
                self?.onStatusChange?()
            }
            session.onComplete = { [weak self] png, message in
                guard let self, !self.shuttingDown else { return }
                self.scrolling = nil
                self.progressPanel?.close()
                self.progressPanel = nil
                self.progressLabel = nil
                self.restoreExistingWindows()
                self.status = nil
                self.onStatusChange?()
                if let png { self.showPreview(png) }
                if let message { self.onError?(message) }
                else if png == nil { self.onError?("没有捕获到可用的画面") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard self.scrolling === session else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                    self.scrolling = nil
                    self.progressPanel?.close()
                    self.progressPanel = nil
                    self.progressLabel = nil
                    self.restoreExistingWindows()
                    self.status = nil
                    self.onStatusChange?()
                    self.onError?("目标应用没有获得焦点，请重试")
                    return
                }
                session.start()
            }
        }
    }

    func stopScrolling() {
        if selecting {
            overlay.cancel()
            selecting = false
            restoreExistingWindows()
            status = nil
            onStatusChange?()
        } else { scrolling?.stopAndPreview() }
    }

    func shutdown() {
        shuttingDown = true
        waitingForRegion = false
        regionCapture.cancel()
        overlay.cancel()
        scrolling?.cancel()
        scrolling = nil
        pins.closeAll()
        preview?.close()
        progressPanel?.close()
    }

    private func hideExistingWindows() {
        historyWasVisible = onHideHistory?() ?? false
        hiddenPins = pins.hideVisible()
        previewWasVisible = preview?.isVisible ?? false
        preview?.orderOut(nil)
    }

    private func restoreExistingWindows() {
        pins.restore(hiddenPins)
        hiddenPins.removeAll()
        if historyWasVisible { onRestoreHistory?() }
        historyWasVisible = false
        if previewWasVisible { preview?.orderFront(nil) }
        previewWasVisible = false
    }

    private func waitForShortcutRelease(_ completion: @escaping () -> Void) {
        guard waitingForRegion else { return }
        let modifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        if NSEvent.modifierFlags.intersection(modifiers).isEmpty { completion(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForShortcutRelease(completion)
        }
    }

    private func showPreview(_ png: Data) {
        guard let image = NSImage(data: png) else { onError?("预览图片无法解码"); return }
        preview?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Paster 滚动截图"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ScrollingPreviewView(image: image,
            onPin: { [weak self] in self?.pins.add(png); self?.preview?.close() },
            onCopy: { [weak self] in self?.onCopy?(png) },
            onSave: { [weak self] in self?.save(png) },
            onDismiss: { [weak self] in self?.preview?.close() }))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preview = panel
    }

    private func save(_ png: Data) {
        let save = NSSavePanel()
        save.allowedContentTypes = [.png]
        save.nameFieldStringValue = "Paster-Scrolling-\(Int(Date().timeIntervalSince1970)).png"
        save.begin { [weak self] response in
            guard response == .OK, let url = save.url else { return }
            do { try png.write(to: url, options: .atomic) }
            catch { self?.onError?("保存失败：\(error.localizedDescription)") }
        }
    }

    private func showProgressPanel(on screen: NSScreen, outside region: NSRect) {
        let size = NSSize(width: 290, height: 62)
        let visible = screen.visibleFrame
        let candidates = [
            NSPoint(x: region.minX, y: region.maxY + 8),
            NSPoint(x: region.minX, y: region.minY - size.height - 8),
            NSPoint(x: region.maxX + 8, y: region.midY),
            NSPoint(x: region.minX - size.width - 8, y: region.midY)
        ]
        guard let origin = candidates.first(where: {
            let rect = NSRect(origin: $0, size: size)
            return visible.contains(rect) && !rect.intersects(region)
        }) else { return }
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        let label = NSTextField(labelWithString: "正在准备滚动截图…")
        label.frame = NSRect(x: 10, y: 32, width: 270, height: 20)
        label.lineBreakMode = .byTruncatingTail
        root.addSubview(label)
        let button = NSButton(title: "停止并预览", target: self, action: #selector(stopFromPanel(_:)))
        button.frame = NSRect(x: 8, y: 3, width: 108, height: 27)
        root.addSubview(button)
        panel.contentView = root
        panel.orderFront(nil)
        progressPanel = panel
        progressLabel = label
    }

    @objc private func stopFromPanel(_ sender: Any?) { stopScrolling() }
}
