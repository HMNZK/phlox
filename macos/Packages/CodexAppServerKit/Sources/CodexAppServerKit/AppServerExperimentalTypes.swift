// Codex app-server experimental API DTOs.
import Foundation

public struct ThreadBackgroundTerminalsListParams: Codable, Equatable, Sendable {
    public var threadId: String
    public var cursor: String? {
        get { cursorValue }
        set {
            cursorValue = newValue
            hasCursor = true
        }
    }
    public var limit: UInt32? {
        get { limitValue }
        set {
            limitValue = newValue
            hasLimit = true
        }
    }

    private var cursorValue: String?
    private var limitValue: UInt32?
    private var hasCursor: Bool
    private var hasLimit: Bool

    public init(threadId: String, cursor: String? = nil, limit: UInt32? = nil) {
        self.threadId = threadId
        self.cursorValue = cursor
        self.limitValue = limit
        self.hasCursor = cursor != nil
        self.hasLimit = limit != nil
    }

    private enum CodingKeys: String, CodingKey {
        case threadId
        case cursor
        case limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(String.self, forKey: .threadId)
        hasCursor = container.contains(.cursor)
        hasLimit = container.contains(.limit)
        cursorValue = try container.decodeIfPresent(String.self, forKey: .cursor)
        limitValue = try container.decodeIfPresent(UInt32.self, forKey: .limit)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadId, forKey: .threadId)
        if hasCursor { try container.encode(cursorValue, forKey: .cursor) }
        if hasLimit { try container.encode(limitValue, forKey: .limit) }
    }
}

public struct ThreadBackgroundTerminal: Codable, Equatable, Sendable {
    public var itemId: String
    public var processId: String
    public var command: String
    public var cwd: String
    public var osPid: UInt32? {
        get { osPidValue }
        set {
            osPidValue = newValue
            hasOsPid = true
        }
    }
    public var cpuPercent: Double? {
        get { cpuPercentValue }
        set {
            cpuPercentValue = newValue
            hasCpuPercent = true
        }
    }
    public var rssKb: UInt64? {
        get { rssKbValue }
        set {
            rssKbValue = newValue
            hasRssKb = true
        }
    }

    private var osPidValue: UInt32?
    private var cpuPercentValue: Double?
    private var rssKbValue: UInt64?
    private var hasOsPid: Bool
    private var hasCpuPercent: Bool
    private var hasRssKb: Bool

    public init(
        itemId: String,
        processId: String,
        command: String,
        cwd: String,
        osPid: UInt32? = nil,
        cpuPercent: Double? = nil,
        rssKb: UInt64? = nil
    ) {
        self.itemId = itemId
        self.processId = processId
        self.command = command
        self.cwd = cwd
        self.osPidValue = osPid
        self.cpuPercentValue = cpuPercent
        self.rssKbValue = rssKb
        self.hasOsPid = osPid != nil
        self.hasCpuPercent = cpuPercent != nil
        self.hasRssKb = rssKb != nil
    }

    private enum CodingKeys: String, CodingKey {
        case itemId
        case processId
        case command
        case cwd
        case osPid
        case cpuPercent
        case rssKb
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(String.self, forKey: .itemId)
        processId = try container.decode(String.self, forKey: .processId)
        command = try container.decode(String.self, forKey: .command)
        cwd = try container.decode(String.self, forKey: .cwd)
        hasOsPid = container.contains(.osPid)
        hasCpuPercent = container.contains(.cpuPercent)
        hasRssKb = container.contains(.rssKb)
        osPidValue = try container.decodeIfPresent(UInt32.self, forKey: .osPid)
        cpuPercentValue = try container.decodeIfPresent(Double.self, forKey: .cpuPercent)
        rssKbValue = try container.decodeIfPresent(UInt64.self, forKey: .rssKb)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(processId, forKey: .processId)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        if hasOsPid { try container.encode(osPidValue, forKey: .osPid) }
        if hasCpuPercent { try container.encode(cpuPercentValue, forKey: .cpuPercent) }
        if hasRssKb { try container.encode(rssKbValue, forKey: .rssKb) }
    }
}

public struct ThreadBackgroundTerminalsListResponse: Codable, Equatable, Sendable {
    public var data: [ThreadBackgroundTerminal]
    public var nextCursor: String? {
        get { nextCursorValue }
        set {
            nextCursorValue = newValue
            hasNextCursor = true
        }
    }

    private var nextCursorValue: String?
    private var hasNextCursor: Bool

    public init(data: [ThreadBackgroundTerminal], nextCursor: String? = nil) {
        self.data = data
        self.nextCursorValue = nextCursor
        self.hasNextCursor = nextCursor != nil
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ThreadBackgroundTerminal].self, forKey: .data)
        hasNextCursor = container.contains(.nextCursor)
        nextCursorValue = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        if hasNextCursor { try container.encode(nextCursorValue, forKey: .nextCursor) }
    }
}

public struct ThreadBackgroundTerminalsTerminateParams: Codable, Equatable, Sendable {
    public var processId: String
    public var threadId: String

    public init(threadId: String, processId: String) {
        self.processId = processId
        self.threadId = threadId
    }
}

public struct ThreadBackgroundTerminalsTerminateResponse: Codable, Equatable, Sendable {
    public var terminated: Bool

    public init(terminated: Bool) {
        self.terminated = terminated
    }
}
