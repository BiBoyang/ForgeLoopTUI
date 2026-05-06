import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum RenderStrategy: Sendable {
    case legacyAbsolute
    case inlineAnchor
}
