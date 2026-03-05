import AppTypes
@preconcurrency import Combine
import CryptoTokenKit

//Using Combine due to bug https://github.com/swiftlang/swift-corelibs-foundation/issues/3807
// Apple Feedback FB22134295

final class CancellableHolder: @unchecked Sendable {
    var cancellables = Set<AnyCancellable>()
}

let GET_ID_APDU: Data = Data([0xFF, 0xCA, 0x00, 0x00, 0x04])

// Merge multiple async sequences
func observeMultipleSlots(_ slots: [TKSmartCardSlot]) -> AsyncStream<SlotName> {
    AsyncStream<SlotName> { continuation in
        // Check current state of each slot before observing changes,
        // so tags already on the reader are detected immediately.
        for slot in slots {
            if slot.state == .validCard {
                continuation.yield(SlotName(slot.name))
            }
        }

        let holder = CancellableHolder()
        for slot in slots {
            slot.publisher(for: \.state, options: [.new])
                .sink { state in
                    if state == .validCard {
                        continuation.yield(SlotName(slot.name))
                    } else {
                        print("change of \(state)")
                    }
                }
                .store(in: &holder.cancellables)
        }

        continuation.onTermination = { _ in
            holder.cancellables.removeAll()
        }
    }
}

public actor SlotMonitor {
    private let slotManager = TKSmartCardSlotManager.default

    public func getNextTag() async -> ReaderState {
        guard let slotManager = slotManager else {
            return .readerError("Unable to get the slot manager")
        }
        
        var slots: [TKSmartCardSlot] = []
        for slotName in slotManager.slotNames {
            guard let slot = await slotManager.getSlot(withName: slotName) else {
                return .readerError("Slot disappeared during setup")
            }
            slots.append(slot)
        }
        
        guard !slots.isEmpty else {
            return .readerError("No slots available")
        }
        
        for await slotName in observeMultipleSlots(slots) {
            // Found a valid card, now get the slot again to access it
            guard let activeSlot = await slotManager.getSlot(withName: slotName.rawValue) else {
                continue
            }
            
            guard let card = activeSlot.makeSmartCard() else {
                return .noTag
            }
            
            do {
                try await card.beginSession()
            } catch {
                return .readerError("Could not start session: \(error)")
            }
            
            defer {
                card.endSession()
            }
            
            guard let response = try? await card.transmit(GET_ID_APDU) else {
                return .readerError("Unable to query tag")
            }
            
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
        return .noTag
    }
}
