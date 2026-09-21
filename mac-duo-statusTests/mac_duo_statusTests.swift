//
//  mac_duo_statusTests.swift
//  mac-duo-statusTests
//

import Foundation
import Combine
import Testing
@testable import mac_duo_status

@MainActor
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

    @Test func coloredIconOnlyChangesBatteryColor() {
        let normal = testBattery(
            chargeFraction: 0.5,
            isCharging: false,
            isLowPowerModeEnabled: false
        )
        let charging = testBattery(
            chargeFraction: 0.5,
            isCharging: true,
            isLowPowerModeEnabled: false
        )
        let lowPowerMode = testBattery(
            chargeFraction: 0.5,
            isCharging: false,
            isLowPowerModeEnabled: true
        )
        let lowBattery = testBattery(
            chargeFraction: 0.1,
            isCharging: false,
            isLowPowerModeEnabled: false
        )
        let chargingInLowPowerMode = testBattery(
            chargeFraction: 0.1,
            isCharging: true,
            isLowPowerModeEnabled: true
        )

        #expect(
            BatteryIconColorResolver.resolve(for: normal, usesColor: false) == .white
        )
        #expect(
            BatteryIconColorResolver.resolve(for: normal, usesColor: true) == .white
        )
        #expect(
            BatteryIconColorResolver.resolve(for: charging, usesColor: true) == .green
        )
        #expect(
            BatteryIconColorResolver.resolve(for: lowPowerMode, usesColor: true) == .yellow
        )
        #expect(
            BatteryIconColorResolver.resolve(for: lowBattery, usesColor: true) == .red
        )
        #expect(
            BatteryIconColorResolver.resolve(
                for: chargingInLowPowerMode,
                usesColor: true
            ) == .green
        )
    }

    @Test func adapterPowerDefinesTheChargingStatus() {
        #expect(PowerSource.powerAdapter.isPoweredByAdapter == true)
        #expect(PowerSource.battery.isPoweredByAdapter == false)
        #expect(PowerSource.unknown.isPoweredByAdapter == nil)
    }

    @Test func wifiRSSIMapsToFourSignalLevels() {
        #expect(NetworkSignalMapper.level(forRSSI: -45) == 4)
        #expect(NetworkSignalMapper.level(forRSSI: -55) == 3)
        #expect(NetworkSignalMapper.level(forRSSI: -65) == 2)
        #expect(NetworkSignalMapper.level(forRSSI: -75) == 1)
        #expect(NetworkSignalMapper.level(forRSSI: -90) == 0)
    }

    @Test func pmsetModeParserMapsAllPowermodeValues() {
        #expect(
            PMSetPowerModeParser.modeName(
                for: PMSetModeReadout(key: "powermode", value: 0)
            ) == "automatic"
        )
        #expect(
            PMSetPowerModeParser.modeName(
                for: PMSetModeReadout(key: "powermode", value: 1)
            ) == "lowPower"
        )
        #expect(
            PMSetPowerModeParser.modeName(
                for: PMSetModeReadout(key: "powermode", value: 2)
            ) == "highPower"
        )
        #expect(
            PMSetPowerModeParser.value(for: "highPower", key: "lowpowermode") == nil
        )
    }

    @Test func pmsetModeParserReadsBatteryAndAdapterSections() {
        let output = """
        Battery Power:
         powermode            1
        AC Power:
         powermode            2
        """

        let readout = PMSetPowerModeParser.parseScopedModes(output)

        #expect(readout?.battery == PMSetModeReadout(key: "powermode", value: 1))
        #expect(readout?.adapter == PMSetModeReadout(key: "powermode", value: 2))
    }

    @Test func pmsetModeParserSupportsLowPowerOnlyOutput() {
        let capabilities = PMSetPowerModeParser.parseCapabilities(
            """
            Capabilities for Battery Power:
             lowpowermode
            """
        )

        #expect(capabilities?.supportsLowPower == true)
        #expect(capabilities?.supportsHighPower == false)
        #expect(
            PMSetPowerModeParser.modeName(
                for: PMSetModeReadout(key: "lowpowermode", value: 1)
            ) == "lowPower"
        )
    }

    @Test func pmsetModeParserReadsAdapterCapabilities() {
        let capabilities = PMSetPowerModeParser.parseCapabilities(
            """
            Capabilities for AC Power:
             lowpowermode
             highpowermode
            """
        )

        #expect(capabilities?.supportsLowPower == true)
        #expect(capabilities?.supportsHighPower == true)
    }

    @Test func pmsetModeParserRejectsMalformedOrIncompleteOutput() {
        #expect(
            PMSetPowerModeParser.parseScopedModes(
                """
                Battery Power:
                 powermode 3
                AC Power:
                 powermode 0
                """
            ) == nil
        )
        #expect(
            PMSetPowerModeParser.parseScopedModes(
                """
                Battery Power:
                 powermode 0
                """
            ) == nil
        )
        #expect(
            PMSetPowerModeParser.parseActiveMode(
                """
                System-wide power settings:
                Currently in use:
                 powermode 0
                 lowpowermode 1
                """
            ) == nil
        )
    }

    @Test func pmsetModeParserReadsTheCurrentActiveSection() {
        let readout = PMSetPowerModeParser.parseActiveMode(
            """
            System-wide power settings:
            Currently in use:
             powermode            0
            """
        )

        #expect(readout == PMSetModeReadout(key: "powermode", value: 0))
    }

    @Test func powerPolicyDoesNotInferAutomaticWithoutAReadback() async {
        let provider = PowerPolicyProvider(
            helper: RecordingPowerControl(capabilities: .unsupported),
            lowPowerModeEnabled: { false }
        )

        let status = await provider.read()

        #expect(status.activeMode == nil)
    }

    @Test func powerPolicyUsesTheHelperActiveModeReadback() async {
        let provider = PowerPolicyProvider(
            helper: RecordingPowerControl(
                capabilities: .unsupported,
                activePowerModeReadback: .highPower
            ),
            lowPowerModeEnabled: { false }
        )

        let status = await provider.read()

        #expect(status.activeMode == .highPower)
    }

    @Test func powerPolicyReadsTheCompletePowerStateOncePerRefresh() async {
        let powerControl = RecordingPowerControl(
            capabilities: .unsupported,
            powerModeReadback: .automatic,
            activePowerModeReadback: .highPower
        )
        let provider = PowerPolicyProvider(
            helper: powerControl,
            lowPowerModeEnabled: { false },
            powerStateRefreshIntervalNanoseconds: 0
        )

        let status = await provider.read()

        #expect(powerControl.readPowerStateCalls == 1)
        #expect(status.activeMode == .highPower)
        #expect(status.batteryMode == .automatic)
        #expect(status.adapterMode == .automatic)
    }

    @Test func powerPolicyCachesPowerStateBetweenRefreshes() async {
        let powerControl = RecordingPowerControl(
            capabilities: .unsupported,
            powerModeReadback: .automatic,
            activePowerModeReadback: .highPower
        )
        let provider = PowerPolicyProvider(
            helper: powerControl,
            lowPowerModeEnabled: { false },
            powerStateRefreshIntervalNanoseconds: 5_000_000_000
        )

        _ = await provider.read()
        _ = await provider.read()

        #expect(powerControl.readPowerStateCalls == 1)
    }

    @Test
    func powerPolicyDoesNotRestoreInvalidatedCacheFromAnOlderRead() async {
        let oldState = PowerModeState(
            activeMode: .automatic,
            batteryMode: .automatic,
            adapterMode: .automatic
        )
        let updatedState = PowerModeState(
            activeMode: .lowPower,
            batteryMode: .lowPower,
            adapterMode: .automatic
        )
        let helper = InterleavedPowerControl(
            initialState: oldState,
            updatedState: updatedState
        )
        let provider = PowerPolicyProvider(
            helper: helper,
            lowPowerModeEnabled: { false },
            powerStateRefreshIntervalNanoseconds: 5_000_000_000
        )

        let olderRead = Task {
            await provider.read()
        }
        await helper.waitForFirstRead()

        try? await provider.setPowerMode(.lowPower, scope: .battery)
        await helper.releaseFirstRead()
        _ = await olderRead.value

        let refreshed = await provider.read()

        #expect(refreshed.batteryMode == .lowPower)
        #expect(helper.readPowerStateCalls == 2)
    }

    @Test
    func powerPolicyDoesNotRestoreInvalidatedCacheAfterAChangeNotification() async {
        let oldState = PowerModeState(
            activeMode: .automatic,
            batteryMode: .automatic,
            adapterMode: .automatic
        )
        let updatedState = PowerModeState(
            activeMode: .lowPower,
            batteryMode: .lowPower,
            adapterMode: .automatic
        )
        let notificationCenter = NotificationCenter()
        let helper = InterleavedPowerControl(
            initialState: oldState,
            updatedState: updatedState
        )
        let provider = PowerPolicyProvider(
            helper: helper,
            notificationCenter: notificationCenter,
            lowPowerModeEnabled: { false },
            powerStateRefreshIntervalNanoseconds: 5_000_000_000
        )
        provider.startObserving {}
        defer { provider.stopObserving() }

        let olderRead = Task {
            await provider.read()
        }
        await helper.waitForFirstRead()

        notificationCenter.post(
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo
        )
        await helper.releaseFirstRead()
        _ = await olderRead.value

        let refreshed = await provider.read()

        #expect(refreshed.batteryMode == .lowPower)
        #expect(helper.readPowerStateCalls == 2)
    }

    @Test func controlStateOnlyMarksPendingOperationsAsBusy() {
        #expect(ControlOperationState.idle.isPending == false)
        #expect(ControlOperationState.pending.isPending)
        #expect(ControlOperationState.failed(.failed).isPending == false)
    }

    @Test
    func coordinatorReportsUnconfirmedPowerReadback() async {
        let suiteName = "DuoStatusTests-(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let powerControl = RecordingPowerControl(
            capabilities: PowerCapabilities(
                energyModeScopes: [.battery],
                supportedPowerModes: [.automatic, .lowPower],
                requiresHelper: true,
                helperStatus: .authorized
            ),
            powerModeReadback: .automatic
        )
        let controls = ControlCoordinator(
            statusStore: makeStatusStore(
                network: .unavailable(reason: "No network"),
                defaults: defaults
            ),
            powerControl: powerControl
        )

        await controls.setPowerMode(.lowPower, scope: .battery)

        #expect(controls.powerOperationState == .failed(.writeUnconfirmed))
        #expect(powerControl.setPowerModeCalls == 1)
    }

    @Test
    func coordinatorBlocksASecondPowerWriteWhileTheFirstIsPending() async {
        let suiteName = "DuoStatusTests-(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let powerControl = BlockingPowerControl()
        let controls = ControlCoordinator(
            statusStore: makeStatusStore(
                network: .unavailable(reason: "No network"),
                defaults: defaults
            ),
            powerControl: powerControl
        )

        let firstOperation = Task { @MainActor in
            await controls.setPowerMode(.lowPower, scope: .battery)
        }
        await Task.yield()

        await controls.setPowerMode(.automatic, scope: .battery)

        #expect(powerControl.setPowerModeCalls == 1)
        #expect(controls.powerOperationState == .pending)

        powerControl.releasePowerMode()
        await firstOperation.value
    }

    @Test
    func coordinatorWaitsForAnInFlightRefreshBeforeConfirmingPowerWrite() async {
        let suiteName = "DuoStatusTests-(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let capabilities = PowerCapabilities(
            energyModeScopes: [.battery],
            supportedPowerModes: [.automatic, .lowPower],
            requiresHelper: true,
            helperStatus: .authorized
        )
        let oldStatus = PowerPolicyStatus(
            availability: .available,
            activeMode: .automatic,
            batteryMode: .automatic,
            adapterMode: .automatic,
            helperStatus: .authorized,
            capabilities: capabilities
        )
        let newStatus = PowerPolicyStatus(
            availability: .available,
            activeMode: .lowPower,
            batteryMode: .lowPower,
            adapterMode: .automatic,
            helperStatus: .authorized,
            capabilities: capabilities
        )
        let policyProvider = SequencedPowerPolicyProvider(
            initialStatus: oldStatus,
            updatedStatus: newStatus
        )
        let powerControl = RecordingPowerControl(
            capabilities: capabilities,
            powerModeReadback: .lowPower
        )
        let store = SystemStatusStore(
            preferences: PreferencesStore(defaults: defaults),
            providers: ProviderContainer(
                battery: FixedBatteryProvider(
                    value: .unavailable(reason: "Battery unavailable")
                ),
                network: FixedNetworkProvider(
                    value: .unavailable(reason: "Network unavailable")
                ),
                health: FixedHealthProvider(
                    value: .unavailable(selectedMetric: .cpu)
                ),
                powerPolicy: policyProvider,
                powerControl: powerControl
            )
        )
        let controls = ControlCoordinator(
            statusStore: store,
            powerControl: powerControl
        )

        store.refreshNow()
        await policyProvider.waitForFirstRead()

        let operation = Task { @MainActor in
            await controls.setPowerMode(.lowPower, scope: .battery)
        }
        while powerControl.setPowerModeCalls == 0 {
            await Task.yield()
        }
        await Task.yield()

        #expect(controls.powerOperationState == .pending)

        await policyProvider.releaseFirstRead()
        await operation.value

        #expect(controls.powerOperationState == .succeeded)
        #expect(powerControl.operationEvents == ["set", "uncached-read"])
        #expect(powerControl.uncachedReadCalls == 1)
        #expect(policyProvider.readCount == 2)
        #expect(store.snapshot.powerPolicy.batteryMode == .lowPower)
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

        let batteryIsAvailable = battery.availability.isAvailable
        let networkIsAvailable = network.availability.isAvailable
        let healthIsAvailable = health.availability.isAvailable

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
    func healthProviderNotifiesOnSystemStateChanges() {
        let notificationCenter = NotificationCenter()
        let provider = HealthProvider(notificationCenter: notificationCenter)
        let counter = LockedCounter()

        provider.startObserving {
            counter.increment()
        }

        notificationCenter.post(
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: ProcessInfo.processInfo
        )
        notificationCenter.post(
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo
        )

        #expect(counter.value == 2)
        provider.stopObserving()
    }

    @Test
    @MainActor
    func preferencesPersistAllV1Settings() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(defaults: defaults)
        preferences.healthMetric = .load
        await preferences.setLaunchAtLogin(true)
        preferences.usesColor = true
        preferences.setExpanded(true, for: .network)

        let restored = PreferencesStore(defaults: defaults)
        #expect(restored.healthMetric == .load)
        #expect(restored.launchAtLogin)
        #expect(restored.usesColor)
        #expect(restored.isExpanded(.network))
    }

    @Test
    func metricSelectionDefersPublishingAndKeepsLatestRequest() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStatusStore(
            network: .unavailable(reason: "Test"),
            defaults: defaults
        )
        var publicationCount = 0
        let subscription = store.$snapshot.dropFirst().sink { _ in
            publicationCount += 1
        }
        defer { subscription.cancel() }

        store.setHealthMetric(.thermal)
        store.setHealthMetric(.load)
        #expect(publicationCount == 0)
        #expect(store.snapshot.health.selectedMetric == .cpu)
        #expect(defaults.string(forKey: "healthMetric") == nil)

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(publicationCount == 1)
        #expect(store.snapshot.health.selectedMetric == .load)
        #expect(store.healthStatusStore.status.selectedMetric == .load)
        #expect(PreferencesStore(defaults: defaults).healthMetric == .load)

        // Returning to the current selection cancels an intermediate request.
        store.setHealthMetric(.cpu)
        store.setHealthMetric(.load)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(publicationCount == 1)
        #expect(store.snapshot.health.selectedMetric == .load)

        store.setHealthMetric(.load)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(publicationCount == 1)
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
    func statusStorePublishesFastDomainsBeforeSlowDomainsFinish() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expectedBattery = testBattery(
            chargeFraction: 0.8,
            isCharging: false,
            isLowPowerModeEnabled: false
        )
        let expectedHealth = HealthStatus(
            availability: .available,
            cpuUsagePercent: 20,
            oneMinuteLoad: 1,
            fiveMinuteLoad: 1,
            fifteenMinuteLoad: 1,
            logicalCPUCount: 4,
            thermalState: .nominal,
            cpuScore: 0.8,
            loadScore: 0.75,
            thermalScore: 1,
            selectedMetric: .cpu,
            selectedScore: 0.8,
            dotCount: 3
        )
        let networkGate = AsyncGate()
        let powerPolicyGate = AsyncGate()
        let store = SystemStatusStore(
            preferences: PreferencesStore(defaults: defaults),
            providers: ProviderContainer(
                battery: FixedBatteryProvider(value: expectedBattery),
                network: GatedNetworkProvider(
                    gate: networkGate,
                    value: .unavailable(reason: "Network read is gated")
                ),
                health: FixedHealthProvider(value: expectedHealth),
                powerPolicy: GatedPowerPolicyProvider(
                    gate: powerPolicyGate,
                    value: .unavailable(reason: "Power policy read is gated")
                )
            ),
            samplingIntervalNanoseconds: 0,
            lowFrequencyRefreshIntervalNanoseconds: 0
        )

        store.start()
        await waitUntil {
            store.snapshot.battery == expectedBattery &&
                store.snapshot.health == expectedHealth
        }

        #expect(store.snapshot.battery == expectedBattery)
        #expect(store.snapshot.health == expectedHealth)

        await networkGate.open()
        await powerPolicyGate.open()
        store.stop()
    }

    @Test
    @MainActor
    func statusStoreRefreshesOnlyAffectedDomainsForProviderEvents() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let batteryProvider = EventedBatteryProvider(
            value: .unavailable(reason: "Battery unavailable")
        )
        let networkProvider = EventedNetworkProvider(
            value: .unavailable(reason: "Network unavailable")
        )
        let healthProvider = EventedHealthProvider(
            value: .unavailable(selectedMetric: .cpu)
        )
        let powerPolicyProvider = EventedPowerPolicyProvider(
            value: .unavailable(reason: "Power policy unavailable")
        )
        let store = SystemStatusStore(
            preferences: PreferencesStore(defaults: defaults),
            providers: ProviderContainer(
                battery: batteryProvider,
                network: networkProvider,
                health: healthProvider,
                powerPolicy: powerPolicyProvider
            ),
            samplingIntervalNanoseconds: 0,
            lowFrequencyRefreshIntervalNanoseconds: 0
        )

        store.start()
        await waitUntil {
            batteryProvider.readCount == 1 &&
                networkProvider.readCount == 1 &&
                healthProvider.readCount == 1 &&
                powerPolicyProvider.readCount == 1
        }

        batteryProvider.resetReadCount()
        networkProvider.resetReadCount()
        healthProvider.resetReadCount()
        powerPolicyProvider.resetReadCount()

        networkProvider.sendEvent()
        await waitUntil { networkProvider.readCount == 1 }
        #expect(batteryProvider.readCount == 0)
        #expect(healthProvider.readCount == 0)
        #expect(powerPolicyProvider.readCount == 0)

        batteryProvider.resetReadCount()
        networkProvider.resetReadCount()
        healthProvider.resetReadCount()
        powerPolicyProvider.resetReadCount()

        powerPolicyProvider.sendEvent()
        await waitUntil { powerPolicyProvider.readCount == 1 }
        #expect(batteryProvider.readCount == 0)
        #expect(networkProvider.readCount == 0)
        #expect(healthProvider.readCount == 0)

        batteryProvider.resetReadCount()
        networkProvider.resetReadCount()
        healthProvider.resetReadCount()
        powerPolicyProvider.resetReadCount()

        healthProvider.sendEvent()
        await waitUntil { healthProvider.readCount == 1 }
        #expect(batteryProvider.readCount == 0)
        #expect(networkProvider.readCount == 0)
        #expect(powerPolicyProvider.readCount == 0)

        batteryProvider.resetReadCount()
        networkProvider.resetReadCount()
        healthProvider.resetReadCount()
        powerPolicyProvider.resetReadCount()

        batteryProvider.setValue(testBattery(
            chargeFraction: 0.7,
            isCharging: true,
            isLowPowerModeEnabled: false
        ))
        batteryProvider.sendEvent()
        await waitUntil {
            batteryProvider.readCount == 1 &&
                powerPolicyProvider.readCount == 1
        }
        #expect(networkProvider.readCount == 0)
        #expect(healthProvider.readCount == 0)

        store.stop()
    }

    @Test
    @MainActor
    func statusStoreUsesTheLowFrequencyFallbackForSlowDomains() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let networkProvider = EventedNetworkProvider(
            value: .unavailable(reason: "Network unavailable")
        )
        let powerPolicyProvider = EventedPowerPolicyProvider(
            value: .unavailable(reason: "Power policy unavailable")
        )
        let store = SystemStatusStore(
            preferences: PreferencesStore(defaults: defaults),
            providers: ProviderContainer(
                battery: FixedBatteryProvider(
                    value: .unavailable(reason: "Battery unavailable")
                ),
                network: networkProvider,
                health: FixedHealthProvider(
                    value: .unavailable(selectedMetric: .cpu)
                ),
                powerPolicy: powerPolicyProvider
            ),
            samplingIntervalNanoseconds: 1_000_000_000,
            lowFrequencyRefreshIntervalNanoseconds: 10_000_000
        )

        store.start()
        await waitUntil {
            networkProvider.readCount >= 1 &&
                powerPolicyProvider.readCount >= 1
        }
        await waitUntil {
            networkProvider.readCount >= 2 &&
                powerPolicyProvider.readCount >= 2
        }

        #expect(networkProvider.readCount >= 2)
        #expect(powerPolicyProvider.readCount >= 2)
        store.stop()
    }

    @Test
    @MainActor
    func statusStoreDoesNotPublishASecondSnapshotForUnchangedProviderValues() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expectedBattery = testBattery(
            chargeFraction: 0.8,
            isCharging: false,
            isLowPowerModeEnabled: false
        )
        let store = SystemStatusStore(
            preferences: PreferencesStore(defaults: defaults),
            providers: ProviderContainer(
                battery: FixedBatteryProvider(value: expectedBattery),
                network: FixedNetworkProvider(
                    value: .unavailable(reason: "Network unavailable")
                ),
                health: FixedHealthProvider(
                    value: .unavailable(selectedMetric: .cpu)
                )
            )
        )
        let publishCounter = LockedCounter()
        let cancellation = store.$snapshot
            .dropFirst()
            .sink { _ in
                publishCounter.increment()
            }

        await store.refreshNowAndWait()
        let publishCountAfterFirstRefresh = publishCounter.value

        await store.refreshNowAndWait()

        #expect(publishCountAfterFirstRefresh > 0)
        #expect(publishCounter.value == publishCountAfterFirstRefresh)
        _ = cancellation
    }

    @Test
    @MainActor
    func launchAtLoginRollsBackWhenRegistrationFails() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(
            defaults: defaults,
            launchAtLoginManager: FailingLaunchAtLoginManager()
        )

        await preferences.setLaunchAtLogin(true)

        #expect(preferences.launchAtLogin == false)
        #expect(defaults.bool(forKey: "launchAtLogin") == false)
    }

    @Test
    @MainActor
    func launchAtLoginShowsProgressWhileRegistrationIsInFlight() async {
        let suiteName = "DuoStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = GatedLaunchAtLoginManager()
        let preferences = PreferencesStore(
            defaults: defaults,
            launchAtLoginManager: manager
        )

        let operation = Task { @MainActor in
            await preferences.setLaunchAtLogin(true)
        }
        await waitUntil { preferences.isUpdatingLaunchAtLogin }

        #expect(preferences.launchAtLogin)
        #expect(preferences.isUpdatingLaunchAtLogin)

        await manager.release()
        await operation.value

        #expect(!preferences.isUpdatingLaunchAtLogin)
        #expect(defaults.bool(forKey: "launchAtLogin"))
    }

    @Test
    @MainActor
    func localizationPersistsTheSelectedLanguage() {
        let suiteName = "DuoStatusLocalizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let localization = LocalizationStore(defaults: defaults)
        #expect(localization.language == .system)

        localization.language = .japanese

        #expect(defaults.string(forKey: "appLanguage") == AppLanguage.japanese.rawValue)
        #expect(LocalizationStore(defaults: defaults).language == .japanese)
    }

    @Test
    @MainActor
    func localizationRejectsUnknownStoredLanguages() {
        let suiteName = "DuoStatusLocalizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("pt-BR", forKey: "appLanguage")

        #expect(LocalizationStore(defaults: defaults).language == .system)
    }

    @Test
    @MainActor
    func localizationSwitchesBundlesAndFallsBackForMissingKeys() {
        let suiteName = "DuoStatusLocalizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let localization = LocalizationStore(defaults: defaults)

        localization.language = .english
        #expect(localization.string("settings.language") == "Language")

        localization.language = .japanese
        #expect(localization.string("settings.language") == "言語")
        #expect(localization.string("localization.missing-key") == "localization.missing-key")
    }

    @Test
    @MainActor
    func widgetSnapshotRoundTripsThroughSharedDefaults() {
        let suiteName = "DuoStatusWidgetTests-\(UUID().uuidString)"
        let writerDefaults = UserDefaults(suiteName: suiteName)!
        defer { writerDefaults.removePersistentDomain(forName: suiteName) }

        let snapshot = WidgetStatusSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            battery: .init(
                isAvailable: true,
                hasBuiltInBattery: true,
                chargeFraction: 0.63,
                isCharging: true,
                isLowPowerModeEnabled: false
            ),
            network: .init(isAvailable: true, kind: .wifi),
            healthDotCount: 3,
            usesColor: true
        )
        let writer = WidgetStatusSnapshotStore(defaults: writerDefaults)

        #expect(writer.write(snapshot))

        let readerDefaults = UserDefaults(suiteName: suiteName)!
        let reader = WidgetStatusSnapshotStore(defaults: readerDefaults)
        #expect(reader.read() == snapshot)
    }

    @Test
    func widgetSnapshotStoreReturnsNilForAnEmptySharedSuite() {
        let suiteName = "DuoStatusWidgetEmptyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WidgetStatusSnapshotStore(defaults: defaults)

        #expect(store.read() == nil)
    }

    @Test
    @MainActor
    func widgetFileStoreReadsNewWritesWithoutRecreatingReader() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let writer = WidgetStatusSnapshotStore(containerURL: container)
        let reader = WidgetStatusSnapshotStore(containerURL: container)
        #expect(reader.read() == nil)

        let first = WidgetStatusSnapshot.placeholder
        #expect(writer.write(first))
        #expect(reader.read() == first)
        let second = WidgetStatusSnapshot.unavailable(updatedAt: first.updatedAt.addingTimeInterval(60))
        #expect(writer.write(second))
        #expect(reader.read() == second)

        let file = container.appendingPathComponent("widget-status-snapshot.json")
        try Data("invalid JSON".utf8).write(to: file)
        #expect(reader.read() == nil)
        #expect(writer.write(first))
        #expect(reader.read() == first)
    }

    @Test
    @MainActor
    func widgetFileStoreReportsFailedWrites() {
        let missingContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = WidgetStatusSnapshotStore(containerURL: missingContainer)
        #expect(!store.write(.placeholder))
        #expect(store.read() == nil)
    }

    @Test
    func widgetDisplayContentIgnoresHeartbeatTimestamp() {
        let first = WidgetStatusSnapshot.placeholder
        let second = WidgetStatusSnapshot(
            updatedAt: first.updatedAt.addingTimeInterval(60),
            battery: first.battery,
            network: first.network,
            healthDotCount: first.healthDotCount,
            usesColor: first.usesColor
        )

        #expect(first.hasSameDisplayContent(as: second))
    }

    @Test
    @MainActor
    func widgetBridgeProjectsExistingStatusSnapshotWithoutNewProviders() {
        let suiteName = "DuoStatusWidgetBridgeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let battery = testBattery(
            chargeFraction: 0.42,
            isCharging: false,
            isLowPowerModeEnabled: true
        )
        let snapshot = SystemStatusSnapshot(
            lastUpdated: Date(),
            battery: battery,
            network: NetworkStatus(
                availability: .available,
                kind: .ethernet,
                name: nil,
                rssi: nil,
                signalLevel: nil,
                hotspotConfirmed: false
            ),
            health: HealthStatus(
                availability: .available,
                cpuUsagePercent: 20,
                oneMinuteLoad: 1,
                fiveMinuteLoad: 1,
                fifteenMinuteLoad: 1,
                logicalCPUCount: 4,
                thermalState: .nominal,
                cpuScore: 0.8,
                loadScore: 0.75,
                thermalScore: 1,
                selectedMetric: .cpu,
                selectedScore: 0.8,
                dotCount: 3
            ),
            powerPolicy: .unavailable(reason: "Not used by widget")
        )
        let store = WidgetStatusSnapshotStore(defaults: defaults)
        let reloadCounter = LockedCounter()
        let bridge = WidgetStatusBridge(
            snapshotStore: store,
            reloadHandler: { reloadCounter.increment() }
        )

        bridge.publish(snapshot: snapshot, usesColor: true)

        let published = store.read()
        #expect(published?.battery.chargeFraction == 0.42)
        #expect(published?.battery.isLowPowerModeEnabled == true)
        #expect(published?.network.kind == .ethernet)
        #expect(published?.healthDotCount == 3)
        #expect(published?.usesColor == true)
        #expect(reloadCounter.value == 1)
    }

    @Test
    @MainActor
    func widgetBridgeReloadsEachDisplayChangeButNotHeartbeatWrites() {
        let suiteName = "DuoStatusWidgetReloadTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let reloadCounter = LockedCounter()
        let store = WidgetStatusSnapshotStore(defaults: defaults)
        let bridge = WidgetStatusBridge(
            snapshotStore: store,
            nowProvider: { now },
            reloadHandler: { reloadCounter.increment() }
        )
        let first = makeWidgetSystemSnapshot(chargeFraction: 0.42)

        bridge.publish(snapshot: first, usesColor: true)
        #expect(reloadCounter.value == 1)
        #expect(store.read()?.updatedAt == now)

        now = now.addingTimeInterval(1)
        bridge.publish(snapshot: first, usesColor: true)
        #expect(reloadCounter.value == 1)
        #expect(store.read()?.updatedAt == Date(timeIntervalSince1970: 1_700_000_000))

        now = now.addingTimeInterval(WidgetStatusConstants.writeHeartbeatInterval)
        bridge.publish(snapshot: first, usesColor: true)
        #expect(reloadCounter.value == 1)
        #expect(store.read()?.updatedAt == now)

        var changed = first
        changed.battery.chargeFraction = 0.41
        now = now.addingTimeInterval(1)
        bridge.publish(snapshot: changed, usesColor: true)
        #expect(reloadCounter.value == 2)
        #expect(store.read()?.battery.chargeFraction == 0.41)
    }

    @Test
    @MainActor
    func widgetBridgeDoesNotReloadWhenSnapshotWriteFails() {
        let missingContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reloadCounter = LockedCounter()
        let bridge = WidgetStatusBridge(
            snapshotStore: WidgetStatusSnapshotStore(containerURL: missingContainer),
            reloadHandler: { reloadCounter.increment() }
        )

        bridge.publish(
            snapshot: makeWidgetSystemSnapshot(),
            usesColor: true
        )

        #expect(reloadCounter.value == 0)
    }
}

