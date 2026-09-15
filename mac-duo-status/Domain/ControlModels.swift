//
//  ControlModels.swift
//  mac-duo-status
//

import Foundation

enum CapabilityState: Equatable, Sendable {
    case unsupported
    case readOnly
    case available
    case authorizationRequired
    case temporarilyUnavailable
}

enum ControlError: Error, Equatable, Sendable {
    case networkNotFound
    case authenticationFailed
    case unsupportedSecurity
    case authorizationRequired
    case helperUnavailable
    case invalidChargeLimit
    case operationTimeout
    case writeUnconfirmed
    case cancelled
    case temporarilyUnavailable
    case failed

    var localizationKey: String {
        switch self {
        case .networkNotFound:
            return "control.error.network-not-found"
        case .authenticationFailed:
            return "control.error.authentication-failed"
        case .unsupportedSecurity:
            return "control.error.unsupported-security"
        case .authorizationRequired:
            return "control.error.authorization-required"
        case .helperUnavailable:
            return "control.error.helper-unavailable"
        case .invalidChargeLimit:
            return "control.error.invalid-charge-limit"
        case .operationTimeout:
            return "control.error.operation-timeout"
        case .writeUnconfirmed:
            return "control.error.write-unconfirmed"
        case .cancelled:
            return "control.error.cancelled"
        case .temporarilyUnavailable:
            return "control.error.temporarily-unavailable"
        case .failed:
            return "control.error.failed"
        }
    }
}

enum ControlOperationState: Equatable, Sendable {
    case idle
    case pending
    case succeeded
    case failed(ControlError)

    var isPending: Bool {
        if case .pending = self {
            return true
        }

        return false
    }
}

struct KeychainIdentityReference: Hashable, Sendable {
    let persistentReference: Data

    init(persistentReference: Data) {
        self.persistentReference = persistentReference
    }
}
