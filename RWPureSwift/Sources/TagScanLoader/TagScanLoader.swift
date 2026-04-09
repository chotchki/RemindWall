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
    case error(String)
}

@Reducer
public struct TagScanLoaderFeature: Sendable {
    @Dependency(\.tagReaderClient) var tagReaderClient
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar
    @Dependency(\.continuousClock) var clock

    @ObservableState
    public struct State: Equatable {
        public var scanResult: ScanResult?
        public init() {}
    }

    public enum Action: Equatable {
        case startMonitoring
        case _tagScanned(ReaderState)
        case _scanProcessed(ScanResult)
        case dismissResult
    }

    enum CancelID { case scanLoop, autoDismiss }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startMonitoring:
                return .run { send in
                    while !Task.isCancelled {
                        let result = await tagReaderClient.nextTagId()
                        await send(._tagScanned(result))
                    }
                }
                .cancellable(id: CancelID.scanLoop, cancelInFlight: true)

            case let ._tagScanned(readerState):
                switch readerState {
                case .noTag:
                    return .none
                case .readerError:
                    return .none
                case .tagPresent(let tagSerial):
                    return .run { [database, now, calendar] send in
                        let result: ScanResult = try await database.write { db in
                            let allReminders = try ReminderTime.all.fetchAll(db)
                            guard let reminder = allReminders.first(where: {
                                $0.associatedTag == tagSerial
                            }) else {
                                return .unknownTag
                            }

                            guard reminder.isScannable(date: now, calendar: calendar) else {
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
                    }
                }

            case let ._scanProcessed(result):
                state.scanResult = result
                return .run { send in
                    try await clock.sleep(for: .seconds(5))
                    await send(.dismissResult)
                }
                .cancellable(id: CancelID.autoDismiss, cancelInFlight: true)

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

