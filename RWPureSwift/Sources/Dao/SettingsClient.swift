import Dependencies
import Foundation
import SQLiteData
import StructuredQueries
import Tagged

public struct SettingsClient: Sendable {
    public var loadString: @Sendable (_ key: String) async throws -> String?
    public var saveString: @Sendable (_ value: String, _ key: String) async throws -> Void

    public init(
        loadString: @escaping @Sendable (_ key: String) async throws -> String?,
        saveString: @escaping @Sendable (_ value: String, _ key: String) async throws -> Void
    ) {
        self.loadString = loadString
        self.saveString = saveString
    }
}

extension SettingsClient: TestDependencyKey {
    public static let testValue = SettingsClient(
        loadString: { _ in nil },
        saveString: { _, _ in }
    )
}

extension SettingsClient: DependencyKey {
    public static let liveValue = SettingsClient(
        loadString: { key in
            @Dependency(\.defaultDatabase) var database
            return try await database.read { db in
                guard let setting = try Setting.where { $0.key.eq(key) }.fetchOne(db) else {
                    return nil
                }
                return setting.value.isEmpty ? nil : setting.value
            }
        },
        saveString: { value, key in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.uuid) var uuid
            @Dependency(\.date.now) var now
            try await database.write { db in
                if try Setting.where { $0.key.eq(key) }.fetchOne(db) != nil {
                    try Setting.where { $0.key.eq(key) }
                        .update {
                            $0.value = value
                            $0.lastModified = now
                        }
                        .execute(db)
                } else {
                    try Setting.insert(
                        Setting(
                            id: Setting.ID(uuid()),
                            key: key,
                            value: value,
                            lastModified: now
                        )
                    ).execute(db)
                }
            }
        }
    )
}

extension DependencyValues {
    public var settingsClient: SettingsClient {
        get { self[SettingsClient.self] }
        set { self[SettingsClient.self] = newValue }
    }
}
