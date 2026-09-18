//
//  WiFiHelperBackend.swift
//  DuoStatusPowerHelper
//

import CoreWLAN
import Foundation
import Security

protocol WiFiSavedNetworkBackend {
    func connectToSavedNetwork(
        interfaceName: String,
        ssidData: Data
    ) throws
}

struct UnavailableWiFiSavedNetworkBackend: WiFiSavedNetworkBackend {
    func connectToSavedNetwork(
        interfaceName: String,
        ssidData: Data
    ) throws {
        throw WiFiBackendError.temporarilyUnavailable
    }
}

enum WiFiBackendError: Error {
    case invalidParameter
    case networkNotFound
    case credentialsRequired
    case authenticationFailed
    case unsupportedSecurity
    case authorizationRequired
    case temporarilyUnavailable
    case operationTimeout
    case failed
}

final class CoreWLANWiFiSavedNetworkBackend: WiFiSavedNetworkBackend {
    private struct EnterpriseCredential {
        let username: String?
        let password: String?
        let identity: SecIdentity?
    }

    private let wifiClient = CWWiFiClient.shared()

    func connectToSavedNetwork(
        interfaceName: String,
        ssidData: Data
    ) throws {
        guard Self.isValidInterfaceName(interfaceName),
              (1...32).contains(ssidData.count)
        else {
            throw WiFiBackendError.invalidParameter
        }

        // networksetup asks the system Wi-Fi stack to use its saved profile.
        // It avoids moving a Wi-Fi password through this helper at all.
        if let ssid = String(data: ssidData, encoding: .utf8),
           !ssid.isEmpty,
           connectUsingNetworkSetup(interfaceName: interfaceName, ssid: ssid) {
            return
        }

        try connectUsingCoreWLAN(
            interfaceName: interfaceName,
            ssidData: ssidData
        )
    }

    private func connectUsingNetworkSetup(
        interfaceName: String,
        ssid: String
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-setairportnetwork", interfaceName, ssid]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func connectUsingCoreWLAN(
        interfaceName: String,
        ssidData: Data
    ) throws {
        guard let interface = wifiClient.interface(withName: interfaceName) else {
            throw WiFiBackendError.temporarilyUnavailable
        }

        guard interface.powerOn() else {
            throw WiFiBackendError.temporarilyUnavailable
        }

        let networks: Set<CWNetwork>
        do {
            networks = try interface.scanForNetworks(
                withSSID: ssidData,
                includeHidden: true
            )
        } catch let error as NSError {
            throw Self.map(error: error)
        }

        guard let network = networks.first(where: {
            Self.resolvedSSIDData(for: $0) == ssidData
        }) else {
            throw WiFiBackendError.networkNotFound
        }

        if Self.isEnterprise(network) {
            try associateEnterprise(network: network, ssidData: ssidData, interface: interface)
            return
        }

        let password: String?
        if Self.isOpen(network) {
            password = nil
        } else if let storedPassword = storedSystemWiFiPassword(for: ssidData) {
            password = storedPassword
        } else {
            throw WiFiBackendError.credentialsRequired
        }

        do {
            try interface.associate(to: network, password: password)
        } catch let error as NSError {
            throw Self.map(error: error)
        }
    }

    private func associateEnterprise(
        network: CWNetwork,
        ssidData: Data,
        interface: CWInterface
    ) throws {
        let credential = try storedSystemEnterpriseCredential(for: ssidData)

        do {
            try interface.associate(
                toEnterpriseNetwork: network,
                identity: credential.identity,
                username: credential.username,
                password: credential.password
            )
        } catch let error as NSError {
            throw Self.map(error: error)
        }
    }

    private func storedSystemWiFiPassword(for ssidData: Data) -> String? {
        var password: NSString?
        let status = CWKeychainFindWiFiPassword(
            .system,
            ssidData,
            &password
        )
        guard status == errSecSuccess,
              let password,
              password.length > 0
        else {
            return nil
        }

        return password as String
    }

    private func storedSystemEnterpriseCredential(
        for ssidData: Data
    ) throws -> EnterpriseCredential {
        var username: NSString?
        var password: NSString?
        let credentialStatus = CWKeychainFindWiFiEAPUsernameAndPassword(
            .system,
            ssidData,
            &username,
            &password
        )

        var unmanagedIdentity: Unmanaged<SecIdentity>?
        let identityStatus = CWKeychainCopyWiFiEAPIdentity(
            .system,
            ssidData,
            &unmanagedIdentity
        )
        let identity = unmanagedIdentity?.takeRetainedValue()

        guard credentialStatus == errSecSuccess || identityStatus == errSecSuccess else {
            throw WiFiBackendError.credentialsRequired
        }

        let credential = EnterpriseCredential(
            username: username.map { $0 as String },
            password: password.map { $0 as String },
            identity: identity
        )
        guard credential.username?.isEmpty == false ||
            credential.password?.isEmpty == false ||
            credential.identity != nil
        else {
            throw WiFiBackendError.credentialsRequired
        }

        return credential
    }

    private static func resolvedSSIDData(for network: CWNetwork) -> Data? {
        network.ssidData ?? network.ssid?.data(using: .utf8)
    }

    private static func isOpen(_ network: CWNetwork) -> Bool {
        [.none, .OWE, .oweTransition].contains { network.supportsSecurity($0) }
    }

    private static func isEnterprise(_ network: CWNetwork) -> Bool {
        [
            CWSecurity.dynamicWEP,
            .wpaEnterprise,
            .wpaEnterpriseMixed,
            .wpa2Enterprise,
            .enterprise,
            .wpa3Enterprise
        ].contains { network.supportsSecurity($0) }
    }

    private static func isValidInterfaceName(_ interfaceName: String) -> Bool {
        guard !interfaceName.isEmpty, interfaceName.count <= 16 else {
            return false
        }

        return interfaceName.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) ||
                $0 == "." || $0 == "_" || $0 == "-"
        }
    }

    private static func map(error: NSError) -> WiFiBackendError {
        switch Int(error.code) {
        case -3905:
            return .operationTimeout
        case -3930:
            return .authorizationRequired
        case -3903:
            return .unsupportedSecurity
        case -3909, -3906, -3910, -3924, -3925:
            return .authenticationFailed
        default:
            return .failed
        }
    }
}
