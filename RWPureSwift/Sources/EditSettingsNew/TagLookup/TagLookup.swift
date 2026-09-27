import AppTypes
import ComposableArchitecture
import Dao
import Foundation
import SQLiteData
import SwiftUI
import TagScanner
import Tagged

public enum TagLookupResult: Equatable, Sendable {
    case paired(TagSerial, [TagDirectory.Owner])
    case unpaired(TagSerial)
    case unreadable(String)
    case readerUnavailable(String)
    case lookupFailed(String)
}

/// Reverse lookup for loose cups: tap a tag, see whose it is and which slot
/// it belongs in. READ-ONLY by design; a tap here never credits a dose (the
/// dashboard's TagScanLoader owns that, and it's stopped while Settings is up).
@Reducer
public struct TagLookupFeature: Sendable {
    @Dependency(\.tagReaderClient) var tagReaderClient
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.continuousClock) var clock
    @Dependency(\.dismiss) var dismiss

    /// A contactless tap can RF-bounce into a trailing failed decode. Inside
    /// this window of a good read the failure can't be told apart from a quick
    /// tap of a DIFFERENT cup (tagUnreadable carries no serial), so the owner
    /// stays up but gets flagged instead of being replaced.
    static let bounceWindow: TimeInterval = 2

    @ObservableState
    public struct State: Equatable {
        public var directory: TagDirectory = .empty
        public var result: TagLookupResult?
        /// Every tag read this session, paired or not; drives the tick-off.
        public var scannedTags: Set<TagSerial> = []
        /// A failed read landed inside the bounce window after the shown
        /// result: either a bounce or a different cup; the view warns.
        public var newerTapFailed = false
        var lastReadAt: Date?

        public var totalCupCount: Int { directory.allTags.count }
        public var scannedCupCount: Int { directory.allTags.intersection(scannedTags).count }

        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case doneTapped
        case resetTapped
        case _directoryLoaded(TagDirectory)
        case _tagScanned(ReaderState)
        case _lookupFinished(TagSerial, TagDirectory)
        case _lookupFailed(String)
    }

    enum CancelID { case scanLoop, lookup }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    .run { [database] send in
                        await send(._directoryLoaded(try await Self.loadDirectory(database)))
                    } catch: { error, send in
                        await send(._lookupFailed(error.localizedDescription))
                    },
                    .run { [tagReaderClient, clock] send in
                        while !Task.isCancelled {
                            let reading = await tagReaderClient.nextTagId()
                            await send(._tagScanned(reading))
                            // readerError returns immediately (no reader / slot
                            // monitor dead) - back off instead of hot-looping.
                            if case .readerError = reading {
                                try await clock.sleep(for: .seconds(30))
                            }
                        }
                    }
                    .cancellable(id: CancelID.scanLoop, cancelInFlight: true)
                )

            case .doneTapped:
                return .run { [dismiss] _ in await dismiss() }

            case .resetTapped:
                state.scannedTags = []
                state.result = nil
                state.newerTapFailed = false
                state.lastReadAt = nil
                return .none

            case let ._directoryLoaded(directory):
                state.directory = directory
                return .none

            case let ._tagScanned(reading):
                switch reading {
                case .noTag:
                    return .none

                case let .readerError(message):
                    state.result = .readerUnavailable(message)
                    return .none

                case let .tagUnreadable(message):
                    if let at = state.lastReadAt, now.timeIntervalSince(at) < Self.bounceWindow {
                        state.newerTapFailed = true
                        return .none
                    }
                    // Clear the previous owner: their name staying up while a
                    // DIFFERENT cup is in hand is how meds get misfiled.
                    state.result = .unreadable(message)
                    state.newerTapFailed = false
                    return .cancel(id: CancelID.lookup)

                case let .tagPresent(tag):
                    state.lastReadAt = now
                    state.newerTapFailed = false
                    state.scannedTags.insert(tag)
                    // Re-read per tap so a pairing edited on another device
                    // (CloudKit) is what the lookup reports.
                    return .run { [database] send in
                        await send(._lookupFinished(tag, try await Self.loadDirectory(database)))
                    } catch: { error, send in
                        await send(._lookupFailed(error.localizedDescription))
                    }
                    .cancellable(id: CancelID.lookup, cancelInFlight: true)
                }

            case let ._lookupFinished(tag, directory):
                state.directory = directory
                let owners = directory.owners(of: tag)
                state.result = owners.isEmpty ? .unpaired(tag) : .paired(tag, owners)
                return .none

            case let ._lookupFailed(message):
                state.result = .lookupFailed(message)
                return .none
            }
        }
    }

    private static func loadDirectory(_ database: any DatabaseReader) async throws -> TagDirectory {
        try await database.read { db in
            TagDirectory(
                trackees: try Trackee.all.fetchAll(db),
                reminders: try ReminderTime.all.fetchAll(db)
            )
        }
    }
}

