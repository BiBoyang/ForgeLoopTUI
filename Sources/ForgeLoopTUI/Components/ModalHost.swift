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
