import ComposableArchitecture
import Slideshow
import SwiftUI
import TagScanLoader

@Reducer
public struct DashboardFeature: Sendable {

    @ObservableState
    public struct State: Equatable {
        public var slideshowState = SlideShowFeature.State()
        public var alertLoaderState = AlertLoaderFeature.State()
        public var calendarEventsState = CalendarEventsFeature.State()
        public var tagScanLoaderState = TagScanLoaderFeature.State()

        public init() {}
    }

    public enum Action {
        case onAppear
        case onDisappear
        case slideshow(SlideShowFeature.Action)
        case alertLoader(AlertLoaderFeature.Action)
        case calendarEvents(CalendarEventsFeature.Action)
        case tagScanLoader(TagScanLoaderFeature.Action)
        case delegate(Delegate)
        case tappedReturnToSettings

        @CasePathable
        public enum Delegate: Equatable {
            case returnToSettings
        }
    }

    @Dependency(\.cursorClient) var cursorClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.slideshowState, action: \.slideshow) {
            SlideShowFeature()
        }

        Scope(state: \.alertLoaderState, action: \.alertLoader) {
            AlertLoaderFeature()
        }

        Scope(state: \.calendarEventsState, action: \.calendarEvents) {
            CalendarEventsFeature()
        }

        Scope(state: \.tagScanLoaderState, action: \.tagScanLoader) {
            TagScanLoaderFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                cursorClient.hide()
                return .merge(
                    .send(.slideshow(.viewAppeared)),
                    .send(.alertLoader(.startMonitoring)),
                    .send(.calendarEvents(.startMonitoring)),
                    .send(.tagScanLoader(.startMonitoring))
                )

            case .onDisappear:
                cursorClient.unhide()
                return .none

            case .slideshow(.delegate(.tapReturnToSettings)):
                return .send(.delegate(.returnToSettings))

            case .tappedReturnToSettings:
                return .send(.delegate(.returnToSettings))

            case .slideshow, .alertLoader, .calendarEvents, .tagScanLoader, .delegate:
                return .none
            }
        }
    }
}

public struct DashboardView: View {
    @Bindable var store: StoreOf<DashboardFeature>

    public init(store: StoreOf<DashboardFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            SlideshowView(store: store.scope(
                state: \.slideshowState,
                action: \.slideshow
            ))

            VStack(alignment: .leading) {
                if let title = store.calendarEventsState.currentEventTitle {
                    NowView(title: title)
                        .transition(.slide)
                }
                Spacer()
                if let nextTitle = store.calendarEventsState.nextEventTitle,
                   let timeUntil = store.calendarEventsState.nextEventTimeUntil {
                    UpNextView(
                        title: nextTitle,
                        timeUntil: timeUntil,
                        leadingEmoji: store.calendarEventsState.nextEventLeadingEmoji
                    )
                    .transition(.slide)
                }
            }

            AlertView(lateTrackeeNames: store.alertLoaderState.lateTrackeeNames)

            TagScanLoaderView(store: store.scope(
                state: \.tagScanLoaderState,
                action: \.tagScanLoader
            ))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.send(.tappedReturnToSettings)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("DashboardView")
        .onAppear {
            store.send(.onAppear)
        }
        .onDisappear {
            store.send(.onDisappear)
        }
    }
}
