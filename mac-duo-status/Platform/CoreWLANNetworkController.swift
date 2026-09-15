//
//  CoreWLANNetworkController.swift
//  mac-duo-status
//

import CoreWLAN
import Foundation
import Security

@_silgen_name("DuoStatusCommitWiFiConfiguration")
private func DuoStatusCommitWiFiConfiguration(
    _ interface: AnyObject,
    _ configuration: AnyObject
) -> Int32

final class CoreWLANNetworkController: NetworkControlProviding, @unchecked Sendable {
    private struct StoredEnterpriseCredential {
        let username: String?
        let password: String?
        let identity: SecIdentity?
    }

    private let wifiClient = CWWiFiClient.shared()
    private let operationQueue = DispatchQueue(
        label: "com.shishishi3.duo-status.wifi-control"
    )

    private var lastScanToken: UUID?
    private var lastInterfaceName: String?
    private var cachedNetworksBySSID: [Data: [CWNetwork]] = [:]

    func scan(
        includeHidden: Bool,
        ssidData: Data? = nil
    ) async throws -> [WiFiNetworkCandidate] {
        let shouldRequestLocation = try await performOnQueue { [self] in
            guard let interface = wifiClient.interface() else {
                throw ControlError.temporarilyUnavailable
            }

            return interface.powerOn()
        }

        if shouldRequestLocation {
            guard await WiFiLocationAuthorization.shared.requestAccessIfNeeded() else {
                throw ControlError.authorizationRequired
            }
        }

        return try await performOnQueue { [self] in
            guard let interface = wifiClient.interface() else {
                throw ControlError.temporarilyUnavailable
            }

            let networks: Set<CWNetwork>
            if interface.powerOn() {
                do {
                    let result = try interface.scanForNetworks(
                        withSSID: ssidData,
                        includeHidden: includeHidden
                    )
                    networks = result
                } catch let error as NSError {
                    throw map(error: error)
                }
            } else {
                guard ssidData == nil else {
                    throw ControlError.temporarilyUnavailable
                }

                // Wi-Fi 关闭时不执行扫描；配置文件仍会参与合并，但 UI 会过滤未发现的网络。
                networks = []
            }

            let token = UUID()
            let networkList = Array(networks)
            let interfaceName = interface.interfaceName ?? "en0"
            let profiles = interface.configuration()?.networkProfiles.compactMap {
                $0 as? CWNetworkProfile
            } ?? []

            let selectedNetworks: [CWNetwork]
            let selectedProfiles: [CWNetworkProfile]
            if let requestedSSID = ssidData {
                selectedNetworks = networkList.filter {
                    resolvedSSIDData(for: $0) == requestedSSID
                }
                selectedProfiles = profiles.filter {
                    resolvedSSIDData(for: $0) == requestedSSID
                }
            } else {
                selectedNetworks = networkList
                selectedProfiles = profiles
            }

            if ssidData != nil && selectedNetworks.isEmpty {
                throw ControlError.networkNotFound
            }

            let candidates = merge(
                networks: selectedNetworks,
                profiles: selectedProfiles,
                interfaceName: interfaceName,
                scanToken: token
            )

            if ssidData != nil && candidates.isEmpty {
                throw ControlError.networkNotFound
            }

            lastScanToken = token
            lastInterfaceName = interfaceName
            var cachedNetworks: [Data: [CWNetwork]] = [:]
            for network in selectedNetworks {
                guard let ssidData = resolvedSSIDData(for: network) else {
                    continue
                }

                cachedNetworks[ssidData, default: []].append(network)
            }
            cachedNetworksBySSID = cachedNetworks

            return candidates
        }
    }

    func setWiFiEnabled(_ enabled: Bool) async throws {
        try await performOnQueue { [self] in
            guard let interface = wifiClient.interface() else {
                throw ControlError.temporarilyUnavailable
            }

            do {
                try interface.setPower(enabled)
            } catch let error as NSError {
                throw map(error: error)
            }
        }
    }