private func makeWidgetSystemSnapshot(
    chargeFraction: Double = 0.42
) -> SystemStatusSnapshot {
    SystemStatusSnapshot(
        lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
        battery: testBattery(
            chargeFraction: chargeFraction,
            isCharging: false,
            isLowPowerModeEnabled: true
        ),
        network: NetworkStatus(
            availability: .available,
            kind: .ethernet,
            name: nil,
            rssi: nil,
            signalLevel: nil,
            hotspotConfirmed: false
        ),
        health: HealthStatus(
            availability: .available,
            cpuUsagePercent: 20,
            oneMinuteLoad: 1,
            fiveMinuteLoad: 1,
            fifteenMinuteLoad: 1,
            logicalCPUCount: 4,
            thermalState: .nominal,
            cpuScore: 0.8,
            loadScore: 0.75,
            thermalScore: 1,
            selectedMetric: .cpu,
            selectedScore: 0.8,
            dotCount: 3
        ),
        powerPolicy: .unavailable(reason: "Not used by widget")
    )
}

private func testBattery(
    chargeFraction: Double,
    isCharging: Bool?,
    isLowPowerModeEnabled: Bool?
) -> BatteryStatus {
    BatteryStatus(
        availability: .available,
        hasBuiltInBattery: true,
        chargeFraction: chargeFraction,
        isCharging: isCharging,
        powerSource: isCharging == true ? .powerAdapter : .battery,
        isLowPowerModeEnabled: isLowPowerModeEnabled
    )
}

