//
//  PlaceholderProviders.swift
//  mac-duo-status
//

import Foundation

struct PlaceholderBatteryProvider: BatteryProviding {
    func read() async -> BatteryStatus {
        .unavailable(reason: "Battery data is unavailable")
    }
}

struct PlaceholderNetworkProvider: NetworkProviding {
    func read() async -> NetworkStatus {
        .unavailable(reason: "Network data is unavailable")
    }
}

struct PlaceholderHealthProvider: HealthProviding {
    func read() async -> HealthStatus {
        .unavailable(selectedMetric: .cpu, reason: "HealthProvider is not configured")
    }
}

struct PlaceholderPowerPolicyProvider: PowerPolicyProviding {
    func read() async -> PowerPolicyStatus {
        .unavailable(reason: "Power policy is unavailable")
    }
}

struct PlaceholderPowerControlProvider: PowerControlProviding {
    func capabilities() async -> PowerCapabilities {
        .unsupported
    }

    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async throws {
        throw ControlError.helperUnavailable
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        nil
    }

    func requestHelperApproval() async -> HelperStatus {
        .notInstalled
    }

    func unregisterHelper() async -> HelperStatus {
        .notInstalled
    }
}
