import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation

/// Audible scan feedback. The NFC reader beeps on tag DETECTION regardless of
/// whether the app processed anything — these sounds confirm end-to-end processing,
/// which also works when the display is dark. Kiosk caveat: route matters — the
/// Mac's default output must be its built-in speakers, HDMI/monitor audio dies
/// when the panel sleeps.
@DependencyClient
public struct ScanSoundPlayer: Sendable {
    public var playSuccess: @Sendable () async -> Void
    public var playFailure: @Sendable () async -> Void
}

extension ScanSoundPlayer: DependencyKey {
    public static var liveValue: Self {
        let bank = SoundBank()
        return Self(
            playSuccess: { await bank.play(.success) },
            playFailure: { await bank.play(.failure) }
        )
    }

    public static let previewValue = Self(
        playSuccess: {},
        playFailure: {}
    )
}

extension ScanSoundPlayer: TestDependencyKey {
    public static let testValue = Self()
}

extension DependencyValues {
    public var scanSoundPlayer: ScanSoundPlayer {
        get { self[ScanSoundPlayer.self] }
        set { self[ScanSoundPlayer.self] = newValue }
    }
}

/// Preloads and owns the AVAudioPlayers — they must stay retained while playing.
private actor SoundBank {
    enum Sound: String {
        case success = "scan-success"
        case failure = "scan-failure"
    }

    private var players: [Sound: AVAudioPlayer] = [:]
    private var sessionConfigured = false

    func play(_ sound: Sound) {
        if !sessionConfigured {
            sessionConfigured = true
            // .playback so iPad silent mode can't mute the feedback — the whole
            // point is confirmation the family can rely on. mixWithOthers keeps
            // us from ducking anything else playing on the kiosk.
            // (AVAudioSession is iOS/Catalyst API; pure-macOS builds — swift test —
            // don't have it and don't need it.)
            #if !os(macOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
        }

        if players[sound] == nil {
            guard let url = Bundle.module.url(forResource: sound.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else {
                return
            }
            player.prepareToPlay()
            players[sound] = player
        }

        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }
}
