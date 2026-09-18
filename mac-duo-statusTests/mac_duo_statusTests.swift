//
//  mac_duo_statusTests.swift
//  mac-duo-statusTests
//

import Foundation
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

    @Test func wifiCandidatesMergeBySSIDDataAndKeepStrongestBSSID() {
        let token = UUID()
        let known = WiFiNetworkCandidate(
            id: "known",
            interfaceName: "en0",
            ssidData: Data([1, 2, 3]),
            displayName: "Office",
            bssid: nil,
            supportedSecurity: [.wpa2Personal],
            rssi: nil,
            isHidden: false,
            isKnown: true,
            hotspotConfirmation: .unavailable,
            scanToken: token
        )
        let weak = WiFiNetworkCandidate(
            id: "weak",
            interfaceName: "en0",
            ssidData: Data([1, 2, 3]),
            displayName: "Office",
            bssid: "00:00:00:00:00:01",
            supportedSecurity: [.wpa2Personal],
            rssi: -70,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: token,
            isDiscovered: true
        )
        let strong = WiFiNetworkCandidate(
            id: "strong",
            interfaceName: "en0",
            ssidData: Data([1, 2, 3]),
            displayName: "Office",
            bssid: "00:00:00:00:00:02",
            supportedSecurity: [.wpa3Personal],
            rssi: -45,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: token,
            isDiscovered: true
        )

        let merged = WiFiNetworkCandidateMerger.merge(
            knownNetworks: [known],
            scannedNetworks: [weak, strong]
        )

        #expect(merged.count == 1)
        #expect(merged.first?.isKnown == true)
        #expect(merged.first?.bssid == strong.bssid)
        #expect(merged.first?.supportedSecurity == [.wpa2Personal, .wpa3Personal])
    }

    @Test func wifiGroupingExcludesKnownNetworksNotDiscoveredByTheCurrentScan() {
        let token = UUID()
        let savedOnly = WiFiNetworkCandidate(
            id: "saved-only",
            interfaceName: "en0",
            ssidData: Data([20]),
            displayName: "Saved Only",
            bssid: nil,
            supportedSecurity: [.wpa2Personal],
            rssi: nil,
            isHidden: false,
            isKnown: true,
            hotspotConfirmation: .unavailable,
            scanToken: token
        )
        let discoveredKnown = WiFiNetworkCandidate(
            id: "discovered-known",
            interfaceName: "en0",
            ssidData: Data([21]),
            displayName: "Discovered Known",
            bssid: "00:00:00:00:00:21",
            supportedSecurity: [.wpa2Personal],
            rssi: nil,
            isHidden: false,
            isKnown: true,
            hotspotConfirmation: .unavailable,
            scanToken: token,
            isDiscovered: true
        )
        let other = WiFiNetworkCandidate(
            id: "other",
            interfaceName: "en0",
            ssidData: Data([22]),
            displayName: "Other",
            bssid: "00:00:00:00:00:22",
            supportedSecurity: [.open],
            rssi: nil,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: token,
            isDiscovered: true
        )

        let candidates = [savedOnly, discoveredKnown, other]

        #expect(
            WiFiNetworkCandidateGrouping.knownNetworks(from: candidates).map(\.id) ==
                [discoveredKnown.id]
        )
        #expect(
            WiFiNetworkCandidateGrouping.otherNetworks(from: candidates).map(\.id) ==
                [other.id]
        )
    }

    @Test func wifiMergingKnownAndScannedNetworksMarksTheResultAsDiscovered() {
        let token = UUID()
        let known = WiFiNetworkCandidate(
            id: "known",
            interfaceName: "en0",
            ssidData: Data([23]),
            displayName: "Office",
            bssid: nil,
            supportedSecurity: [.wpa2Personal],
            rssi: nil,
            isHidden: false,
            isKnown: true,
            hotspotConfirmation: .unavailable,
            scanToken: token
        )
        let scanned = WiFiNetworkCandidate(
            id: "scanned",
            interfaceName: "en0",
            ssidData: Data([23]),
            displayName: "Office",
            bssid: "00:00:00:00:00:23",
            supportedSecurity: [.wpa2Personal],
            rssi: nil,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: token,
            isDiscovered: true
        )

        let merged = WiFiNetworkCandidateMerger.merge(
            knownNetworks: [known],
            scannedNetworks: [scanned]
        )

        #expect(merged.count == 1)
        #expect(merged.first?.isKnown == true)
        #expect(merged.first?.isDiscovered == true)
    }

    @Test func wifiMergingMultipleAccessPointsKeepsUnconfiguredNetworkAsOther() {
        let token = UUID()
        let firstAccessPoint = WiFiNetworkCandidate(
            id: "first-access-point",
            interfaceName: "en0",
            ssidData: Data([24]),
            displayName: "Guest",
            bssid: "00:00:00:00:00:24",
            supportedSecurity: [.open],
            rssi: -65,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: token,
            isDiscovered: true
        )
        let secondAccessPoint = WiFiNetworkCandidate(
            id: "second-access-point",
            interfaceName: "en0",
            ssidData: Data([24]),
            displayName: "Guest",
            bssid: "00:00:00:00:00:25",
            supportedSecurity: [.open],
            rssi: -55,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: token,
            isDiscovered: true
        )

        let merged = WiFiNetworkCandidateMerger.merge(
            knownNetworks: [],
            scannedNetworks: [firstAccessPoint, secondAccessPoint]
        )

        #expect(merged.count == 1)
        #expect(merged.first?.isKnown == false)
        #expect(
            WiFiNetworkCandidateGrouping.otherNetworks(from: merged).map(\.id) ==
                [merged.first?.id].compactMap { $0 }
        )
    }

    @Test func wifiPrimarySecurityPrefersTheStrongestSupportedFamily() {
        let candidate = WiFiNetworkCandidate(
            id: "wifi",
            interfaceName: "en0",
            ssidData: Data([4, 5, 6]),
            displayName: "Office",
            bssid: nil,
            supportedSecurity: [.wpa2Personal, .wpa3Personal],
            rssi: nil,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: UUID()
        )

        #expect(candidate.primarySecurity == .wpa3Personal)
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

    @Test func controlStateOnlyMarksPendingOperationsAsBusy() {
        #expect(ControlOperationState.idle.isPending == false)
        #expect(ControlOperationState.pending.isPending)
        #expect(ControlOperationState.failed(.networkNotFound).isPending == false)
    }

    @Test
    func coordinatorKeepsConnectionSuccessSeparateFromRememberFailure() async {
        let suiteName = "DuoStatusTests-(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ssidData = Data([7, 8, 9])
        let networkStatus = NetworkStatus(
            availability: .available,
            kind: .wifi,
            name: "Office",
            rssi: -50,
            signalLevel: 4,
            hotspotConfirmed: false,
            ssidData: ssidData,
            bssid: "00:00:00:00:00:07",
            isWiFiEnabled: true
        )
        let store = makeStatusStore(network: networkStatus, defaults: defaults)
        let networkControl = RecordingNetworkControl(
            result: WiFiConnectionResult(wasRemembered: false)
        )
        let controls = ControlCoordinator(
            statusStore: store,
            networkControl: networkControl,
            powerControl: PlaceholderPowerControlProvider(),
            wifiAuthorization: RecordingWiFiAuthorization(),
            networkConfirmationAttempts: 1,
            networkConfirmationDelayNanoseconds: 0
        )
        let target = WiFiNetworkCandidate(
            id: "office",
            interfaceName: "en0",
            ssidData: ssidData,
            displayName: "Office",
            bssid: "00:00:00:00:00:07",
            supportedSecurity: [.wpa2Personal],
            rssi: -50,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: UUID()
        )

        await controls.connect(
            to: target,
            credential: .passphrase("temporary-password"),
            remember: true
        )

        #expect(controls.networkOperationState == .succeeded)
        #expect(controls.lastNetworkRememberRequest)
        #expect(controls.lastNetworkResult?.wasRemembered == false)
        #expect(networkControl.connectCalls == 1)
    }

    @Test
    func coordinatorSurfacesCredentialsRequiredForNativeFallback() async {
        let suiteName = "DuoStatusTests-(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let networkControl = RecordingNetworkControl(
            result: WiFiConnectionResult(wasRemembered: false),
            connectError: .credentialsRequired
        )
        let controls = ControlCoordinator(
            statusStore: makeStatusStore(
                network: .unavailable(reason: "No network"),
                defaults: defaults
            ),
            networkControl: networkControl,
            powerControl: PlaceholderPowerControlProvider(),
            wifiAuthorization: RecordingWiFiAuthorization()
        )
        let target = WiFiNetworkCandidate(
            id: "known-office",
            interfaceName: "en0",
            ssidData: Data([12, 13]),
            displayName: "Known Office",
            bssid: nil,
            supportedSecurity: [.wpa2Personal],
            rssi: nil,
            isHidden: false,
            isKnown: true,
            hotspotConfirmation: .unavailable,
            scanToken: UUID(),
            isDiscovered: true
        )

        let error = await controls.connect(
            to: target,
            credential: nil,
            remember: false
        )

        #expect(error == .credentialsRequired)
        #expect(controls.networkOperationState == .failed(.credentialsRequired))
        #expect(networkControl.connectCalls == 1)
    }

    @Test
    func coordinatorBlocksKnownNetworkUntilAppAuthorizationSucceeds() async {
        let suiteName = "DuoStatusTests-(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let networkControl = RecordingNetworkControl(
            result: WiFiConnectionResult(wasRemembered: true)
        )
        let authorization = RecordingWiFiAuthorization(shouldAuthorize: false)
        let controls = ControlCoordinator(
            statusStore: makeStatusStore(
                network: .unavailable(reason: "No network"),
                defaults: defaults
            ),
            networkControl: networkControl,
            powerControl: PlaceholderPowerControlProvider(),
            wifiAuthorization: authorization
        )
        let target = WiFiNetworkCandidate(
            id: "known-office",
            interfaceName: "en0",
            ssidData: Data([14, 15]),
            displayName: "Known Office",
            bssid: nil,
            supportedSecurity: [.wpa2Personal],
            rssi: nil,
            isHidden: false,
            isKnown: true,
            hotspotConfirmation: .unavailable,
            scanToken: UUID(),
            isDiscovered: true
        )

        let error = await controls.connect(
            to: target,
            credential: nil,
            remember: false
        )

        #expect(error == .authorizationRequired)
        #expect(controls.networkOperationState == .failed(.authorizationRequired))
        #expect(authorization.ensureAuthorizedCalls == 1)
        #expect(networkControl.connectCalls == 0)
    }

    @Test
    func persistentWiFiAuthorizationReusesTheMarkerWithoutReauthenticating() async {
        let store = InMemoryWiFiAuthorizationStore()
        let authenticator = RecordingWiFiSystemAuthenticator(result: true)
        let authorization = LocalAuthenticationWiFiAuthorizer(
            store: store,
            authenticator: authenticator
        )

        #expect(!authorization.isAuthorized)
        #expect(await authorization.ensureAuthorized())
        #expect(authorization.isAuthorized)
        #expect(await authorization.ensureAuthorized())
        #expect(authenticator.authenticateCalls == 1)

        let reloadedAuthorization = LocalAuthenticationWiFiAuthorizer(
            store: store,
            authenticator: authenticator
        )
        #expect(reloadedAuthorization.isAuthorized)
        #expect(await reloadedAuthorization.ensureAuthorized())
        #expect(authenticator.authenticateCalls == 1)

        #expect(reloadedAuthorization.revoke())
        #expect(!reloadedAuthorization.isAuthorized)
        #expect(!store.containsMarker())
    }

    @Test
    func coordinatorDoesNotReportSuccessWhenNetworkReadbackTimesOut() async {
        let suiteName = "DuoStatusTests-(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = makeStatusStore(
            network: .unavailable(reason: "No network"),
            defaults: defaults
        )
        let networkControl = RecordingNetworkControl(
            result: WiFiConnectionResult(wasRemembered: true)
        )
        let controls = ControlCoordinator(
            statusStore: store,
            networkControl: networkControl,
            powerControl: PlaceholderPowerControlProvider(),
            wifiAuthorization: RecordingWiFiAuthorization(),
            networkConfirmationAttempts: 1,
            networkConfirmationDelayNanoseconds: 0
        )
        let target = WiFiNetworkCandidate(
            id: "missing",
            interfaceName: "en0",
            ssidData: Data([10, 11]),
            displayName: "Missing",
            bssid: nil,
            supportedSecurity: [.open],
            rssi: -60,
            isHidden: false,
            isKnown: false,
            hotspotConfirmation: .unavailable,
            scanToken: UUID()
        )

        await controls.connect(to: target, credential: WiFiCredential.none, remember: false)

        #expect(controls.networkOperationState == .failed(.operationTimeout))
        #expect(controls.lastNetworkResult == nil)
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
            networkControl: PlaceholderNetworkControlProvider(),
            powerControl: powerControl,
            wifiAuthorization: RecordingWiFiAuthorization()
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
            networkControl: PlaceholderNetworkControlProvider(),
            powerControl: powerControl,
            wifiAuthorization: RecordingWiFiAuthorization()
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
        lock.lock()
        count += 1
        lock.unlock()
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

