//
//  TagScannerTest.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 12/6/25.
//
import ComposableArchitecture
@testable import TagScanner
import AppTypes
import Testing

//@Test("Tag Scan Valid Result")
func valid_result() async throws {
    let aT = Shared(value: nil as TagSerial?);
    let testSerial = TagSerial([0x0, 0x1, 0x2]);
    
    let store = await TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
        AssociateTagFeature()
    } withDependencies: {
        $0.tagReaderClient.nextTagId = {
                .tagPresent(testSerial)
        }
    }
    
    await store.send(.startScanningTapped) {state in 
        state.scanning = true
    };
    
    await store.receive(\.scanResult){state in
        state.$associatedTag.withLock{ $0 = testSerial}
        state.scanning = false
    };
}

//@Test("Tag Scan No Tag")
func no_tag() async throws {
    let aT = Shared(value: nil as TagSerial?);

    let store = await TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
        AssociateTagFeature()
    } withDependencies: {
        $0.tagReaderClient.nextTagId = {
                .noTag
        }
    }

    await store.send(.startScanningTapped) {state in
        state.scanning = true
    };

    await store.receive(\.scanResult){state in
        state.$associatedTag.withLock{ $0 = nil}
        state.scanning = false
        state.errorMessage = "No tag detected. Please try again."
    };
}

//@Test("Tag Scan Reader Error")
func reader_error() async throws {
    let aT = Shared(value: nil as TagSerial?)

    let store = await TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
        AssociateTagFeature()
    } withDependencies: {
        $0.tagReaderClient.nextTagId = {
            .readerError("Connection failed")
        }
    }

    await store.send(.startScanningTapped) { state in
        state.scanning = true
    }

    await store.receive(\.scanResult) { state in
        state.scanning = false
        state.errorMessage = "Connection failed"
    }
}

//@Test("Cancel Scanning Tapped")
func cancel_scanning() async throws {
    let aT = Shared(value: nil as TagSerial?)

    let store = await TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
        AssociateTagFeature()
    } withDependencies: {
        $0.tagReaderClient.nextTagId = {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            return .noTag
        }
    }

    await store.send(.startScanningTapped) { state in
        state.scanning = true
    }

    await store.send(.cancelScanningTapped) { state in
        state.scanning = false
    }
}

//@Test("Dismiss Error clears error message")
func dismiss_error() async throws {
    let aT = Shared(value: nil as TagSerial?)

    var initialState = AssociateTagFeature.State(associatedTag: aT)
    initialState.errorMessage = "Some error"

    let store = await TestStore(initialState: initialState) {
        AssociateTagFeature()
    }

    await store.send(.dismissError) { state in
        state.errorMessage = nil
    }
}
