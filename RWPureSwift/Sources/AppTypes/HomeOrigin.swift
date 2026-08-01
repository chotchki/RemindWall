import Tagged

/// The drive-time origin, picked once in settings and synced.
/// Encoding: "<latitude>,<longitude>|<display name>" - coordinates before the
/// FIRST pipe, so the name may contain pipes.
public enum HomeOriginTag {}
public typealias HomeOrigin = Tagged<HomeOriginTag, String>

extension HomeOrigin {
    public init(latitude: Double, longitude: Double, name: String) {
        self.init(rawValue: "\(latitude),\(longitude)|\(name)")
    }

    public var latitude: Double? { coordinate(0) }
    public var longitude: Double? { coordinate(1) }

    public var name: String {
        guard let split = rawValue.firstIndex(of: "|") else { return "" }
        return String(rawValue[rawValue.index(after: split)...])
    }

    private func coordinate(_ index: Int) -> Double? {
        guard let head = rawValue.split(separator: "|", maxSplits: 1).first else { return nil }
        let coords = head.split(separator: ",")
        guard coords.count == 2 else { return nil }
        return Double(coords[index])
    }
}
