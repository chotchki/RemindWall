// Observation plumbing mirrors sqlite-data's internal FetchKey:
// https://github.com/pointfreeco/sqlite-data/blob/main/Sources/SQLiteData/Internal/FetchKey.swift
@preconcurrency import Combine
import AppTypes
import CryptoKit
import Dependencies
import Foundation
import GRDB
import Sharing
import SQLiteData
import Synchronization
import Tagged

/// In-flight local save counts per setting key. While a local save is
/// pending, observation emissions are suppressed: the in-memory value is
/// newer than whatever the database says, and a stale echo of save N must
/// never clobber write N+1. The final commit's emission (or the equality of
/// in-memory with what was written) always reconciles.
private let pendingSaves = Mutex<[String: Int]>([:])

/// String round-trip for values stored through `.syncedSetting`.
///
/// The string is the same one `.appStorage` persists for
/// `RawRepresentable<String>` types, so a one-time seed from UserDefaults can
/// copy values verbatim.
public protocol SyncedSettingValue: Sendable {
    var settingValue: String { get }
    init?(settingValue: String)
}

extension String: SyncedSettingValue {
    public var settingValue: String { self }
    public init?(settingValue: String) { self = settingValue }
}

extension Bool: SyncedSettingValue {
    public var settingValue: String { self ? "true" : "false" }
    public init?(settingValue: String) {
        switch settingValue {
        case "true": self = true
        case "false": self = false
        default: return nil
        }
    }
}

extension Int: SyncedSettingValue {
    public var settingValue: String { String(self) }
    public init?(settingValue: String) {
        guard let value = Int(settingValue) else { return nil }
        self = value
    }
}

extension Tagged: SyncedSettingValue where RawValue == String {
    public var settingValue: String { rawValue }
    public init?(settingValue: String) { self.init(rawValue: settingValue) }
}

extension SharedKey {
    /// A setting replicated across devices through the CloudKit-synced
    /// `settings` table. A missing or undecodable row falls back to the
    /// `@Shared` default.
    public static func syncedSetting<V>(_ key: String) -> Self
    where Self == SyncedSettingKey<V>, V: SyncedSettingValue {
        SyncedSettingKey(
            key: key,
            encode: { $0.settingValue },
            decode: { raw in raw.flatMap(V.init(settingValue:)) }
        )
    }

    /// Optional flavor: writing nil deletes the row; a missing row falls back
    /// to the `@Shared` default (nil unless one is given).
    public static func syncedSetting<V>(_ key: String) -> Self
    where Self == SyncedSettingKey<V?>, V: SyncedSettingValue {
        SyncedSettingKey(
            key: key,
            encode: { $0?.settingValue },
            decode: { raw -> V?? in
                guard let raw, let value = V(settingValue: raw) else { return .none }
                return .some(.some(value))
            }
        )
    }
}

/// A `SharedKey` persisting one value in the `settings` table.
///
/// Reads resolve by key with the newest `lastModified` winning. Writes upsert a
/// row whose id derives deterministically from the key (UUIDv5), so every
/// device targets the same primary key and the sync engine merges concurrent
/// writes into one record instead of accumulating per-device duplicates. A
/// GRDB ValueObservation feeds SyncEngine-applied remote writes back into live
/// UI.
public struct SyncedSettingKey<Value: Sendable>: SharedKey {
    private let key: String
    private let database: any DatabaseWriter
    private let encode: @Sendable (Value) -> String?
    private let decode: @Sendable (String?) -> Value?

    fileprivate init(
        key: String,
        encode: @escaping @Sendable (Value) -> String?,
        decode: @escaping @Sendable (String?) -> Value?
    ) {
        @Dependency(\.defaultDatabase) var defaultDatabase
        self.key = key
        self.database = defaultDatabase
        self.encode = encode
        self.decode = decode
    }

    public struct ID: Hashable {
        fileprivate let key: String
        fileprivate let databaseID: ObjectIdentifier
        fileprivate let valueType: ObjectIdentifier
    }

    public var id: ID {
        ID(
            key: key,
            databaseID: ObjectIdentifier(database),
            valueType: ObjectIdentifier(Value.self)
        )
    }

