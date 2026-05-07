import Foundation
import ForgeLoopTUI

final class Runner: @unchecked Sendable {
    private let lock = NSLock()
    private var _running = true
    var running: Bool {
        get { lock.withLock { _running } }
        set { lock.withLock { _running = newValue } }
    }
}

let runner = Runner()

let reader: InputReader
do {
    reader = try InputReader { events in
        for event in events {
            switch event.key {
            case .character("q") where event.modifiers.isEmpty:
                print("Quit")
                runner.running = false
            case .escape:
                print("Escape")
            case .paste(let text):
                print("Paste: \(text)")
            case .up:
                print("↑")
            case .down:
                print("↓")
            case .left:
                print("←")
            case .right:
                print("→")
            case .enter:
                print("Enter")
            case .tab:
                print("Tab")
            case .backspace:
                print("Backspace")
            case .character(let c):
                if event.modifiers.contains(.ctrl) {
                    print("Ctrl+\(c)")
                } else if event.modifiers.contains(.alt) {
                    print("Alt+\(c)")
                } else {
                    print("Char: \(c)")
                }
            default:
                print(event)
            }
        }
    }
} catch {
    print("Failed to create InputReader: \(error)")
    exit(1)
}

do {
    try reader.start()
} catch {
    print("Failed to start InputReader: \(error)")
    exit(1)
}

print("ForgeLoopTUI Input Demo started. Press 'q' to quit.")

while runner.running {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
}

reader.stop()
print("Bye")