    func connect(
        to target: WiFiNetworkCandidate,
        credential: WiFiCredential?,
        remember: Bool
    ) async throws -> WiFiConnectionResult {
        try await performOnQueue { [self] in
            guard target.scanToken == lastScanToken else {
                throw ControlError.networkNotFound
            }

            guard let interface = wifiClient.interface(withName: target.interfaceName)
                ?? wifiClient.interface(),
                let interfaceName = interface.interfaceName
            else {
                throw ControlError.temporarilyUnavailable
            }

            guard interfaceName == target.interfaceName || lastInterfaceName == nil else {
                throw ControlError.networkNotFound
            }

            let network = try resolveNetwork(for: target, interface: interface)
            try associate(
                network: network,
                target: target,
                credential: credential
            )

            guard remember else {
                return WiFiConnectionResult(wasRemembered: false)
            }

            do {
                try rememberNetwork(
                    target,
                    interface: interface,
                    credential: credential
                )
                return WiFiConnectionResult(wasRemembered: true)
            } catch {
                // 连接已经成功，系统配置文件写入失败只影响“记住网络”结果。
                return WiFiConnectionResult(wasRemembered: false)
            }
        }
    }

    private func resolveNetwork(
        for target: WiFiNetworkCandidate,
        interface: CWInterface
    ) throws -> CWNetwork {
        if let cached = cachedNetworksBySSID[target.ssidData]?.first(where: { network in
            guard let targetBSSID = target.bssid else {
                return true
            }

            return network.bssid == targetBSSID
        }) {
            return cached
        }

        let directedScan: Set<CWNetwork>
        do {
            directedScan = try interface.scanForNetworks(
                withSSID: target.ssidData,
                includeHidden: true
            )
        } catch let error as NSError {
            throw map(error: error)
        }
        if let network = directedScan.first(where: { network in
            guard let targetBSSID = target.bssid else {
                return true
            }

            return network.bssid == targetBSSID
        }) {
            return network
        }

        throw ControlError.networkNotFound
    }

    private func associate(
        network: CWNetwork,
        target: WiFiNetworkCandidate,
        credential: WiFiCredential?
    ) throws {
        if target.primarySecurity.isEnterprise || isEnterpriseCredential(credential) {
            let enterpriseCredential = try enterpriseCredential(
                for: target,
                credential: credential
            )

            guard let interface = interfaceForAssociation() else {
                throw ControlError.temporarilyUnavailable
            }
            do {
                try interface.associate(
                    toEnterpriseNetwork: network,
                    identity: enterpriseCredential.identity,
                    username: enterpriseCredential.username,
                    password: enterpriseCredential.password
                )
            } catch let error as NSError {
                throw map(error: error)
            }
            return
        }

        let password = try personalPassword(
            for: target,
            credential: credential
        )

        guard let interface = interfaceForAssociation() else {
            throw ControlError.temporarilyUnavailable
        }
        do {
            try interface.associate(to: network, password: password)
        } catch let error as NSError {
            throw map(error: error)
        }
    }

    private func interfaceForAssociation() -> CWInterface? {
        guard let interfaceName = lastInterfaceName else {
            return wifiClient.interface()
        }

        return wifiClient.interface(withName: interfaceName) ?? wifiClient.interface()
    }

    private func rememberNetwork(
        _ target: WiFiNetworkCandidate,
        interface: CWInterface,
        credential: WiFiCredential?
    ) throws {
        try rememberCredential(
            for: target,
            credential: credential
        )

        guard let security = nativeSecurity(for: target.primarySecurity)
        else {
            throw ControlError.unsupportedSecurity
        }

        let currentConfiguration = interface.configuration()
        let configuration = currentConfiguration
            .map(CWMutableConfiguration.init(configuration:))
            ?? CWMutableConfiguration()
        let existingProfiles = configuration.networkProfiles.compactMap {
            $0 as? CWNetworkProfile
        }
        let existingProfile = existingProfiles.first { profile in
            profile.ssidData == target.ssidData && profile.security == security
        }
        let mutableProfile = existingProfile.flatMap {
            $0.mutableCopy() as? CWMutableNetworkProfile
        } ?? CWMutableNetworkProfile()
        mutableProfile.ssidData = target.ssidData
        mutableProfile.security = security

        var updatedProfiles = existingProfiles.filter { profile in
            !(profile.ssidData == target.ssidData && profile.security == security)
        }
        updatedProfiles.append(mutableProfile)
        configuration.networkProfiles = NSOrderedSet(array: updatedProfiles)

        let errorCode = DuoStatusCommitWiFiConfiguration(interface, configuration)
        guard errorCode == 0 else {
            throw map(errorCode: errorCode)
        }
    }

