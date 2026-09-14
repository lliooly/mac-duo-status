//
//  mac_duo_statusTests.swift
//  mac-duo-statusTests
//

import Foundation
import Testing
@testable import mac_duo_status

struct mac_duo_statusTests {
    @Test func cpuScoreUsesTheConfirmedFormula() {
        #expect(HealthScoreCalculator.cpuScore(usagePercent: 25) == 0.75)
    }

    @Test func loadScoreUsesLogicalCPUCount() {
        #expect(
            HealthScoreCalculator.loadScore(
                oneMinuteLoad: 2,
                logicalCPUCount: 4
            ) == 0.5
        )
    }

    @Test func thermalScoresMatchTheProductSpecification() {
        #expect(HealthScoreCalculator.thermalScore(for: .nominal) == 1.00)
        #expect(HealthScoreCalculator.thermalScore(for: .fair) == 0.67)
        #expect(HealthScoreCalculator.thermalScore(for: .serious) == 0.33)
        #expect(HealthScoreCalculator.thermalScore(for: .critical) == 0)
    }

    @Test func dotCountRoundsTheScoreTimesFour() {
        #expect(HealthScoreCalculator.dotCount(for: 0.67) == 3)
        #expect(HealthScoreCalculator.dotCount(for: 0.33) == 1)
        #expect(HealthScoreCalculator.dotCount(for: -0.5) == 0)
        #expect(HealthScoreCalculator.dotCount(for: 1.5) == 4)
    }

    @Test func movingAverageKeepsTheConfiguredWindow() {
        var smoother = MovingAverageSmoother(windowSize: 3)

        #expect(smoother.append(1) == 1)
        #expect(smoother.append(2) == 1.5)
        #expect(smoother.append(4) == 7.0 / 3.0)
        #expect(smoother.append(8) == 14.0 / 3.0)
    }

    @Test func batteryFractionIsBounded() {
        #expect(BatteryChargeCalculator.fraction(currentCapacity: 50, maximumCapacity: 100) == 0.5)
        #expect(BatteryChargeCalculator.fraction(currentCapacity: -10, maximumCapacity: 100) == 0)
        #expect(BatteryChargeCalculator.fraction(currentCapacity: 120, maximumCapacity: 100) == 1)
        #expect(BatteryChargeCalculator.fraction(currentCapacity: 50, maximumCapacity: 0) == nil)
    }

    @Test func wifiRSSIMapsToFourSignalLevels() {
        #expect(NetworkSignalMapper.level(forRSSI: -45) == 4)
        #expect(NetworkSignalMapper.level(forRSSI: -55) == 3)
        #expect(NetworkSignalMapper.level(forRSSI: -65) == 2)
        #expect(NetworkSignalMapper.level(forRSSI: -75) == 1)
        #expect(NetworkSignalMapper.level(forRSSI: -90) == 0)
    }

    @Test func onlyWiFiShowsSignalStrength() {
        let wifi = NetworkStatus(
            availability: .available,
            kind: .wifi,
            name: "Home",
            rssi: -55,
            signalLevel: 3,
            hotspotConfirmed: false
        )
        let hotspot = NetworkStatus(
            availability: .available,
            kind: .hotspot,
            name: "Phone",
            rssi: -55,
            signalLevel: 3,
            hotspotConfirmed: true
        )
        let ethernet = NetworkStatus(
            availability: .available,
            kind: .ethernet,
            name: nil,
            rssi: nil,
            signalLevel: nil,
            hotspotConfirmed: false
        )

        #expect(wifi.shouldShowWiFiSignal)
        #expect(!hotspot.shouldShowWiFiSignal)
        #expect(!ethernet.shouldShowWiFiSignal)
    }

    @Test func placeholderProvidersExposeUnavailableStates() async {
        let battery = await PlaceholderBatteryProvider().read()
        let network = await PlaceholderNetworkProvider().read()
        let health = await PlaceholderHealthProvider().read()

        let batteryIsAvailable = await battery.availability.isAvailable
        let networkIsAvailable = await network.availability.isAvailable
        let healthIsAvailable = await health.availability.isAvailable

        #expect(batteryIsAvailable == false)
        #expect(networkIsAvailable == false)
        #expect(healthIsAvailable == false)
    }

    @Test
    @MainActor
    func healthProviderSmoothsCPUAndLoadSamples() async {
        let provider = HealthProvider(
            smoothingWindowSize: 3,
            cpuReader: SequenceCPUReader(values: [20, 40]),
            loadReader: FixedLoadReader(value: (1, 2, 3))
        )

        let first = await provider.read()
        let second = await provider.read()

        #expect(first.cpuUsagePercent == 20)
        #expect(abs((second.cpuUsagePercent ?? 0) - 30) < 0.001)
        #expect(first.oneMinuteLoad == 1)
        #expect(second.oneMinuteLoad == 1)
    }

    @Test
    @MainActor
    func preferencesPersistAllV1Settings() {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(defaults: defaults)
        preferences.healthMetric = .load
        preferences.launchAtLogin = true
        preferences.usesColor = true
        preferences.setExpanded(true, for: .network)

        let restored = PreferencesStore(defaults: defaults)
        #expect(restored.healthMetric == .load)
        #expect(restored.launchAtLogin)
        #expect(restored.usesColor)
        #expect(restored.isExpanded(.network))
    }

    @Test
    @MainActor
    func statusStorePublishesOneSnapshotFromAllProviders() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expectedBattery = BatteryStatus(
            availability: .available,
            hasBuiltInBattery: true,
            chargeFraction: 0.8,
            isCharging: false,
            powerSource: .battery,
            isLowPowerModeEnabled: false
        )
        let expectedNetwork = NetworkStatus(
            availability: .available,
            kind: .wifi,
            name: "Test Wi-Fi",
            rssi: -55,
            signalLevel: 3,
            hotspotConfirmed: false
        )
        let expectedHealth = HealthStatus(
            availability: .available,
            cpuUsagePercent: 25,
            oneMinuteLoad: 1,
            fiveMinuteLoad: 1,
            fifteenMinuteLoad: 1,
            logicalCPUCount: 4,
            thermalState: .nominal,
            cpuScore: 0.75,
            loadScore: 0.75,
            thermalScore: 1,
            selectedMetric: .cpu,
            selectedScore: 0.75,
            dotCount: 3
        )

        let preferences = PreferencesStore(defaults: defaults)
        let store = SystemStatusStore(
            preferences: preferences,
            providers: ProviderContainer(
                battery: FixedBatteryProvider(value: expectedBattery),
                network: FixedNetworkProvider(value: expectedNetwork),
                health: FixedHealthProvider(value: expectedHealth)
            ),
            samplingIntervalNanoseconds: 50_000_000
        )

        store.start()
        defer { store.stop() }
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.snapshot.battery == expectedBattery)
        #expect(store.snapshot.network == expectedNetwork)
        #expect(store.snapshot.health.selectedScore == 0.75)
    }

    @Test
    @MainActor
    func statusStoreKeepsProviderFailuresScoped() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expectedNetwork = NetworkStatus(
            availability: .available,
            kind: .ethernet,
            name: nil,
            rssi: nil,
            signalLevel: nil,
            hotspotConfirmed: false
        )
        let expectedHealth = HealthStatus(
            availability: .available,
            cpuUsagePercent: 10,
            oneMinuteLoad: 0.5,
            fiveMinuteLoad: 0.5,
            fifteenMinuteLoad: 0.5,
            logicalCPUCount: 4,
            thermalState: .nominal,
            cpuScore: 0.9,
            loadScore: 0.875,
            thermalScore: 1,
            selectedMetric: .cpu,
            selectedScore: 0.9,
            dotCount: 4
        )

        let preferences = PreferencesStore(defaults: defaults)
        let store = SystemStatusStore(
            preferences: preferences,
            providers: ProviderContainer(
                battery: FixedBatteryProvider(
                    value: .unavailable(reason: "Battery unavailable")
                ),
                network: FixedNetworkProvider(value: expectedNetwork),
                health: FixedHealthProvider(value: expectedHealth)
            ),
            samplingIntervalNanoseconds: 50_000_000
        )

        store.start()
        defer { store.stop() }
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.snapshot.battery.availability.isAvailable == false)
        #expect(store.snapshot.network == expectedNetwork)
        #expect(store.snapshot.health == expectedHealth)
    }

    @Test
    @MainActor
    func launchAtLoginRollsBackWhenRegistrationFails() {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(
            defaults: defaults,
            launchAtLoginManager: FailingLaunchAtLoginManager()
        )

        preferences.launchAtLogin = true

        #expect(preferences.launchAtLogin == false)
        #expect(defaults.bool(forKey: "launchAtLogin") == false)
    }
}

