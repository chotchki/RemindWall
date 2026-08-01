import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SwiftUI
import TrafficAPI

@Reducer
public struct AddDriveFeature: Sendable {
    @Dependency(\.placeSearch) var placeSearch
    @Dependency(\.dismiss) var dismiss

    @ObservableState
    public struct State: Equatable {
        public var sortOrder: Int
        public var query: String = ""
        public var results: [FoundPlace] = []
        public var selectedPlace: FoundPlace?
        public var label: String = ""
        public var normalMinutes: Int = 15
        public var isSearching: Bool = false
        public var errorMessage: String?

        public init(sortOrder: Int) {
            self.sortOrder = sortOrder
        }

        public var canSave: Bool {
            selectedPlace != nil
                && !label.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    public enum Action: Equatable {
        case queryChanged(String)
        case searchTapped
        case _resultsLoaded([FoundPlace])
        case _searchFailed(String)
        case placeSelected(FoundPlace)
        case labelChanged(String)
        case normalMinutesChanged(Int)
        case saveButtonTapped
        case cancelButtonTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case saveRoute(MonitoredRoute.Draft)
        }
    }

    enum CancelID { case search }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .queryChanged(query):
                state.query = query
                return .none

            case .searchTapped:
                let query = state.query.trimmingCharacters(in: .whitespaces)
                guard !query.isEmpty else { return .none }
                state.isSearching = true
                state.errorMessage = nil
                return .run { [placeSearch] send in
                    do {
                        await send(._resultsLoaded(try await placeSearch.search(query)))
                    } catch {
                        await send(._searchFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let ._resultsLoaded(results):
                state.isSearching = false
                state.results = results
                state.errorMessage = results.isEmpty ? "No places found" : nil
                return .none

            case let ._searchFailed(message):
                state.isSearching = false
                state.errorMessage = message
                return .none

            case let .placeSelected(place):
                state.selectedPlace = place
                if state.label.isEmpty {
                    state.label = place.name
                }
                return .none

            case let .labelChanged(label):
                state.label = label
                return .none

            case let .normalMinutesChanged(minutes):
                state.normalMinutes = min(max(minutes, 1), 240)
                return .none

            case .saveButtonTapped:
                guard let place = state.selectedPlace, state.canSave else { return .none }
                let draft = MonitoredRoute.Draft(
                    label: state.label.trimmingCharacters(in: .whitespaces),
                    destinationLatitude: place.latitude,
                    destinationLongitude: place.longitude,
                    destinationName: place.name,
                    normalMinutes: state.normalMinutes,
                    sortOrder: state.sortOrder,
                    window: nil,
                    enabled: true
                )
                return .concatenate(
                    .send(.delegate(.saveRoute(draft))),
                    .run { _ in await dismiss() }
                )

            case .cancelButtonTapped:
                return .run { _ in await dismiss() }

            case .delegate:
                return .none
            }
        }
    }
}

public struct AddDriveView: View {
    @Bindable var store: StoreOf<AddDriveFeature>

    public init(store: StoreOf<AddDriveFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    HStack {
                        TextField("Search Apple Maps", text: Binding(
                            get: { store.query },
                            set: { store.send(.queryChanged($0)) }
                        ))
                        Button("Search") { store.send(.searchTapped) }
                            .disabled(store.query.isEmpty || store.isSearching)
                    }
                    if store.isSearching {
                        ProgressView()
                    }
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.results) { place in
                        Button {
                            store.send(.placeSelected(place))
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(place.name)
                                    Text(place.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.selectedPlace?.id == place.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Alert") {
                    TextField("Label (e.g. School run)", text: Binding(
                        get: { store.label },
                        set: { store.send(.labelChanged($0)) }
                    ))
                    Stepper(
                        "Normal drive: \(store.normalMinutes) min",
                        value: Binding(
                            get: { store.normalMinutes },
                            set: { store.send(.normalMinutesChanged($0)) }
                        ),
                        in: 1...240,
                        step: 1
                    )
                }
            }
            .navigationTitle("Add drive time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.cancelButtonTapped) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.saveButtonTapped) }
                        .disabled(!store.canSave)
                }
            }
        }
    }
}