    private func resolvedSSIDData(for network: CWNetwork) -> Data? {
        network.ssidData ?? network.ssid?.data(using: .utf8)
    }

    private func resolvedSSIDData(for profile: CWNetworkProfile) -> Data? {
        profile.ssidData ?? profile.ssid?.data(using: .utf8)
    }

    private func merge(
        networks: [CWNetwork],
        profiles: [CWNetworkProfile],
        interfaceName: String,
        scanToken: UUID
    ) -> [WiFiNetworkCandidate] {
        var bySSID: [Data: WiFiNetworkCandidate] = [:]

        for profile in profiles {
            guard let ssidData = resolvedSSIDData(for: profile) else {
                continue
            }

            let security = map(security: profile.security)
            bySSID[ssidData] = WiFiNetworkCandidate(
                id: candidateID(ssidData: ssidData, bssid: nil),
                interfaceName: interfaceName,
                ssidData: ssidData,
                displayName: profile.ssid ?? String(data: ssidData, encoding: .utf8),
                bssid: nil,
                supportedSecurity: [security],
                rssi: nil,
                isHidden: profile.ssid == nil,
                isKnown: true,
                hotspotConfirmation: .unavailable,
                scanToken: scanToken,
                isDiscovered: false
            )
        }

        for network in networks {
            guard let ssidData = resolvedSSIDData(for: network) else {
                continue
            }

            let supportedSecurity = Self.securityMappings.reduce(into: Set<WiFiSecurity>()) {
                if network.supportsSecurity($1.core) {
                    $0.insert($1.value)
                }
            }
            let security = supportedSecurity.isEmpty ? [.unknown] : supportedSecurity
            let isKnown = bySSID[ssidData] != nil
            let rssi = network.rssiValue == 0 ? nil : network.rssiValue
            let candidate = WiFiNetworkCandidate(
                id: candidateID(ssidData: ssidData, bssid: network.bssid),
                interfaceName: interfaceName,
                ssidData: ssidData,
                displayName: network.ssid ?? String(data: ssidData, encoding: .utf8),
                bssid: network.bssid,
                supportedSecurity: security,
                rssi: rssi,
                isHidden: network.ssid == nil,
                isKnown: isKnown,
                hotspotConfirmation: .unavailable,
                scanToken: scanToken,
                isDiscovered: true
            )

            if let existing = bySSID[ssidData] {
                let preferred = preferredCandidate(existing, candidate)
                bySSID[ssidData] = WiFiNetworkCandidate(
                    id: preferred.id,
                    interfaceName: interfaceName,
                    ssidData: ssidData,
                    displayName: preferred.displayName ?? existing.displayName,
                    bssid: preferred.bssid,
                    supportedSecurity: existing.supportedSecurity.union(
                        candidate.supportedSecurity
                    ),
                    rssi: preferred.rssi,
                    isHidden: existing.isHidden && candidate.isHidden,
                    isKnown: existing.isKnown || candidate.isKnown,
                    hotspotConfirmation: .unavailable,
                    scanToken: scanToken,
                    isDiscovered: existing.isDiscovered || candidate.isDiscovered
                )
            } else {
                bySSID[ssidData] = candidate
            }
        }

        return bySSID.values.sorted {
            ($0.isKnown ? 0 : 1, $0.displayName ?? "") <
                ($1.isKnown ? 0 : 1, $1.displayName ?? "")
        }
    }

