import Foundation
import SwiftData

@Model
public class Settings: Equatable {
    @Attribute(.unique) public var id: Int = 1
    public var selectedAlbumId: String?
    public var selectedCalendarId: String?

    public init(
        selectedAlbumId: String? = nil,
        selectedCalendarId: String? = nil
    ) {
        self.selectedAlbumId = selectedAlbumId
        self.selectedCalendarId = selectedCalendarId
    }
}
