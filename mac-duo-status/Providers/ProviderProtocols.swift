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
    let powerPolicy: any PowerPolicyProviding
    let powerControl: any PowerControlProviding

    init(
        battery: any BatteryProviding,
        network: any NetworkProviding,
        health: any HealthProviding,
        powerPolicy: any PowerPolicyProviding = PlaceholderPowerPolicyProvider(),
        powerControl: any PowerControlProviding = PlaceholderPowerControlProvider()
    ) {
        self.battery = battery
        self.network = network
        self.health = health
        self.powerPolicy = powerPolicy
        self.powerControl = powerControl
    }

    static var placeholders: ProviderContainer {
        ProviderContainer(
            battery: PlaceholderBatteryProvider(),
            network: PlaceholderNetworkProvider(),
            health: PlaceholderHealthProvider(),
            powerPolicy: PlaceholderPowerPolicyProvider(),
            powerControl: PlaceholderPowerControlProvider()
        )
    }

    static var live: ProviderContainer {
        let helper = PowerHelperClient()
        let powerControl = PowerPolicyProvider(helper: helper)

        return ProviderContainer(
            battery: BatteryProvider(),
            network: NetworkProvider(),
            health: HealthProvider(),
            powerPolicy: powerControl,
            powerControl: powerControl
        )
    }
}
