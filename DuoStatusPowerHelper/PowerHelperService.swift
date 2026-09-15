//
//  PowerHelperService.swift
//  DuoStatusPowerHelper
//

import Foundation

struct PowerBackendCapabilities {
    let energyModeScopes: [String]
    let supportedPowerModes: [String]
    let chargeLimitMinimum: NSNumber?
    let chargeLimitMaximum: NSNumber?
}

protocol PowerBackend {
    var capabilities: PowerBackendCapabilities { get }
    func readPowerState() -> (
        batteryMode: String?,
        adapterMode: String?,
        activeMode: String?,
        chargeLimit: NSNumber?
    )
    func setPowerMode(scope: String, mode: String) throws
    func setChargeLimit(_ percent: Int) throws
}

struct UnavailablePowerBackend: PowerBackend {
    let capabilities = PowerBackendCapabilities(
        energyModeScopes: [],
        supportedPowerModes: [],
        chargeLimitMinimum: nil,
        chargeLimitMaximum: nil
    )

    func readPowerState() -> (
        batteryMode: String?,
        adapterMode: String?,
        activeMode: String?,
        chargeLimit: NSNumber?
    ) {
        (nil, nil, nil, nil)
    }

    func setPowerMode(scope: String, mode: String) throws {
        throw PowerBackendError.unsupported
    }

    func setChargeLimit(_ percent: Int) throws {
        throw PowerBackendError.unsupported
    }
}

enum PowerBackendError: Error {
    case unsupported
    case invalidParameter
}

final class PowerHelperService: NSObject, DuoStatusPowerHelperProtocol {
    private let backend: any PowerBackend

    init(backend: any PowerBackend = UnavailablePowerBackend()) {
        self.backend = backend
    }

    func getCapabilities(
        withReply reply: @escaping (NSArray, NSArray, NSNumber?, NSNumber?) -> Void
    ) {
        let capabilities = backend.capabilities
        reply(
            capabilities.energyModeScopes as NSArray,
            capabilities.supportedPowerModes as NSArray,
            capabilities.chargeLimitMinimum,
            capabilities.chargeLimitMaximum
        )
    }

    func readPowerState(
        withReply reply: @escaping (NSString?, NSString?, NSString?, NSNumber?) -> Void
    ) {
        let state = backend.readPowerState()
        reply(
            state.batteryMode as NSString?,
            state.adapterMode as NSString?,
            state.activeMode as NSString?,
            state.chargeLimit
        )
    }

    func setPowerMode(
        _ scope: NSString,
        mode: NSString,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        do {
            try backend.setPowerMode(scope: String(scope), mode: String(mode))
            reply(nil)
        } catch {
            reply(Self.error(for: error))
        }
    }

    func readChargeLimit(withReply reply: @escaping (NSNumber?) -> Void) {
        reply(backend.readPowerState().chargeLimit)
    }

    func setChargeLimit(
        _ percent: NSNumber,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        guard (80...100).contains(percent.intValue) else {
            reply(Self.error(for: PowerBackendError.invalidParameter))
            return
        }

        do {
            try backend.setChargeLimit(percent.intValue)
            reply(nil)
        } catch {
            reply(Self.error(for: error))
        }
    }

    private static func error(for error: Error) -> NSError {
        let code: Int
        switch error {
        case PowerBackendError.invalidParameter:
            code = 1
        case PowerBackendError.unsupported:
            code = 2
        default:
            code = 3
        }

        return NSError(
            domain: "com.shishishi3.duo-status.power-helper",
            code: code,
            userInfo: nil
        )
    }
}
