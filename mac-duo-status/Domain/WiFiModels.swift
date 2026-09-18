//
//  WiFiModels.swift
//  mac-duo-status
//

import Foundation

enum WiFiSecurity: String, CaseIterable, Hashable, Identifiable, Sendable {
    case open
    case wep
    case wpaPersonal
    case wpaPersonalMixed
    case wpa2Personal
    case personal
    case dynamicWEP
    case wpaEnterprise
    case wpaEnterpriseMixed
    case wpa2Enterprise
    case enterprise
    case wpa3Personal
    case wpa3Enterprise
    case wpa3Transition
    case owe
    case oweTransition
    case unknown

    var id: String { rawValue }

    var isEnterprise: Bool {
        switch self {
        case .dynamicWEP, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise,
             .enterprise, .wpa3Enterprise:
            return true
        default:
            return false
        }
    }

    var requiresPassphrase: Bool {
        switch self {
        case .open, .owe, .oweTransition:
            return false
        default:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .open:
            return NSLocalizedString("wifi.security.open", comment: "")
        case .wep:
            return NSLocalizedString("wifi.security.wep", comment: "")
        case .dynamicWEP:
            return NSLocalizedString("wifi.security.dynamic-wep", comment: "")
        case .wpaPersonal, .wpaPersonalMixed, .wpa2Personal, .personal,
             .wpa3Personal, .wpa3Transition:
            return NSLocalizedString("wifi.security.personal", comment: "")
        case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise,
             .wpa3Enterprise:
            return NSLocalizedString("wifi.security.enterprise", comment: "")
        case .owe, .oweTransition:
            return NSLocalizedString("wifi.security.owe", comment: "")
        case .unknown:
            return NSLocalizedString("wifi.security.unknown", comment: "")
        }
    }
}

enum HotspotConfirmation: String, Hashable, Sendable {
    case confirmed
    case notConfirmed
    case unavailable
}

struct WiFiNetworkCandidate: Hashable, Identifiable, Sendable {
    let id: String
    let interfaceName: String
    let ssidData: Data
    let displayName: String?
    let bssid: String?
    let supportedSecurity: Set<WiFiSecurity>
    let rssi: Int?
    let isHidden: Bool
    let isKnown: Bool
    let isDiscovered: Bool
    let hotspotConfirmation: HotspotConfirmation
    let scanToken: UUID

    nonisolated init(
        id: String,
        interfaceName: String,
        ssidData: Data,
        displayName: String?,
        bssid: String?,
        supportedSecurity: Set<WiFiSecurity>,
        rssi: Int?,
        isHidden: Bool,
        isKnown: Bool,
        hotspotConfirmation: HotspotConfirmation,
        scanToken: UUID,
        isDiscovered: Bool = false
    ) {
        self.id = id
        self.interfaceName = interfaceName
        self.ssidData = ssidData
        self.displayName = displayName
        self.bssid = bssid
        self.supportedSecurity = supportedSecurity
        self.rssi = rssi
        self.isHidden = isHidden
        self.isKnown = isKnown
        self.isDiscovered = isDiscovered
        self.hotspotConfirmation = hotspotConfirmation
        self.scanToken = scanToken
    }

    var primarySecurity: WiFiSecurity {
        let order: [WiFiSecurity] = [
            .wpa3Enterprise,
            .wpa3Personal,
            .wpa3Transition,
            .enterprise,
            .wpa2Enterprise,
            .wpaEnterprise,
            .wpa2Personal,
            .personal,
            .wpaPersonal,
            .wep,
            .dynamicWEP,
            .owe,
            .oweTransition,
            .open,
            .unknown
        ]

        return order.first(where: supportedSecurity.contains) ?? .unknown
    }
}

enum WiFiCredential: Sendable {
    case none
    case passphrase(String)
    case enterprise(
        username: String?,
        password: String?,
        identityReference: KeychainIdentityReference?
    )
}

struct WiFiConnectionResult: Equatable, Sendable {
    let wasRemembered: Bool
}

enum WiFiNetworkCandidateMerger {
    nonisolated static func merge(
        knownNetworks: [WiFiNetworkCandidate],
        scannedNetworks: [WiFiNetworkCandidate]
    ) -> [WiFiNetworkCandidate] {
        var bySSID: [Data: WiFiNetworkCandidate] = [:]

        for network in knownNetworks {
            bySSID[network.ssidData] = network
        }

        for network in scannedNetworks {
            guard let existing = bySSID[network.ssidData] else {
                bySSID[network.ssidData] = network
                continue
            }

            let preferred = preferred(existing, network)
            bySSID[network.ssidData] = WiFiNetworkCandidate(
                id: preferred.id,
                interfaceName: preferred.interfaceName,
                ssidData: network.ssidData,
                displayName: preferred.displayName ?? existing.displayName,
                bssid: preferred.bssid,
                supportedSecurity: existing.supportedSecurity.union(
                    network.supportedSecurity
                ),
                rssi: preferred.rssi,
                isHidden: existing.isHidden && network.isHidden,
                isKnown: existing.isKnown || network.isKnown,
                hotspotConfirmation: existing.hotspotConfirmation,
                scanToken: network.scanToken,
                isDiscovered: existing.isDiscovered || network.isDiscovered
            )
        }

        return bySSID.values.sorted {
            ($0.isKnown ? 0 : 1, $0.displayName ?? "") <
                ($1.isKnown ? 0 : 1, $1.displayName ?? "")
        }
    }

    private nonisolated static func preferred(
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
}

enum WiFiNetworkCandidateGrouping {
    nonisolated static func hotspots(
        from candidates: [WiFiNetworkCandidate]
    ) -> [WiFiNetworkCandidate] {
        candidates.filter {
            $0.isDiscovered && $0.hotspotConfirmation == .confirmed
        }
    }

    nonisolated static func knownNetworks(
        from candidates: [WiFiNetworkCandidate]
    ) -> [WiFiNetworkCandidate] {
        candidates.filter {
            $0.isDiscovered && $0.isKnown && $0.hotspotConfirmation != .confirmed
        }
    }

    nonisolated static func otherNetworks(
        from candidates: [WiFiNetworkCandidate]
    ) -> [WiFiNetworkCandidate] {
        candidates.filter {
            $0.isDiscovered && !$0.isKnown && $0.hotspotConfirmation != .confirmed
        }
    }
}

protocol NetworkControlProviding: Sendable {
    func scan(
        includeHidden: Bool,
        ssidData: Data?
    ) async throws -> [WiFiNetworkCandidate]
    func setWiFiEnabled(_ enabled: Bool) async throws
    func connect(
        to target: WiFiNetworkCandidate,
        credential: WiFiCredential?,
        remember: Bool
    ) async throws -> WiFiConnectionResult
}

protocol SavedWiFiNetworkConnecting: Sendable {
    func connectToSavedNetwork(
        interfaceName: String,
        ssidData: Data
    ) async throws
}
