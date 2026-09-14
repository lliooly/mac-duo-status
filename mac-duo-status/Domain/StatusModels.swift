//
//  StatusModels.swift
//  mac-duo-status
//

import Foundation

enum DataAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case stale(reason: String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }

        return false
    }
}

enum HealthMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case thermal
    case load

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .cpu:
            return "health.metric.cpu"
        case .thermal:
            return "health.metric.thermal"
        case .load:
            return "health.metric.load"
        }
    }

    var localizedTitle: String {
        NSLocalizedString(localizationKey, comment: "")
    }
}

enum StatusSection: String, CaseIterable, Identifiable, Sendable {
    case battery
    case network
    case systemHealth

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .battery:
            return "section.battery"
        case .network:
            return "section.network"
        case .systemHealth:
            return "section.system-health"
        }
    }

    var localizedTitle: String {
        NSLocalizedString(localizationKey, comment: "")
    }

    var systemImageName: String {
        switch self {
        case .battery:
            return "battery.100"
        case .network:
            return "network"
        case .systemHealth:
            return "waveform.path.ecg"
        }
    }
}

enum PowerSource: String, Sendable {
    case battery
    case powerAdapter
    case unknown
}

struct BatteryStatus: Equatable, Sendable {
    var availability: DataAvailability
    var hasBuiltInBattery: Bool
    var chargeFraction: Double?
    var isCharging: Bool?
    var powerSource: PowerSource
    var isLowPowerModeEnabled: Bool?

    static func unavailable(reason: String) -> BatteryStatus {
        BatteryStatus(
            availability: .unavailable(reason: reason),
            hasBuiltInBattery: false,
            chargeFraction: nil,
            isCharging: nil,
            powerSource: .unknown,
            isLowPowerModeEnabled: nil
        )
    }
}

enum NetworkKind: String, Sendable {
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

struct NetworkStatus: Equatable, Sendable {
    var availability: DataAvailability
    var kind: NetworkKind
    var name: String?
    var rssi: Int?
    var signalLevel: Int?
    var hotspotConfirmed: Bool

    static func unavailable(reason: String) -> NetworkStatus {
        NetworkStatus(
            availability: .unavailable(reason: reason),
            kind: .unavailable,
            name: nil,
            rssi: nil,
            signalLevel: nil,
            hotspotConfirmed: false
        )
    }
}

enum ThermalState: String, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

struct HealthStatus: Equatable, Sendable {
    var availability: DataAvailability
    var cpuUsagePercent: Double?
    var oneMinuteLoad: Double?
    var fiveMinuteLoad: Double?
    var fifteenMinuteLoad: Double?
    var logicalCPUCount: Int?
    var thermalState: ThermalState?
    var cpuScore: Double?
    var loadScore: Double?
    var thermalScore: Double?
    var selectedMetric: HealthMetric
    var selectedScore: Double?
    var dotCount: Int?

    static func unavailable(selectedMetric: HealthMetric) -> HealthStatus {
        HealthStatus(
            availability: .unavailable(reason: "HealthProvider has not been implemented"),
            cpuUsagePercent: nil,
            oneMinuteLoad: nil,
            fiveMinuteLoad: nil,
            fifteenMinuteLoad: nil,
            logicalCPUCount: nil,
            thermalState: nil,
            cpuScore: nil,
            loadScore: nil,
            thermalScore: nil,
            selectedMetric: selectedMetric,
            selectedScore: nil,
            dotCount: nil
        )
    }

    func selecting(_ metric: HealthMetric) -> HealthStatus {
        var copy = self
        copy.selectedMetric = metric

        switch metric {
        case .cpu:
            copy.selectedScore = cpuScore
        case .thermal:
            copy.selectedScore = thermalScore
        case .load:
            copy.selectedScore = loadScore
        }

        if let selectedScore = copy.selectedScore {
            copy.dotCount = HealthScoreCalculator.dotCount(for: selectedScore)
        } else {
            copy.dotCount = nil
        }

        return copy
    }
}

struct SystemStatusSnapshot: Equatable, Sendable {
    var lastUpdated: Date
    var battery: BatteryStatus
    var network: NetworkStatus
    var health: HealthStatus

    static func initial(selectedMetric: HealthMetric) -> SystemStatusSnapshot {
        SystemStatusSnapshot(
            lastUpdated: Date(),
            battery: .unavailable(reason: "BatteryProvider has not been implemented"),
            network: .unavailable(reason: "NetworkProvider has not been implemented"),
            health: .unavailable(selectedMetric: selectedMetric)
        )
    }
}
