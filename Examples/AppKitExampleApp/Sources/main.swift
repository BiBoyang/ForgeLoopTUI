import AppKit
import Foundation
import ForgeLoopTUI

@MainActor
final class ExampleAppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let adapter = HybridRenderAdapter()
    private let eventAdapter = AppKitEventAdapter()

    private var window: NSWindow?
    private var titleLabel: NSTextField?
    private var subtitleLabel: NSTextField?
    private var statusLabel: NSTextField?
    private var queueLabel: NSTextField?
    private var transcriptView: NSTextView?
    private var inputView: NSTextView?
    private var keyHintLabel: NSTextField?
    private var keyMonitor: Any?

    private var inputState = MultiLineInputState(viewport: Viewport(width: 60))
    private var transcriptLines: [String] = [
        "Assistant: ForgeLoopTUI AppKit bridge is ready.",
        "Assistant: Type a prompt and press Enter to submit.",
    ]
    private var submittedCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        installKeyMonitor()
        updateViewportWidth()
        render()

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeKeyMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    func windowDidResize(_ notification: Notification) {
        updateViewportWidth()
        render()
    }

    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ForgeLoopTUI ExampleApp"
        window.delegate = self
        window.center()

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "ForgeLoopTUI AppKit Example")
        title.font = NSFont.systemFont(ofSize: 24, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Single-source state via HybridRenderAdapter.appKitProjection(of:)")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        let status = NSTextField(labelWithString: "")
        status.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let queue = NSTextField(labelWithString: "")
        queue.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        queue.textColor = .secondaryLabelColor

        let transcript = NSTextView()
        transcript.isEditable = false
        transcript.isSelectable = true
        transcript.usesAdaptiveColorMappingForDarkAppearance = true
        transcript.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        transcript.textContainerInset = NSSize(width: 8, height: 8)

        let transcriptScroll = NSScrollView()
        transcriptScroll.borderType = .bezelBorder
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.documentView = transcript
        transcriptScroll.translatesAutoresizingMaskIntoConstraints = false

        let inputHeader = NSTextField(labelWithString: "Input")
        inputHeader.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        let input = NSTextView()
        input.isEditable = false
        input.isSelectable = false
        input.drawsBackground = true
        input.backgroundColor = .controlBackgroundColor
        input.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        input.textContainerInset = NSSize(width: 8, height: 8)

        let inputScroll = NSScrollView()
        inputScroll.borderType = .bezelBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.documentView = input
        inputScroll.translatesAutoresizingMaskIntoConstraints = false

        let hints = NSTextField(labelWithString: "Enter submit | Option+Enter newline | Arrow/Home/End move | Esc clear | Ctrl-C quit")
        hints.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hints.textColor = .secondaryLabelColor

        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(status)
        root.addArrangedSubview(queue)
        root.addArrangedSubview(transcriptScroll)
        root.addArrangedSubview(inputHeader)
        root.addArrangedSubview(inputScroll)
        root.addArrangedSubview(hints)

        guard let contentView = window.contentView else {
            fatalError("NSWindow contentView is missing")
        }

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            transcriptScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])

        self.window = window
        self.titleLabel = title
        self.subtitleLabel = subtitle
        self.statusLabel = status
        self.queueLabel = queue
        self.transcriptView = transcript
        self.inputView = input
        self.keyHintLabel = hints
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            guard let keyEvent = self.eventAdapter.keyEvent(from: event) else { return event }
            guard self.handleKeyEvent(keyEvent) else { return event }
            self.updateViewportWidth()
            self.render()
            return nil
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .character(let ch):
            return handleCharacter(ch, modifiers: event.modifiers)
        case .paste(let text):
            inputState.handle(.insertText(text))
            return true
        case .enter:
            if event.modifiers.contains(.alt) {
                inputState.handle(.insertNewline)
            } else {
                submitInput()
            }
            return true
        case .backspace:
            inputState.handle(.backspace)
            return true
        case .delete:
            inputState.handle(.deleteForward)
            return true
        case .left:
            inputState.handle(.moveLeft)
            return true
        case .right:
            inputState.handle(.moveRight)
            return true
        case .up:
            inputState.handle(.moveUp)
            return true
        case .down:
            inputState.handle(.moveDown)
            return true
        case .home:
            inputState.handle(.moveToLineStart)
            return true
        case .end:
            inputState.handle(.moveToLineEnd)
            return true
        case .escape:
            inputState.handle(.clear)
            return true
        default:
            return false
        }
    }

    private func handleCharacter(_ ch: Character, modifiers: Modifiers) -> Bool {
        if modifiers.isEmpty {
            inputState.handle(.insert(ch))
            return true
        }

        if modifiers == .ctrl {
            let command = String(ch).uppercased()
            switch command {
            case "A":
                inputState.handle(.moveToLineStart)
                return true
            case "C":
                NSApp.terminate(nil)
                return true
            case "E":
                inputState.handle(.moveToLineEnd)
                return true
            case "K":
                inputState.handle(.killToLineEnd)
                return true
            case "O":
                inputState.handle(.insertNewline)
                return true
            case "U":
                inputState.handle(.killToLineStart)
                return true
            default:
                return false
            }
        }

        return false
    }

    private func submitInput() {
        let submitted = inputState.text
        let normalized = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        inputState.handle(.clear)

        guard !normalized.isEmpty else { return }

        submittedCount += 1
        let lines = splitLines(submitted)
        transcriptLines.append(contentsOf: lines.map { "You: \($0)" })
        transcriptLines.append("Assistant: Echo #\(submittedCount): \(normalized)")
        transcriptLines.append("Assistant: mixed-width sample -> ab中文cd ✅")
    }

    private func splitLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func updateViewportWidth() {
        guard let inputView else { return }
        let font = inputView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let cellWidth = max(1, "W".size(withAttributes: [.font: font]).width)
        let contentWidth = inputView.enclosingScrollView?.contentSize.width ?? 600
        let estimatedColumns = max(1, Int(contentWidth / cellWidth) - 2)

        if inputState.viewport?.width != estimatedColumns {
            inputState.setViewport(Viewport(width: estimatedColumns))
        }
    }

    private func render() {
        let state = makeHybridState()
        let panel = adapter.appKitProjection(of: state)
        apply(panel)
    }

    private func makeHybridState() -> HybridRenderState {
        let transcriptCount = transcriptLines.filter { $0.hasPrefix("You:") }.count
        let status = "status: ready | messages: \(transcriptCount)"
        let queue = "queue: none"

        return HybridRenderState(
            headerLines: [],
            transcriptLines: transcriptLines,
            queueLines: [queue],
            statusLines: [status],
            inputLines: inputState.lines,
            pinnedTranscriptRange: nil,
            panelMeta: PanelMeta(
                title: "ForgeLoopTUI AppKit Example",
                summary: "\(transcriptCount) submitted message(s)",
                statusBadge: "Ready",
                isActive: false,
                subtitle: "SPM local package dependency",
                accessoryBadge: "Example"
            )
        )
    }

    private func apply(_ panel: AppKitPanelState) {
        titleLabel?.stringValue = panel.meta.title
        subtitleLabel?.stringValue = "\(panel.meta.summary) | \(panel.meta.subtitle ?? "")"
        statusLabel?.stringValue = panel.statusLines.joined(separator: " | ")
        queueLabel?.stringValue = panel.queueLines.joined(separator: " | ")

        transcriptView?.string = panel.transcriptLines.joined(separator: "\n")
        transcriptView?.scrollToEndOfDocument(nil)

        inputView?.string = panel.inputLines.joined(separator: "\n")
        inputView?.scrollToEndOfDocument(nil)

        if panel.inputFocused {
            keyHintLabel?.stringValue = "Enter submit | Option+Enter newline | Arrow/Home/End move | Esc clear | Ctrl-C quit"
        } else {
            keyHintLabel?.stringValue = "Start typing to focus input | Ctrl-C quit"
        }
    }
}

let app = NSApplication.shared
let delegate = ExampleAppController()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
