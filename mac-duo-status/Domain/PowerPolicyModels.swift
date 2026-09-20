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
    let requiresHelper: Bool
    let helperStatus: HelperStatus

    static let unsupported = PowerCapabilities(
        energyModeScopes: [],
        supportedPowerModes: [],
        requiresHelper: true,
        helperStatus: .notInstalled
    )
}

struct PowerModeState: Equatable, Sendable {
    let activeMode: PowerMode?
    let batteryMode: PowerMode?
    let adapterMode: PowerMode?

    static let unavailable = PowerModeState(
        activeMode: nil,
        batteryMode: nil,
        adapterMode: nil
    )
}

struct PowerPolicyStatus: Equatable, Sendable {
    let availability: DataAvailability
    let activeMode: PowerMode?
    let batteryMode: PowerMode?
    let adapterMode: PowerMode?
    let helperStatus: HelperStatus
    let capabilities: PowerCapabilities

    static func unavailable(reason: String) -> PowerPolicyStatus {
        PowerPolicyStatus(
            availability: .unavailable(reason: reason),
            activeMode: nil,
            batteryMode: nil,
            adapterMode: nil,
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
    func readPowerState() async -> PowerModeState
    func readPowerModes() async -> (batteryMode: PowerMode?, adapterMode: PowerMode?)
    func readPowerMode(scope: PowerSourceScope) async -> PowerMode?
    func readPowerModeUncached(scope: PowerSourceScope) async -> PowerMode?
    func readActivePowerMode() async -> PowerMode?
    func requestHelperApproval() async -> HelperStatus
    func unregisterHelper() async -> HelperStatus
}

extension PowerControlProviding {
    func readPowerState() async -> PowerModeState {
        async let activeMode = readActivePowerMode()
        async let powerModes = readPowerModes()
        let (active, modes) = await (activeMode, powerModes)

        return PowerModeState(
            activeMode: active,
            batteryMode: modes.batteryMode,
            adapterMode: modes.adapterMode
        )
    }

    func readPowerModes() async -> (batteryMode: PowerMode?, adapterMode: PowerMode?) {
        (
            await readPowerMode(scope: .battery),
            await readPowerMode(scope: .powerAdapter)
        )
    }

    func readPowerModeUncached(scope: PowerSourceScope) async -> PowerMode? {
        await readPowerMode(scope: scope)
    }

    func readActivePowerMode() async -> PowerMode? {
        nil
    }
}
