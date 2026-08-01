import Foundation
import Tagged

/// The battery accessories the household has told to shut up (a hardwired
/// door reporting 0% was the founding member). Keyed by accessory NAME, not
/// uniqueIdentifier: HomeKit UUIDs differ per user device, names are shared
/// home data and HomeKit enforces their uniqueness within a home - so the
/// list syncs meaningfully to every panel.
///
/// Encoding: a JSON array of names, sorted so equal sets produce equal raw
/// values (stable sync writes, deterministic tests).
public enum BatteryIgnoreListTag {}
public typealias BatteryIgnoreList = Tagged<BatteryIgnoreListTag, String>

extension BatteryIgnoreList {
    public static let empty = BatteryIgnoreList(rawValue: "[]")

    public var names: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: Data(rawValue.utf8))) ?? []
    }

    public func contains(_ name: String) -> Bool {
        names.contains(name)
    }

    public func toggling(_ name: String) -> BatteryIgnoreList {
        var set = names
        if set.contains(name) {
            set.remove(name)
        } else {
            set.insert(name)
        }
        let data = (try? JSONEncoder().encode(set.sorted())) ?? Data("[]".utf8)
        return BatteryIgnoreList(rawValue: String(decoding: data, as: UTF8.self))
    }
}
