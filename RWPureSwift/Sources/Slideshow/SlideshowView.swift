import DataModel
import PhotosUI
import SwiftUI

public struct SlideshowView: View {
    @Environment(Settings.self) private var settings
    @Binding var state: AppState
    
    @State private var viewModel = SlideshowViewModel()
    
    public init(state: Binding<AppState>){
        self._state = state
    }
    
    public var body: some View {
        Group {
            if settings.selectedAlbumId == nil {
                //Button("Return to Settings", action: {
                //    state = .editSettings
                //})
            } else {
                GeometryReader { reader in
                    if let ca = viewModel.currentAsset {
                        AssetLoaderView(imageManager: viewModel.imageManager, asset: ca, viewSize: reader.size)
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .task {//From: https://fatbobman.com/en/posts/mastering_swiftui_task_modifier/
            while !Task.isCancelled {
                await viewModel.loadNextAsset(selectedAlbumId: settings.selectedAlbumId)
                try? await Task.sleep(nanoseconds: UInt64(10 * Double(NSEC_PER_SEC)))
            }
        }
    }
}

#Preview {
    SlideshowView(state: .constant(.dashboard))
}
