import Foundation

public struct CaptureGate {
    private var lastChangeCount: Int
    private var selfWrittenChangeCount: Int?

    public init(initialChangeCount: Int) { self.lastChangeCount = initialChangeCount }

    public mutating func reset(to changeCount: Int) {
        lastChangeCount = changeCount
        selfWrittenChangeCount = nil
    }

    public mutating func markSelfWrite(_ changeCount: Int) {
        selfWrittenChangeCount = changeCount
    }

    public mutating func shouldCapture(changeCount: Int, recordingEnabled: Bool, paused: Bool,
                                       sourceBundleID: String?, excludedBundleIDs: Set<String>) -> Bool {
        guard changeCount != lastChangeCount else { return false }
        lastChangeCount = changeCount
        if selfWrittenChangeCount == changeCount {
            selfWrittenChangeCount = nil
            return false
        }
        guard recordingEnabled, !paused else { return false }
        if let sourceBundleID, excludedBundleIDs.contains(sourceBundleID) { return false }
        return true
    }
}
