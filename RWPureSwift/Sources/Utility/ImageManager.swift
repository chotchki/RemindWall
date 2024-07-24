import PhotosUI
import SwiftUI

private struct ImageManagerKey: EnvironmentKey {
  static let defaultValue = PHCachingImageManager()
}

extension EnvironmentValues {
  public var imageManager: PHCachingImageManager {
    get { self[ImageManagerKey.self] }
    set { self[ImageManagerKey.self] = newValue }
  }
}
