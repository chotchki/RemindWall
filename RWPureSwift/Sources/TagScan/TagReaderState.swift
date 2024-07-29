public enum TagReaderState: Equatable {
    case loading
    case noReader
    case waitingForRequest
    case waitingForTag
    case readTag([UInt8])
    case readerError(String)
}
