//
//  SlotMonitor.swift
//  RW2
//
//  Created by Christopher Hotchkiss on 10/11/25.
//
import Combine
import CryptoTokenKit
import TagTypes

let GET_ID_APDU: Data = Data([0xFF, 0xCA, 0x00, 0x00, 0x04])

extension TKSmartCardSlot {
    typealias AsyncValues<T> = AsyncPublisher<AnyPublisher<T, Never>>
    func observeKey<T>(at path: KeyPath<TKSmartCardSlot, T>) -> AsyncValues<T> {
        return self.publisher(for: path, options: [.initial, .new])
            .buffer(size: 1, prefetch: .byRequest, whenFull: .dropOldest)
            .eraseToAnyPublisher()
            .values
    }
}

public actor SlotMonitor {
    private var slot: TKSmartCardSlot
    public init(slot: TKSmartCardSlot) {
        self.slot = slot
    }
    
    public func getNextTag() async -> ReaderState {
        for await newState in slot.observeKey(at: \.state) {
            if newState != TKSmartCardSlot.State.validCard {
                continue
            }
            
            guard let card = slot.makeSmartCard() else {
                return .noTag
            }
                
            let session = try? await card.beginSession();
            guard let session else {
                return .readerError("Could not start session")
            }
            if !session {
                return .readerError("Could not start session")
            }
                    
            guard let response = try? await card.transmit(GET_ID_APDU) else {
                card.endSession();
                return .readerError("Unable to query tag")
            }
                
            card.endSession();
                
            if response.count < 2 {
                return .readerError("Response too short \(response)")
            }
            
            let response_status = response.suffix(2)
            
            if response_status != Data([0x90, 0x00]) {
                return .readerError("Response status \(response_status) error")
            }
            
            let response_data = response.dropLast(2)
            
            if response_data.isEmpty {
                return .readerError("No Tag ID found")
            }
                
            return .tagPresent(TagSerial([UInt8](response_data)))
        }
        return .readerError("State didn't change")
    }
}
