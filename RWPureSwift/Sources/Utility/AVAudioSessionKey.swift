import AVFAudio
import SwiftUI

public struct AVAudioSessionKey: EnvironmentKey {
  public static let defaultValue: AVAudioSession = {
      let session = AVAudioSession.sharedInstance()
      try! session.setCategory(.ambient)
      return session
  }()
}

extension EnvironmentValues {
  public var aVAudioSession: AVAudioSession {
    get { self[AVAudioSessionKey.self] }
    set { self[AVAudioSessionKey.self] = newValue }
  }
}
