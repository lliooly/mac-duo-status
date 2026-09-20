//
//  SystemStatusStore.swift
//  mac-duo-status
//

import Combine
import Foundation
import AppKit

@MainActor
final class BatteryStatusStore: ObservableObject {
    @Published private(set) var status: BatteryStatus

    init(status: BatteryStatus) {
        self.status = status
    }

    fileprivate func update(_ status: BatteryStatus) {
        guard self.status != status else {
            return
        }

        self.status = status
    }
}

@MainActor
final class NetworkStatusStore: ObservableObject {
    @Published private(set) var status: NetworkStatus

    init(status: NetworkStatus) {
        self.status = status
    }

    fileprivate func update(_ status: NetworkStatus) {
        guard self.status != status else {
            return
        }

        self.status = status
    }
}

@MainActor
final class HealthStatusStore: ObservableObject {
    @Published private(set) var status: HealthStatus

    init(status: HealthStatus) {
        self.status = status
    }

    fileprivate func update(_ status: HealthStatus) {
        guard self.status != status else {
            return
        }

        self.status = status
    }
}

@MainActor
final class PowerPolicyStatusStore: ObservableObject {
    @Published private(set) var status: PowerPolicyStatus

    init(status: PowerPolicyStatus) {
        self.status = status
    }

    fileprivate func update(_ status: PowerPolicyStatus) {
        guard self.status != status else {
            return
        }

        self.status = status
    }
}

@MainActor
final class StatusLastUpdatedStore: ObservableObject {
    @Published private(set) var date: Date

    init(date: Date) {
        self.date = date
    }

    fileprivate func update(_ date: Date) {
        self.date = date
    }
}

@MainActor
final class SystemStatusStore: ObservableObject {
    @Published private(set) var snapshot: SystemStatusSnapshot

    let batteryStatusStore: BatteryStatusStore
    let networkStatusStore: NetworkStatusStore
    let healthStatusStore: HealthStatusStore
    let powerPolicyStatusStore: PowerPolicyStatusStore
    let lastUpdatedStore: StatusLastUpdatedStore

    private let preferences: PreferencesStore
    private let providers: ProviderContainer
    private let widgetStatusBridge: WidgetStatusBridge?
    private let samplingIntervalNanoseconds: UInt64
    private let lowFrequencyRefreshIntervalNanoseconds: UInt64
    private let workspaceNotificationCenter: NotificationCenter
    private var preferenceCancellables = Set<AnyCancellable>()

    private var samplingTask: Task<Void, Never>?
    private var lowFrequencyRefreshTask: Task<Void, Never>?
    private var lifecycleTokens: [NSObjectProtocol] = []
    private var pendingHealthMetric: HealthMetric?
    private var isStarted = false
    private var refreshGeneration: UInt64 = 0

    private var batteryRefreshTask: Task<Void, Never>?
    private var networkRefreshTask: Task<Void, Never>?
    private var healthRefreshTask: Task<Void, Never>?
    private var powerPolicyRefreshTask: Task<Void, Never>?
    private var batteryRefreshPending = false
    private var networkRefreshPending = false
    private var healthRefreshPending = false
    private var powerPolicyRefreshPending = false

