//
//  WidgetStatusBridge.swift
//  mac-duo-status
//

import Foundation
import WidgetKit

@MainActor
final class WidgetStatusBridge {
    private let snapshotStore: WidgetStatusSnapshotStore
    private var lastPublishedSnapshot: WidgetStatusSnapshot?
    private var lastWriteDate = Date.distantPast
    private var lastReloadDate = Date.distantPast

    init() {
        self.snapshotStore = WidgetStatusSnapshotStore()
    }

    init(snapshotStore: WidgetStatusSnapshotStore) {
        self.snapshotStore = snapshotStore
    }

    func publish(snapshot: SystemStatusSnapshot, usesColor: Bool) {
        let now = Date()
        let candidate = WidgetStatusSnapshot(
            snapshot: snapshot,
            usesColor: usesColor,
            updatedAt: now
        )
        let contentChanged = lastPublishedSnapshot.map {
            !$0.hasSameDisplayContent(as: candidate)
        } ?? true
        let heartbeatDue = now.timeIntervalSince(lastWriteDate)
            >= WidgetStatusConstants.writeHeartbeatInterval

        guard contentChanged || heartbeatDue else {
            return
        }

        guard snapshotStore.write(candidate) else {
            return
        }

        lastPublishedSnapshot = candidate
        lastWriteDate = now

        guard now.timeIntervalSince(lastReloadDate)
                >= WidgetStatusConstants.reloadMinimumInterval
        else {
            return
        }

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStatusConstants.kind)
        lastReloadDate = now
    }
}

private extension WidgetStatusSnapshot {
    init(
        snapshot: SystemStatusSnapshot,
        usesColor: Bool,
        updatedAt: Date
    ) {
        self.init(
            updatedAt: updatedAt,
            battery: Battery(
                isAvailable: snapshot.battery.availability.isAvailable,
                hasBuiltInBattery: snapshot.battery.hasBuiltInBattery,
                chargeFraction: snapshot.battery.chargeFraction,
                isCharging: snapshot.battery.isCharging,
                isLowPowerModeEnabled: snapshot.battery.isLowPowerModeEnabled
            ),
            network: Network(
                isAvailable: snapshot.network.availability.isAvailable,
                kind: WidgetNetworkKind(rawValue: snapshot.network.kind.rawValue)
                    ?? .unavailable
            ),
            healthDotCount: snapshot.health.dotCount,
            usesColor: usesColor
        )
    }
}