private struct SequenceCPUReader: CPUUsageReading {
    let values: [Double]
    private let state = LockedSequence()

    func readUsagePercent() -> Double? {
        state.next(from: values)
    }
}

private final class LockedSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0

    func next(from values: [Double]) -> Double? {
        lock.lock()
        defer { lock.unlock() }

        guard index < values.count else {
            return values.last
        }

        defer { index += 1 }
        return values[index]
    }
}

private struct FixedLoadReader: LoadAverageReading {
    let value: (oneMinute: Double, fiveMinute: Double, fifteenMinute: Double)

    func readLoadAverages() -> (oneMinute: Double, fiveMinute: Double, fifteenMinute: Double)? {
        value
    }
}

private struct FixedBatteryProvider: BatteryProviding {
    let value: BatteryStatus

    func read() async -> BatteryStatus {
        value
    }
}

private struct FixedNetworkProvider: NetworkProviding {
    let value: NetworkStatus

    func read() async -> NetworkStatus {
        value
    }
}

private struct FixedHealthProvider: HealthProviding {
    let value: HealthStatus

    func read() async -> HealthStatus {
        value
    }
}

private struct FailingLaunchAtLoginManager: LaunchAtLoginManaging {
    @MainActor
    func setEnabled(_ enabled: Bool) throws {
        throw RegistrationError.failed
    }

    private enum RegistrationError: Error {
        case failed
    }
}
