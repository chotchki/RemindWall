import ConcurrencyExtras
import Dependencies
import DependenciesMacros
import Foundation
import Security

@DependencyClient
public struct TransitKeyStore: Sendable {
    public var read: @Sendable () -> String?
    public var write: @Sendable (String?) -> Void
}

extension TransitKeyStore: DependencyKey {
    public static let liveValue: Self = {
        let service = "io.hotchkiss.RemindWall.transit"
        let account = "oba_api_key"

        return Self(
            read: {
                var query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecAttrSynchronizable as String: kCFBooleanTrue!,
                    kSecReturnData as String: kCFBooleanTrue!,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                guard status == errSecSuccess,
                      let data = item as? Data,
                      let value = String(data: data, encoding: .utf8) else {
                    return nil
                }
                _ = query
                return value
            },
            write: { newValue in
                let baseQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecAttrSynchronizable as String: kCFBooleanTrue!,
                ]
                _ = SecItemDelete(baseQuery as CFDictionary)

                guard let value = newValue, !value.isEmpty,
                      let data = value.data(using: .utf8) else {
                    return
                }
                var addQuery = baseQuery
                addQuery[kSecValueData as String] = data
                _ = SecItemAdd(addQuery as CFDictionary, nil)
            }
        )
    }()

    public static var testValue: Self {
        let storage = LockIsolated<String?>(nil)
        return Self(
            read: { storage.value },
            write: { storage.setValue($0) }
        )
    }

    public static let previewValue = Self(
        read: { nil },
        write: { _ in }
    )
}

extension DependencyValues {
    public var transitKeyStore: TransitKeyStore {
        get { self[TransitKeyStore.self] }
        set { self[TransitKeyStore.self] = newValue }
    }
}
