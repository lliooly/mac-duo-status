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
    private static let helperRevision = 2
    private let backend: any PowerBackend
    private let wifiBackend: any WiFiSavedNetworkBackend

    init(
        backend: any PowerBackend = PMSetPowerBackend(),
        wifiBackend: any WiFiSavedNetworkBackend = CoreWLANWiFiSavedNetworkBackend()
    ) {
        self.backend = backend
        self.wifiBackend = wifiBackend
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

    func connectToSavedWiFi(
        _ interfaceName: NSString,
        ssidData: NSData,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        do {
            try wifiBackend.connectToSavedNetwork(
                interfaceName: String(interfaceName),
                ssidData: ssidData as Data
            )
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
        case WiFiBackendError.invalidParameter:
            code = 101
        case WiFiBackendError.networkNotFound:
            code = 102
        case WiFiBackendError.credentialsRequired:
            code = 103
        case WiFiBackendError.authenticationFailed:
            code = 104
        case WiFiBackendError.unsupportedSecurity:
            code = 105
        case WiFiBackendError.authorizationRequired:
            code = 106
        case WiFiBackendError.temporarilyUnavailable:
            code = 107
        case WiFiBackendError.operationTimeout:
            code = 108
        case WiFiBackendError.failed:
            code = 109
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
