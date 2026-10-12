import Carbon

private func hotkeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return noErr }
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    var identifier = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    if status == noErr {
        if identifier.id == 1 { service.onPressed?() }
        if identifier.id == 2 { service.onScreenshotPressed?() }
    }
    return noErr
}

final class HotkeyService {
    var onPressed: (() -> Void)?
    var onScreenshotPressed: (() -> Void)?
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    deinit { unregister() }

    @discardableResult
    func register(_ choice: HotkeyChoice) -> Bool {
        register(history: choice, screenshot: nil).history
    }

    func register(history: HotkeyChoice, screenshot: ScreenshotHotkeyChoice?) -> (history: Bool, screenshot: Bool) {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler,
                                                1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard handlerStatus == noErr else { return (false, false) }
        let history = registerKey(code: UInt32(kVK_ANSI_V), modifiers: history.carbonModifiers, id: 1)
        let screenshotResult = screenshot.map { registerKey(code: UInt32(kVK_ANSI_B), modifiers: $0.carbonModifiers, id: 2) } ?? false
        return (history, screenshotResult)
    }

    private func registerKey(code: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x50415354), id: id)
        guard RegisterEventHotKey(code, modifiers, identifier, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return false }
        hotkeys.append(ref)
        return true
    }

    private func unregister() {
        for hotkey in hotkeys { UnregisterEventHotKey(hotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotkeys.removeAll()
        eventHandler = nil
    }
}
