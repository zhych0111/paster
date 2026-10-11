import Foundation
import PasterCore

@main
struct PasterSelfTests {
    static func main() throws {
        try testNormalizationAndDuplicates()
        try testPinnedRetentionAndImageDeletion()
        try testClearAll()
        testCaptureGate()
        try testCountLimit()
        print("PasterSelfTests: 5 checks passed")
    }

    private static func require(_ condition: Bool) { precondition(condition) }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func testNormalizationAndDuplicates() throws {
        require(ClipPayload.normalizedText("https://example.com/a") == .url("https://example.com/a"))
        require(ClipPayload.normalizedText("hello") == .text("hello"))
        require(ClipPayload.normalizedText("") == nil)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstDate = Date(timeIntervalSince1970: 1_000_000)
        let firstID: UUID
        do {
            let store = try HistoryStore(directory: directory)
            firstID = try store.save(.text("hello"), at: firstDate).id
            let second = try store.save(.text("hello"), at: firstDate.addingTimeInterval(60))
            require(second.id == firstID && second.copyCount == 2)
            require(try store.items().count == 1)
        }
        let reopened = try HistoryStore(directory: directory)
        require(try reopened.items().first?.id == firstID)
        require(try reopened.items(search: "HEL").count == 1)
        try reopened.touch(id: firstID, at: firstDate.addingTimeInterval(120))
        require(try reopened.items().first?.copyCount == 3)
    }

    private static func testPinnedRetentionAndImageDeletion() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let old = Date(timeIntervalSince1970: 1_000_000)
        let image = try store.save(.image(Data([1, 2, 3, 4])), at: old)
        try store.setPinned(true, id: image.id)
        _ = try store.save(.text("expired"), at: old)
        try store.cleanup(retentionDays: 30, now: old.addingTimeInterval(31 * 86_400))
        require(try store.items().map(\.id) == [image.id])
        require(try store.payload(for: image) == .image(Data([1, 2, 3, 4])))
        let imageURL = directory.appendingPathComponent(image.payloadPath!)
        try store.delete(id: image.id)
        require(!FileManager.default.fileExists(atPath: imageURL.path))
        require(try store.items().isEmpty)
    }

    private static func testClearAll() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let pinned = try store.save(.text("pinned"))
        try store.setPinned(true, id: pinned.id)
        _ = try store.save(.text("normal"))
        try store.clearAll()
        require(try store.items().isEmpty)
    }

    private static func testCaptureGate() {
        var gate = CaptureGate(initialChangeCount: 7)
        let noExclusions: Set<String> = []
        require(!gate.shouldCapture(changeCount: 7, recordingEnabled: true, paused: false,
                                    sourceBundleID: nil, excludedBundleIDs: noExclusions))
        require(gate.shouldCapture(changeCount: 8, recordingEnabled: true, paused: false,
                                   sourceBundleID: nil, excludedBundleIDs: noExclusions))
        gate.markSelfWrite(9)
        require(!gate.shouldCapture(changeCount: 9, recordingEnabled: true, paused: false,
                                    sourceBundleID: nil, excludedBundleIDs: noExclusions))
        gate.reset(to: 12)
        require(!gate.shouldCapture(changeCount: 12, recordingEnabled: true, paused: false,
                                    sourceBundleID: nil, excludedBundleIDs: noExclusions))
        require(!gate.shouldCapture(changeCount: 13, recordingEnabled: true, paused: true,
                                    sourceBundleID: nil, excludedBundleIDs: noExclusions))
        require(!gate.shouldCapture(changeCount: 14, recordingEnabled: true, paused: false,
                                    sourceBundleID: "com.example.private", excludedBundleIDs: ["com.example.private"]))
        require(gate.shouldCapture(changeCount: 15, recordingEnabled: true, paused: false,
                                   sourceBundleID: "com.example.public", excludedBundleIDs: ["com.example.private"]))
    }

    private static func testCountLimit() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let now = Date()
        for number in 0...1000 {
            _ = try store.save(.text("item-\(number)"), at: now.addingTimeInterval(Double(number)))
        }
        let items = try store.items()
        require(items.count == 1000)
        require(!items.contains { $0.text == "item-0" })
    }
}