    public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
        guard case .userInitiated = context else {
            // At `@Shared` init the subscription delivers the first row
            // synchronously; a read here would be a duplicate.
            continuation.resumeReturningInitialValue()
            return
        }
        let key = key
        let decode = decode
        database.asyncRead { dbResult in
            let result = dbResult.flatMap { db in
                Result { try Self.currentRawValue(db, key: key) }
            }
            switch result {
            case .success(let raw):
                if let value = decode(raw) {
                    continuation.resume(returning: value)
                } else {
                    continuation.resumeReturningInitialValue()
                }
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    public func subscribe(
        context: LoadContext<Value>, subscriber: SharedSubscriber<Value>
    ) -> SharedSubscription {
        let key = key
        let decode = decode
        let observation = ValueObservation.tracking { db in
            try Self.currentRawValue(db, key: key)
        }
        let dropFirst =
            switch context {
            case .initialValue: false
            case .userInitiated: true
            }
        let cancellable = observation
            .publisher(in: database, scheduling: ImmediateScheduler())
            .dropFirst(dropFirst ? 1 : 0)
            .sink { completion in
                if case .failure(let error) = completion {
                    subscriber.yield(throwing: error)
                }
            } receiveValue: { raw in
                guard pendingSaves.withLock({ $0[key, default: 0] }) == 0 else { return }
                if let value = decode(raw) {
                    subscriber.yield(value)
                } else {
                    subscriber.yieldReturningInitialValue()
                }
            }
        return SharedSubscription {
            cancellable.cancel()
        }
    }

    public func save(_ value: Value, context: SaveContext, continuation: SaveContinuation) {
        // Resolved here, not at key init: only writers need a date, and
        // `lastModified` should come from the saving context's clock.
        @Dependency(\.date) var date
        let key = key
        let rowID = Setting.ID(.v5(name: key))
        let row = encode(value).map { encoded in
            Setting(id: rowID, key: key, value: encoded, lastModified: date())
        }
        pendingSaves.withLock { $0[key, default: 0] += 1 }
        database.asyncWrite { db in
            if let row {
                try Setting.upsert { row }.execute(db)
                // Concurrent first-writes on two devices can still leave a
                // stray row under another id; deleting it here makes the
                // table self-healing.
                try Setting
                    .where { $0.key.eq(key) && $0.id.neq(rowID) }
                    .delete()
                    .execute(db)
            } else {
                try Setting.where { $0.key.eq(key) }.delete().execute(db)
            }
        } completion: { _, result in
            pendingSaves.withLock { $0[key] = max(0, ($0[key] ?? 1) - 1) }
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    /// Newest row wins when duplicates exist (last-writer-wins on `lastModified`).
    private static func currentRawValue(_ db: Database, key: String) throws -> String? {
        try Setting
            .where { $0.key.eq(key) }
            .order { $0.lastModified.desc() }
            .fetchOne(db)?
            .value
    }
}

/// The portable settings replicated across devices; albumId/calendarId stay
/// local (their identifiers don't travel between photo/calendar stores).
public let SYNCED_SETTING_SEED_KEYS = [
    SCREEN_OFF_SETTING_KEY,
    BUS_WINDOW_SETTING_KEY,
    BUS_ALERTS_ENABLED_SETTING_KEY,
]

/// One-time migration of appStorage-held settings into the synced settings
/// table. Seeds only keys with no existing row: an already-synced value beats
/// the local legacy one, and a seeded row never re-seeds.
public func seedSyncedSettings(
    from defaults: UserDefaults,
    keys: [String] = SYNCED_SETTING_SEED_KEYS,
    now: Date,
    in db: Database
) throws {
    for key in keys {
        guard
            try Setting.where({ $0.key.eq(key) }).fetchOne(db) == nil,
            let object = defaults.object(forKey: key)
        else { continue }
        let encoded: String
        switch object {
        case let string as String:
            encoded = string
        case let number as NSNumber:
            // appStorage stores Bool as a CFBoolean (objCType "c"); other
            // numbers keep their digits.
            encoded = String(cString: number.objCType) == "c"
                ? (number.boolValue ? "true" : "false")
                : number.stringValue
        default:
            continue
        }
        try Setting.insert {
            Setting(
                id: Setting.ID(.v5(name: key)),
                key: key,
                value: encoded,
                lastModified: now
            )
        }.execute(db)
    }
}

extension UUID {
    /// RFC 4122 v5 (SHA-1, name-based) UUID: the same setting key maps to the
    /// same row id on every device.
    fileprivate static func v5(name: String) -> UUID {
        // Fixed namespace, generated once for the settings table.
        let namespace: uuid_t = (
            0xC4, 0x0D, 0x2F, 0xD1, 0x6B, 0xF0, 0x4E, 0x27,
            0x9C, 0x1B, 0x5A, 0x83, 0xE3, 0xD5, 0xD9, 0xA6
        )
        var data = Data()
        withUnsafeBytes(of: namespace) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array(name.utf8))
        var digest = Array(Insecure.SHA1.hash(data: data))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

private struct ImmediateScheduler: ValueObservationScheduler, Hashable {
    func immediateInitialValue() -> Bool { true }
    func schedule(_ action: @escaping @Sendable () -> Void) {
        action()
    }
}
