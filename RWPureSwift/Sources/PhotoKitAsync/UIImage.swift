//
//  UIImage.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 3/1/26.
//
// Idea from here on how to handle the UImage vs NSImage problem https://www.swiftbysundell.com/tips/making-uiimage-macos-compatible/

#if os(macOS)
import Cocoa

// Step 1: Typealias UIImage to NSImage
public typealias UIImage = NSImage

// Step 2: You might want to add these APIs that UIImage has but NSImage doesn't.
extension NSImage {
    var cgImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)

        return cgImage(forProposedRect: &proposedRect,
                       context: nil,
                       hints: nil)
    }

    //convenience init?(named name: String) {
    //    self.init(named: Name(name))
    //}
}

#endif