    init(
        preferences: PreferencesStore,
        providers: ProviderContainer,
        samplingIntervalNanoseconds: UInt64 = 1_000_000_000,
        lowFrequencyRefreshIntervalNanoseconds: UInt64 = 30_000_000_000,
        widgetStatusBridge: WidgetStatusBridge? = nil
    ) {
        self.preferences = preferences
        self.providers = providers
        self.widgetStatusBridge = widgetStatusBridge
        self.samplingIntervalNanoseconds = samplingIntervalNanoseconds
        self.lowFrequencyRefreshIntervalNanoseconds = lowFrequencyRefreshIntervalNanoseconds
        self.workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        let initialBattery = BatteryStatus.unavailable(reason: "Battery data is unavailable")
        let initialNetwork = NetworkStatus.unavailable(reason: "Network data is unavailable")
        let initialHealth = HealthStatus.unavailable(selectedMetric: preferences.healthMetric)
        let initialPowerPolicy = PowerPolicyStatus.unavailable(
            reason: "Power policy is unavailable"
        )
        let initialDate = Date()

        self.batteryStatusStore = BatteryStatusStore(status: initialBattery)
        self.networkStatusStore = NetworkStatusStore(status: initialNetwork)
        self.healthStatusStore = HealthStatusStore(status: initialHealth)
        self.powerPolicyStatusStore = PowerPolicyStatusStore(status: initialPowerPolicy)
        self.lastUpdatedStore = StatusLastUpdatedStore(date: initialDate)
        self.snapshot = SystemStatusSnapshot(
            lastUpdated: initialDate,
            battery: initialBattery,
            network: initialNetwork,
            health: initialHealth,
            powerPolicy: initialPowerPolicy
        )

        preferences.$usesColor
            .dropFirst()
            .sink { [weak self] usesColor in
                guard let self else {
                    return
                }

                self.widgetStatusBridge?.publish(
                    snapshot: self.snapshot,
                    usesColor: usesColor
                )
            }
            .store(in: &preferenceCancellables)
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        startProviderObservers()
        observeWorkspaceLifecycle()
        startSampling()
        startLowFrequencyRefresh()
    }

    func stop() {
        guard isStarted else {
            return
        }

        isStarted = false
        samplingTask?.cancel()
        samplingTask = nil
        lowFrequencyRefreshTask?.cancel()
        lowFrequencyRefreshTask = nil
        cancelInFlightRefreshes()
        providers.battery.stopObserving()
        providers.network.stopObserving()
        providers.health.stopObserving()
        providers.powerPolicy.stopObserving()
        removeWorkspaceObservers()
    }

    func refreshNow() {
        requestBatteryRefresh(allowWhenStopped: true)
        requestNetworkRefresh(allowWhenStopped: true)
        requestHealthRefresh(allowWhenStopped: true)
        requestPowerPolicyRefresh(allowWhenStopped: true)
    }

    func refreshNowAndWait() async {
        requestBatteryRefresh(allowWhenStopped: true)
        requestNetworkRefresh(allowWhenStopped: true)
        requestHealthRefresh(allowWhenStopped: true)
        requestPowerPolicyRefresh(allowWhenStopped: true)

        await waitForBatteryRefresh()
        await waitForNetworkRefresh()
        await waitForHealthRefresh()
        await waitForPowerPolicyRefresh()
    }

    func refreshPowerPolicyNowAndWait() async {
        requestPowerPolicyRefresh(allowWhenStopped: true)
        await waitForPowerPolicyRefresh()
    }

    func setHealthMetric(_ metric: HealthMetric) {
        let isScheduled = pendingHealthMetric != nil
        pendingHealthMetric = metric
        guard !isScheduled else { return }

        // Native picker callbacks can run during SwiftUI view updates.
        // Commit on the next main-queue turn, keeping only the latest selection.
        DispatchQueue.main.async { [weak self] in
            guard let self, let metric = self.pendingHealthMetric else { return }
            self.pendingHealthMetric = nil
            guard self.preferences.healthMetric != metric else { return }

            self.preferences.healthMetric = metric
            self.healthStatusStore.update(self.healthStatusStore.status.selecting(metric))
            self.rebuildSnapshot()
        }
    }