    private func preferredCandidate(
        _ lhs: WiFiNetworkCandidate,
        _ rhs: WiFiNetworkCandidate
    ) -> WiFiNetworkCandidate {
        guard let lhsRSSI = lhs.rssi else {
            return rhs
        }
        guard let rhsRSSI = rhs.rssi else {
            return lhs
        }

        return rhsRSSI > lhsRSSI ? rhs : lhs
    }

    private func candidateID(ssidData: Data, bssid: String?) -> String {
        let ssid = ssidData.base64EncodedString()
        return [ssid, bssid ?? "known"].joined(separator: ":")
    }

    private func map(security: CWSecurity) -> WiFiSecurity {
        Self.securityMappings.first(where: { $0.core == security })?.value ?? .unknown
    }

    private func nativeSecurity(for security: WiFiSecurity) -> CWSecurity? {
        Self.securityMappings.first(where: { $0.value == security })?.core
    }

    private func personalPassword(
        for target: WiFiNetworkCandidate,
        credential: WiFiCredential?
    ) throws -> String? {
        switch credential {
        case .some(.none):
            guard isOpenSecurity(target.primarySecurity) else {
                throw ControlError.credentialsRequired
            }
            return nil
        case let .some(.passphrase(value)):
            guard !value.isEmpty else {
                throw ControlError.credentialsRequired
            }
            return value
        case .some(.enterprise):
            throw ControlError.unsupportedSecurity
        case nil:
            if isOpenSecurity(target.primarySecurity) {
                return nil
            }

            guard target.isKnown,
                  let password = storedWiFiPassword(for: target.ssidData)
            else {
                throw ControlError.credentialsRequired
            }
            return password
        }
    }

    private func enterpriseCredential(
        for target: WiFiNetworkCandidate,
        credential: WiFiCredential?
    ) throws -> StoredEnterpriseCredential {
        switch credential {
        case let .some(.enterprise(username, password, identityReference)):
            let identity = identityReference.flatMap(resolveIdentity)
            guard identityReference == nil || identity != nil else {
                throw ControlError.authenticationFailed
            }
            guard hasEnterpriseCredential(
                username: username,
                password: password,
                identity: identity
            ) else {
                throw ControlError.credentialsRequired
            }
            return StoredEnterpriseCredential(
                username: username,
                password: password,
                identity: identity
            )
        case nil:
            guard target.isKnown,
                  let stored = storedEnterpriseCredential(for: target.ssidData)
            else {
                throw ControlError.credentialsRequired
            }
            return stored
        case .some(.none):
            throw ControlError.credentialsRequired
        case .some(.passphrase):
            throw ControlError.unsupportedSecurity
        }
    }

    private func rememberCredential(
        for target: WiFiNetworkCandidate,
        credential: WiFiCredential?
    ) throws {
        switch credential {
        case let .some(.passphrase(value)):
            guard !value.isEmpty else {
                throw ControlError.credentialsRequired
            }
            let status = CWKeychainSetWiFiPassword(
                .user,
                target.ssidData,
                value
            )
            guard status == errSecSuccess else {
                throw ControlError.failed
            }
        case let .some(.enterprise(username, password, identityReference)):
            if username != nil || password != nil {
                let status = CWKeychainSetWiFiEAPUsernameAndPassword(
                    .user,
                    target.ssidData,
                    username,
                    password
                )
                guard status == errSecSuccess else {
                    throw ControlError.failed
                }
            }

            if let identityReference {
                guard let identity = resolveIdentity(identityReference) else {
                    throw ControlError.authenticationFailed
                }
                let status = CWKeychainSetWiFiEAPIdentity(
                    .user,
                    target.ssidData,
                    identity
                )
                guard status == errSecSuccess else {
                    throw ControlError.failed
                }
            }
        case .some(.none), nil:
            break
        }
    }

