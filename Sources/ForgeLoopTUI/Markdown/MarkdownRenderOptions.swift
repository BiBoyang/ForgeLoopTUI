import Foundation

public struct MarkdownRenderOptions: Sendable, Equatable {
    public var tablePolicy: TableRenderPolicy
    public var tableStreamingBehavior: TableStreamingBehavior

    public init(
        tablePolicy: TableRenderPolicy = .default,
        tableStreamingBehavior: TableStreamingBehavior = .monotonic
    ) {
        self.tablePolicy = tablePolicy
        self.tableStreamingBehavior = tableStreamingBehavior
    }
}

public struct TableRenderPolicy: Sendable, Equatable {
    public var maxRenderedWidth: Int
    public var minColumnWidth: Int
    public var maxColumnWidth: Int?
    public var truncationIndicator: String
    public var overflowBehavior: TableOverflowBehavior
    public var wideTableStrategy: WideTableStrategy
    public var autoReadableTruncatedCellThreshold: Double
    public var autoReadableTrimmedWidthThreshold: Double

    /// Library default keeps existing zero-regression behavior (`alwaysBox`).
    /// Consumers opt into `autoReadable` explicitly.
    public static let `default` = TableRenderPolicy(
        maxRenderedWidth: 80,
        minColumnWidth: 6,
        maxColumnWidth: 24,
        truncationIndicator: "…",
        overflowBehavior: .compactThenTruncateThenDegrade,
        wideTableStrategy: .alwaysBox,
        autoReadableTruncatedCellThreshold: 0.4,
        autoReadableTrimmedWidthThreshold: 0.3
    )

    public init(
        maxRenderedWidth: Int = 80,
        minColumnWidth: Int = 6,
        maxColumnWidth: Int? = 24,
        truncationIndicator: String = "…",
        overflowBehavior: TableOverflowBehavior = .compactThenTruncateThenDegrade,
        wideTableStrategy: WideTableStrategy = .alwaysBox,
        autoReadableTruncatedCellThreshold: Double = 0.4,
        autoReadableTrimmedWidthThreshold: Double = 0.3
    ) {
        self.maxRenderedWidth = maxRenderedWidth
        self.minColumnWidth = minColumnWidth
        self.maxColumnWidth = maxColumnWidth
        self.truncationIndicator = truncationIndicator.isEmpty ? "…" : truncationIndicator
        self.overflowBehavior = overflowBehavior
        self.wideTableStrategy = wideTableStrategy
        self.autoReadableTruncatedCellThreshold = autoReadableTruncatedCellThreshold
        self.autoReadableTrimmedWidthThreshold = autoReadableTrimmedWidthThreshold
    }
}

public enum TableOverflowBehavior: Sendable, Equatable {
    case degradeImmediately
    case compactThenTruncateThenDegrade
}

/// Controls how wide tables are presented when box-drawing readability suffers.
public enum WideTableStrategy: Sendable, Equatable {
    /// Always render tables as box-drawing tables, even when heavily truncated.
    case alwaysBox
    /// Degrade to raw markdown when readability would be poor due to excessive truncation.
    case autoReadable
}

/// Controls how streaming markdown tables are rendered before completion.
public enum TableStreamingBehavior: Sendable, Equatable {
    /// Parse and render any currently valid table rows without regressing
    /// to raw markdown while the last row is still streaming.
    case monotonic

    /// Keep raw markdown until the current table block is fully terminated.
    case strict
}
