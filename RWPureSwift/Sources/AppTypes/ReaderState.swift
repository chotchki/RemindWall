//
//  ReaderState.swift
//  RW2
//
//  Created by Christopher Hotchkiss on 10/11/25.
//

@frozen
public enum ReaderState: Equatable {
    case noTag
    case tagPresent(TagSerial)
    case readerError(String)
}
