import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import SwiftUI
import TrafficAPI
import TransitAPI

/// The one-time ceremony, out of the everyday flow (TR1.4 review decision):
/// the OneBusAway API key + test connection, and the drive-time home origin.
@Reducer
public struct AlertsSetupFeature: Sendable {
    @Dependency(\.transitAPI) var transitAPI
    @Dependency(\.transitKeyStore) var transitKeyStore
    @Dependency(\.placeSearch) var placeSearch
    @Dependency(\.dismiss) var dismiss

    @ObservableState
    public struct State: Equatable {
        @Shared(.syncedSetting(HOME_ORIGIN_SETTING_KEY)) public var homeOrigin: HomeOrigin?

        public var apiKeyDraft: String = ""
        public var hasStoredApiKey: Bool = false
        public var isTestingConnection: Bool = false
        public var connectionStatus: String?

        public var originQuery: String = ""
        public var originResults: [FoundPlace] = []
        public var isSearchingOrigin: Bool = false
        public var originError: String?

        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case apiKeyChanged(String)
        case saveApiKey
        case testConnection
        case _connectionResult(Bool, String?)
        case originQueryChanged(String)
        case originSearchTapped
        case _originResults([FoundPlace])
        case _originSearchFailed(String)
        case originSelected(FoundPlace)
        case doneTapped
    }

    enum CancelID { case originSearch }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let stored = transitKeyStore.read()
                state.apiKeyDraft = stored ?? ""
                state.hasStoredApiKey = stored?.isEmpty == false
                return .none

            case let .apiKeyChanged(value):
                state.apiKeyDraft = value
                return .none

            case .saveApiKey:
                let key = state.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                state.hasStoredApiKey = !key.isEmpty
                return .run { [transitKeyStore] _ in
                    transitKeyStore.write(key.isEmpty ? nil : key)
                }

            case .testConnection:
                let key = state.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else {
                    state.connectionStatus = "Enter an API key first"
                    return .none
                }
                state.isTestingConnection = true
                state.connectionStatus = nil
                return .run { [transitAPI] send in
                    do {
                        try await transitAPI.testConnection(apiKey: key)
                        await send(._connectionResult(true, "Connected"))
                    } catch let error as TransitAPIError {
                        await send(._connectionResult(false, message(for: error)))
                    } catch {
                        await send(._connectionResult(false, error.localizedDescription))
                    }
                }

            case let ._connectionResult(_, message):
                state.isTestingConnection = false
                state.connectionStatus = message
                return .none

            case let .originQueryChanged(query):
                state.originQuery = query
                return .none

            case .originSearchTapped:
                let query = state.originQuery.trimmingCharacters(in: .whitespaces)
                guard !query.isEmpty else { return .none }
                state.isSearchingOrigin = true
                state.originError = nil
                return .run { [placeSearch] send in
                    do {
                        await send(._originResults(try await placeSearch.search(query)))
                    } catch {
                        await send(._originSearchFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.originSearch, cancelInFlight: true)

            case let ._originResults(results):
                state.isSearchingOrigin = false
                state.originResults = results
                state.originError = results.isEmpty ? "No places found" : nil
                return .none

            case let ._originSearchFailed(message):
                state.isSearchingOrigin = false
                state.originError = message
                return .none

            case let .originSelected(place):
                state.$homeOrigin.withLock {
                    $0 = HomeOrigin(
                        latitude: place.latitude,
                        longitude: place.longitude,
                        name: place.name
                    )
                }
                state.originResults = []
                state.originQuery = ""
                return .none

            case .doneTapped:
                return .run { _ in await dismiss() }
            }
        }
    }

    private func message(for error: TransitAPIError) -> String {
        switch error {
        case .unauthorized: return "API key was rejected"
        case .notFound: return "Endpoint not found"
        case .rateLimited: return "Rate limited — try again"
        case .invalidResponse: return "Unexpected response"
        case let .network(detail): return "Network error: \(detail)"
        case let .decoding(detail): return "Decoding error: \(detail)"
        }
    }
}

public struct AlertsSetupView: View {
    @Bindable var store: StoreOf<AlertsSetupFeature>

    public init(store: StoreOf<AlertsSetupFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("OneBusAway (buses)") {
                    HStack {
                        TextField("API key", text: Binding(
                            get: { store.apiKeyDraft },
                            set: { store.send(.apiKeyChanged($0)) }
                        ))
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        Button("Save") { store.send(.saveApiKey) }
                            .disabled(store.apiKeyDraft.isEmpty)
                    }
                    Button {
                        store.send(.testConnection)
                    } label: {
                        HStack {
                            if store.isTestingConnection {
                                ProgressView()
                                Text("Testing…")
                            } else {
                                Image(systemName: "network")
                                Text("Test Connection")
                            }
                        }
                    }
                    .disabled(store.isTestingConnection)
                    if let status = store.connectionStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Need a key? Email oba_api_key@soundtransit.org")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section("Driving (Apple Maps)") {
                    if let origin = store.homeOrigin {
                        LabeledContent("Home origin") { Text("📍 \(origin.name)") }
                    }
                    HStack {
                        TextField(
                            store.homeOrigin == nil ? "Search for home" : "Change origin",
                            text: Binding(
                                get: { store.originQuery },
                                set: { store.send(.originQueryChanged($0)) }
                            )
                        )
                        Button("Search") { store.send(.originSearchTapped) }
                            .disabled(store.originQuery.isEmpty || store.isSearchingOrigin)
                    }
                    if store.isSearchingOrigin {
                        ProgressView()
                    }
                    if let error = store.originError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.originResults) { place in
                        Button {
                            store.send(.originSelected(place))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(place.name)
                                Text(place.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Drive times are measured from here. No key needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Setup")
            .toolbar {
                ToolbarItem {
                    Button("Done") { store.send(.doneTapped) }
                }
            }
            .onAppear { store.send(.onAppear) }
        }
    }
}
