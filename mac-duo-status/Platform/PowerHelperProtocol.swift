//
//  PowerHelperProtocol.swift
//  mac-duo-status
//

import Foundation

@objc(DuoStatusPowerHelperProtocol)
protocol DuoStatusPowerHelperProtocol {
    func getHelperInfo(withReply reply: @escaping (NSNumber) -> Void)
    func getCapabilities(
        withReply reply: @escaping (NSArray, NSArray) -> Void
    )
    func readPowerState(
        withReply reply: @escaping (NSString?, NSString?, NSString?) -> Void
    )
    func setPowerMode(
        _ scope: NSString,
        mode: NSString,
        withReply reply: @escaping (NSError?) -> Void
    )
    func connectToSavedWiFi(
        _ interfaceName: NSString,
        ssidData: NSData,
        withReply reply: @escaping (NSError?) -> Void
    )
}
