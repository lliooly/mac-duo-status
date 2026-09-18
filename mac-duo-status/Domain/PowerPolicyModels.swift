//
//  PowerPolicyModels.swift
//  mac-duo-status
//

import Foundation

enum PowerMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case automatic
    case lowPower
    case highPower

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .automatic:
            return "power.mode.automatic"
        case .lowPower:
            return "power.mode.low-power"
        case .highPower:
            return "power.mode.high-power"
        }
    }
}

enum ChargeLimitValidator {
    nonisolated static func isInSystemRange(_ percent: Int) -> Bool {
        (80...100).contains(percent)
    }

    nonisolated static func isAllowed(_ percent: Int, values: Set<Int>) -> Bool {
        isInSystemRange(percent) && values.contains(percent)
    }
}

enum PowerSourceScope: String, CaseIterable, Hashable, Identifiable, Sendable {
    case battery
    case powerAdapter

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .battery:
            return "power.scope.battery"
        case .powerAdapter:
            return "power.scope.adapter"
        }
    }
}

enum HelperStatus: Equatable, Sendable {
    case notInstalled
    case requiresApproval
    case authorized
    case unavailable(reason: String)
    case failed(reason: String)

    var isAuthorized: Bool {
        if case .authorized = self {
            return true
        }

        return false
    }
}

struct PowerCapabilities: Equatable, Sendable {
    let energyModeScopes: Set<PowerSourceScope>
    let supportedPowerModes: Set<PowerMode>
    let chargeLimitValues: Set<Int>
    let requiresHelper: Bool
    let helperStatus: HelperStatus

    var chargeLimitState: CapabilityState {
        if !chargeLimitValues.isEmpty && helperStatus.isAuthorized {
            return .available
        }

        if requiresHelper && helperStatus == .requiresApproval {
            return .authorizationRequired
        }

        if !chargeLimitValues.isEmpty {
            return .readOnly
        }

        return .unsupported
    }

    static let unsupported = PowerCapabilities(
        energyModeScopes: [],
        supportedPowerModes: [],
        chargeLimitValues: [],
        requiresHelper: true,
        helperStatus: .notInstalled
    )
}

struct PowerPolicyStatus: Equatable, Sendable {
    let availability: DataAvailability
    let activeMode: PowerMode?
    let batteryMode: PowerMode?
    let adapterMode: PowerMode?
    let chargeLimit: Int?
    let chargeLimitCapability: CapabilityState
    let helperStatus: HelperStatus
    let capabilities: PowerCapabilities

    static func unavailable(reason: String) -> PowerPolicyStatus {
        PowerPolicyStatus(
            availability: .unavailable(reason: reason),
            activeMode: nil,
            batteryMode: nil,
            adapterMode: nil,
            chargeLimit: nil,
            chargeLimitCapability: .unsupported,
            helperStatus: .unavailable(reason: reason),
            capabilities: .unsupported
        )
    }
}

protocol PowerPolicyProviding: Sendable {
    func read() async -> PowerPolicyStatus
    func startObserving(_ handler: @escaping @Sendable () -> Void)
    func stopObserving()
}

extension PowerPolicyProviding {
    func startObserving(_ handler: @escaping @Sendable () -> Void) {}
    func stopObserving() {}
}

protocol PowerControlProviding: Sendable {
    func capabilities() async -> PowerCapabilities
    func setPowerMode(_ mode: PowerMode, scope: PowerSourceScope) async throws
    func readPowerMode(scope: PowerSourceScope) async -> PowerMode?
    func readActivePowerMode() async -> PowerMode?
    func setChargeLimit(_ percent: Int) async throws
    func readChargeLimit() async -> Int?
    func requestHelperApproval() async -> HelperStatus
    func unregisterHelper() async -> HelperStatus
}

extension PowerControlProviding {
    func readActivePowerMode() async -> PowerMode? {
        nil
    }
}
