//
//  ReaderState.swift
//  RW2
//
//  Created by Christopher Hotchkiss on 10/11/25.
//

@frozen
public enum ReaderState: Equatable {
    /// No tag event. Also the sentinel a cancelled waiter resumes with — always silent in the UI.
    case noTag
    case tagPresent(TagSerial)
    /// A tag physically reached the reader but the UID read failed (left the field
    /// mid-read, marginal RF coupling / muteCard). User-facing: "tap again and hold".
    case tagUnreadable(String)
    /// Infrastructure failure (slot monitor init, reader gone) — not a per-tap outcome.
    case readerError(String)
}
