//
//  LivePhotoView.swift
//  WallScreen
//
//  Created by Christopher Hotchkiss on 1/5/24.
// https://stackoverflow.com/a/65388856/160208
import SwiftUI
import PhotosUI

#if canImport(UIKit)
/// Player lifecycle is explicit: every slide mints a fresh view under the
/// crossfade, so without it one PHLivePhotoView's player tears down while the
/// next one's spins up.
struct LivePhotoView: UIViewRepresentable {
    var livephoto: PHLivePhoto

    init(livephoto: PHLivePhoto) {
        self.livephoto = livephoto
    }

    func makeCoordinator() -> DeferredPlayback {
        DeferredPlayback()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let phlpv = PHLivePhotoView()
        phlpv.isMuted = true
        phlpv.contentMode = .scaleAspectFill
        Self.show(livephoto, in: phlpv, playback: context.coordinator)
        return phlpv
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PHLivePhotoView, context: Context) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func updateUIView(_ lpView: PHLivePhotoView, context: Context) {
        if livephoto != lpView.livePhoto {
            Self.show(livephoto, in: lpView, playback: context.coordinator)
        }
    }

    /// Releases the player now instead of whenever the view deallocs, and
    /// kills a start that hasn't fired yet.
    static func dismantleUIView(_ lpView: PHLivePhotoView, coordinator: DeferredPlayback) {
        coordinator.cancel()
        lpView.stopPlayback()
        lpView.livePhoto = nil
    }

    /// The key frame shows immediately (it carries the crossfade); motion
    /// waits for the outgoing slide's player to be gone.
    private static func show(_ livePhoto: PHLivePhoto, in lpView: PHLivePhotoView, playback: DeferredPlayback) {
        lpView.stopPlayback()
        lpView.livePhoto = livePhoto
        playback.schedule(after: SlideShowFeature.livePhotoStartDelay) { [weak lpView] in
            lpView?.startPlayback(with: .full)
        }
    }
}
#endif
