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
        case .open, .owe, .oweTransition, .unknown:
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

struct WiFiAccessPoint: Hashable, Identifiable, Sendable {
    let bssid: String
    let rssi: Int?

    var id: String { bssid }
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
    let hotspotConfirmation: HotspotConfirmation
    let scanToken: UUID
    let accessPoints: [WiFiAccessPoint]

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
        accessPoints: [WiFiAccessPoint] = []
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
        self.hotspotConfirmation = hotspotConfirmation
        self.scanToken = scanToken
        self.accessPoints = accessPoints
    }

    nonisolated var selectableAccessPoints: [WiFiAccessPoint] {
        let current = bssid.map { WiFiAccessPoint(bssid: $0, rssi: rssi) }
        return WiFiAccessPointMerger.merge(accessPoints + (current.map { [$0] } ?? []))
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

    nonisolated func selectingAccessPoint(
        _ accessPoint: WiFiAccessPoint
    ) -> WiFiNetworkCandidate {
        WiFiNetworkCandidate(
            id: id,
            interfaceName: interfaceName,
            ssidData: ssidData,
            displayName: displayName,
            bssid: accessPoint.bssid,
            supportedSecurity: supportedSecurity,
            rssi: accessPoint.rssi,
            isHidden: isHidden,
            isKnown: isKnown,
            hotspotConfirmation: hotspotConfirmation,
            scanToken: scanToken,
            accessPoints: accessPoints
        )
    }
}

enum WiFiAccessPointMerger {
    nonisolated static func merge(_ accessPoints: [WiFiAccessPoint]) -> [WiFiAccessPoint] {
        var byBSSID: [String: WiFiAccessPoint] = [:]

        for accessPoint in accessPoints {
            if let existing = byBSSID[accessPoint.bssid] {
                byBSSID[accessPoint.bssid] = preferred(existing, accessPoint)
            } else {
                byBSSID[accessPoint.bssid] = accessPoint
            }
        }

        return byBSSID.values.sorted { lhs, rhs in
            switch (lhs.rssi, rhs.rssi) {
            case let (lhsRSSI?, rhsRSSI?):
                if lhsRSSI != rhsRSSI {
                    return lhsRSSI > rhsRSSI
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }

            return lhs.bssid < rhs.bssid
        }
    }

    private nonisolated static func preferred(
        _ lhs: WiFiAccessPoint,
        _ rhs: WiFiAccessPoint
    ) -> WiFiAccessPoint {
        guard let lhsRSSI = lhs.rssi else {
            return rhs
        }
        guard let rhsRSSI = rhs.rssi else {
            return lhs
        }

        return rhsRSSI > lhsRSSI ? rhs : lhs
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
                isKnown: true,
                hotspotConfirmation: existing.hotspotConfirmation,
                scanToken: network.scanToken,
                accessPoints: WiFiAccessPointMerger.merge(
                    existing.selectableAccessPoints + network.selectableAccessPoints
                )
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
