import CryptoTokenKit

let GET_ID_APDU: Data = Data([0xFF, 0xCA, 0x00, 0x00, 0x04])

public typealias TagId = [UInt8]

public class ReaderDevice {
    public func getFirstSlot() -> TKSmartCardSlot? {
        guard let slotManager = TKSmartCardSlotManager.default else {
            return nil
        }
        
        guard let slotName = slotManager.slotNames.first else {
            return nil
        }
        
        guard let slot = slotManager.slotNamed(slotName) else {
            return nil
        }
        
        return slot
    }
    
    
    @frozen
    public enum State: Equatable {
        case noTag
        case tagPresent(TagId)
        case readerError(String)
    }
    
    public func getTagId(slot: TKSmartCardSlot) async -> State {
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
            
        return .tagPresent([UInt8](response_data))
    }
}
