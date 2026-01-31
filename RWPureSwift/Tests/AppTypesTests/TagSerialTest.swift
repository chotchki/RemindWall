//
//  TagIdTest.swift
//  RW2
//
//  Created by Christopher Hotchkiss on 10/11/25.
//
import AppTypes
import Testing

@Test("Convert to strings", arguments: [
    ([0x01, 0x02, 0x03], "010203")
])
func conversion(value: [UInt8], expected: String) async throws {
    let tagId = TagSerial(value);
    #expect(tagId.hexa == expected)
}
