import Dependencies
import DependenciesMacros
import Foundation
#if canImport(HomeKit)
import HomeKit
#endif

/// One battery-service accessory's state, as plain values - nothing
/// HomeKit-typed escapes this module.
public struct BatteryStatus: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let accessoryName: String
    public let roomName: String?
    /// 0-100; nil when the characteristic couldn't be read.
    public let levelPercent: Int?
    /// The accessory's own StatusLowBattery flag.
    public let isLow: Bool

    public init(
        id: UUID,
        accessoryName: String,
        roomName: String?,
        levelPercent: Int?,
        isLow: Bool
    ) {
        self.id = id
        self.accessoryName = accessoryName
        self.roomName = roomName
        self.levelPercent = levelPercent
        self.isLow = isLow
    }

    /// H1's alert rule: the accessory says it's low OR the level dropped
    /// under the user threshold. An unreadable level never alerts on its own.
    public func isAlertable(belowPercent threshold: Int) -> Bool {
        if isLow { return true }
        guard let levelPercent else { return false }
        return levelPercent < threshold
    }
}

/// HMHomeManagerAuthorizationStatus flattened to what callers act on.
public enum HomeKitAuthStatus: Equatable, Sendable {
    case undetermined
    case restricted
    case authorized
}

@DependencyClient
public struct HomeKitAsyncClient: Sendable {
    public var authorizationStatus: @Sendable () async -> HomeKitAuthStatus = { .undetermined }
    /// Every accessory exposing the battery service, with fresh characteristic
    /// reads (cached values can be hours old).
    public var batteryStatuses: @Sendable () async -> [BatteryStatus] = { [] }
}

extension HomeKitAsyncClient: DependencyKey {
    public static var liveValue: Self {
        #if canImport(HomeKit)
        let store = HomeKitStore()
        return Self(
            authorizationStatus: { await store.authorizationStatus() },
            batteryStatuses: { await store.batteryStatuses() }
        )
        #else
        // Pure macOS (swift test) has no HomeKit; the Mac APP is Catalyst,
        // which does. H1.1's probe decides whether Catalyst actually
        // enumerates the home from the sandbox.
        return Self(
            authorizationStatus: { .undetermined },
            batteryStatuses: { [] }
        )
        #endif
    }
}

extension HomeKitAsyncClient: TestDependencyKey {
    public static let testValue = Self()

    public static var previewValue: Self {
        Self(
            authorizationStatus: { .authorized },
            batteryStatuses: {
                [
                    BatteryStatus(
                        id: UUID(0),
                        accessoryName: "Front Door Sensor",
                        roomName: "Entry",
                        levelPercent: 8,
                        isLow: true
                    ),
                    BatteryStatus(
                        id: UUID(1),
                        accessoryName: "Bedroom Thermostat",
                        roomName: "Bedroom",
                        levelPercent: 76,
                        isLow: false
                    ),
                ]
            }
        )
    }
}

extension DependencyValues {
    public var homeKitAsync: HomeKitAsyncClient {
        get { self[HomeKitAsyncClient.self] }
        set { self[HomeKitAsyncClient.self] = newValue }
    }
}

#if canImport(HomeKit)
/// Owns the HMHomeManager (created lazily - instantiation is what triggers
/// the HomeKit permission prompt) and bridges its delegate-driven home loading
/// to async. If the first homes update never arrives (the H1.1 sandbox
/// question), callers suspend until it does - the battery poll just stays
/// empty rather than crashing.
@MainActor
private final class HomeKitStore: NSObject, HMHomeManagerDelegate {
    private var manager: HMHomeManager?
    private var homesLoaded = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// liveValue is nonisolated and constructs the store synchronously; safe
    /// because init touches no actor state - the HMHomeManager itself is
    /// created lazily on the main actor at first use.
    nonisolated override init() {
        super.init()
    }

    private func ensureManager() -> HMHomeManager {
        if let manager { return manager }
        let created = HMHomeManager()
        created.delegate = self
        manager = created
        return created
    }

    func authorizationStatus() -> HomeKitAuthStatus {
        let status = ensureManager().authorizationStatus
        if status.contains(.restricted) { return .restricted }
        if status.contains(.authorized) { return .authorized }
        return .undetermined
    }

    func batteryStatuses() async -> [BatteryStatus] {
        let manager = ensureManager()
        if !homesLoaded {
            await withCheckedContinuation { waiters.append($0) }
        }
        var result: [BatteryStatus] = []
        for home in manager.homes {
            for accessory in home.accessories {
                for service in accessory.services
                where service.serviceType == HMServiceTypeBattery {
                    let level = service.characteristics.first {
                        $0.characteristicType == HMCharacteristicTypeBatteryLevel
                    }
                    let low = service.characteristics.first {
                        $0.characteristicType == HMCharacteristicTypeStatusLowBattery
                    }
                    try? await level?.readValue()
                    try? await low?.readValue()
                    result.append(BatteryStatus(
                        id: accessory.uniqueIdentifier,
                        accessoryName: accessory.name,
                        roomName: accessory.room?.name,
                        levelPercent: level?.value as? Int,
                        isLow: (low?.value as? Int) == 1
                    ))
                }
            }
        }
        return result
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            homesLoaded = true
            let resumed = waiters
            waiters = []
            for waiter in resumed {
                waiter.resume()
            }
        }
    }
}
#endif
