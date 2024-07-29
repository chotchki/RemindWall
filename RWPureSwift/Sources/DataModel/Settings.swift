import Foundation
import SwiftData

@Model
public class Settings: Equatable {
    public var id: Int = 1
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

///Technique from here: https://stackoverflow.com/a/77775620
extension Settings {
    @MainActor
    public static var preview: ModelContainer {
        let container  = DataSchema.modelContainer
        container.mainContext.insert(Settings())
        return container
    }
}
