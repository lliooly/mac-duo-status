//
//  WidgetStatusSnapshot.swift
//  mac-duo-status
//

import Foundation

enum WidgetStatusConstants {
    static let kind = "DuoStatusWidget"
    static let appGroupIdentifier = "group.com.shishishi3.mac-duo-status"
    static let snapshotKey = "widget.status.snapshot"
    static let staleInterval: TimeInterval = 10 * 60
    static let timelineInterval: TimeInterval = 60
    static let reloadMinimumInterval: TimeInterval = 30
    static let writeHeartbeatInterval: TimeInterval = 60
}

struct WidgetStatusSnapshot: Codable, Equatable, Sendable {
    struct Battery: Codable, Equatable, Sendable {
        let isAvailable: Bool
        let hasBuiltInBattery: Bool
        let chargeFraction: Double?
        let isCharging: Bool?
        let isLowPowerModeEnabled: Bool?
    }

    struct Network: Codable, Equatable, Sendable {
        let isAvailable: Bool
        let kind: WidgetNetworkKind
    }

    let updatedAt: Date
    let battery: Battery
    let network: Network
    let healthDotCount: Int?
    let usesColor: Bool

    var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > WidgetStatusConstants.staleInterval
    }

    var iconPresentation: StatusIconPresentation {
        StatusIconPresentation(
            batteryIsAvailable: battery.isAvailable,
            batteryHasBuiltInBattery: battery.hasBuiltInBattery,
            batteryChargeFraction: battery.chargeFraction,
            batteryIsCharging: battery.isCharging,
            batteryIsLowPowerModeEnabled: battery.isLowPowerModeEnabled,
            networkKind: network.kind,
            healthDotCount: healthDotCount
        )
    }

    func hasSameDisplayContent(as other: WidgetStatusSnapshot) -> Bool {
        battery == other.battery &&
            network == other.network &&
            healthDotCount == other.healthDotCount &&
            usesColor == other.usesColor
    }

    static var placeholder: WidgetStatusSnapshot {
        WidgetStatusSnapshot(
            updatedAt: Date(),
            battery: Battery(
                isAvailable: true,
                hasBuiltInBattery: true,
                chargeFraction: 0.72,
                isCharging: false,
                isLowPowerModeEnabled: false
            ),
            network: Network(isAvailable: true, kind: .wifi),
            healthDotCount: 4,
            usesColor: true
        )
    }

    static func unavailable(updatedAt: Date = Date()) -> WidgetStatusSnapshot {
        WidgetStatusSnapshot(
            updatedAt: updatedAt,
            battery: Battery(
                isAvailable: false,
                hasBuiltInBattery: false,
                chargeFraction: nil,
                isCharging: nil,
                isLowPowerModeEnabled: nil
            ),
            network: Network(isAvailable: false, kind: .unavailable),
            healthDotCount: nil,
            usesColor: false
        )
    }
}
