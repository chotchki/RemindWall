///From: https://stackoverflow.com/a/33548238

import Foundation

extension StringProtocol {
    public var hexa: [UInt8] {
        var startIndex = self.startIndex
        return (0..<count/2).compactMap { _ in
            let endIndex = index(after: startIndex)
            defer { startIndex = index(after: endIndex) }
            return UInt8(self[startIndex...endIndex], radix: 16)
        }
    }
}
extension DataProtocol {
    public var data: Data { .init(self) }
    public var hexa: String { map { .init(format: "%02x", $0) }.joined() }
}
