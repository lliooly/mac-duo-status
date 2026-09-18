//
//  WiFiAuthorization.swift
//  mac-duo-status
//

import Combine
import LocalAuthentication
import Security

@MainActor
protocol WiFiAuthorizationProviding: AnyObject {
    var isAuthorized: Bool { get }

    func ensureAuthorized() async -> Bool

    @discardableResult
    func revoke() -> Bool
}

@MainActor
protocol WiFiAuthorizationStore {
    func containsMarker() -> Bool

    func saveMarker() -> Bool

    func removeMarker() -> Bool
}

@MainActor
protocol WiFiSystemAuthenticator {
    func authenticate() async -> Bool
}

@MainActor
final class LocalAuthenticationWiFiAuthorizer: ObservableObject, WiFiAuthorizationProviding {
    @Published private(set) var isAuthorized: Bool

    private let store: any WiFiAuthorizationStore
    private let authenticator: any WiFiSystemAuthenticator
    private var authorizationTask: Task<Bool, Never>?

    init(
        store: any WiFiAuthorizationStore,
        authenticator: any WiFiSystemAuthenticator
    ) {
        self.store = store
        self.authenticator = authenticator
        isAuthorized = store.containsMarker()
    }

    convenience init() {
        self.init(
            store: KeychainWiFiAuthorizationStore(),
            authenticator: LocalAuthenticationSystemAuthenticator()
        )
    }

    func ensureAuthorized() async -> Bool {
        if isAuthorized {
            return true
        }

        if let authorizationTask {
            return await authorizationTask.value
        }

        let task = Task { @MainActor [self] in
            defer { authorizationTask = nil }

            guard await authenticator.authenticate() else {
                return false
            }

            guard !Task.isCancelled else {
                return false
            }

            guard store.saveMarker() else {
                return false
            }

            isAuthorized = true
            return true
        }
        authorizationTask = task

        return await task.value
    }

    @discardableResult
    func revoke() -> Bool {
        authorizationTask?.cancel()
        authorizationTask = nil

        let didRemove = store.removeMarker()
        if didRemove {
            isAuthorized = false
        }
        return didRemove
    }
}

@MainActor
private final class LocalAuthenticationSystemAuthenticator: WiFiSystemAuthenticator {
    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = nil

        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: NSLocalizedString(
                    "wifi.authorization.reason",
                    comment: ""
                )
            )
            return true
        } catch {
            return false
        }
    }
}

@MainActor
private struct KeychainWiFiAuthorizationStore: WiFiAuthorizationStore {
    private static let service = "com.shishishi3.duo-status.wifi-authorization"
    private static let account = "v1"
    private static let marker = Data([0x01])

    func containsMarker() -> Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func saveMarker() -> Bool {
        var item = baseQuery
        item[kSecValueData as String] = Self.marker
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }

        guard status == errSecDuplicateItem else {
            return false
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Self.marker
        ]
        return SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        ) == errSecSuccess
    }

    func removeMarker() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
