//
//  ToSlideshowWithCalendarCrash.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 4/9/26.
//

@MainActor
@Suite("Reproducing a crash", .dependencies {
    $0.defaultDatabase = try! $0.appDatabase()
    $0.uuid = .incrementing
})
struct ToSlideshowWithCalendarCrash async {
    @Test("Load Settings, enable calendar, start slideshow, return to settings")
    func test() async {
        let store = TestStore(initialState: AppNavigationFeature.State()) {
            AppNavigationFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(Date())
            $0.calendar = .current
            $0.screenControl.getBrightness = { 0.75 }
            $0.screenControl.setBrightness = { _ in }
        }

        store.exhaustivity = .off
        
        await store.send(.onAppear)
        await store.receive(\.screenOffMonitor.startMonitoring)
        await store.finish()
    }
}
