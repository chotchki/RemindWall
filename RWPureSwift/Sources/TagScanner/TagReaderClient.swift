//
//  TagScanner.swift
//  RW2
//
//  Created by Christopher Hotchkiss on 10/6/25.
//

import AppTypes
import Dependencies
import DependenciesMacros


@DependencyClient
public struct TagReaderClient: Sendable {
    public var nextTagId: @Sendable () async -> ReaderState = {.noTag}
}

extension TagReaderClient: DependencyKey {
    public static var liveValue: Self {
        let smartCardMonitor = SmartCardMonitor.shared

        return Self(
            nextTagId: {
                return await smartCardMonitor.nextValidCard()
            })
        }
    public static let previewValue = TagReaderClient(
        nextTagId: {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000);
            return .tagPresent(TagSerial([0x0, 0x1, 0x2]))
        }
    )
}

extension TagReaderClient: TestDependencyKey {
    public static let testValue = Self()
}

extension DependencyValues {
  public var tagReaderClient: TagReaderClient {
    get { self[TagReaderClient.self] }
    set { self[TagReaderClient.self] = newValue }
  }
}
