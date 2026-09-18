//
//  ControlCoordinator.swift
//  mac-duo-status
//

import Combine
import Foundation

@MainActor
final class ControlCoordinator: ObservableObject {
    @Published private(set) var networkOperationState: ControlOperationState = .idle
    @Published private(set) var powerOperationState: ControlOperationState = .idle
    @Published private(set) var networkCandidates: [WiFiNetworkCandidate] = []
    @Published private(set) var lastNetworkResult: WiFiConnectionResult?
    @Published private(set) var lastNetworkRememberRequest = false

    private let statusStore: SystemStatusStore
    private let networkControl: any NetworkControlProviding
    private let powerControl: any PowerControlProviding
    private let wifiAuthorization: any WiFiAuthorizationProviding
    private let networkConfirmationAttempts: Int
    private let networkConfirmationDelayNanoseconds: UInt64

    init(
        statusStore: SystemStatusStore,
        networkControl: any NetworkControlProviding,
        powerControl: any PowerControlProviding,
        wifiAuthorization: any WiFiAuthorizationProviding,
        networkConfirmationAttempts: Int = 12,
        networkConfirmationDelayNanoseconds: UInt64 = 250_000_000
    ) {
        self.statusStore = statusStore
        self.networkControl = networkControl
        self.powerControl = powerControl
        self.wifiAuthorization = wifiAuthorization
        self.networkConfirmationAttempts = max(networkConfirmationAttempts, 1)
        self.networkConfirmationDelayNanoseconds = networkConfirmationDelayNanoseconds
    }

    var helperStatus: HelperStatus {
        statusStore.snapshot.powerPolicy.helperStatus
    }

    func scanNetworks(includeHidden: Bool, ssidData: Data? = nil) async {
        guard !networkOperationState.isPending else {
            return
        }

        networkOperationState = .pending
        lastNetworkResult = nil
        lastNetworkRememberRequest = false

        do {
            networkCandidates = try await networkControl.scan(
                includeHidden: includeHidden,
                ssidData: ssidData
            )
            networkOperationState = .succeeded
        } catch let error as ControlError {
            networkOperationState = .failed(error)
        } catch {
            networkOperationState = .failed(.failed)
        }
    }

    func setWiFiEnabled(_ enabled: Bool) async {
        guard !networkOperationState.isPending else {
            return
        }

        networkOperationState = .pending
        do {
            try await networkControl.setWiFiEnabled(enabled)
            guard await waitForNetworkState({ status in
                status.isWiFiEnabled == enabled
            }) else {
                throw ControlError.operationTimeout
            }
            networkOperationState = .succeeded
        } catch let error as ControlError {
            networkOperationState = .failed(error)
        } catch {
            networkOperationState = .failed(.failed)
        }
    }

    @discardableResult
    func connect(
        to target: WiFiNetworkCandidate,
        credential: WiFiCredential?,
        remember: Bool
    ) async -> ControlError? {
        guard !networkOperationState.isPending else {
            return .temporarilyUnavailable
        }

        networkOperationState = .pending
        lastNetworkResult = nil
        lastNetworkRememberRequest = remember

        if target.isKnown,
           await !wifiAuthorization.ensureAuthorized() {
            networkOperationState = .failed(.authorizationRequired)
            return .authorizationRequired
        }

        do {
            let result = try await networkControl.connect(
                to: target,
                credential: credential,
                remember: remember
            )
            guard await waitForNetworkState({ status in
                Self.matches(status: status, target: target)
            }) else {
                throw ControlError.operationTimeout
            }

            lastNetworkResult = result
            networkOperationState = .succeeded
            return nil
        } catch let error as ControlError {
            networkOperationState = .failed(error)
            return error
        } catch {
            networkOperationState = .failed(.failed)
            return .failed
        }
    }

    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async {
        guard !powerOperationState.isPending else {
            return
        }

        powerOperationState = .pending

        do {
            let capabilities = await powerControl.capabilities()
            guard capabilities.energyModeScopes.contains(scope),
                  capabilities.supportedPowerModes.contains(mode)
            else {
                throw capabilities.helperStatus == .requiresApproval
                    ? ControlError.authorizationRequired
                    : ControlError.helperUnavailable
            }

            try await powerControl.setPowerMode(mode, scope: scope)
            guard await powerControl.readPowerMode(scope: scope) == mode else {
                throw ControlError.writeUnconfirmed
            }

            await statusStore.refreshNowAndWait()
            guard Self.matches(
                status: statusStore.snapshot.powerPolicy,
                mode: mode,
                scope: scope
            ) else {
                throw ControlError.writeUnconfirmed
            }
            powerOperationState = .succeeded
        } catch let error as ControlError {
            powerOperationState = .failed(error)
        } catch {
            powerOperationState = .failed(.failed)
        }
    }

    func requestHelperApproval() async {
        guard !powerOperationState.isPending else {
            return
        }

        powerOperationState = .pending
        let status = await powerControl.requestHelperApproval()
        await statusStore.refreshNowAndWait()

        if status == .authorized || statusStore.snapshot.powerPolicy.helperStatus == .authorized {
            powerOperationState = .succeeded
        } else if status == .requiresApproval {
            powerOperationState = .failed(.authorizationRequired)
        } else {
            powerOperationState = .failed(.helperUnavailable)
        }
    }

    func unregisterHelper() async {
        guard !powerOperationState.isPending else {
            return
        }

        powerOperationState = .pending
        let status = await powerControl.unregisterHelper()
        await statusStore.refreshNowAndWait()
        powerOperationState = status == .notInstalled
            ? .succeeded
            : .failed(.helperUnavailable)
    }

    func resetOperationStates() {
        networkOperationState = .idle
        powerOperationState = .idle
        lastNetworkResult = nil
        lastNetworkRememberRequest = false
    }

    private func waitForNetworkState(
        _ predicate: @escaping @Sendable (NetworkStatus) -> Bool
    ) async -> Bool {
        for attempt in 0..<networkConfirmationAttempts {
            await statusStore.refreshNowAndWait()
            if predicate(statusStore.snapshot.network) {
                return true
            }

            guard attempt + 1 < networkConfirmationAttempts else {
                return false
            }

            do {
                try await Task.sleep(nanoseconds: networkConfirmationDelayNanoseconds)
            } catch {
                return false
            }
        }

        return false
    }

    nonisolated private static func matches(
        status: NetworkStatus,
        target: WiFiNetworkCandidate
    ) -> Bool {
        guard status.availability.isAvailable,
              status.kind == .wifi || status.kind == .hotspot
        else {
            return false
        }

        if let ssidData = status.ssidData {
            return ssidData == target.ssidData
        }

        return status.name != nil && status.name == target.displayName
    }

    nonisolated private static func matches(
        status: PowerPolicyStatus,
        mode: PowerMode,
        scope: PowerSourceScope
    ) -> Bool {
        switch scope {
        case .battery:
            return status.batteryMode == mode
        case .powerAdapter:
            return status.adapterMode == mode
        }
    }
}
