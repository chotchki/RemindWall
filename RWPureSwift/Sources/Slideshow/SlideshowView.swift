import DataModel
import PhotosUI
import SwiftUI

public struct SlideshowView: View {
    @Binding var state: AppState
    @Binding var selectedAlbumId: String?
    
    @State private var assetList: [PHAsset]?
    @State private var currentAlbumIndex: Int = 0
    @State var currentAsset: PHAsset?
        
    public init(state: Binding<AppState>, selectedAlbumId: Binding<String?>){
        self._state = state
        self._selectedAlbumId = selectedAlbumId
    }
    
    public var body: some View {
        Group {
            if selectedAlbumId == nil {
                Button("Return to Settings", action: {
                    state = .editSettings
                })
            } else {
                GeometryReader { reader in
                    if let ca = Binding($currentAsset) {
                        AssetLoaderView(asset: ca, viewSize: reader.size).onTapGesture {
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
                }
                
                try? await Task.sleep(nanoseconds: UInt64(10 * Double(NSEC_PER_SEC)))
                
                currentAlbumIndex += 1
                if currentAlbumIndex > assetList?.count ?? -1 {
                    assetList = await loadAlbumAssets(albumId: selectedAlbumId)
                    currentAlbumIndex = 0
                }
            }
        })
        .task {//From: https://fatbobman.com/en/posts/mastering_swiftui_task_modifier/
            
        }
    }
}
