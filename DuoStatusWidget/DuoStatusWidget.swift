//
//  DuoStatusWidget.swift
//  DuoStatusWidget
//

import AppKit
import SwiftUI
import WidgetKit

struct DuoStatusWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetStatusSnapshot
}

struct DuoStatusWidgetProvider: TimelineProvider {
    private let snapshotStore = WidgetStatusSnapshotStore()

    func placeholder(in context: Context) -> DuoStatusWidgetEntry {
        DuoStatusWidgetEntry(
            date: Date(),
            snapshot: .placeholder
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (DuoStatusWidgetEntry) -> Void
    ) {
        let snapshot = snapshotStore.read() ?? .unavailable()
        completion(
            DuoStatusWidgetEntry(
                date: Date(),
                snapshot: snapshot
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<DuoStatusWidgetEntry>) -> Void
    ) {
        let now = Date()
        let snapshot = snapshotStore.read() ?? .unavailable(updatedAt: now)
        let entry = DuoStatusWidgetEntry(date: now, snapshot: snapshot)
        let nextRefresh = now.addingTimeInterval(
            WidgetStatusConstants.timelineFallbackInterval
        )

        completion(
            Timeline(
                entries: [entry],
                policy: .after(nextRefresh)
            )
        )
    }
}

struct DuoStatusWidgetView: View {
    let entry: DuoStatusWidgetEntry

    @ViewBuilder
    var body: some View {
        if #available(macOS 14.0, *) {
            widgetContent
                .containerBackground(.clear, for: .widget)
        } else {
            widgetContent
                .background(Color.clear)
        }
    }

    private var widgetContent: some View {
        ZStack {
            Image(nsImage: StatusIconRenderer.image(
                presentation: entry.snapshot.iconPresentation,
                size: 112,
                usesColor: false,
                batteryColorOverride: WidgetBatteryColorResolver.resolve(
                    for: entry.snapshot
                ),
                foregroundColor: .white,
                isTemplate: true
            ))
            .interpolation(.high)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(.primary)
            .scaledToFit()
            .frame(width: 112, height: 112)
            .opacity(entry.snapshot.isStale ? 0.62 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Duo Status")
        .accessibilityValue("Battery, network, and system health status")
    }
}

private enum WidgetBatteryColorResolver {
    static func resolve(for snapshot: WidgetStatusSnapshot) -> NSColor? {
        let color = BatteryIconColorResolver.resolve(
            chargeFraction: snapshot.battery.chargeFraction,
            isCharging: snapshot.battery.isCharging,
            isLowPowerModeEnabled: snapshot.battery.isLowPowerModeEnabled,
            usesColor: snapshot.usesColor
        )

        guard color != .white else {
            return nil
        }

        return color.nsColor
    }
}

@main
struct DuoStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetStatusConstants.kind,
            provider: DuoStatusWidgetProvider()
        ) { entry in
            DuoStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Duo Status")
        .description("See your Mac battery, network, and system health at a glance.")
        .supportedFamilies([.systemSmall])
    }
}
