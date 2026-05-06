import Foundation

public struct ModalRenderer: Sendable {
    public let styleMode: Style.RenderingMode
    public let capability: TerminalCapability

    public init(styleMode: Style.RenderingMode = .automatic, capability: TerminalCapability = .truecolor) {
        self.styleMode = styleMode
        self.capability = capability
    }

    public func render(title: String, body: [String], footer: String? = nil) -> [String] {
        var lines: [String] = [Style.header(title, mode: styleMode, capability: capability)]

        if !body.isEmpty {
            lines.append("")
            lines.append(contentsOf: body)
        }

        if let footer, !footer.isEmpty {
            lines.append("")
            lines.append(Style.dimmed(footer, mode: styleMode, capability: capability))
        }

        return lines
    }
}
