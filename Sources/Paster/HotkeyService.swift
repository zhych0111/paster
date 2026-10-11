import Carbon

private func hotkeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    service.onPressed?()
    return noErr
}

final class HotkeyService {
    var onPressed: (() -> Void)?
    private var hotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    deinit { unregister() }

    @discardableResult
    func register(_ choice: HotkeyChoice) -> Bool {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler,
                                                1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard handlerStatus == noErr else { return false }
        let identifier = EventHotKeyID(signature: OSType(0x50415354), id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_V), choice.carbonModifiers, identifier,
                                         GetApplicationEventTarget(), 0, &hotkey)
        if result != noErr { unregister(); return false }
        return true
    }

    private func unregister() {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotkey = nil
        eventHandler = nil
    }
}
