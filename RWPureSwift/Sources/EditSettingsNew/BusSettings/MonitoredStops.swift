import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI

@Reducer
public struct MonitoredStopsFeature: Sendable {
    @Dependency(\.defaultDatabase) var defaultDatabase

    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?

        @FetchAll(MonitoredStop.none)
        var stops: [MonitoredStop]

        public init() {
            self._stops = FetchAll(MonitoredStop.all.order(by: \.sortOrder))
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteStop(MonitoredStop.ID)
        case destination(PresentationAction<Destination.Action>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce<State, Action> { state, action in
            switch action {
            case .addButtonTapped:
                let nextSortOrder = (state.stops.map(\.sortOrder).max() ?? -1) + 1
                state.destination = .addStop(
                    AddMonitoredStopFeature.State(sortOrder: nextSortOrder)
                )
                return .none

            case let .deleteStop(id):
                return .run { [s = state.$stops] _ in
                    await withErrorReporting {
                        try await defaultDatabase.write { db in
                            try MonitoredStop.find(id).delete().execute(db)
                        }
                        try await s.load(MonitoredStop.all.order(by: \.sortOrder))
                    }
                }

            case let .destination(.presented(.addStop(.delegate(.saveStop(draft))))):
                return .run { [s = state.$stops] _ in
                    await withErrorReporting {
                        try await defaultDatabase.write { db in
                            try MonitoredStop.insert { draft }.execute(db)
                        }
                        try await s.load(MonitoredStop.all.order(by: \.sortOrder))
                    }
                }

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) {
            Destination.body
        }
    }
}

extension MonitoredStopsFeature {
    @Reducer
    public enum Destination {
        case addStop(AddMonitoredStopFeature)
    }
}

extension MonitoredStopsFeature.Destination.State: Equatable {}

public struct MonitoredStopsView: View {
    @Bindable var store: StoreOf<MonitoredStopsFeature>

    public init(store: StoreOf<MonitoredStopsFeature>) {
        self.store = store
    }

    public var body: some View {
        if store.stops.isEmpty {
            Text("No stops monitored")
                .foregroundStyle(.secondary)
        } else {
            ForEach(store.stops) { stop in
                HStack {
                    Text(stop.routeShortName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading) {
                        Text(stop.label)
                            .font(.body)
                        Text(stop.stopId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.send(.deleteStop(stop.id))
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete monitored stop")
                }
                .padding(.vertical, 4)
            }
        }

        Color.clear
            .frame(height: 0)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .sheet(item: $store.scope(state: \.$destination, action: \.destination).addStop) { addStore in
                AddMonitoredStopView(store: addStore)
            }
    }
}
