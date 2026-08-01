import AppTypes
import CalendarAsync
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import PhotoKitAsync

/// Keeps the device-local album/calendar ids in step with their synced
/// descriptors. Runs for the app's lifetime from AppNavigation:
///
/// - descriptor present -> resolve it to a local id and cache it; no local
///   match clears the stale id, which is what surfaces "pick again" in the
///   pickers (their needsRePick is descriptor-set-and-id-nil).
/// - descriptor absent but an id is cached -> backfill the descriptor from
///   the local pick, so a pre-descriptor kiosk publishes its configuration
///   without a re-pick (the id-side twin of the S1.2 seed).
/// - a deliberate calendar "None" syncs as `.noSelection`, distinct from
///   absent, so it clears other devices instead of triggering backfill.
///
/// Reconciliation is skipped entirely while the library/calendar isn't
/// authorized - an unauthorized device must never clear a good id.
@Reducer
public struct SettingsResolverFeature: Sendable {
    @Dependency(\.photoKitAlbums) var photoKitAlbums
    @Dependency(\.calendarAsync) var calendarAsync

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(ALBUM_SETTING_KEY)) var selectedAlbum: AlbumLocalId?
        @Shared(.syncedSetting(ALBUM_DESCRIPTOR_SETTING_KEY)) var albumDescriptor: AlbumDescriptor?
        @Shared(.appStorage(CALENDAR_SETTING_KEY)) var selectedCalendar: CalendarId?
        @Shared(.syncedSetting(CALENDAR_DESCRIPTOR_SETTING_KEY)) var calendarDescriptor: CalendarDescriptor?

        public init() {}
    }

    public enum Action {
        case start
        case stop
        case _albumDescriptorChanged(AlbumDescriptor?)
        case _calendarDescriptorChanged(CalendarDescriptor?)
        case _setAlbum(AlbumLocalId?)
        case _setAlbumDescriptor(AlbumDescriptor)
        case _setCalendar(CalendarId?)
        case _setCalendarDescriptor(CalendarDescriptor)
    }

    enum CancelID { case observation }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .start:
                // The publishers prepend the current value, so subscribing IS
                // the launch reconcile; later emissions cover remote writes.
                let albumDescriptor = state.$albumDescriptor
                let calendarDescriptor = state.$calendarDescriptor
                return .merge(
                    .publisher {
                        albumDescriptor.publisher.map(Action._albumDescriptorChanged)
                    },
                    .publisher {
                        calendarDescriptor.publisher.map(Action._calendarDescriptorChanged)
                    }
                )
                .cancellable(id: CancelID.observation, cancelInFlight: true)

            case .stop:
                return .cancel(id: CancelID.observation)

            case let ._albumDescriptorChanged(descriptor):
                guard photoKitAlbums.libraryAccess() == .authorized else { return .none }
                if let descriptor {
                    return .run { [photoKitAlbums] send in
                        await send(._setAlbum(photoKitAlbums.findAlbum(descriptor)))
                    }
                }
                guard let cached = state.selectedAlbum else { return .none }
                return .run { [photoKitAlbums] send in
                    guard let backfilled = await photoKitAlbums.albumDescriptor(cached) else { return }
                    await send(._setAlbumDescriptor(backfilled))
                }

            case let ._calendarDescriptorChanged(descriptor):
                guard calendarAsync.calendarAccess() == .fullAccess else { return .none }
                if let descriptor {
                    if descriptor == .noSelection {
                        return .run { send in await send(._setCalendar(nil)) }
                    }
                    return .run { [calendarAsync] send in
                        await send(._setCalendar(calendarAsync.findCalendar(descriptor)))
                    }
                }
                guard let cached = state.selectedCalendar else { return .none }
                return .run { [calendarAsync] send in
                    guard let backfilled = calendarAsync.calendarDescriptor(cached) else { return }
                    await send(._setCalendarDescriptor(backfilled))
                }

            case let ._setAlbum(albumId):
                if state.selectedAlbum != albumId {
                    state.$selectedAlbum.withLock { $0 = albumId }
                }
                return .none

            case let ._setAlbumDescriptor(descriptor):
                state.$albumDescriptor.withLock { $0 = descriptor }
                return .none

            case let ._setCalendar(calendarId):
                if state.selectedCalendar != calendarId {
                    state.$selectedCalendar.withLock { $0 = calendarId }
                }
                return .none

            case let ._setCalendarDescriptor(descriptor):
                state.$calendarDescriptor.withLock { $0 = descriptor }
                return .none
            }
        }
    }
}
