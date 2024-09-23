//
//  FetchOptions.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 9/22/24.
//
import Photos

// These are common settings for fetches in PhotoKit
public func baseFetchOptions() -> PHFetchOptions {
    // From: https://stackoverflow.com/a/49495326/160208
    // We don't sort because we'll be shuffling anyway
    let pfo = PHFetchOptions()
    pfo.includeHiddenAssets = false

    return pfo
}

public func albumContentsFetchOptions() -> PHFetchOptions {
    let pfo = baseFetchOptions()

    // Get all still images
    let imagesPredicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

    // Get all live photos
    let liveImagesPredicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue)

    // Merge them all
    pfo.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [liveImagesPredicate, imagesPredicate])

    return pfo
}

public func getContentMode() -> PHImageContentMode {
    return PHImageContentMode.aspectFill
}

public func imageRequestOptions() -> PHImageRequestOptions {
    let iro = PHImageRequestOptions()
    iro.isNetworkAccessAllowed = true
    iro.isSynchronous = true
    iro.deliveryMode = .highQualityFormat
    iro.version = .current
    return iro
}

public func livePhotoRequestOptions() -> PHLivePhotoRequestOptions {
    let lpro = PHLivePhotoRequestOptions()
    lpro.isNetworkAccessAllowed = true
    lpro.deliveryMode = PHImageRequestOptionsDeliveryMode.highQualityFormat
    return lpro
}
