import AppTypes
import ComposableArchitecture
import Dao
import Dependencies
import Foundation
import StructuredQueries
import SwiftUI
import TagScanner

public enum ScanResult: Equatable, Sendable {
    case success(String)
    case unknownTag
    case wrongScanWindow
    /// A tag reached the reader but couldn't be read — the user should retry.
    case tryAgain(String)
    case error(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

@Reducer
public struct TagScanLoaderFeature: Sendable {
    @Dependency(\.tagReaderClient) var tagReaderClient
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar
    @Dependency(\.continuousClock) var clock
    @Dependency(\.scanSoundPlayer) var scanSoundPlayer

    @ObservableState
    public struct State: Equatable {
        public var scanResult: ScanResult?
        public init() {}
    }

    public enum Action: Equatable {
        case startMonitoring
        case stopMonitoring
        case _tagScanned(ReaderState)
        case _scanProcessed(ScanResult)
        case dismissResult
    }

    enum CancelID { case scanLoop, autoDismiss, processing }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startMonitoring:
                return .run { [clock] send in
                    while !Task.isCancelled {
                        let result = await tagReaderClient.nextTagId()
                        await send(._tagScanned(result))
                        // readerError means infrastructure is down (slot monitor never
                        // initialized) and returns immediately — back off so a dead
                        // reader shows a persistent-ish error instead of a hot loop.
                        if case .readerError = result {
                            try await clock.sleep(for: .seconds(30))
                        }
                    }
                }
                .cancellable(id: CancelID.scanLoop, cancelInFlight: true)

            case .stopMonitoring:
                // Leaving the dashboard: without this the loop keeps consuming scans
                // (falsely marking meds taken while a tag is being associated in settings).
                state.scanResult = nil
                return .merge(
                    .cancel(id: CancelID.scanLoop),
                    .cancel(id: CancelID.autoDismiss),
                    .cancel(id: CancelID.processing)
                )

            case let ._tagScanned(readerState):
                switch readerState {
                case .noTag:
                    // Cancellation sentinel / empty poll — never user-visible.
                    return .none
                case .readerError(let message):
                    return .send(._scanProcessed(.error(message)))
                case .tagUnreadable(let message):
                    // A tap can RF-bounce: a trailing failed decode of the SAME tap
                    // must not stomp the success confirmation the user is reading.
                    if case .success = state.scanResult {
                        return .none
                    }
                    return .send(._scanProcessed(.tryAgain(message)))
                case .tagPresent(let tagSerial):
                    return .run { [database, now, calendar] send in
                        let result: ScanResult = try await database.write { db in
                            let matching = try ReminderTime.all.fetchAll(db)
                                .filter { $0.associatedTag == tagSerial }
                            guard !matching.isEmpty else {
                                return .unknownTag
                            }

                            // Several reminders can share one tag (e.g. morning + evening
                            // doses) — credit a currently-scannable one, preferring the
                            // dose that hasn't been recorded yet over re-crediting one
                            // scanned minutes ago (overlapping windows).
                            let scannable = matching.filter {
                                $0.isScannable(date: now, calendar: calendar)
                            }
                            guard let reminder = scannable.first(where: { $0.lastScan == nil })
                                ?? scannable.min(by: {
                                    ($0.lastScan ?? .distantPast) < ($1.lastScan ?? .distantPast)
                                })
                            else {
                                return .wrongScanWindow
                            }

                            try ReminderTime.where { $0.id.eq(reminder.id) }
                                .update { $0.lastScan = #bind(now) }
                                .execute(db)

                            let trackee = try Trackee.find(reminder.trackeeId)
                                .fetchOne(db)
                            return .success(trackee?.name ?? "Unknown")
                        }
                        await send(._scanProcessed(result))
                    } catch: { error, send in
                        await send(._scanProcessed(.error(error.localizedDescription)))
                    }
                    .cancellable(id: CancelID.processing, cancelInFlight: false)
                }

            case let ._scanProcessed(result):
                state.scanResult = result

                // The reader's own beep only proves detection; these prove the scan
                // was processed — audible even when the panel is dark. Sounds are for
                // per-tap outcomes only: .error is infrastructure (and can repeat on
                // the readerError backoff cycle), so it stays visual to avoid a kiosk
                // that buzzes all night over a dead reader.
                let soundEffect: Effect<Action>
                switch result {
                case .success:
                    soundEffect = .run { [scanSoundPlayer] _ in await scanSoundPlayer.playSuccess() }
                case .unknownTag, .wrongScanWindow, .tryAgain:
                    soundEffect = .run { [scanSoundPlayer] _ in await scanSoundPlayer.playFailure() }
                case .error:
                    soundEffect = .none
                }

                return .merge(
                    soundEffect,
                    .run { send in
                        try await clock.sleep(for: .seconds(5))
                        await send(.dismissResult)
                    }
                    .cancellable(id: CancelID.autoDismiss, cancelInFlight: true)
                )

            case .dismissResult:
                state.scanResult = nil
                return .none
            }
        }
    }
}

