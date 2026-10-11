import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable {
    case text
    case url
    case image
}

public enum ClipPayload: Equatable {
    case text(String)
    case url(String)
    case image(Data)

    public var kind: ClipKind {
        switch self {
        case .text: return .text
        case .url: return .url
        case .image: return .image
        }
    }

    public var text: String? {
        switch self {
        case .text(let value), .url(let value): return value
        case .image: return nil
        }
    }

    public var byteCount: Int {
        switch self {
        case .text(let value), .url(let value): return value.utf8.count
        case .image(let data): return data.count
        }
    }

    public var contentHash: String {
        let bytes: Data
        switch self {
        case .text(let value), .url(let value): bytes = Data(value.utf8)
        case .image(let data): bytes = data
        }
        var input = Data(kind.rawValue.utf8)
        input.append(0)
        input.append(bytes)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    public static func normalizedText(_ raw: String) -> ClipPayload? {
        guard !raw.isEmpty, raw.utf8.count <= 20 * 1_024 * 1_024 else { return nil }
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           url.host != nil, !candidate.contains(where: \.isNewline) {
            return .url(candidate)
        }
        return .text(raw)
    }
}

public struct ClipItem: Identifiable, Equatable {
    public let id: UUID
    public let kind: ClipKind
    public let text: String?
    public let sourceBundleID: String?
    public let contentHash: String
    public let createdAt: Date
    public let lastCopiedAt: Date
    public let copyCount: Int
    public let isPinned: Bool
    public let payloadPath: String?

    public init(id: UUID, kind: ClipKind, text: String?, sourceBundleID: String?, contentHash: String,
                createdAt: Date, lastCopiedAt: Date, copyCount: Int, isPinned: Bool, payloadPath: String?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.sourceBundleID = sourceBundleID
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.isPinned = isPinned
        self.payloadPath = payloadPath
    }
}
