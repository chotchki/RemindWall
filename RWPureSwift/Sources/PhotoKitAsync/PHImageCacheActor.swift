import Foundation
import PhotosUI

@globalActor public actor PHImageCacheActor: GlobalActor {
    public static let shared = PHImageCacheActor()
    
    let cache = PHCachingImageManager()
    
    public func loadAsset(asset: PHAsset, viewSize: CGSize) async -> AssetType {
        if asset.mediaSubtypes.contains(PHAssetMediaSubtype.photoLive){
            return await withCheckedContinuation({ continuation in
                cache.requestLivePhoto(for: asset, targetSize: viewSize, contentMode: getContentMode(), options: livePhotoRequestOptions(), resultHandler: { livephoto, _ in
                    if let lp = livephoto {
                        continuation.resume(returning: .livePhoto(LivePhotoWrapper(lp)))
                    } else {
                        continuation.resume(returning: .errorPhoto)
                    }
                })
            })
        } else if asset.mediaType == PHAssetMediaType.image {
            return await withCheckedContinuation({ continuation in
                cache.requestImage(for: asset, targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions(), resultHandler: {
                        imageloaded, _ in
                            if let il = imageloaded {
                                continuation.resume(returning: .staticImage(il))
                            } else {
                                continuation.resume(returning: .errorPhoto)
                            }
                    })
            })
        } else {
            return AssetType.errorPhoto
        }
    }
    
    public func startCaching(asset: PHAsset, viewSize: CGSize) {
        cache.startCachingImages(for: [asset], targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions())
    }
    
    public func unloadCache(asset: PHAsset, viewSize: CGSize) {
        cache.stopCachingImages(for: [asset], targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions())
    }
}
