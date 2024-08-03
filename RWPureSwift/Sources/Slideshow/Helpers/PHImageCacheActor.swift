import Foundation
import PhotosUI

@globalActor actor PHImageCacheActor: GlobalActor {
    static let shared = PHImageCacheActor()
    
    let cache = PHCachingImageManager()
    
    public func loadAsset(asset: PHAsset, viewSize: CGSize) async -> AssetType {
        let result = await Task {
            return await withCheckedContinuation({ continuation in
                if asset.mediaSubtypes.contains(PHAssetMediaSubtype.photoLive){
                    cache.requestLivePhoto(for: asset, targetSize: viewSize, contentMode: getContentMode(), options: livePhotoRequestOptions(), resultHandler: { livephoto, _ in
                            if let lp = livephoto {
                                continuation.resume(returning: AssetType.livePhoto(lp))
                            } else {
                                continuation.resume(returning: .errorPhoto)
                            }
                    })
                } else if asset.mediaType == PHAssetMediaType.image {
                    cache.requestImage(for: asset, targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions(), resultHandler: {
                            imageloaded, _ in
                                if let il = imageloaded {
                                    continuation.resume(returning: .staticImage(il))
                                } else {
                                    continuation.resume(returning: .errorPhoto)
                                }
                        })
                } else {
                    continuation.resume(returning: .errorPhoto)
                }
            })
        }.value
        
        return result
    }
    
    public func startCaching(asset: PHAsset, viewSize: CGSize) {
        cache.startCachingImages(for: [asset], targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions())
    }
    
    public func unloadCache(asset: PHAsset, viewSize: CGSize) {
        cache.stopCachingImages(for: [asset], targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions())
    }
}
