//
//  PowerHelperService.swift
//  DuoStatusPowerHelper
//

import Foundation

struct PowerBackendCapabilities {
    let energyModeScopes: [String]
    let supportedPowerModes: [String]
}

protocol PowerBackend {
    var capabilities: PowerBackendCapabilities { get }
    func readPowerState() -> (
        batteryMode: String?,
        adapterMode: String?,
        activeMode: String?
    )
    func setPowerMode(scope: String, mode: String) throws
}

struct UnavailablePowerBackend: PowerBackend {
    let capabilities = PowerBackendCapabilities(
        energyModeScopes: [],
        supportedPowerModes: []
    )

    func readPowerState() -> (
        batteryMode: String?,
        adapterMode: String?,
        activeMode: String?
    ) {
        (nil, nil, nil)
    }

    func setPowerMode(scope: String, mode: String) throws {
        throw PowerBackendError.unsupported
    }
}

enum PowerBackendError: Error {
    case unsupported
    case invalidParameter
    case executionFailed
    case timeout
}

final class PowerHelperService: NSObject, DuoStatusPowerHelperProtocol {
    private static let helperRevision = 5
    private let backend: any PowerBackend

    init(backend: any PowerBackend = PMSetPowerBackend()) {
        self.backend = backend
    }

    func getHelperInfo(withReply reply: @escaping (NSNumber) -> Void) {
        reply(Self.helperRevision as NSNumber)
    }

    func getCapabilities(
        withReply reply: @escaping (NSArray, NSArray) -> Void
    ) {
        let capabilities = backend.capabilities
        reply(
            capabilities.energyModeScopes as NSArray,
            capabilities.supportedPowerModes as NSArray
        )
    }

    func readPowerState(
        withReply reply: @escaping (NSString?, NSString?, NSString?) -> Void
    ) {
        let state = backend.readPowerState()
        reply(
            state.batteryMode as NSString?,
            state.adapterMode as NSString?,
            state.activeMode as NSString?
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

    private static func error(for error: Error) -> NSError {
        let code: Int
        switch error {
        case PowerBackendError.invalidParameter:
            code = 1
        case PowerBackendError.unsupported:
            code = 2
        case PowerBackendError.executionFailed, PowerBackendError.timeout:
            code = 3
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
