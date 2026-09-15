//
//  SystemStatusStore.swift
//  mac-duo-status
//

import Combine
import Foundation
import AppKit

@MainActor
final class SystemStatusStore: ObservableObject {
    @Published private(set) var snapshot: SystemStatusSnapshot

    private let preferences: PreferencesStore
    private let providers: ProviderContainer
    private let samplingIntervalNanoseconds: UInt64
    private let workspaceNotificationCenter: NotificationCenter

    private var refreshTask: Task<Void, Never>?
    private var lifecycleTokens: [NSObjectProtocol] = []
    private var isStarted = false
    private var isRefreshing = false
    private var batteryStatus: BatteryStatus
    private var networkStatus: NetworkStatus
    private var healthStatus: HealthStatus
    private var powerPolicyStatus: PowerPolicyStatus

    init(
        preferences: PreferencesStore,
        providers: ProviderContainer,
        samplingIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.preferences = preferences
        self.providers = providers
        self.samplingIntervalNanoseconds = samplingIntervalNanoseconds
        self.workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        self.batteryStatus = .unavailable(reason: "Battery data is unavailable")
        self.networkStatus = .unavailable(reason: "Network data is unavailable")
        self.healthStatus = .unavailable(selectedMetric: preferences.healthMetric)
        self.powerPolicyStatus = .unavailable(reason: "Power policy is unavailable")
        self.snapshot = .initial(selectedMetric: preferences.healthMetric)
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        startProviderObservers()
        observeWorkspaceLifecycle()
        startSampling()
    }

    func stop() {
        guard isStarted else {
            return
        }

        isStarted = false
        refreshTask?.cancel()
        refreshTask = nil
        providers.battery.stopObserving()
        providers.network.stopObserving()
        providers.health.stopObserving()
        providers.powerPolicy.stopObserving()
        removeWorkspaceObservers()
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    func refreshNowAndWait() async {
        await refresh()
    }

    func setHealthMetric(_ metric: HealthMetric) {
        preferences.healthMetric = metric
        healthStatus = healthStatus.selecting(metric)
        rebuildSnapshot()
    }

    private func startSampling() {
        guard refreshTask == nil else {
            return
        }

        let interval = samplingIntervalNanoseconds
        refreshTask = Task { [weak self] in
            await self?.refresh()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                await self?.refresh()
            }
        }
    }

    private func startProviderObservers() {
        let handler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.refreshNow()
            }
        }

        providers.battery.startObserving(handler)
        providers.network.startObserving(handler)
        providers.health.startObserving(handler)
        providers.powerPolicy.startObserving(handler)
    }

    private func observeWorkspaceLifecycle() {
        lifecycleTokens = [
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.pauseSamplingForSleep()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.resumeSamplingAfterWake()
                }
            }
        ]
    }

    private func removeWorkspaceObservers() {
        lifecycleTokens.forEach(workspaceNotificationCenter.removeObserver)
        lifecycleTokens.removeAll()
    }

    private func pauseSamplingForSleep() {
        guard isStarted else {
            return
        }

        refreshTask?.cancel()
        refreshTask = nil
    }

    private func resumeSamplingAfterWake() {
        guard isStarted else {
            return
        }

        startSampling()
        refreshNow()
    }

    private func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let providers = providers
        let batteryTask = Task.detached(priority: .utility) {
            await providers.battery.read()
        }
        let networkTask = Task.detached(priority: .utility) {
            await providers.network.read()
        }
        let healthTask = Task.detached(priority: .utility) {
            await providers.health.read()
        }
        let powerPolicyTask = Task.detached(priority: .utility) {
            await providers.powerPolicy.read()
        }

        let battery = await batteryTask.value
        let network = await networkTask.value
        let health = await healthTask.value
        let powerPolicy = await powerPolicyTask.value

        batteryStatus = battery
        networkStatus = network
        healthStatus = health.selecting(preferences.healthMetric)
        powerPolicyStatus = powerPolicy
        rebuildSnapshot()
    }

    private func rebuildSnapshot() {
        snapshot = SystemStatusSnapshot(
            lastUpdated: Date(),
            battery: batteryStatus,
            network: networkStatus,
            health: healthStatus.selecting(preferences.healthMetric),
            powerPolicy: powerPolicyStatus
        )
    }
}
