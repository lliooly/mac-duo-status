//
//  ProviderProtocols.swift
//  mac-duo-status
//

import Foundation

protocol BatteryProviding: Sendable {
    func read() async -> BatteryStatus
    func startObserving(_ handler: @escaping @Sendable () -> Void)
    func stopObserving()
}

extension BatteryProviding {
    func startObserving(_ handler: @escaping @Sendable () -> Void) {}
    func stopObserving() {}
}

protocol NetworkProviding: Sendable {
    func read() async -> NetworkStatus
    func startObserving(_ handler: @escaping @Sendable () -> Void)
    func stopObserving()
}

extension NetworkProviding {
    func startObserving(_ handler: @escaping @Sendable () -> Void) {}
    func stopObserving() {}
}

protocol HealthProviding: Sendable {
    func read() async -> HealthStatus
    func startObserving(_ handler: @escaping @Sendable () -> Void)
    func stopObserving()
}

extension HealthProviding {
    func startObserving(_ handler: @escaping @Sendable () -> Void) {}
    func stopObserving() {}
}

struct ProviderContainer: Sendable {
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

    static var live: ProviderContainer {
        ProviderContainer(
            battery: BatteryProvider(),
            network: NetworkProvider(),
            health: HealthProvider()
        )
    }
}
