import Foundation

public struct ModalRenderer: Sendable {
    public let styleMode: Style.RenderingMode

    public init(styleMode: Style.RenderingMode = .automatic) {
        self.styleMode = styleMode
    }

    public func render(title: String, body: [String], footer: String? = nil) -> [String] {
        var lines: [String] = [Style.header(title, mode: styleMode)]

        if !body.isEmpty {
            lines.append("")
            lines.append(contentsOf: body)
        }

        if let footer, !footer.isEmpty {
            lines.append("")
            lines.append(Style.dimmed(footer, mode: styleMode))
        }

        return lines
    }
}

public struct ListPickerItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

public enum ListPickerAction: Sendable, Equatable {
    case moveUp
    case moveDown
    case select(index: Int)
    case confirm
    case cancel
}

public enum ListPickerOutcome: Sendable, Equatable {
    case none
    case confirmed(ListPickerItem)
    case cancelled
}

public struct ListPickerState: Sendable, Equatable {
    public let title: String
    public let subtitle: String?
    public let footer: String
    public let items: [ListPickerItem]
    public private(set) var selectedIndex: Int

    public init(
        title: String,
        subtitle: String? = nil,
        items: [ListPickerItem],
        selectedIndex: Int = 0,
        footer: String = "(↑↓ to select, Enter to confirm, Esc to cancel)"
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.items = items
        if items.isEmpty {
            self.selectedIndex = 0
        } else {
            self.selectedIndex = min(max(0, selectedIndex), items.count - 1)
        }
    }

    public var selectedItem: ListPickerItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public mutating func handle(_ action: ListPickerAction) -> ListPickerOutcome {
        switch action {
        case .moveUp:
            guard !items.isEmpty else { return .none }
            selectedIndex = max(0, selectedIndex - 1)
            return .none
        case .moveDown:
            guard !items.isEmpty else { return .none }
            selectedIndex = min(items.count - 1, selectedIndex + 1)
            return .none
        case .select(let index):
            guard items.indices.contains(index) else { return .none }
            selectedIndex = index
            return .none
        case .confirm:
            guard let item = selectedItem else { return .none }
            return .confirmed(item)
        case .cancel:
            return .cancelled
        }
    }
}

public struct ListPickerRenderer: Sendable {
    public let styleMode: Style.RenderingMode
    private let modalRenderer: ModalRenderer

    public init(styleMode: Style.RenderingMode = .automatic) {
        self.styleMode = styleMode
        self.modalRenderer = ModalRenderer(styleMode: styleMode)
    }

    public func render(state: ListPickerState) -> [String] {
        var body: [String] = []

        if let subtitle = state.subtitle, !subtitle.isEmpty {
            body.append(Style.dimmed(subtitle, mode: styleMode))
            if !state.items.isEmpty {
                body.append("")
            }
        }

        if state.items.isEmpty {
            body.append(Style.dimmed("(no options)", mode: styleMode))
        } else {
            for (index, item) in state.items.enumerated() {
                let symbol = index == state.selectedIndex ? "● " : "○ "
                let titleLine = symbol + item.title
                if index == state.selectedIndex {
                    body.append(Style.selection(titleLine, mode: styleMode))
                } else {
                    body.append(titleLine)
                }
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    body.append(Style.dimmed("  \(subtitle)", mode: styleMode))
                }
            }
        }

        return modalRenderer.render(title: state.title, body: body, footer: state.footer)
    }
}