    private func storedWiFiPassword(for ssidData: Data) -> String? {
        for domain in Self.wifiKeychainDomains {
            var password: NSString?
            let status = CWKeychainFindWiFiPassword(
                domain,
                ssidData,
                &password
            )
            guard status == errSecSuccess,
                  let password,
                  password.length > 0
            else {
                continue
            }
            return password as String
        }

        return nil
    }

    private func storedEnterpriseCredential(
        for ssidData: Data
    ) -> StoredEnterpriseCredential? {
        for domain in Self.wifiKeychainDomains {
            var username: NSString?
            var password: NSString?
            let credentialStatus = CWKeychainFindWiFiEAPUsernameAndPassword(
                domain,
                ssidData,
                &username,
                &password
            )

            var unmanagedIdentity: Unmanaged<SecIdentity>?
            let identityStatus = CWKeychainCopyWiFiEAPIdentity(
                domain,
                ssidData,
                &unmanagedIdentity
            )
            let identity = unmanagedIdentity?.takeRetainedValue()

            guard credentialStatus == errSecSuccess || identityStatus == errSecSuccess
            else {
                continue
            }

            let storedCredential = StoredEnterpriseCredential(
                username: username.map { $0 as String },
                password: password.map { $0 as String },
                identity: identity
            )
            guard hasEnterpriseCredential(
                username: storedCredential.username,
                password: storedCredential.password,
                identity: storedCredential.identity
            ) else {
                continue
            }
            return storedCredential
        }

        return nil
    }

    private func hasEnterpriseCredential(
        username: String?,
        password: String?,
        identity: SecIdentity?
    ) -> Bool {
        username?.isEmpty == false || password?.isEmpty == false || identity != nil
    }

    private func isOpenSecurity(_ security: WiFiSecurity) -> Bool {
        switch security {
        case .open, .owe, .oweTransition:
            return true
        default:
            return false
        }
    }

    private func isEnterpriseCredential(_ credential: WiFiCredential?) -> Bool {
        if case .enterprise = credential {
            return true
        }

        return false
    }

    private func resolveIdentity(
        _ reference: KeychainIdentityReference
    ) -> SecIdentity? {
        let query: [CFString: Any] = [
            kSecValuePersistentRef: reference.persistentReference,
            kSecReturnRef: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let result else {
            return nil
        }

        guard CFGetTypeID(result) == SecIdentityGetTypeID() else {
            return nil
        }

        return (result as! SecIdentity)
    }

    private func map(error: NSError?) -> ControlError {
        guard let error else {
            return .failed
        }

        return map(errorCode: Int32(error.code))
    }

    private func map(errorCode: Int32) -> ControlError {
        switch Int(errorCode) {
        case -3905:
            return .operationTimeout
        case -3930:
            return .authorizationRequired
        case -3903:
            return .unsupportedSecurity
        case -3909, -3906, -3910, -3924, -3925:
            return .authenticationFailed
        default:
            return .failed
        }
    }

    private func performOnQueue<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            operationQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static let securityMappings: [(core: CWSecurity, value: WiFiSecurity)] = [
        (.none, .open),
        (.WEP, .wep),
        (.wpaPersonal, .wpaPersonal),
        (.wpaPersonalMixed, .wpaPersonalMixed),
        (.wpa2Personal, .wpa2Personal),
        (.personal, .personal),
        (.dynamicWEP, .dynamicWEP),
        (.wpaEnterprise, .wpaEnterprise),
        (.wpaEnterpriseMixed, .wpaEnterpriseMixed),
        (.wpa2Enterprise, .wpa2Enterprise),
        (.enterprise, .enterprise),
        (.wpa3Personal, .wpa3Personal),
        (.wpa3Enterprise, .wpa3Enterprise),
        (.wpa3Transition, .wpa3Transition),
        (.OWE, .owe),
        (.oweTransition, .oweTransition),
        (.unknown, .unknown)
    ]

    private static let wifiKeychainDomains: [CWKeychainDomain] = [
        .user,
        .system
    ]
}
