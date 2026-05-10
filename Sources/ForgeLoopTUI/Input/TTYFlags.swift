import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public func hasUTF8EraseFlag(_ inputFlags: tcflag_t) -> Bool {
    (inputFlags & tcflag_t(IUTF8)) != 0
}

public func withUTF8EraseFlag(_ inputFlags: tcflag_t) -> tcflag_t {
    inputFlags | tcflag_t(IUTF8)
}
