//
//  PlaceholderProviders.swift
//  mac-duo-status
//

import Foundation

struct PlaceholderBatteryProvider: BatteryProviding {
    func read() async -> BatteryStatus {
        .unavailable(reason: "BatteryProvider has not been implemented")
    }
}

struct PlaceholderNetworkProvider: NetworkProviding {
    func read() async -> NetworkStatus {
        .unavailable(reason: "NetworkProvider has not been implemented")
    }
}

struct PlaceholderHealthProvider: HealthProviding {
    func read() async -> HealthStatus {
        .unavailable(selectedMetric: .cpu)
    }
}
