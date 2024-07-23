import PhotosUI

@Observable
public class AssetLoaderViewModel {
    public let asset: PHAsset
    public let viewSize: CGSize
    
    public var assetType: AssetType = .loading
    
    public init(asset: PHAsset, viewSize: CGSize) {
        self.asset = asset
        self.viewSize = viewSize
    }
    
    @MainActor
    private func updateAssetType(_: AssetType) async -> (){
        self.assetType = assetType
    }
    
    public func load(imageManager: PHCachingImageManager) async -> (){
        //Ignore caching the next image for now
        let assetType = await withCheckedContinuation({ (continuation: CheckedContinuation<AssetType, Never>) in
            if asset.mediaSubtypes.contains(PHAssetMediaSubtype.photoLive){
                imageManager.requestLivePhoto(for: asset, targetSize: viewSize, contentMode: getContentMode(), options: livePhotoRequestOptions(), resultHandler: { livephoto, _ in
                        if let lp = livephoto {
                            continuation.resume(returning: AssetType.livePhoto(lp))
                        } else {
                            continuation.resume(returning: AssetType.errorPhoto)
                        }
                })
            } else if asset.mediaType == PHAssetMediaType.image {
                    imageManager.requestImage(for: asset, targetSize: viewSize, contentMode: getContentMode(), options: imageRequestOptions(), resultHandler: {
                        imageloaded, _ in
                            if let il = imageloaded {
                                continuation.resume(returning: AssetType.staticImage(il))
                            } else {
                                continuation.resume(returning: AssetType.errorPhoto)
                            }
                    })
            } else {
                continuation.resume(returning: AssetType.errorPhoto)
            }
        })
        await self.updateAssetType(assetType)
    }
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
