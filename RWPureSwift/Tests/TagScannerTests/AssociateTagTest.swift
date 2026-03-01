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

@Test("Tag Scan Valid Result")
func valid_result() async throws {
    let aT = Shared(value: nil as String?);
    let testSerial = TagSerial([0x0, 0x1, 0x2]);
    
    let store = await TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
        AssociateTagFeature()
    } withDependencies: {
        $0.tagReaderClient.slotNames = {["Test Slot"]}
        $0.tagReaderClient.nextTagId = {
            _,_ in
                .tagPresent(testSerial)
        }
    }
    
    await store.send(.startScanningTapped) {state in 
        state.scanning = true
    };
    
    await store.receive(\.scanResult){state in
        state.$associatedTag.withLock{ $0 = testSerial.hexa}
        state.scanning = false
    };
}

@Test("Tag Scan No Tag")
func no_tag() async throws {
    let aT = Shared(value: nil as String?);
    
    let store = await TestStore(initialState: AssociateTagFeature.State(associatedTag: aT)) {
        AssociateTagFeature()
    } withDependencies: {
        $0.tagReaderClient.slotNames = {["Test Slot"]}
        $0.tagReaderClient.nextTagId = {
            _,_ in
                .noTag
        }
    }
    
    await store.send(.startScanningTapped) {state in
        state.scanning = true
    };
    
    await store.receive(\.scanResult){state in
        state.$associatedTag.withLock{ $0 = nil}
        state.scanning = false
    };
}
