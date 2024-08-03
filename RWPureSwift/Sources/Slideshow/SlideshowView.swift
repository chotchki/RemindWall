import AppModel
import DataModel
import PhotosUI
import SwiftUI

public struct SlideshowView: View {
    @Binding var state: AppState
    @Binding var selectedAlbumId: String?
    
    @State private var assetList: [PHAsset]?
    @State private var currentAlbumIndex: Int = 0
    
    @State var currentAsset: PHAsset?
    @State var nextAsset: PHAsset?
        
    public init(state: Binding<AppState>, selectedAlbumId: Binding<String?>){
        self._state = state
        self._selectedAlbumId = selectedAlbumId
    }
    
    public var body: some View {
        Group {
            if selectedAlbumId == nil {
                ContentUnavailableView {
                    Label("Slideshow Not Configured", systemImage: "photo.stack")
                } description: {
                    Button("Return to Settings", action: {
                        state = .editSettings
                    })
                }
            } else {
                GeometryReader { reader in
                    if let ca = currentAsset {
                        AssetLoaderView(asset: ca, nextAsset: nextAsset, frame: reader.frame(in: .local)).onTapGesture {
                            state = .editSettings
                        }
                    } else {
                        VStack {
                            ProgressView()
                            Button("Return to Settings", action: {
                                state = .editSettings
                            })
                        }
                    }
                }
            }
        }
        .task(id: selectedAlbumId, {
            assetList = await loadAlbumAssets(albumId: selectedAlbumId)
            
            while !Task.isCancelled {
                if let al = assetList{
                    if al.count > currentAlbumIndex {
                        currentAsset = al[currentAlbumIndex]
                    }
                    
                    if al.count > currentAlbumIndex + 1 {
                        nextAsset = al[currentAlbumIndex + 1]
                    }
                }
                
                try? await Task.sleep(nanoseconds: UInt64(10 * Double(NSEC_PER_SEC)))
                
                currentAlbumIndex += 1
                if currentAlbumIndex > assetList?.count ?? -1 {
                    assetList = await loadAlbumAssets(albumId: selectedAlbumId)
                    currentAlbumIndex = 0
                }
            }
        })
    }
}
