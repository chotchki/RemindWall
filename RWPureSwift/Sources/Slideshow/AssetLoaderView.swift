import PhotosUI
import SwiftUI
import Utility

public struct AssetLoaderView: View {
    let asset: PHAsset
    let nextAsset: PHAsset?
    
    let frame: CGRect
    
    @State private var assetType: AssetType = .loading
    @State private var align: Alignment = .topLeading

    public init(asset: PHAsset, nextAsset: PHAsset?, frame: CGRect) {
        self.asset = asset
        self.nextAsset = nextAsset
        
        self.frame = frame
    }

    public var body: some View {
        KenBurnsPanView(assetType: assetType, size: frame.size)
        .task(id: asset, {
            self.align = .topLeading
            self.assetType = await PHImageCacheActor.shared.loadAsset(asset: asset, viewSize: frame.size)
            
            withAnimation(.linear(duration: 10)) {
                self.align = .bottomTrailing
            }
            
            if let nA = nextAsset {
                await PHImageCacheActor.shared.startCaching(asset: nA, viewSize: frame.size)
            }
        })
        .onDisappear(perform: {
            Task {
                await PHImageCacheActor.shared.unloadCache(asset: asset, viewSize: frame.size)
            }
        })
    }
}
