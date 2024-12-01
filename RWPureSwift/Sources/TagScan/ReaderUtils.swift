import CryptoTokenKit
import Foundation
import Deadline

public class ReaderUtils {
    public static func getNextTag() async -> TagId? {
        let reader = ReaderDevice()
        var slot: TKSmartCardSlot?
        
        while !Task.isCancelled {
            if slot == nil {
                slot = reader.getFirstSlot()
            }
            guard let slot else {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            
            if case let .tagPresent(tag) = await reader.getTagId(slot: slot) {
                return tag
            }
            
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        //This should only occur due to cancellation
        return nil
    }
    
    public static func getNextTag(timeout: ContinuousClock.Duration) async -> TagId? {
        return try? await deadline(until: .now + timeout){
            let reader = ReaderDevice()
            var slot: TKSmartCardSlot?
            
            while !Task.isCancelled {
                if slot == nil {
                    slot = reader.getFirstSlot()
                }
                guard let slot else {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }
                
                if case let .tagPresent(tag) = await reader.getTagId(slot: slot) {
                    return tag
                }
                
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            return nil
        }
    }
}
