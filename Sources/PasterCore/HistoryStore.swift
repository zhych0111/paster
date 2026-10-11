import Foundation
import SQLite3

public enum HistoryStoreError: Error, LocalizedError {
    case database(String)
    case invalidPayload
    case missingPayload

    public var errorDescription: String? {
        switch self {
        case .database(let message): return "History database error: \(message)"
        case .invalidPayload: return "The clipboard content is empty or too large."
        case .missingPayload: return "The saved image is missing."
        }
    }
}

public final class HistoryStore {
    private let directory: URL
    private let imagesDirectory: URL
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(directory: URL) throws {
        self.directory = directory
        self.imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("history.sqlite3").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw HistoryStoreError.database(String(cString: sqlite3_errmsg(db)))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        try execute("PRAGMA journal_mode=WAL")
        let version = try schemaVersion()
        guard version <= 1 else { throw HistoryStoreError.database("Unsupported schema version \(version)") }
        try execute("CREATE TABLE IF NOT EXISTS clips (id TEXT PRIMARY KEY, kind TEXT NOT NULL, text TEXT, source_bundle_id TEXT, content_hash TEXT NOT NULL UNIQUE, created_at REAL NOT NULL, last_copied_at REAL NOT NULL, copy_count INTEGER NOT NULL, is_pinned INTEGER NOT NULL DEFAULT 0, payload_path TEXT)")
        try execute("CREATE INDEX IF NOT EXISTS clips_recent ON clips (is_pinned DESC, last_copied_at DESC)")
        if version == 0 { try execute("PRAGMA user_version=1") }
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    public func save(_ payload: ClipPayload, sourceBundleID: String? = nil, at date: Date = Date(),
                     retentionDays: Int = 30) throws -> ClipItem {
        guard payload.byteCount > 0, payload.byteCount <= 20 * 1_024 * 1_024 else {
            throw HistoryStoreError.invalidPayload
        }
        let hash = payload.contentHash
        if let existing = try item(withHash: hash) {
            let statement = try prepare("UPDATE clips SET last_copied_at=?, copy_count=copy_count+1, source_bundle_id=? WHERE id=?")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            bind(sourceBundleID, to: 2, in: statement)
            bind(existing.id.uuidString, to: 3, in: statement)
            try stepDone(statement)
            try cleanup(retentionDays: retentionDays, now: date)
            return try item(withHash: hash)!
        }

        let id = UUID()
        var relativePath: String?
        if case .image(let data) = payload {
            relativePath = "images/\(id.uuidString).png"
            let file = directory.appendingPathComponent(relativePath!)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        do {
            let statement = try prepare("INSERT INTO clips (id,kind,text,source_bundle_id,content_hash,created_at,last_copied_at,copy_count,is_pinned,payload_path) VALUES (?,?,?,?,?,?,?,?,?,?)")
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, to: 1, in: statement)
            bind(payload.kind.rawValue, to: 2, in: statement)
            bind(payload.text, to: 3, in: statement)
            bind(sourceBundleID, to: 4, in: statement)
            bind(hash, to: 5, in: statement)
            sqlite3_bind_double(statement, 6, date.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, date.timeIntervalSince1970)
            sqlite3_bind_int(statement, 8, 1)
            sqlite3_bind_int(statement, 9, 0)
            bind(relativePath, to: 10, in: statement)
            try stepDone(statement)
        } catch {
            if let relativePath { try? FileManager.default.removeItem(at: directory.appendingPathComponent(relativePath)) }
            throw error
        }
        try cleanup(retentionDays: retentionDays, now: date)
        return try item(withHash: hash)!
    }

    public func items(search: String = "") throws -> [ClipItem] {
        let statement = try prepare("SELECT id,kind,text,source_bundle_id,content_hash,created_at,last_copied_at,copy_count,is_pinned,payload_path FROM clips ORDER BY is_pinned DESC, last_copied_at DESC")
        defer { sqlite3_finalize(statement) }
        var result: [ClipItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = decode(statement) { result.append(item) }
        }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return result }
        return result.filter { $0.text?.localizedCaseInsensitiveContains(term) == true }
    }

    public func payload(for item: ClipItem) throws -> ClipPayload {
        switch item.kind {
        case .text: return .text(item.text ?? "")
        case .url: return .url(item.text ?? "")
        case .image:
            guard let path = item.payloadPath,
                  let data = try? Data(contentsOf: directory.appendingPathComponent(path)) else {
                throw HistoryStoreError.missingPayload
            }
            return .image(data)
        }
    }

    public func setPinned(_ pinned: Bool, id: UUID) throws {
        let statement = try prepare("UPDATE clips SET is_pinned=? WHERE id=?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, pinned ? 1 : 0)
        bind(id.uuidString, to: 2, in: statement)
        try stepDone(statement)
    }

    public func touch(id: UUID, at date: Date = Date()) throws {
        let statement = try prepare("UPDATE clips SET last_copied_at=?, copy_count=copy_count+1 WHERE id=?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        bind(id.uuidString, to: 2, in: statement)
        try stepDone(statement)
    }

    public func delete(id: UUID) throws {
        guard let item = try items().first(where: { $0.id == id }) else { return }
        let statement = try prepare("DELETE FROM clips WHERE id=?")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        try stepDone(statement)
        if let path = item.payloadPath { try? FileManager.default.removeItem(at: directory.appendingPathComponent(path)) }
    }

    public func clearAll() throws {
        let paths = try items().compactMap(\.payloadPath)
        try execute("DELETE FROM clips")
        for path in paths { try? FileManager.default.removeItem(at: directory.appendingPathComponent(path)) }
    }

    public func cleanup(retentionDays: Int, now: Date = Date()) throws {
        let unpinned = try items().filter { !$0.isPinned }
        let cutoff = now.addingTimeInterval(-Double(max(1, retentionDays)) * 86_400)
        for (index, item) in unpinned.enumerated() where item.lastCopiedAt < cutoff || index >= 1000 {
            try delete(id: item.id)
        }
    }

    private func item(withHash hash: String) throws -> ClipItem? {
        let statement = try prepare("SELECT id,kind,text,source_bundle_id,content_hash,created_at,last_copied_at,copy_count,is_pinned,payload_path FROM clips WHERE content_hash=?")
        defer { sqlite3_finalize(statement) }
        bind(hash, to: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW ? decode(statement) : nil
    }

    private func decode(_ statement: OpaquePointer?) -> ClipItem? {
        guard let idString = string(statement, 0), let id = UUID(uuidString: idString),
              let kindString = string(statement, 1), let kind = ClipKind(rawValue: kindString),
              let hash = string(statement, 4) else { return nil }
        return ClipItem(id: id, kind: kind, text: string(statement, 2), sourceBundleID: string(statement, 3),
                        contentHash: hash, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                        lastCopiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                        copyCount: Int(sqlite3_column_int(statement, 7)), isPinned: sqlite3_column_int(statement, 8) != 0,
                        payloadPath: string(statement, 9))
    }

    private func string(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, index))
        return String(bytes: UnsafeBufferPointer(start: pointer, count: length), encoding: .utf8)
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer?) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), transient) }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.database(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw HistoryStoreError.database(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryStoreError.database(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func schemaVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HistoryStoreError.database("Unable to read schema version")
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}
