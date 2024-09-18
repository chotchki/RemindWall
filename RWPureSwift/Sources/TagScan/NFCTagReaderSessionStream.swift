#if canImport(CoreNFC)
import CoreNFC
import Foundation

public class NFCTagReaderSessionStream: NSObject, NFCTagReaderSessionDelegate {
    lazy var stream: AsyncStream<Data> = {
        AsyncStream { (continuation: AsyncStream<Data>.Continuation) -> Void in
            self.continuation = continuation
        }
    }()
    var continuation: AsyncStream<Data>.Continuation?
    
    
    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("active session")
    }
    
    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
        print("session died")
    }
    
    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        for tag in tags {
            switch(tag){
            case let .iso7816(t):
                continuation?.yield(t.identifier)
            default:
                print("What's this?")
            }
        }
    }
}

#endif
