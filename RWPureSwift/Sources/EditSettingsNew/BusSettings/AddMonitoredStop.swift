import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SwiftUI
import TransitAPI

public struct PugetSoundAgency: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public static let all: [PugetSoundAgency] = [
        .init(id: "1", name: "King County Metro"),
        .init(id: "3", name: "Pierce Transit"),
        .init(id: "19", name: "Intercity Transit"),
        .init(id: "20", name: "Kitsap Transit"),
        .init(id: "23", name: "City of Seattle"),
        .init(id: "29", name: "Community Transit"),
        .init(id: "40", name: "Sound Transit"),
        .init(id: "95", name: "Washington State Ferries"),
        .init(id: "97", name: "Everett Transit"),
    ]
}

@Reducer
public struct AddMonitoredStopFeature: Sendable {
    @Dependency(\.transitAPI) var transitAPI
    @Dependency(\.transitKeyStore) var transitKeyStore
    @Dependency(\.uuid) var uuid
    @Dependency(\.dismiss) var dismiss

    @ObservableState
    public struct State: Equatable {
        public var sortOrder: Int
        public var agencyId: String = PugetSoundAgency.all[0].id
        public var stopCode: String = ""
        public var label: String = ""
        public var selectedRouteId: String?
        public var lookedUpStop: StopInfo?
        public var routeOptions: [RouteInfo] = []
        public var isLooking: Bool = false
        public var errorMessage: String?

        public init(sortOrder: Int) {
            self.sortOrder = sortOrder
        }

        public var canSave: Bool {
            lookedUpStop != nil
                && selectedRouteId != nil
                && !label.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    public enum Action: Equatable {
        case agencyChanged(String)
        case stopCodeChanged(String)
        case labelChanged(String)
        case routeChanged(String?)
        case lookupTapped
        case _stopFetched(StopInfo)
        case _lookupFailed(String)
        case _routesFetched([RouteInfo])
        case saveButtonTapped
        case cancelButtonTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case saveStop(MonitoredStop.Draft)
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce<State, Action> { state, action in
            switch action {
            case let .agencyChanged(id):
                state.agencyId = id
                state.lookedUpStop = nil
                state.routeOptions = []
                state.selectedRouteId = nil
                state.errorMessage = nil
                return .none

            case let .stopCodeChanged(code):
                state.stopCode = code
                state.lookedUpStop = nil
                state.routeOptions = []
                state.selectedRouteId = nil
                state.errorMessage = nil
                return .none

            case let .labelChanged(label):
                state.label = label
                return .none

            case let .routeChanged(id):
                state.selectedRouteId = id
                return .none

            case .lookupTapped:
                guard !state.stopCode.isEmpty else { return .none }
                guard let key = transitKeyStore.read() else {
                    state.errorMessage = "No API key configured"
                    return .none
                }
                let composedId = "\(state.agencyId)_\(state.stopCode)"
                state.isLooking = true
                state.errorMessage = nil
                return .run { [transitAPI] send in
                    do {
                        let stop = try await transitAPI.fetchStop(apiKey: key, stopId: composedId)
                        await send(._stopFetched(stop))
                        var routes: [RouteInfo] = []
                        for routeId in stop.routeIds {
                            if let route = try? await transitAPI.fetchRoute(
                                apiKey: key, routeId: routeId
                            ) {
                                routes.append(route)
                            }
                        }
                        await send(._routesFetched(routes))
                    } catch let error as TransitAPIError {
                        await send(._lookupFailed(message(for: error)))
                    } catch {
                        await send(._lookupFailed(error.localizedDescription))
                    }
                }

            case let ._stopFetched(stop):
                state.lookedUpStop = stop
                state.errorMessage = nil
                if state.label.isEmpty { state.label = stop.name }
                return .none

            case let ._routesFetched(routes):
                state.routeOptions = routes
                state.selectedRouteId = routes.first?.routeId
                state.isLooking = false
                return .none

            case let ._lookupFailed(message):
                state.isLooking = false
                state.errorMessage = message
                return .none

            case .saveButtonTapped:
                guard let stop = state.lookedUpStop,
                      let routeId = state.selectedRouteId,
                      let route = state.routeOptions.first(where: { $0.routeId == routeId })
                else {
                    return .none
                }
                let draft = MonitoredStop.Draft(
                    label: state.label.trimmingCharacters(in: .whitespaces),
                    stopId: stop.stopId,
                    routeId: route.routeId,
                    routeShortName: route.shortName,
                    sortOrder: state.sortOrder
                )
                return .run { [dismiss] send in
                    await send(.delegate(.saveStop(draft)))
                    await dismiss()
                }

            case .cancelButtonTapped:
                return .run { [dismiss] _ in
                    await dismiss()
                }

            case .delegate:
                return .none
            }
        }
    }

    private func message(for error: TransitAPIError) -> String {
        switch error {
        case .unauthorized: return "API key was rejected — check it in Settings."
        case .notFound: return "Stop not found. Check the agency and stop code."
        case .rateLimited: return "Too many requests. Try again in a moment."
        case .invalidResponse: return "Unexpected response from the server."
        case let .network(detail): return "Network error: \(detail)"
        case let .decoding(detail): return "Could not parse response: \(detail)"
        }
    }
}

public struct AddMonitoredStopView: View {
    @Bindable var store: StoreOf<AddMonitoredStopFeature>

    public init(store: StoreOf<AddMonitoredStopFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Agency") {
                    Picker("Agency", selection: Binding(
                        get: { store.agencyId },
                        set: { store.send(.agencyChanged($0)) }
                    )) {
                        ForEach(PugetSoundAgency.all) { agency in
                            Text(agency.name).tag(agency.id)
                        }
                    }
                }

                Section("Stop") {
                    HStack {
                        TextField("Stop code (from sign)", text: Binding(
                            get: { store.stopCode },
                            set: { store.send(.stopCodeChanged($0)) }
                        ))
                        #if !os(macOS)
                        .keyboardType(.numberPad)
                        #endif
                        Button("Look up") {
                            store.send(.lookupTapped)
                        }
                        .disabled(store.stopCode.isEmpty || store.isLooking)
                    }

                    if store.isLooking {
                        HStack {
                            ProgressView()
                            Text("Looking up…")
                        }
                    }

                    if let stop = store.lookedUpStop {
                        Label(stop.name, systemImage: "mappin.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if !store.routeOptions.isEmpty {
                    Section("Route") {
                        Picker("Route", selection: Binding(
                            get: { store.selectedRouteId },
                            set: { store.send(.routeChanged($0)) }
                        )) {
                            ForEach(store.routeOptions, id: \.routeId) { route in
                                Text("\(route.shortName) — \(route.longName)")
                                    .tag(route.routeId as String?)
                            }
                        }
                    }
                }

                if store.lookedUpStop != nil {
                    Section("Label") {
                        TextField("Display name", text: Binding(
                            get: { store.label },
                            set: { store.send(.labelChanged($0)) }
                        ))
                    }
                }
            }
            .navigationTitle("Add Stop")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
