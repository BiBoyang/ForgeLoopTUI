import Foundation

/// `liveBudget` 计入方式。
///
/// - ``logicalLines``: 用逻辑行数(`live.count`)作为预算。
///   适合输入框、状态行等可控行数的场景,亦是历史默认。
/// - ``physicalRows``: 用 `physicalRows(for:width:)` 的物理行数累加作为预算。
///   适合 streaming/markdown 等会发生 wrap 的内容,以及窄终端。
///
/// 稳定等级: Provisional。
public enum LiveBudgetMode: Sendable, Equatable {
    case logicalLines
    case physicalRows
}

/// `LiveBudgetPlanner` 把"live 超出预算"这件事统一成一次沉降决策。
///
/// 规则:
/// - 只从 live 头部向 committed 尾部沉降,顺序不变。
/// - 不做"部分行切割";一行要么整行留在 live,要么整行被沉降。
/// - 至少保留 1 行 live,即使该行的物理行数已经超过 budget。
///
/// 当 ``mode`` 为 ``LiveBudgetMode/physicalRows`` 时,沉降基于
/// `physicalRows(for:width:)` 计算 wrap 后的行数;只要 `width` 改变,同样的内容
/// 也会得到不同的沉降结果,这正是"resize 后下一帧自然重新沉降"的来源。
///
/// 该类型对外不可见(internal),由 ``TUI`` 与 ``FrameComposer`` 共享同一份算法。
internal struct LiveBudgetPlanner: Sendable {
    let mode: LiveBudgetMode
    let budget: Int
    let width: Int

    struct Plan: Sendable, Equatable {
        let committed: [String]
        let live: [String]
    }

    func plan(committed: [String], live: [String]) -> Plan {
        guard budget > 0, !live.isEmpty else {
            return Plan(committed: committed, live: live)
        }
        // O(n) prefix-accumulation:
        // 1) compute per-line row cost once (avoids repeated visibleWidth scans);
        // 2) advance a single head pointer until removing one more line would
        //    either leave fewer than one live line or already fit the budget.
        // Replaces the previous O(n²) loop that called `totalRows` and
        // `removeFirst()` on every iteration.
        let rowsPerLine = live.map { rows(for: $0) }
        var remaining = rowsPerLine.reduce(0, +)
        if remaining <= budget {
            return Plan(committed: committed, live: live)
        }

        // Invariant: keep at least one live line so a diff/cursor anchor exists.
        let maxSettle = live.count - 1
        var settleCount = 0
        while settleCount < maxSettle, remaining > budget {
            remaining -= rowsPerLine[settleCount]
            settleCount += 1
        }

        guard settleCount > 0 else {
            // Single-line case where the lone line itself exceeds budget;
            // nothing to settle, the line stays in live.
            return Plan(committed: committed, live: live)
        }

        let settled = Array(live.prefix(settleCount))
        let remainingLive = Array(live.dropFirst(settleCount))
        return Plan(committed: committed + settled, live: remainingLive)
    }

    private func rows(for line: String) -> Int {
        switch mode {
        case .logicalLines:
            return 1
        case .physicalRows:
            return physicalRows(for: line, width: width)
        }
    }
}