@MainActor
private final class RecordingNetworkControl: NetworkControlProviding {
    let result: WiFiConnectionResult
    let connectError: ControlError?
    private(set) var connectCalls = 0

    init(
        result: WiFiConnectionResult,
        connectError: ControlError? = nil
    ) {
        self.result = result
        self.connectError = connectError
    }

    func scan(
        includeHidden: Bool,
        ssidData: Data?
    ) async throws -> [WiFiNetworkCandidate] {
        []
    }

    func setWiFiEnabled(_ enabled: Bool) async throws {}

    func connect(
        to target: WiFiNetworkCandidate,
        credential: WiFiCredential?,
        remember: Bool
    ) async throws -> WiFiConnectionResult {
        connectCalls += 1
        if let connectError {
            throw connectError
        }
        return result
    }
}

@MainActor
private final class RecordingWiFiAuthorization: WiFiAuthorizationProviding {
    private let shouldAuthorize: Bool
    private(set) var ensureAuthorizedCalls = 0
    private(set) var isAuthorized = false

    init(shouldAuthorize: Bool = true) {
        self.shouldAuthorize = shouldAuthorize
    }

    func ensureAuthorized() async -> Bool {
        ensureAuthorizedCalls += 1
        isAuthorized = shouldAuthorize
        return shouldAuthorize
    }

