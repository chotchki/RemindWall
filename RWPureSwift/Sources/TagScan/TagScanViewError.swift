import Foundation

public enum TagScanViewError: Equatable, Error, Hashable {
    case unknownTag
    case wrongScanWindow
    case noDevice
    case unknown(String)
}
