import AppKit

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var selection: NSRect = .zero
    var onFinish: ((NSRect?) -> Void)?
    private var start: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        guard selection.width >= 80, selection.height >= 80, let window else {
            onFinish?(nil)
            return
        }
        onFinish?(window.convertToScreen(selection))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) }
        else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 2
            outline.stroke()
        }
        let hint = "拖出滚动内容区域，松开开始 · Esc 取消"
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white,
                                                     .font: NSFont.systemFont(ofSize: 16, weight: .medium)]
        (hint as NSString).draw(at: NSPoint(x: max(20, bounds.midX - 170), y: bounds.maxY - 52),
                                withAttributes: attrs)
    }
}

final class ScrollSelectionOverlay {
    private var panel: SelectionPanel?

    func select(on screen: NSScreen, completion: @escaping (NSRect?) -> Void) {
        cancel()
        let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless],
                                   backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rect in
            self?.cancel()
            completion(rect)
        }
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func cancel() {
        panel?.close()
        panel = nil
    }
}
