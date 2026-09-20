//
//  StatusModels.swift
//  mac-duo-status
//

import Foundation

enum DataAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case stale(reason: String)

    nonisolated var isAvailable: Bool {
        if case .available = self {
            return true
        }

        return false
    }

    nonisolated var reason: String? {
        switch self {
        case .available:
            return nil
        case let .unavailable(reason), let .stale(reason):
            return reason
        }
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

    var systemImageName: String {
        switch self {
        case .battery:
            return "battery.100"
        case .network:
            return "globe"
        case .systemHealth:
            return "waveform.path.ecg"
        }
    }
}

enum PowerSource: String, Sendable {
    case battery
    case powerAdapter
    case unknown

    var isPoweredByAdapter: Bool? {
        switch self {
        case .battery:
            return false
        case .powerAdapter:
            return true
        case .unknown:
            return nil
        }
    }
}

struct BatteryStatus: Equatable, Sendable {
    var availability: DataAvailability
    var hasBuiltInBattery: Bool
    var chargeFraction: Double?
    var isCharging: Bool?
    var powerSource: PowerSource
    var isLowPowerModeEnabled: Bool?

    static func unavailable(reason: String, hasBuiltInBattery: Bool = false) -> BatteryStatus {
        BatteryStatus(
            availability: .unavailable(reason: reason),
            hasBuiltInBattery: hasBuiltInBattery,
            chargeFraction: nil,
            isCharging: nil,
            powerSource: .unknown,
            isLowPowerModeEnabled: nil
        )
    }

    static var noBuiltInBattery: BatteryStatus {
        BatteryStatus(
            availability: .available,
            hasBuiltInBattery: false,
            chargeFraction: nil,
            isCharging: nil,
            powerSource: .powerAdapter,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
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

    var shouldShowWiFiSignal: Bool {
        kind == .wifi && !hotspotConfirmed
    }

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

    static func unavailable(
        selectedMetric: HealthMetric,
        reason: String = "Health data is unavailable"
    ) -> HealthStatus {
        HealthStatus(
            availability: .unavailable(reason: reason),
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
    var powerPolicy: PowerPolicyStatus

    static func initial(selectedMetric: HealthMetric) -> SystemStatusSnapshot {
        SystemStatusSnapshot(
            lastUpdated: Date(),
            battery: .unavailable(reason: "Battery data is unavailable"),
            network: .unavailable(reason: "Network data is unavailable"),
            health: .unavailable(
                selectedMetric: selectedMetric,
                reason: "Health data is unavailable"
            ),
            powerPolicy: .unavailable(reason: "Power policy is unavailable")
        )
    }
}
