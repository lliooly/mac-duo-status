//
//  SystemStatusStore.swift
//  mac-duo-status
//

import Combine
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    @Published private(set) var snapshot: SystemStatusSnapshot

    private let preferences: PreferencesStore
    private let providers: ProviderContainer
    private let samplingIntervalNanoseconds: UInt64

    private var refreshTask: Task<Void, Never>?
    private var batteryStatus: BatteryStatus
    private var networkStatus: NetworkStatus
    private var healthStatus: HealthStatus

    init(
        preferences: PreferencesStore,
        providers: ProviderContainer,
        samplingIntervalNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.preferences = preferences
        self.providers = providers
        self.samplingIntervalNanoseconds = samplingIntervalNanoseconds
        self.batteryStatus = .unavailable(reason: "BatteryProvider has not been implemented")
        self.networkStatus = .unavailable(reason: "NetworkProvider has not been implemented")
        self.healthStatus = .unavailable(selectedMetric: preferences.healthMetric)
        self.snapshot = .initial(selectedMetric: preferences.healthMetric)
    }

    func start() {
        guard refreshTask == nil else {
            return
        }

        let interval = samplingIntervalNanoseconds
        refreshTask = Task { [weak self] in
            await self?.refresh()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)

                guard !Task.isCancelled else {
                    return
                }

                await self?.refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    func setHealthMetric(_ metric: HealthMetric) {
        preferences.healthMetric = metric
        healthStatus = healthStatus.selecting(metric)
        rebuildSnapshot()
    }

    private func refresh() async {
        let battery = await providers.battery.read()
        let network = await providers.network.read()
        let health = await providers.health.read()

        batteryStatus = battery
        networkStatus = network
        healthStatus = health.selecting(preferences.healthMetric)
        rebuildSnapshot()
    }

    private func rebuildSnapshot() {
        snapshot = SystemStatusSnapshot(
            lastUpdated: Date(),
            battery: batteryStatus,
            network: networkStatus,
            health: healthStatus.selecting(preferences.healthMetric)
        )
    }
}