@MainActor
private func makeStatusStore(
    network: NetworkStatus,
    defaults: UserDefaults
) -> SystemStatusStore {
    SystemStatusStore(
        preferences: PreferencesStore(defaults: defaults),
        providers: ProviderContainer(
            battery: FixedBatteryProvider(
                value: .unavailable(reason: "Battery unavailable")
            ),
            network: FixedNetworkProvider(value: network),
            health: FixedHealthProvider(
                value: .unavailable(selectedMetric: .cpu)
            )
        )
    )
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

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        _ = incrementAndRead()
    }

    @discardableResult
    func incrementAndRead() -> Int {
        lock.lock()
        count += 1
        let value = count
        lock.unlock()
        return value
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

private struct GatedNetworkProvider: NetworkProviding {
    let gate: AsyncGate
    let value: NetworkStatus

    func read() async -> NetworkStatus {
        await gate.wait()
        return value
    }
}

private struct GatedPowerPolicyProvider: PowerPolicyProviding {
    let gate: AsyncGate
    let value: PowerPolicyStatus

    func read() async -> PowerPolicyStatus {
        await gate.wait()
        return value
    }
}

private final class ProviderEventState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var handler: (@Sendable () -> Void)?

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func recordRead() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func resetReadCount() {
        lock.lock()
        count = 0
        lock.unlock()
    }

    func setHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func clearHandler() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func sendEvent() {
        lock.lock()
        let handler = handler
        lock.unlock()
        handler?()
    }
}

