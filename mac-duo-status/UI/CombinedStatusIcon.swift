//
//  CombinedStatusIcon.swift
//  mac-duo-status
//

import AppKit
import SwiftUI

struct CombinedStatusIcon: View {
    let snapshot: SystemStatusSnapshot
    let size: CGFloat
    let usesColor: Bool

    init(
        snapshot: SystemStatusSnapshot,
        size: CGFloat = 32,
        usesColor: Bool = false
    ) {
        self.snapshot = snapshot
        self.size = size
        self.usesColor = usesColor
    }

    var body: some View {
        Image(nsImage: StatusIconRenderer.image(
            presentation: StatusIconPresentation(snapshot: snapshot),
            size: size,
            usesColor: usesColor,
            foregroundColor: .white
        ))
        .interpolation(.high)
        .frame(width: size, height: size)
        .fixedSize()
        .accessibilityLabel("Duo Status")
    }
}

extension StatusIconPresentation {
    init(snapshot: SystemStatusSnapshot) {
        self.init(
            batteryIsAvailable: snapshot.battery.availability.isAvailable,
            batteryHasBuiltInBattery: snapshot.battery.hasBuiltInBattery,
            batteryChargeFraction: snapshot.battery.chargeFraction,
            batteryIsCharging: snapshot.battery.isCharging,
            batteryIsLowPowerModeEnabled: snapshot.battery.isLowPowerModeEnabled,
            networkKind: WidgetNetworkKind(rawValue: snapshot.network.kind.rawValue)
                ?? .unavailable,
            healthDotCount: snapshot.health.dotCount
        )
    }
}

extension BatteryIconColorResolver {
    static func resolve(
        for battery: BatteryStatus,
        usesColor: Bool
    ) -> BatteryIconColor {
        resolve(
            chargeFraction: battery.chargeFraction,
            isCharging: battery.isCharging,
            isLowPowerModeEnabled: battery.isLowPowerModeEnabled,
            usesColor: usesColor
        )
    }
}
