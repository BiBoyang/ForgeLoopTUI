import XCTest
@testable import ForgeLoopTUI

/// TASK-21 回归测试：流式回放（blockStart → 累积 blockUpdate → blockEnd）
/// 终态必须与一次性静态 blockEnd 渲染逐行一致。覆盖最小表格逐字符回放与
/// 全量 fixture 多 chunk 粒度（1/2/3/5/7/11）。
final class ScratchProbeTests: XCTestCase {
    @MainActor
    private func replay(
        markdown: String,
        chunk: Int
    ) -> (final: [String], staticRender: [String]) {
        let chars = Array(markdown)

        // 静态基线：一次性 blockEnd 全文。
        let staticRenderer = TranscriptRenderer()
        staticRenderer.applyCore(.blockStart(id: "static"))
        staticRenderer.applyCore(.blockEnd(id: "static", lines: [markdown], footer: nil))
        let staticRender = staticRenderer.transcriptLines

        // 流式回放：累积快照，模拟 MinimalAIApp 的 blockUpdate(lines: [全文])。
        let streaming = TranscriptRenderer()
        streaming.applyCore(.blockStart(id: "assistant"))
        var acc = ""
        var i = 0
        while i < chars.count {
            let end = min(i + chunk, chars.count)
            acc += String(chars[i..<end])
            streaming.applyCore(.blockUpdate(id: "assistant", lines: [acc]))
            i = end
        }
        streaming.applyCore(.blockEnd(id: "assistant", lines: [markdown], footer: nil))
        return (streaming.transcriptLines, staticRender)
    }

    private func firstDiff(_ a: [String], _ b: [String]) -> Int? {
        let n = min(a.count, b.count)
        for i in 0..<n where a[i] != b[i] { return i }
        return a.count == b.count ? nil : n
    }

    private func context(_ lines: [String], _ index: Int) -> String {
        let lo = max(0, index - 3)
        let hi = min(lines.count, index + 4)
        var out = ""
        for i in lo..<hi {
            let mark = i == index ? ">>" : "  "
            out += "\(mark) [\(i)] \(lines[i])\n"
        }
        return out
    }

    /// 探针 1：最小表格序列，逐字符回放，终态 vs 静态。
    @MainActor
    func testProbeMinimalTablePerChar() {
        let md = """
        intro

        | 姓名 | 年龄 |
        |:--:|:--:|
        | 张三 | 28 |
        | 李四 | 32 |

        after

        """
        let (final, staticRender) = replay(markdown: md, chunk: 1)
        if let d = firstDiff(final, staticRender) {
            print("=== MINIMAL TABLE: DIVERGES AT \(d); final=\(final.count) static=\(staticRender.count) ===")
            print("--- streaming final ---\n\(context(final, d))")
            print("--- static ---\n\(context(staticRender, d))")
            XCTFail("minimal table replay diverges at line \(d)")
        } else {
            print("=== MINIMAL TABLE: converged, \(final.count) lines ===")
        }
    }

    /// 探针 3：多 chunk 粒度 × 全量 fixture，终态 vs 静态；dump 终态文本。
    @MainActor
    func testProbeGranularities() {
        let md = StreamingGarbleFixture.markdown
        let staticRenderer = TranscriptRenderer()
        staticRenderer.applyCore(.blockStart(id: "static"))
        staticRenderer.applyCore(.blockEnd(id: "static", lines: [md], footer: nil))
        let staticRender = staticRenderer.transcriptLines
        try? staticRender.joined(separator: "\n").write(toFile: "/tmp/task21-static.txt", atomically: true, encoding: .utf8)

        for chunk in [1, 2, 3, 5, 7, 11] {
            let (final, _) = replay(markdown: md, chunk: chunk)
            let d = firstDiff(final, staticRender)
            let label = d == nil ? "converged" : "DIVERGES@\(d!)"
            print("=== chunk=\(chunk): final=\(final.count) static=\(staticRender.count) -> \(label) ===")
            if chunk == 1 {
                try? final.joined(separator: "\n").write(toFile: "/tmp/task21-streaming-final.txt", atomically: true, encoding: .utf8)
            }
        }
    }
}
