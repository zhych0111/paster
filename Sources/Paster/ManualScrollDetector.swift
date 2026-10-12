import AppKit
import ApplicationServices

final class ManualScrollGate {
    enum Mode { case automatic, manual, stopped }
    private let lock = NSLock()
    private var value: Mode = .automatic

    var mode: Mode { lock.lock(); defer { lock.unlock() }; return value }
    func takeOver() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value == .automatic else { return false }
        value = .manual
        return true
    }
    func stop() { lock.lock(); value = .stopped; lock.unlock() }
}

private func manualScrollTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType,
                                     _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let detector = Unmanaged<ManualScrollDetector>.fromOpaque(userInfo).takeUnretainedValue()
    detector.observe(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

final class ManualScrollDetector {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let gate: ManualScrollGate
    private let marker: Int64
    private(set) var observedOwnScroll = false
    var onTakeover: (() -> Void)?

    init(gate: ManualScrollGate, marker: Int64) {
        self.gate = gate
        self.marker = marker
    }

    func start() -> Bool {
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .rightMouseDown,
                                     .leftMouseDragged, .rightMouseDragged, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: manualScrollTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
    }

    fileprivate func observe(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            switchToManual()
            return
        }
        if type == .scrollWheel && event.getIntegerValueField(.eventSourceUserData) == marker {
            observedOwnScroll = true
            return
        }
        if type == .scrollWheel || type == .leftMouseDown || type == .rightMouseDown ||
            type == .leftMouseDragged || type == .rightMouseDragged || type == .keyDown {
            switchToManual()
        }
    }

    private func switchToManual() {
        guard gate.takeOver() else { return }
        onTakeover?()
    }
}

final class ScrollDriver {
    private let gate: ManualScrollGate
    private let marker: Int64
    init(gate: ManualScrollGate, marker: Int64) { self.gate = gate; self.marker = marker }

    var canPost: Bool { AXIsProcessTrusted() && gate.mode == .automatic }

    @discardableResult
    func postStep(at point: CGPoint, pixels: Int32 = 140) -> Bool {
        guard canPost,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: -pixels, wheel2: 0, wheel3: 0) else { return false }
        event.location = point
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        guard gate.mode == .automatic else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