private final class EventedBatteryProvider: BatteryProviding, @unchecked Sendable {
    private let state = ProviderEventState()
    private let currentValue: LockedValue<BatteryStatus>

    init(value: BatteryStatus) {
        currentValue = LockedValue(value)
    }

    var readCount: Int { state.readCount }

    func read() async -> BatteryStatus {
        state.recordRead()
        return currentValue.get()
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        state.setHandler(handler)
    }

    func stopObserving() {
        state.clearHandler()
    }

    func setValue(_ value: BatteryStatus) {
        currentValue.set(value)
    }

    func resetReadCount() {
        state.resetReadCount()
    }

    func sendEvent() {
        state.sendEvent()
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Value) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}

private final class EventedNetworkProvider: NetworkProviding, @unchecked Sendable {
    private let state = ProviderEventState()
    private let value: NetworkStatus

    init(value: NetworkStatus) {
        self.value = value
    }

    var readCount: Int { state.readCount }

    func read() async -> NetworkStatus {
        state.recordRead()
        return value
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        state.setHandler(handler)
    }

    func stopObserving() {
        state.clearHandler()
    }

    func resetReadCount() {
        state.resetReadCount()
    }

    func sendEvent() {
        state.sendEvent()
    }
}

private final class EventedHealthProvider: HealthProviding, @unchecked Sendable {
    private let state = ProviderEventState()
    private let value: HealthStatus

