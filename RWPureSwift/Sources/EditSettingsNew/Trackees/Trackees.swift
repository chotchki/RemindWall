import ComposableArchitecture
import Dao
import SQLiteData
import SwiftUI

@Reducer
public struct TrackeesFeature: Sendable {
    @Dependency(\.defaultDatabase) var defaultDatabase
    @Dependency(\.uuid) var uuid
    
    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?
        var path = StackState<TrackeeDetailFeature.State>()
        
        @FetchAll(Trackee.none)
        var trackees: [Trackee]
        
        public init(){
            self._trackees = FetchAll(Trackee.all.order(by: \.name))
        }
    }
    
    public enum Action {
        case addButtonTapped
        case deleteTrackee(Trackee.ID)
        case destination(PresentationAction<Destination.Action>)
        case path(StackActionOf<TrackeeDetailFeature>)
        case reloadTrackees
    }
    
    public init() {
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                state.destination = .addTrackee(
                    AddTrackeeFeature.State(
                        trackee: Trackee(id: Trackee.ID(uuid()), name: "")
                    )
                )
                return .none
                
            case let .deleteTrackee(trackeeId):
                return .run { [t = state.$trackees, dd = self.defaultDatabase] send in
                    await withErrorReporting {
                        try await dd.write { db in
                            try ReminderTime.where { $0.trackeeId.eq(trackeeId) }.delete().execute(db)
                            try Trackee.find(trackeeId).delete().execute(db)
                        }
                        try await t.load(Trackee.all.order(by: \.name))
                    }
                }
                
            case let .destination(.presented(.addTrackee(.delegate(.saveTrackee(trackee))))):
                return .run { [t = state.$trackees, dd = self.defaultDatabase] send in
                    await withErrorReporting {
                        try await dd.write { db in
                            try Trackee.insert{trackee}.execute(db)
                        }
                        try await t.load(Trackee.all.order(by: \.name))
                    }
                }
                
            case let .path(.element(id: id, action: .delegate(.confirmDeletion))):
              guard let detailState = state.path[id: id]
              else { return .none }
                return .send(.deleteTrackee(detailState.trackee.id))
                
            case .reloadTrackees:
                return .run { [t = state.$trackees] send in
                    _ = await withErrorReporting {
                        try await t.load(Trackee.all.order(by: \.name))
                    }
                }
            case .destination:
                return .none
            case .path:
                return .none
            }
        }.ifLet(\.$destination, action: \.destination) {
            Destination.body
        }.forEach(\.path, action: \.path) {
            TrackeeDetailFeature()
        }
    }
}

extension TrackeesFeature {
  @Reducer
  public enum Destination {
    case addTrackee(AddTrackeeFeature)
  }
}

extension TrackeesFeature.Destination.State: Equatable {}
    

public struct TrackeesView: View {
    @Bindable var store: StoreOf<TrackeesFeature>
    public let isEmbedded: Bool
    
    public init(store: StoreOf<TrackeesFeature>, isEmbedded: Bool = false) {
        self.store = store
        self.isEmbedded = isEmbedded
    }
    
    public var body: some View {
        if isEmbedded {
            embeddedContent
        } else {
            standaloneContent
        }
    }

    @ViewBuilder
    private func trackeeRow(_ trackee: Trackee) -> some View {
        HStack {
            Text(trackee.name)
            Spacer()
            statusBadge(enabled: trackee.remindersEnabled)
        }
    }

    /// A pill that names the reminder state outright — "Active" (green) vs
    /// "Paused" (orange) — so a paused trackee pops in a list of active ones
    /// without opening the detail.
    private func statusBadge(enabled: Bool) -> some View {
        let tint: Color = enabled ? .green : .orange
        return Label(
            enabled ? "Active" : "Paused",
            systemImage: enabled ? "bell.fill" : "bell.slash.fill"
        )
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.15)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(enabled ? "Reminders active" : "Reminders paused")
    }
    
    @ViewBuilder
    private var embeddedContent: some View {
        if store.trackees.isEmpty {
            Text("No trackees configured")
        } else {
            ForEach(store.trackees){ trackee in
                NavigationLink(state: TrackeeDetailFeature.State(trackee: trackee)) {
                    trackeeRow(trackee)
                }
            }
        }
        
        Color.clear
            .frame(height: 0)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .sheet(
                item: $store.scope(state: \.$destination, action: \.destination).addTrackee
            ) { addTrackeeStore in
                NavigationStack {
                    AddTrackeeView(store: addTrackeeStore)
                }
            }
    }
    
    @ViewBuilder
    private var standaloneContent: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                if store.trackees.isEmpty {
                    Text("No trackees configured")
                } else {
                    ForEach(store.trackees){ trackee in
                        NavigationLink(state: TrackeeDetailFeature.State(trackee: trackee)) {
                            trackeeRow(trackee)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }.navigationTitle("Trackees")
                .toolbar {
                    ToolbarItem {
                        Button {
                            store.send(.addButtonTapped)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
        } destination: { store in
            TrackeeDetailView(store: store)
        }
        .sheet(
            item: $store.scope(state: \.$destination, action: \.destination).addTrackee
          ) { addTrackeeStore in
            NavigationStack {
              AddTrackeeView(store: addTrackeeStore)
            }
          }
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
      }
    
    TrackeesView(
    store: Store(
      initialState: TrackeesFeature.State()
    ) {
        TrackeesFeature()
    }
  )
}
