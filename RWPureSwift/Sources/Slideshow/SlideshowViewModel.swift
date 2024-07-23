import PhotosUI

@Observable
public class SlideshowViewModel {
    var imageManager: PHCachingImageManager

    var albumContents: [PHAsset]?
    var currentAlbumIndex: Int = 0
    var currentAsset: PHAsset?
    
    public init(){
        self.imageManager = PHCachingImageManager()
    }
    
    @MainActor
    private func updateAlbumContents(contents: [PHAsset]?) async {
        self.albumContents = contents
    }
    
    @MainActor
    private func updateCurrentAlbum(index: Int, asset: PHAsset?) async {
        self.currentAlbumIndex = index
        self.currentAsset = asset
    }
    
    public func loadNextAsset(selectedAlbumId: String?) async {
        guard let albumId = selectedAlbumId else {
            await self.updateAlbumContents(contents: nil)
            return
        }
        
        let albumContents = self.albumContents
        var currentIndex = self.currentAlbumIndex
        
        currentIndex += 1
        Task {
            if albumContents == nil || albumContents?.count ?? -1 < currentAlbumIndex + 1 {
                guard let fetchAlbumObj = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: baseFetchOptions()).firstObject else {
                    await self.updateAlbumContents(contents: nil)
                    return
                }
                
                let fetchResult = PHAsset.fetchAssets(in: fetchAlbumObj, options: albumContentsFetchOptions())
                
                // The caching image manager demands an array so we can't leverage the fetchresult
                var contents: [PHAsset] = []
                fetchResult.enumerateObjects({ obj, _, _ in
                    contents.append(obj)
                })
                contents.shuffle()
                
                await self.updateAlbumContents(contents: contents)
                await self.updateCurrentAlbum(index: 0, asset: contents.first)
                return
            }
            
            guard let ac = albumContents else { return }
            await self.updateCurrentAlbum(index: currentAlbumIndex, asset: ac[currentAlbumIndex])
        }
    }
}
