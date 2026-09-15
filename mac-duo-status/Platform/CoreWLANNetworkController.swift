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
        try await performOnQueue { [self] in
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

                // Wi-Fi 关闭时仍然返回系统已保存的网络，供 UI 展示为不可用状态。
                networks = []
            }

            let token = UUID()
            let networkList = Array(networks)
            let interfaceName = interface.interfaceName ?? "en0"
            let profiles = interface.configuration()?.networkProfiles.compactMap {
                $0 as? CWNetworkProfile
            } ?? []
            let candidates = merge(
                networks: networkList,
                profiles: profiles,
                interfaceName: interfaceName,
                scanToken: token
            )

            if ssidData != nil && candidates.isEmpty {
                throw ControlError.networkNotFound
            }

            lastScanToken = token
            lastInterfaceName = interfaceName
            var cachedNetworks: [Data: [CWNetwork]] = [:]
            for network in networkList {
                guard let ssidData = network.ssidData else {
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
                security: target.primarySecurity,
                credential: credential
            )

            guard remember else {
                return WiFiConnectionResult(wasRemembered: false)
            }

            do {
                try rememberNetwork(target, interface: interface)
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
        security: WiFiSecurity,
        credential: WiFiCredential?
    ) throws {
        if security.isEnterprise || isEnterpriseCredential(credential) {
            let enterpriseCredential = enterpriseCredential(from: credential)
            let identity = enterpriseCredential.identityReference.flatMap(resolveIdentity)
            guard enterpriseCredential.identityReference == nil || identity != nil else {
                throw ControlError.authenticationFailed
            }

            guard let interface = interfaceForAssociation() else {
                throw ControlError.temporarilyUnavailable
            }
            do {
                try interface.associate(
                    toEnterpriseNetwork: network,
                    identity: identity,
                    username: enterpriseCredential.username,
                    password: enterpriseCredential.password
                )
            } catch let error as NSError {
                throw map(error: error)
            }
            return
        }

        let password: String?
        switch credential ?? .none {
        case .none:
            password = nil
        case let .passphrase(value):
            password = value
        case .enterprise:
            throw ControlError.unsupportedSecurity
        }

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
        interface: CWInterface
    ) throws {
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

    private func merge(
        networks: [CWNetwork],
        profiles: [CWNetworkProfile],
        interfaceName: String,
        scanToken: UUID
    ) -> [WiFiNetworkCandidate] {
        var bySSID: [Data: WiFiNetworkCandidate] = [:]

        for profile in profiles {
            guard let ssidData = profile.ssidData else {
                continue
            }

            let security = map(security: profile.security)
            bySSID[ssidData] = WiFiNetworkCandidate(
                id: candidateID(ssidData: ssidData, bssid: nil),
                interfaceName: interfaceName,
                ssidData: ssidData,
                displayName: profile.ssid,
                bssid: nil,
                supportedSecurity: [security],
                rssi: nil,
                isHidden: profile.ssid == nil,
                isKnown: true,
                hotspotConfirmation: .unavailable,
                scanToken: scanToken
            )
        }

        for network in networks {
            guard let ssidData = network.ssidData else {
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
            let accessPoints = network.bssid.map {
                [WiFiAccessPoint(bssid: $0, rssi: rssi)]
            } ?? []
            let candidate = WiFiNetworkCandidate(
                id: candidateID(ssidData: ssidData, bssid: network.bssid),
                interfaceName: interfaceName,
                ssidData: ssidData,
                displayName: network.ssid,
                bssid: network.bssid,
                supportedSecurity: security,
                rssi: rssi,
                isHidden: network.ssid == nil,
                isKnown: isKnown,
                hotspotConfirmation: .unavailable,
                scanToken: scanToken,
                accessPoints: accessPoints
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
                    isKnown: true,
                    hotspotConfirmation: .unavailable,
                    scanToken: scanToken,
                    accessPoints: WiFiAccessPointMerger.merge(
                        existing.selectableAccessPoints + candidate.selectableAccessPoints
                    )
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

    private func isEnterpriseCredential(_ credential: WiFiCredential?) -> Bool {
        if case .enterprise = credential {
            return true
        }

        return false
    }

    private func enterpriseCredential(
        from credential: WiFiCredential?
    ) -> (username: String?, password: String?, identityReference: KeychainIdentityReference?) {
        guard case let .enterprise(username, password, identityReference) = credential else {
            return (nil, nil, nil)
        }

        return (username, password, identityReference)
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
}
