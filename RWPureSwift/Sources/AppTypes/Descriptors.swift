import Tagged

/// Portable stand-in for an album pick: the album's title. Photo-library
/// local identifiers don't travel between devices, so this is what syncs;
/// each device resolves it back to its own local identifier. If two albums
/// share a title, resolution takes the first match.
public enum AlbumDescriptorTag {}
public typealias AlbumDescriptor = Tagged<AlbumDescriptorTag, String>

/// Portable stand-in for a calendar pick: "title|sourceTitle" (the source
/// disambiguates a "Home" calendar in iCloud from one on-device).
/// Split happens at the LAST pipe — titles may contain pipes, source names
/// realistically don't.
public enum CalendarDescriptorTag {}
public typealias CalendarDescriptor = Tagged<CalendarDescriptorTag, String>

extension CalendarDescriptor {
    /// A deliberate "None" pick. Distinct from an absent row: absent means
    /// never-configured (a pre-descriptor device backfills from its cached
    /// id), noSelection means some device chose no calendar.
    public static let noSelection = CalendarDescriptor(rawValue: "")

    public init(title: String, sourceTitle: String) {
        self.init(rawValue: "\(title)|\(sourceTitle)")
    }

    public var title: String {
        guard let split = rawValue.lastIndex(of: "|") else { return rawValue }
        return String(rawValue[..<split])
    }

    public var sourceTitle: String {
        guard let split = rawValue.lastIndex(of: "|") else { return "" }
        return String(rawValue[rawValue.index(after: split)...])
    }
}
