//
//  TagId.swift
//  RW2
//
//  Created by Christopher Hotchkiss on 10/11/25.
//
import Foundation
import Tagged

public enum TagSerialTag {}
public typealias TagSerial = Tagged<TagSerialTag, [UInt8]>

extension TagSerial {
    public var hexa: String {
        return self.map{ String(format:"%02X", $0) }.joined()
    }
}


    
    
    ///From: https://stackoverflow.com/a/33548238
    /*public var description: String {
        var startIndex = self.value.startIndex
        return (0..<self.value.count/2).compactMap { _ in
            let endIndex = self.value.index(after: startIndex)
            defer { startIndex = index(after: endIndex) }
            return UInt8(self.value[startIndex...endIndex], radix: 16)
        }
    }*/
