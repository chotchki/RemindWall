//
//  AssetType.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 9/22/24.
//
import PhotosUI

public enum AssetType: Sendable, Equatable {
    case loading
    case staticImage(UIImage)
    case livePhoto(PHLivePhoto)
    case errorPhoto
}
