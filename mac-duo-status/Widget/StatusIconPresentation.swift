//
//  StatusIconPresentation.swift
//  mac-duo-status
//

import AppKit
import Foundation

enum BatteryIconColor: Equatable {
    case white
    case green
    case yellow
    case red

    var nsColor: NSColor {
        switch self {
        case .white:
            return .white
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .red:
            return .systemRed
        }
    }
}

enum BatteryIconColorResolver {
    static func resolve(
        chargeFraction: Double?,
        isCharging: Bool?,
        isLowPowerModeEnabled: Bool?,
        usesColor: Bool
    ) -> BatteryIconColor {
        guard usesColor else {
            return .white
        }

        if isCharging == true {
            return .green
        }

        if isLowPowerModeEnabled == true {
            return .yellow
        }

        if isCharging == false,
           isLowPowerModeEnabled == false,
           let chargeFraction,
           chargeFraction < 0.2 {
            return .red
        }

        return .white
    }
}

enum WidgetNetworkKind: String, Codable, Equatable, Sendable {
    case wifi
    case ethernet
    case hotspot
    case disconnected
    case unavailable

    var systemImageName: String {
        switch self {
        case .wifi:
            return "wifi"
        case .ethernet:
            return "network"
        case .hotspot:
            return "personalhotspot"
        case .disconnected:
            return "wifi.slash"
        case .unavailable:
            return "questionmark.circle"
        }
    }
}

struct StatusIconPresentation: Equatable, Sendable {
    let batteryIsAvailable: Bool
    let batteryHasBuiltInBattery: Bool
    let batteryChargeFraction: Double?
    let batteryIsCharging: Bool?
    let batteryIsLowPowerModeEnabled: Bool?
    let networkKind: WidgetNetworkKind
    let healthDotCount: Int?
}
