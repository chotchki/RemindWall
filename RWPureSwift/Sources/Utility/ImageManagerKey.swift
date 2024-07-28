import PhotosUI
import SwiftUI

public struct ImageManagerKey: EnvironmentKey {
  public static let defaultValue = PHCachingImageManager()
}

extension EnvironmentValues {
  public var imageManager: PHCachingImageManager {
    get { self[ImageManagerKey.self] }
    set { self[ImageManagerKey.self] = newValue }
  }
}
