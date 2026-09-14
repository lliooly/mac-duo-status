//
//  ProviderProtocols.swift
//  mac-duo-status
//

import Foundation

protocol BatteryProviding {
    func read() async -> BatteryStatus
}

protocol NetworkProviding {
    func read() async -> NetworkStatus
}

protocol HealthProviding {
    func read() async -> HealthStatus
}

struct ProviderContainer {
    let battery: any BatteryProviding
    let network: any NetworkProviding
    let health: any HealthProviding

    static var placeholders: ProviderContainer {
        ProviderContainer(
            battery: PlaceholderBatteryProvider(),
            network: PlaceholderNetworkProvider(),
            health: PlaceholderHealthProvider()
        )
    }
}
