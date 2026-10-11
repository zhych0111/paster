import Foundation
import Combine
import Carbon

enum HotkeyChoice: Int, CaseIterable, Identifiable {
    case controlOptionV = 0
    case controlShiftV = 1
    case commandShiftV = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .controlOptionV: return "⌃⌥V"
        case .controlShiftV: return "⌃⇧V"
        case .commandShiftV: return "⌘⇧V"
        }
    }
    var carbonModifiers: UInt32 {
        switch self {
        case .controlOptionV: return UInt32(controlKey | optionKey)
        case .controlShiftV: return UInt32(controlKey | shiftKey)
        case .commandShiftV: return UInt32(cmdKey | shiftKey)
        }
    }
}

final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    var onCapturePolicyChanged: (() -> Void)?
    var onHotkeyChanged: (() -> Void)?

    @Published var recordingEnabled: Bool {
        didSet { defaults.set(recordingEnabled, forKey: "recordingEnabled"); onCapturePolicyChanged?() }
    }
    @Published var paused: Bool {
        didSet { defaults.set(paused, forKey: "paused"); onCapturePolicyChanged?() }
    }
    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: "retentionDays"); onCapturePolicyChanged?() }
    }
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") }
    }
    @Published var autoPasteEnabled: Bool {
        didSet { defaults.set(autoPasteEnabled, forKey: "autoPasteEnabled") }
    }
    @Published var hotkeyChoice: HotkeyChoice {
        didSet { defaults.set(hotkeyChoice.rawValue, forKey: "hotkeyChoice"); onHotkeyChanged?() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recordingEnabled = defaults.bool(forKey: "recordingEnabled")
        paused = defaults.bool(forKey: "paused")
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 30
        excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        autoPasteEnabled = defaults.bool(forKey: "autoPasteEnabled")
        hotkeyChoice = HotkeyChoice(rawValue: defaults.integer(forKey: "hotkeyChoice")) ?? .controlOptionV
    }
}
