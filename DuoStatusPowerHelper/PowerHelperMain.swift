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

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let information = signingInformation as? [String: Any]
        else {
            return false
        }

        let identifier = information[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String

        return identifier == "com.shishishi3.mac-duo-status" &&
            teamIdentifier == "PM2QH96LXN"
    }
}
