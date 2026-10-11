import AppKit
import ApplicationServices
import PasterCore

enum PasteResult {
    case copied
    case attemptedPaste
    case manualPasteRequired(String)
}

final class QuickPasteController {
    private let pasteboard: NSPasteboard
    private let isAccessibilityTrusted: () -> Bool

    init(pasteboard: NSPasteboard = .general, isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.pasteboard = pasteboard
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }

    static func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    @discardableResult
    func copy(_ payload: ClipPayload) -> Bool {
        pasteboard.clearContents()
        switch payload {
        case .text(let value): return pasteboard.setString(value, forType: .string)
        case .url(let value):
            let textWritten = pasteboard.setString(value, forType: .string)
            let urlWritten = pasteboard.setString(value, forType: .URL)
            return textWritten || urlWritten
        case .image(let data): return pasteboard.setData(data, forType: .png)
        }
    }

    func paste(to target: NSRunningApplication?, completion: @escaping (PasteResult) -> Void) {
        guard let target, !target.isTerminated else {
            completion(.manualPasteRequired("目标应用已关闭。内容已复制，请手动粘贴。"))
            return
        }
        guard isAccessibilityTrusted() else {
            completion(.manualPasteRequired("自动粘贴需要在系统设置中授予辅助功能权限。内容已复制，请手动粘贴。"))
            return
        }
        guard target.activate(options: [.activateIgnoringOtherApps]) else {
            completion(.manualPasteRequired("无法切回目标应用。内容已复制，请手动粘贴。"))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
                completion(.manualPasteRequired("无法发送粘贴按键。内容已复制，请手动粘贴。"))
                return
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            completion(.attemptedPaste)
        }
    }
}
