//
//  LivePhotoView.swift
//  WallScreen
//
//  Created by Christopher Hotchkiss on 1/5/24.
// https://stackoverflow.com/a/65388856/160208
import SwiftUI
import PhotosUI

public struct LivePhotoView: UIViewRepresentable {
    var livephoto: PHLivePhoto

    public init(livephoto: PHLivePhoto) {
        self.livephoto = livephoto
    }

    public func makeUIView(context: Context) -> PHLivePhotoView {
        PHLivePhotoView()
    }

    public func updateUIView(_ lpView: PHLivePhotoView, context: Context) {
        if livephoto != lpView.livePhoto {
            lpView.isMuted = true
            lpView.livePhoto = livephoto
            lpView.startPlayback(with: .full)
        }
    }
}
