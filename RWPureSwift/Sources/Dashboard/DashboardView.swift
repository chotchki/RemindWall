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
        public var busArrivalsState = BusArrivalsFeature.State()
        public var batteryAlertsState = BatteryAlertsFeature.State()
        public var trafficAlertsState = TrafficAlertsFeature.State()
        public var tagScanLoaderState = TagScanLoaderFeature.State()

        /// The dashboard owns assembly: sources contribute cards, this orders
        /// and caps them (SPEC-DASHBOARD).
        public var rail: DashboardRail {
            DashboardRail.assemble(
                busArrivalsState.railCards
                    + calendarEventsState.railCards
                    + trafficAlertsState.railCards,
                capacity: DashboardRail.platformCapacity
            )
        }

        public init() {}
    }

    public enum Action {
        case onAppear
        case onDisappear
        case slideshow(SlideShowFeature.Action)
        case alertLoader(AlertLoaderFeature.Action)
        case calendarEvents(CalendarEventsFeature.Action)
        case busArrivals(BusArrivalsFeature.Action)
        case batteryAlerts(BatteryAlertsFeature.Action)
        case trafficAlerts(TrafficAlertsFeature.Action)
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

        Scope(state: \.busArrivalsState, action: \.busArrivals) {
            BusArrivalsFeature()
        }

        Scope(state: \.batteryAlertsState, action: \.batteryAlerts) {
            BatteryAlertsFeature()
        }

        Scope(state: \.trafficAlertsState, action: \.trafficAlerts) {
            TrafficAlertsFeature()
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
                    .send(.busArrivals(.startMonitoring)),
                    .send(.batteryAlerts(.startMonitoring)),
                    .send(.trafficAlerts(.startMonitoring)),
                    .send(.tagScanLoader(.startMonitoring))
                )

            case .onDisappear:
                cursorClient.unhide()
                // The scan loop must not keep consuming taps while settings is up —
                // it would falsely mark meds taken during tag association.
                return .send(.tagScanLoader(.stopMonitoring))

            case .slideshow(.delegate(.tapReturnToSettings)):
                return .send(.delegate(.returnToSettings))

            case .tappedReturnToSettings:
                return .send(.delegate(.returnToSettings))

            case .slideshow, .alertLoader, .calendarEvents, .busArrivals, .batteryAlerts, .trafficAlerts, .tagScanLoader, .delegate:
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
                if !store.batteryAlertsState.ambientChips.isEmpty {
                    AmbientChipsView(chips: store.batteryAlertsState.ambientChips)
                        .padding(.leading, 24)
                        .padding(.top, 8)
                }
                Spacer()
                RailView(rail: store.rail)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }

            AlertView(lateTrackeeNames: store.alertLoaderState.lateTrackeeNames, dayOfWeek: store.alertLoaderState.dayOfWeek)

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