    @discardableResult
    func revoke() -> Bool {
        isAuthorized = false
        return true
    }
}

@MainActor
private final class InMemoryWiFiAuthorizationStore: WiFiAuthorizationStore {
    private(set) var markerExists = false

    func containsMarker() -> Bool {
        markerExists
    }

    func saveMarker() -> Bool {
        markerExists = true
        return true
    }

    func removeMarker() -> Bool {
        markerExists = false
        return true
    }
}

@MainActor
private final class RecordingWiFiSystemAuthenticator: WiFiSystemAuthenticator {
    let result: Bool
    private(set) var authenticateCalls = 0

    init(result: Bool) {
        self.result = result
    }

    func authenticate() async -> Bool {
        authenticateCalls += 1
        return result
    }
}

@MainActor
private final class RecordingPowerControl: PowerControlProviding {
    let capabilitiesValue: PowerCapabilities
    let powerModeReadback: PowerMode?
    let activePowerModeReadback: PowerMode?
    private(set) var setPowerModeCalls = 0

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
    }

    func readPowerMode(scope: PowerSourceScope) async -> PowerMode? {
        powerModeReadback
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
    func setEnabled(_ enabled: Bool) throws {
        throw RegistrationError.failed
    }

    private enum RegistrationError: Error {
        case failed
    }
}
