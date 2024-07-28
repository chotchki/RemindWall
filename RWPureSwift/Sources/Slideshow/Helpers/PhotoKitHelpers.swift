import PhotosUI

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


public func loadAlbumAssets(albumId: String?) async -> [PHAsset]? {
    guard let albumId = albumId else {
        return nil
    }
    
    let result = await Task {
        guard let fetchAlbumObj = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: baseFetchOptions()).firstObject else {
            return nil as [PHAsset]?
        }
        
        let fetchResult = PHAsset.fetchAssets(in: fetchAlbumObj, options: albumContentsFetchOptions())
        
        // The caching image manager demands an array so we can't leverage the fetchresult
        var contents: [PHAsset] = []
        fetchResult.enumerateObjects({ obj, _, _ in
            contents.append(obj)
        })
        contents.shuffle()
        
        return contents
    }.value

    return result
}

public enum AssetType: Equatable, Sendable {
    case loading
    case staticImage(UIImage)
    case livePhoto(PHLivePhoto)
    case errorPhoto
}

// Based on my reading here: https://developer.apple.com/documentation/swift/sendable
// NSCopyable should qualify as sendable
extension PHLivePhoto: @unchecked Sendable {}
