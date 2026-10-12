import AppKit

private final class PinnedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class DragHandle: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class ResizeHandle: NSView {
    private var startPoint: NSPoint = .zero
    private var startFrame: NSRect = .zero

    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = NSEvent.mouseLocation
        let width = max(180, startFrame.width + point.x - startPoint.x)
        let height = max(130, startFrame.height - point.y + startPoint.y)
        window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height,
                               width: width, height: height), display: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setStroke()
        let path = NSBezierPath()
        for offset in stride(from: 3.0, through: 12.0, by: 4.0) {
            path.move(to: NSPoint(x: offset, y: 2))
            path.line(to: NSPoint(x: 16, y: 18 - offset))
        }
        path.stroke()
    }
}

final class PinnedImageManager: NSObject, NSWindowDelegate {
    private struct Entry {
        let window: NSPanel
        let png: Data
        let pixels: Int
        let imageView: NSImageView
        let scrollView: NSScrollView
        let imageAspect: CGFloat
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    var onCopy: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var count: Int { entries.count }

    func add(_ png: Data, show: Bool = true) {
        guard let rep = NSBitmapImageRep(data: png), rep.pixelsWide > 0, rep.pixelsHigh > 0,
              let image = NSImage(data: png) else { onError?("截图图片无法解码"); return }
        let pixels = rep.pixelsWide * rep.pixelsHigh
        guard pixels <= 25_000_000 else { onError?("图片超过 2500 万像素，请缩小选区"); return }
        guard entries.count < 10 else { onError?("最多同时贴 10 张图，请先关闭一张"); return }
        guard entries.values.reduce(0, { $0 + $1.pixels }) + pixels <= 50_000_000 else {
            onError?("贴图总像素已达上限，请先关闭部分贴图"); return
        }

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let aspect = CGFloat(rep.pixelsWide) / CGFloat(rep.pixelsHigh)
        let width = min(max(300, CGFloat(rep.pixelsWide) / 2), available.width * 0.7)
        let height = min(max(180, width / aspect + 36), available.height * 0.7)
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: min(max(mouse.x, available.minX), available.maxX - width),
                             y: min(max(mouse.y - height, available.minY), available.maxY - height))
        let panel = PinnedPanel(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
                                styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.title = "Paster 贴图"
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = NSSize(width: 180, height: 130)
        let root = NSView(frame: panel.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        panel.contentView = root

        let header = DragHandle(frame: NSRect(x: 0, y: height - 34, width: width, height: 34))
        header.autoresizingMask = [.width, .minYMargin]
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(header)
        let actions: [(String, Selector)] = [("×", #selector(closeClicked(_:))), ("复制", #selector(copyClicked(_:))),
                                             ("保存", #selector(saveClicked(_:)))]
        var actionX: CGFloat = 8
        for (title, selector) in actions {
            let button = NSButton(title: title, target: self, action: selector)
            let buttonWidth: CGFloat = title == "×" ? 28 : 48
            button.frame = NSRect(x: actionX, y: 3, width: buttonWidth, height: 28)
            button.bezelStyle = .inline
            button.identifier = NSUserInterfaceItemIdentifier(String(ObjectIdentifier(panel).hashValue))
            header.addSubview(button)
            actionX += buttonWidth + 4
        }
        header.toolTip = "拖动工具栏空白处移动；拖动右下角缩放"

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height - 34))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: width,
                                                  height: max(height - 34, width / aspect)))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        let contextMenu = NSMenu()
        for (title, selector) in [("复制", #selector(menuCopy(_:))),
                                  ("保存 PNG", #selector(menuSave(_:))),
                                  ("关闭", #selector(menuClose(_:)))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            item.representedObject = panel
            contextMenu.addItem(item)
        }
        imageView.menu = contextMenu
        scroll.documentView = imageView
        root.addSubview(scroll)
        let resize = ResizeHandle(frame: NSRect(x: width - 18, y: 0, width: 18, height: 18))
        resize.autoresizingMask = [.minXMargin]
        root.addSubview(resize)
        let entry = Entry(window: panel, png: png, pixels: pixels, imageView: imageView,
                          scrollView: scroll, imageAspect: aspect)
        entries[ObjectIdentifier(panel)] = entry
        if show { panel.orderFrontRegardless() }
    }

    func hideVisible() -> [NSPanel] {
        let visible = entries.values.map(\.window).filter(\.isVisible)
        visible.forEach { $0.orderOut(nil) }
        return visible
    }

    func restore(_ windows: [NSPanel]) {
        for window in windows where entries[ObjectIdentifier(window)] != nil { window.orderFrontRegardless() }
    }

    func closeAll() {
        let windows = entries.values.map(\.window)
        entries.removeAll()
        windows.forEach { $0.close() }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        entries.removeValue(forKey: ObjectIdentifier(window))
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = entries[ObjectIdentifier(window)] else { return }
        let width = entry.scrollView.contentSize.width
        entry.imageView.frame.size = NSSize(width: width, height: max(entry.scrollView.contentSize.height,
                                                                     width / entry.imageAspect))
    }

    private func entry(for sender: NSButton) -> Entry? {
        guard let raw = sender.identifier?.rawValue,
              let hash = Int(raw) else { return nil }
        return entries.first(where: { $0.key.hashValue == hash })?.value
    }

    @objc private func closeClicked(_ sender: NSButton) { entry(for: sender)?.window.close() }
    @objc private func copyClicked(_ sender: NSButton) {
        guard let entry = entry(for: sender) else { return }
        onCopy?(entry.png)
    }
    @objc private func saveClicked(_ sender: NSButton) {
        guard let entry = entry(for: sender) else { return }
        save(entry)
    }

    @objc private func menuClose(_ item: NSMenuItem) { (item.representedObject as? NSPanel)?.close() }
    @objc private func menuCopy(_ item: NSMenuItem) {
        guard let panel = item.representedObject as? NSPanel,
              let entry = entries[ObjectIdentifier(panel)] else { return }
        onCopy?(entry.png)
    }
    @objc private func menuSave(_ item: NSMenuItem) {
        guard let panel = item.representedObject as? NSPanel,
              let entry = entries[ObjectIdentifier(panel)] else { return }
        save(entry)
    }

    private func save(_ entry: Entry) {
        let save = NSSavePanel()
        save.allowedContentTypes = [.png]
        save.nameFieldStringValue = "Paster-\(Int(Date().timeIntervalSince1970)).png"
        save.begin { [weak self] response in
            guard response == .OK, let url = save.url else { return }
            do { try entry.png.write(to: url, options: .atomic) }
            catch { self?.onError?("保存失败：\(error.localizedDescription)") }
        }
    }
}
