//
//  PowerHelperMain.swift
//  DuoStatusPowerHelper
//

import Foundation
import Security

@main
final class DuoStatusPowerHelperMain: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(
            machServiceName: "com.shishishi3.duo-status.power-helper"
        )
        super.init()
        listener.delegate = self
    }

    static func main() {
        let helper = DuoStatusPowerHelperMain()
        helper.listener.resume()
        RunLoop.main.run()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard isTrustedClient(newConnection) else {
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(
            with: DuoStatusPowerHelperProtocol.self
        )
        newConnection.exportedObject = PowerHelperService()
        newConnection.invalidationHandler = {}
        newConnection.interruptionHandler = {}
        newConnection.resume()
        return true
    }

    private func isTrustedClient(_ connection: NSXPCConnection) -> Bool {
        let attributes: [CFString: Any] = [
            kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)
        ]
        var guestCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(
            nil,
            attributes as CFDictionary,
            [],
            &guestCode
        ) == errSecSuccess,
        let guestCode
        else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(
            guestCode,
            [],
            &staticCode
        ) == errSecSuccess,
        let staticCode
        else {
            return false
        }

        guard let information = signingInformation(for: staticCode),
              let identifier = information[kSecCodeInfoIdentifier as String] as? String,
              identifier == "com.shishishi3.mac-duo-status",
              let clientTeamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String,
              let helperTeamIdentifier = ownTeamIdentifier()
        else {
            return false
        }

        return clientTeamIdentifier == helperTeamIdentifier
    }

    private func ownTeamIdentifier() -> String? {
        var selfCode: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess,
              let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let staticCode,
              let information = signingInformation(for: staticCode)
        else {
            return nil
        }

        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func signingInformation(for code: SecStaticCode) -> [String: Any]? {
        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let information = signingInformation as? [String: Any]
        else {
            return nil
        }

        return information
    }
}
