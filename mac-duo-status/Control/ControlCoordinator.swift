//
//  ControlCoordinator.swift
//  mac-duo-status
//

import Combine
import Foundation

@MainActor
final class ControlCoordinator: ObservableObject {
    @Published private(set) var powerOperationState: ControlOperationState = .idle

    private let statusStore: SystemStatusStore
    private let powerControl: any PowerControlProviding

    init(
        statusStore: SystemStatusStore,
        powerControl: any PowerControlProviding
    ) {
        self.statusStore = statusStore
        self.powerControl = powerControl
    }

    var helperStatus: HelperStatus {
        statusStore.snapshot.powerPolicy.helperStatus
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

            // Read back only after the write has completed and bypass the
            // status cache; the store refresh below separately confirms the
            // published snapshot.
            let readback = await powerControl.readPowerModeUncached(scope: scope)
            guard readback == mode else {
                throw ControlError.writeUnconfirmed
            }

            await statusStore.refreshPowerPolicyNowAndWait()
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
        await statusStore.refreshPowerPolicyNowAndWait()

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
        await statusStore.refreshPowerPolicyNowAndWait()
        powerOperationState = status == .notInstalled
            ? .succeeded
            : .failed(.helperUnavailable)
    }

    func resetOperationStates() {
        powerOperationState = .idle
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
