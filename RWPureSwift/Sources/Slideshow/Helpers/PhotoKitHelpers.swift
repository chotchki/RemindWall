import PhotosUI
import PhotoKitAsync

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