    init(value: HealthStatus) {
        self.value = value
    }

    var readCount: Int { state.readCount }

    func read() async -> HealthStatus {
        state.recordRead()
        return value
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        state.setHandler(handler)
    }

    func stopObserving() {
        state.clearHandler()
    }

    func resetReadCount() {
        state.resetReadCount()
    }

    func sendEvent() {
        state.sendEvent()
    }
}

private final class EventedPowerPolicyProvider: PowerPolicyProviding, @unchecked Sendable {
    private let state = ProviderEventState()
    private let value: PowerPolicyStatus

    init(value: PowerPolicyStatus) {
        self.value = value
    }

    var readCount: Int { state.readCount }

    func read() async -> PowerPolicyStatus {
        state.recordRead()
        return value
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        state.setHandler(handler)
    }

    func stopObserving() {
        state.clearHandler()
    }

    func resetReadCount() {
        state.resetReadCount()
    }

    func sendEvent() {
        state.sendEvent()
    }
}

@MainActor
private func waitUntil(
    iterations: Int = 100,
    condition: () -> Bool
) async {
    for _ in 0 ..< iterations {
        if condition() {
            return
        }

        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}

private final class SequencedPowerPolicyProvider: PowerPolicyProviding, @unchecked Sendable {
    private let initialStatus: PowerPolicyStatus
    private let updatedStatus: PowerPolicyStatus
    private let firstReadStarted = AsyncGate()
    private let releaseFirstReadGate = AsyncGate()
    private let readCounter = LockedCounter()

    var readCount: Int {
        readCounter.value
    }

    init(
        initialStatus: PowerPolicyStatus,
        updatedStatus: PowerPolicyStatus
    ) {
        self.initialStatus = initialStatus
        self.updatedStatus = updatedStatus
    }

    func read() async -> PowerPolicyStatus {
        let readNumber = readCounter.incrementAndRead()

        if readNumber == 1 {
            await firstReadStarted.open()
            await releaseFirstReadGate.wait()
            return initialStatus
        }

        return updatedStatus
    }

    func waitForFirstRead() async {
        await firstReadStarted.wait()
    }

    func releaseFirstRead() async {
        await releaseFirstReadGate.open()
    }
}

private final class InterleavedPowerControl: PowerControlProviding, @unchecked Sendable {
    private let initialState: PowerModeState
    private let updatedState: PowerModeState
    private let firstReadStarted = AsyncGate()
    private let releaseFirstReadGate = AsyncGate()
    private let readCounter = LockedCounter()

    var readPowerStateCalls: Int {
        readCounter.value
    }

    init(initialState: PowerModeState, updatedState: PowerModeState) {
        self.initialState = initialState
        self.updatedState = updatedState
    }

    func capabilities() async -> PowerCapabilities {
        PowerCapabilities(
            energyModeScopes: [.battery],
            supportedPowerModes: [.automatic, .lowPower],
            requiresHelper: true,
            helperStatus: .authorized
        )
    }

    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async throws {}

    func readPowerState() async -> PowerModeState {
        let readNumber = readCounter.incrementAndRead()

        if readNumber == 1 {
            await firstReadStarted.open()
            await releaseFirstReadGate.wait()
            return initialState
        }

        return updatedState
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        scope == .battery ? updatedState.batteryMode : updatedState.adapterMode
    }

    func requestHelperApproval() async -> HelperStatus {
        .authorized
    }

    func unregisterHelper() async -> HelperStatus {
        .notInstalled
    }

    func waitForFirstRead() async {
        await firstReadStarted.wait()
    }

    func releaseFirstRead() async {
        await releaseFirstReadGate.open()
    }
}

@MainActor
private final class RecordingPowerControl: PowerControlProviding {
    let capabilitiesValue: PowerCapabilities
    let powerModeReadback: PowerMode?
    let activePowerModeReadback: PowerMode?
    private(set) var readPowerStateCalls = 0
    private(set) var setPowerModeCalls = 0
    private(set) var uncachedReadCalls = 0
    private(set) var operationEvents: [String] = []

    init(
        capabilities: PowerCapabilities,
        powerModeReadback: PowerMode? = nil,
        activePowerModeReadback: PowerMode? = nil
    ) {
        self.capabilitiesValue = capabilities
        self.powerModeReadback = powerModeReadback
        self.activePowerModeReadback = activePowerModeReadback
    }

    func capabilities() async -> PowerCapabilities {
        capabilitiesValue
    }

    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async throws {
        setPowerModeCalls += 1
        operationEvents.append("set")
    }

    func readPowerState() async -> PowerModeState {
        readPowerStateCalls += 1
        return PowerModeState(
            activeMode: activePowerModeReadback,
            batteryMode: powerModeReadback,
            adapterMode: powerModeReadback
        )
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        operationEvents.append("read")
        return powerModeReadback
    }

    func readPowerModeUncached(scope: PowerSourceScope) async -> PowerMode? {
        uncachedReadCalls += 1
        operationEvents.append("uncached-read")
        return powerModeReadback
    }

    func readActivePowerMode() async -> PowerMode? {
        activePowerModeReadback
    }

    func requestHelperApproval() async -> HelperStatus {
        .authorized
    }

    func unregisterHelper() async -> HelperStatus {
        .notInstalled
    }
}

@MainActor
private final class BlockingPowerControl: PowerControlProviding {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var setPowerModeCalls = 0

    func capabilities() async -> PowerCapabilities {
        PowerCapabilities(
            energyModeScopes: [.battery],
            supportedPowerModes: [.automatic, .lowPower],
            requiresHelper: true,
            helperStatus: .authorized
        )
    }

    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async throws {
        setPowerModeCalls += 1
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        .lowPower
    }

    func requestHelperApproval() async -> HelperStatus {
        .authorized
    }

    func unregisterHelper() async -> HelperStatus {
        .notInstalled
    }

    func releasePowerMode() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct FailingLaunchAtLoginManager: LaunchAtLoginManaging {
    @MainActor
    func setEnabled(_ enabled: Bool) async throws {
        throw RegistrationError.failed
    }

    private enum RegistrationError: Error {
        case failed
    }
}

@MainActor
private final class GatedLaunchAtLoginManager: LaunchAtLoginManaging {
    private let gate = AsyncGate()

    func setEnabled(_ enabled: Bool) async throws {
        await gate.wait()
    }

    func release() async {
        await gate.open()
    }
}