    private func startSampling() {
        guard samplingTask == nil else {
            return
        }

        let interval = samplingIntervalNanoseconds
        samplingTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.requestBatteryRefresh()
            self.requestHealthRefresh()

            guard interval > 0 else {
                return
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                guard self.isStarted else {
                    return
                }

                self.requestBatteryRefresh()
                self.requestHealthRefresh()
            }
        }
    }

    private func startLowFrequencyRefresh() {
        guard lowFrequencyRefreshTask == nil else {
            return
        }

        let interval = lowFrequencyRefreshIntervalNanoseconds
        lowFrequencyRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.requestNetworkRefresh()
            self.requestPowerPolicyRefresh()

            guard interval > 0 else {
                return
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                guard self.isStarted else {
                    return
                }

                self.requestNetworkRefresh()
                self.requestPowerPolicyRefresh()
            }
        }
    }

    private func startProviderObservers() {
        let batteryHandler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else {
                    return
                }

                self.requestBatteryRefresh()
            }
        }
        let networkHandler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else {
                    return
                }

                self.requestNetworkRefresh()
            }
        }
        let healthHandler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else {
                    return
                }

                self.requestHealthRefresh()
            }
        }
        let powerPolicyHandler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else {
                    return
                }

                self.requestPowerPolicyRefresh()
            }
        }

        providers.battery.startObserving(batteryHandler)
        providers.network.startObserving(networkHandler)
        providers.health.startObserving(healthHandler)
        providers.powerPolicy.startObserving(powerPolicyHandler)
    }

    private func observeWorkspaceLifecycle() {
        lifecycleTokens = [
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pauseSamplingForSleep()
                }
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
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

        samplingTask?.cancel()
        samplingTask = nil
        lowFrequencyRefreshTask?.cancel()
        lowFrequencyRefreshTask = nil
        cancelInFlightRefreshes()
    }

    private func resumeSamplingAfterWake() {
        guard isStarted else {
            return
        }

        startSampling()
        startLowFrequencyRefresh()
    }

    private func requestBatteryRefresh(allowWhenStopped: Bool = false) {
        guard isStarted || allowWhenStopped else {
            return
        }

        if batteryRefreshTask != nil {
            batteryRefreshPending = true
            return
        }

        let provider = providers.battery
        let generation = refreshGeneration
        let task = Task { @MainActor [weak self] in
            defer {
                self?.finishBatteryRefresh(
                    generation: generation,
                    allowWhenStopped: allowWhenStopped
                )
            }

            let battery = await Task.detached(priority: .utility) {
                await provider.read()
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.refreshGeneration == generation
            else {
                return
            }

            let previousPowerSource = self.batteryStatusStore.status.powerSource
            self.batteryStatusStore.update(battery)
            self.rebuildSnapshot()

            if previousPowerSource.rawValue != battery.powerSource.rawValue {
                self.requestPowerPolicyRefresh(allowWhenStopped: allowWhenStopped)
            }
        }
        batteryRefreshTask = task
    }

    private func requestNetworkRefresh(allowWhenStopped: Bool = false) {
        guard isStarted || allowWhenStopped else {
            return
        }

        if networkRefreshTask != nil {
            networkRefreshPending = true
            return
        }

        let provider = providers.network
        let generation = refreshGeneration
        let task = Task { @MainActor [weak self] in
            defer {
                self?.finishNetworkRefresh(
                    generation: generation,
                    allowWhenStopped: allowWhenStopped
                )
            }

            let network = await Task.detached(priority: .utility) {
                await provider.read()
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.refreshGeneration == generation
            else {
                return
            }

            self.networkStatusStore.update(network)
            self.rebuildSnapshot()
        }
        networkRefreshTask = task
    }

    private func requestHealthRefresh(allowWhenStopped: Bool = false) {
        guard isStarted || allowWhenStopped else {
            return
        }

        if healthRefreshTask != nil {
            healthRefreshPending = true
            return
        }

        let provider = providers.health
        let generation = refreshGeneration
        let task = Task { @MainActor [weak self] in
            defer {
                self?.finishHealthRefresh(
                    generation: generation,
                    allowWhenStopped: allowWhenStopped
                )
            }

            let health = await Task.detached(priority: .utility) {
                await provider.read()
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.refreshGeneration == generation
            else {
                return
            }

            self.healthStatusStore.update(health.selecting(self.preferences.healthMetric))
            self.rebuildSnapshot()
        }
        healthRefreshTask = task
    }

    private func requestPowerPolicyRefresh(allowWhenStopped: Bool = false) {
        guard isStarted || allowWhenStopped else {
            return
        }

        if powerPolicyRefreshTask != nil {
            powerPolicyRefreshPending = true
            return
        }

        let provider = providers.powerPolicy
        let generation = refreshGeneration
        let task = Task { @MainActor [weak self] in
            defer {
                self?.finishPowerPolicyRefresh(
                    generation: generation,
                    allowWhenStopped: allowWhenStopped
                )
            }

            let powerPolicy = await Task.detached(priority: .utility) {
                await provider.read()
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.refreshGeneration == generation
            else {
                return
            }

            self.powerPolicyStatusStore.update(powerPolicy)
            self.rebuildSnapshot()
        }
        powerPolicyRefreshTask = task
    }

    private func finishBatteryRefresh(
        generation: UInt64,
        allowWhenStopped: Bool
    ) {
        guard refreshGeneration == generation else {
            return
        }

        batteryRefreshTask = nil
        guard batteryRefreshPending else {
            return
        }

        batteryRefreshPending = false
        requestBatteryRefresh(allowWhenStopped: allowWhenStopped || isStarted)
    }

    private func finishNetworkRefresh(
        generation: UInt64,
        allowWhenStopped: Bool
    ) {
        guard refreshGeneration == generation else {
            return
        }

        networkRefreshTask = nil
        guard networkRefreshPending else {
            return
        }

        networkRefreshPending = false
        requestNetworkRefresh(allowWhenStopped: allowWhenStopped || isStarted)
    }

    private func finishHealthRefresh(
        generation: UInt64,
        allowWhenStopped: Bool
    ) {
        guard refreshGeneration == generation else {
            return
        }

        healthRefreshTask = nil
        guard healthRefreshPending else {
            return
        }

        healthRefreshPending = false
        requestHealthRefresh(allowWhenStopped: allowWhenStopped || isStarted)
    }

    private func finishPowerPolicyRefresh(
        generation: UInt64,
        allowWhenStopped: Bool
    ) {
        guard refreshGeneration == generation else {
            return
        }

        powerPolicyRefreshTask = nil
        guard powerPolicyRefreshPending else {
            return
        }

        powerPolicyRefreshPending = false
        requestPowerPolicyRefresh(allowWhenStopped: allowWhenStopped || isStarted)
    }

    private func waitForBatteryRefresh() async {
        while let task = batteryRefreshTask {
            await task.value
        }
    }

    private func waitForNetworkRefresh() async {
        while let task = networkRefreshTask {
            await task.value
        }
    }

    private func waitForHealthRefresh() async {
        while let task = healthRefreshTask {
            await task.value
        }
    }

    private func waitForPowerPolicyRefresh() async {
        while let task = powerPolicyRefreshTask {
            await task.value
        }
    }

    private func cancelInFlightRefreshes() {
        refreshGeneration &+= 1
        batteryRefreshTask?.cancel()
        networkRefreshTask?.cancel()
        healthRefreshTask?.cancel()
        powerPolicyRefreshTask?.cancel()
        batteryRefreshTask = nil
        networkRefreshTask = nil
        healthRefreshTask = nil
        powerPolicyRefreshTask = nil
        batteryRefreshPending = false
        networkRefreshPending = false
        healthRefreshPending = false
        powerPolicyRefreshPending = false
    }

    private func rebuildSnapshot() {
        let battery = batteryStatusStore.status
        let network = networkStatusStore.status
        let health = healthStatusStore.status.selecting(preferences.healthMetric)
        let powerPolicy = powerPolicyStatusStore.status

        guard snapshot.battery != battery ||
                snapshot.network != network ||
                snapshot.health != health ||
                snapshot.powerPolicy != powerPolicy
        else {
            return
        }

        let lastUpdated = Date()
        lastUpdatedStore.update(lastUpdated)
        snapshot = SystemStatusSnapshot(
            lastUpdated: lastUpdated,
            battery: battery,
            network: network,
            health: health,
            powerPolicy: powerPolicy
        )
        widgetStatusBridge?.publish(
            snapshot: snapshot,
            usesColor: preferences.usesColor
        )
    }
}
