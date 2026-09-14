//
//  BatteryProvider.swift
//  mac-duo-status
//

import Foundation
import IOKit.ps

enum BatteryChargeCalculator {
    nonisolated static func fraction(currentCapacity: Int, maximumCapacity: Int) -> Double? {
        guard maximumCapacity > 0 else {
            return nil
        }

        return min(
            max(Double(currentCapacity) / Double(maximumCapacity), 0),
            1
        )
    }
}

final class BatteryProvider: BatteryProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var changeHandler: (@Sendable () -> Void)?
    private var notificationSource: CFRunLoopSource?

    func read() async -> BatteryStatus {
        readSynchronously()
    }

    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        guard notificationSource == nil else {
            lock.unlock()
            return
        }
        changeHandler = handler
        lock.unlock()

        guard let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else {
                    return
                }

                let provider = Unmanaged<BatteryProvider>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                provider.notifyChange()
            },
            Unmanaged.passUnretained(self).toOpaque()
        )?.takeRetainedValue() else {
            lock.lock()
            changeHandler = nil
            lock.unlock()
            return
        }

        lock.lock()
        notificationSource = source
        lock.unlock()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stopObserving() {
        lock.lock()
        let source = notificationSource
        notificationSource = nil
        changeHandler = nil
        lock.unlock()

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func notifyChange() {
        lock.lock()
        let handler = changeHandler
        lock.unlock()
        handler?()
    }

    private func readSynchronously() -> BatteryStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unavailable(reason: "Battery information is unavailable")
        }

        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }

        guard let description = descriptions.first(where: { description in
            isPresent(description) && string(description, forKey: kIOPSTypeKey) == kIOPSInternalBatteryType
        }) else {
            return .noBuiltInBattery
        }

        guard
            let currentCapacity = integer(description, forKey: kIOPSCurrentCapacityKey),
            let maximumCapacity = integer(description, forKey: kIOPSMaxCapacityKey),
            maximumCapacity > 0
        else {
            return .unavailable(
                reason: "Battery capacity is unavailable",
                hasBuiltInBattery: true
            )
        }

        guard let chargeFraction = BatteryChargeCalculator.fraction(
            currentCapacity: currentCapacity,
            maximumCapacity: maximumCapacity
        ) else {
            return .unavailable(
                reason: "Battery capacity is unavailable",
                hasBuiltInBattery: true
            )
        }
        let powerSource = powerSource(for: description)

        return BatteryStatus(
            availability: .available,
            hasBuiltInBattery: true,
            chargeFraction: chargeFraction,
            isCharging: bool(description, forKey: kIOPSIsChargingKey),
            powerSource: powerSource,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private func powerSource(for description: [String: Any]) -> PowerSource {
        switch string(description, forKey: kIOPSPowerSourceStateKey) {
        case kIOPSACPowerValue:
            return .powerAdapter
        case kIOPSBatteryPowerValue:
            return .battery
        default:
            return .unknown
        }
    }

    private func isPresent(_ description: [String: Any]) -> Bool {
        bool(description, forKey: kIOPSIsPresentKey) ?? true
    }

    private func bool(_ description: [String: Any], forKey key: String) -> Bool? {
        if let value = description[key] as? Bool {
            return value
        }

        return (description[key] as? NSNumber)?.boolValue
    }

    private func integer(_ description: [String: Any], forKey key: String) -> Int? {
        if let value = description[key] as? Int {
            return value
        }

        return (description[key] as? NSNumber)?.intValue
    }

    private func string(_ description: [String: Any], forKey key: String) -> String? {
        description[key] as? String
    }
}
