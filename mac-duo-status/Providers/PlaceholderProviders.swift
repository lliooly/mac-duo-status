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
