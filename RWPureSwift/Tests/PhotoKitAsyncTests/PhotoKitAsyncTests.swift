import DependenciesTestSupport
import Photos
import Testing

@testable import PhotoKitAsync

@Suite("PhotoKitAsync Tests", .dependencies {
    $0.uuid = .incrementing
})
struct PhotoKitAsyncTests {

    // MARK: - PHFetchResultCollection Tests

    @Test("empty fetch result collection has zero count")
    func emptyFetchResultCollection() {
        let collection = PHFetchResultCollection<PHAssetCollection>()
        #expect(collection.startIndex == 0)
        #expect(collection.endIndex == 0)
        #expect(collection.isEmpty)
    }

    // MARK: - PHFetchResultCollectionMock Tests

    @Test("mock collection returns items in reverse order")
    func mockCollectionReverseOrder() {
        let mock1 = PHAssetCollectionMock(title: "First")
        let mock2 = PHAssetCollectionMock(title: "Second")
        let collection = PHFetchResultCollectionMock<PHAssetCollection>([mock1, mock2])

        #expect(collection.count == 2)
        #expect(collection[0].localizedTitle == "Second")
        #expect(collection[1].localizedTitle == "First")
    }

    @Test("mock collection with single item")
    func mockCollectionSingleItem() {
        let mock = PHAssetCollectionMock(title: "Only Album")
        let collection = PHFetchResultCollectionMock<PHAssetCollection>([mock])

        #expect(collection.count == 1)
        #expect(collection[0].localizedTitle == "Only Album")
    }

    @Test("empty mock collection has zero count")
    func emptyMockCollection() {
        let collection = PHFetchResultCollectionMock<PHAssetCollection>([])
        #expect(collection.isEmpty)
        #expect(collection.startIndex == 0)
        #expect(collection.endIndex == 0)
    }

    // MARK: - PHAssetCollectionMock Tests

    @Test("mock asset collection stores title")
    func mockAssetCollectionTitle() {
        let mock = PHAssetCollectionMock(title: "Test Album")
        #expect(mock.localizedTitle == "Test Album")
    }

    @Test("mock asset collection has unique identifier")
    func mockAssetCollectionIdentifier() {
        let mock1 = PHAssetCollectionMock(title: "Album 1")
        let mock2 = PHAssetCollectionMock(title: "Album 2")
        #expect(!mock1.localIdentifier.isEmpty)
        #expect(!mock2.localIdentifier.isEmpty)
        #expect(mock1.localIdentifier != mock2.localIdentifier)
    }

    // MARK: - FetchOptions Tests

    @Test("baseFetchOptions does not include hidden assets")
    func baseFetchOptionsNoHidden() {
        let options = baseFetchOptions()
        #expect(options.includeHiddenAssets == false)
    }

    @Test("albumContentsFetchOptions has predicate for images and live photos")
    func albumContentsFetchOptionsPredicate() {
        let options = albumContentsFetchOptions()
        #expect(options.predicate != nil)
        #expect(options.includeHiddenAssets == false)
    }

    @Test("getContentMode returns aspectFill")
    func contentModeIsAspectFill() {
        let mode = getContentMode()
        #expect(mode == .aspectFill)
    }

    @Test("imageRequestOptions has correct settings")
    func imageRequestOptionsSettings() {
        let options = imageRequestOptions()
        #expect(options.isNetworkAccessAllowed == true)
        #expect(options.isSynchronous == true)
        #expect(options.deliveryMode == .highQualityFormat)
        #expect(options.version == .current)
    }

    @Test("livePhotoRequestOptions has correct settings")
    func livePhotoRequestOptionsSettings() {
        let options = livePhotoRequestOptions()
        #expect(options.isNetworkAccessAllowed == true)
        #expect(options.deliveryMode == .highQualityFormat)
    }

}