public struct TagScanLoaderView: View {
    let store: StoreOf<TagScanLoaderFeature>

    public init(store: StoreOf<TagScanLoaderFeature>) {
        self.store = store
    }

    public var body: some View {
        if let scanResult = store.scanResult {
            scanResultView(scanResult)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    store.send(.dismissResult)
                }
        }
    }

    @ViewBuilder
    private func scanResultView(_ result: ScanResult) -> some View {
        switch result {
        case let .success(name):
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.custom("Overlay", size: 200.0, relativeTo: .largeTitle))
                Text("Thank you, \(name) for taking your meds!")
                    .font(.custom("Overlay", size: 80.0, relativeTo: .largeTitle))
                    .colorInvert()
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green.opacity(0.5))

        case .unknownTag:
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "questionmark.circle.fill")
                    .font(.custom("Overlay", size: 200.0, relativeTo: .largeTitle))
                Text("Unknown Tag Scanned")
                    .font(.custom("Overlay", size: 80.0, relativeTo: .largeTitle))
                    .colorInvert()
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red.opacity(0.5))

        case .wrongScanWindow:
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.custom("Overlay", size: 200.0, relativeTo: .largeTitle))
                Text("Tag not scannable now, are you taking the right meds?")
                    .font(.custom("Overlay", size: 80.0, relativeTo: .largeTitle))
                    .colorInvert()
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red.opacity(0.5))

        case .tryAgain:
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "wave.3.right.circle")
                    .font(.custom("Overlay", size: 200.0, relativeTo: .largeTitle))
                Text("Couldn't read the tag — tap again and hold it on the reader")
                    .font(.custom("Overlay", size: 80.0, relativeTo: .largeTitle))
                    .colorInvert()
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.orange.opacity(0.5))

        case let .error(message):
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.custom("Overlay", size: 200.0, relativeTo: .largeTitle))
                Text("Error: \(message)")
                    .font(.custom("Overlay", size: 80.0, relativeTo: .largeTitle))
                    .colorInvert()
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red.opacity(0.5))
        }
    }
}

@MainActor
private func previewStore(_ result: ScanResult?) -> StoreOf<TagScanLoaderFeature> {
    var state = TagScanLoaderFeature.State()
    state.scanResult = result
    return Store(initialState: state) {
        TagScanLoaderFeature()
    }
}

#Preview("No Scan") {
    ZStack {
        Color.blue.ignoresSafeArea()
        TagScanLoaderView(store: previewStore(nil))
    }
}

#Preview("Success") {
    ZStack {
        Color.blue.ignoresSafeArea()
        TagScanLoaderView(store: previewStore(.success("Bob")))
    }
}

#Preview("Unknown Tag") {
    ZStack {
        Color.blue.ignoresSafeArea()
        TagScanLoaderView(store: previewStore(.unknownTag))
    }
}

#Preview("Wrong Scan Window") {
    ZStack {
        Color.blue.ignoresSafeArea()
        TagScanLoaderView(store: previewStore(.wrongScanWindow))
    }
}

#Preview("Error") {
    ZStack {
        Color.blue.ignoresSafeArea()
        TagScanLoaderView(store: previewStore(.error("Bork Bork")))
    }
}