public struct TagLookupView: View {
    let store: StoreOf<TagLookupFeature>

    public init(store: StoreOf<TagLookupFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                if store.directory.people.isEmpty {
                    Section("Cups") {
                        Text("No trackees configured")
                    }
                } else {
                    ForEach(store.directory.people) { person in
                        personSection(person)
                    }
                }
            }
            // Pinned, not a Form row: with the table scrolled to find a cup,
            // the latest tap's owner must still be on screen.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    resultPanel
                    Divider()
                    HStack {
                        Text("\(store.scannedCupCount) of \(store.totalCupCount) cups scanned")
                            .font(.headline)
                            .monospacedDigit()
                        Spacer()
                        Text("Lookup only: never marks a dose taken")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Tag Lookup")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { store.send(.resetTapped) }
                        .disabled(store.scannedTags.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.send(.doneTapped) }
                }
            }
            .onAppear { store.send(.onAppear) }
        }
    }

    // MARK: - Result panel

    @ViewBuilder
    private var resultPanel: some View {
        switch store.result {
        case .none:
            Label("Tap a cup on the reader", systemImage: "sensor.tag.radiowaves.forward")
                .font(.title2)
                .foregroundStyle(.secondary)

        case let .paired(tag, owners):
            VStack(alignment: .leading, spacing: 12) {
                newerTapWarning
                if owners.count > 1 {
                    Label(
                        "Paired to more than one person: a scan credits whoever's dose is due",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout.weight(.semibold))
                }
                ForEach(owners) { owner in
                    ownerBlock(owner)
                }
                tagCaption(tag)
            }

        case let .unpaired(tag):
            VStack(alignment: .leading, spacing: 8) {
                newerTapWarning
                Label("Not paired to anyone", systemImage: "questionmark.circle.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.red)
                Text("Set it aside; after the sweep, pair it by adding a reminder with this tag on a trackee.")
                    .foregroundStyle(.secondary)
                tagCaption(tag)
            }

        case .unreadable:
            Label("Couldn't read that tag: tap again and hold it on the reader", systemImage: "wave.3.right.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)

        case let .readerUnavailable(message):
            Label("Reader unavailable: \(message)", systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)

        case let .lookupFailed(message):
            Label("Lookup failed: \(message)", systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var newerTapWarning: some View {
        if store.newerTapFailed {
            Label(
                "A newer tap didn't read. Holding a different cup? Tap it again.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.orange)
        }
    }

    private func ownerBlock(_ owner: TagDirectory.Owner) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(owner.person.name)
                    .font(.system(size: 44, weight: .bold))
                if !owner.person.remindersEnabled {
                    pausedBadge
                }
            }
            ForEach(owner.cup.slots, id: \.self) { slot in
                Text(slot)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            Text(lastScanText(owner.cup.lastScan))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tagCaption(_ tag: TagSerial) -> some View {
        Label(tag.hexa, systemImage: "sensor.tag.radiowaves.forward")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    // MARK: - Cup table

    private func personSection(_ person: TagDirectory.Person) -> some View {
        Section {
            if person.cups.isEmpty && person.untaggedReminderCount == 0 {
                Text("No reminders")
                    .foregroundStyle(.secondary)
            }
            ForEach(person.cups) { cup in
                cupRow(cup)
            }
            if person.untaggedReminderCount > 0 {
                Label(
                    person.untaggedReminderCount == 1
                        ? "1 reminder has no cup paired"
                        : "\(person.untaggedReminderCount) reminders have no cup paired",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }
        } header: {
            HStack {
                Text(person.name)
                if !person.remindersEnabled {
                    pausedBadge
                }
            }
        }
    }

    private func cupRow(_ cup: TagDirectory.Cup) -> some View {
        let scanned = store.scannedTags.contains(cup.tag)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: scanned ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(scanned ? .green : .secondary)
                .accessibilityLabel(scanned ? "Scanned" : "Not scanned yet")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(cup.slots, id: \.self) { slot in
                    Text(slot)
                        .font(.headline)
                        .monospacedDigit()
                }
                if !cup.sharedWith.isEmpty {
                    Label("Also paired to \(cup.sharedWith.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(cup.tag.hexa)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(isLatest(cup.tag) ? Color.accentColor.opacity(0.15) : nil)
    }

    private func isLatest(_ tag: TagSerial) -> Bool {
        if case let .paired(latest, _) = store.result { return latest == tag }
        return false
    }

    private var pausedBadge: some View {
        Label("Paused", systemImage: "bell.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .accessibilityLabel("Reminders paused")
    }

    private func lastScanText(_ date: Date?) -> String {
        guard let date else { return "Never scanned on the dashboard" }
        return "Last scanned \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! $0.appDatabase()
    }

    TagLookupView(store: Store(initialState: TagLookupFeature.State()) {
        TagLookupFeature()
    })
}
