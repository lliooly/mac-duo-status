//
//  StatusPopoverView.swift
//  mac-duo-status
//

import AppKit
import Foundation
import SwiftUI

struct StatusPopoverView: View {
    private enum PopoverDestination: Hashable {
        case root
        case power
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var localization: LocalizationStore

    private let batteryStatusStore: BatteryStatusStore
    private let powerPolicyStatusStore: PowerPolicyStatusStore

    @State private var destination: PopoverDestination = .root
    @State private var navigationDirection = 1

    init(
        batteryStatusStore: BatteryStatusStore,
        powerPolicyStatusStore: PowerPolicyStatusStore
    ) {
        self.batteryStatusStore = batteryStatusStore
        self.powerPolicyStatusStore = powerPolicyStatusStore
    }

    var body: some View {
        popoverSurface
            .tint(DuoStatusStyle.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var destinationView: some View {
        ZStack(alignment: .top) {
            switch destination {
            case .root:
                StatusRootView {
                    navigate(to: .power, direction: 1)
                }
                    .transition(pageTransition)
            case .power:
                PowerControlView(
                    batteryStatusStore: batteryStatusStore,
                    powerPolicyStatusStore: powerPolicyStatusStore
                ) {
                    navigate(to: .root, direction: -1)
                }
                .transition(pageTransition)
            }
        }
        .animation(reduceMotion ? nil : DuoStatusStyle.pageAnimation, value: destination)
    }

    @ViewBuilder
    private var popoverSurface: some View {
        if #available(macOS 26.0, *) {
            destinationView
                .padding(DuoStatusStyle.panelPadding)
                .frame(width: adaptivePanelWidth)
                .glassEffect(
                    .clear,
                    in: RoundedRectangle(
                        cornerRadius: DuoStatusStyle.panelCornerRadius,
                        style: .continuous
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: DuoStatusStyle.panelCornerRadius,
                        style: .continuous
                    )
                )
        } else {
            destinationView
                .padding(DuoStatusStyle.panelPadding)
                .frame(width: adaptivePanelWidth)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: DuoStatusStyle.panelCornerRadius,
                        style: .continuous
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: DuoStatusStyle.panelCornerRadius,
                        style: .continuous
                    )
                )
                .shadow(color: Color.black.opacity(0.18), radius: 24, y: 10)
        }
    }

    private var adaptivePanelWidth: CGFloat {
        let metricFont = NSFont.systemFont(ofSize: 13)
        let actionFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let metricLabelsWidth = HealthMetric.allCases.reduce(0) { width, metric in
            width + DuoStatusStyle.textWidth(
                localization.string(metric.localizationKey),
                font: metricFont
            )
        }
        let actionLabelWidth = [
            localization.string("power.open-control"),
            localization.string("wifi.settings")
        ].map {
            DuoStatusStyle.textWidth($0, font: actionFont)
        }.max() ?? 0

        let metricSelectorWidth = metricLabelsWidth + 3 * 28 + 64
        let actionRowWidth = actionLabelWidth + 210
        return DuoStatusStyle.clamped(
            max(metricSelectorWidth, actionRowWidth),
            min: DuoStatusStyle.panelMinWidth,
            max: DuoStatusStyle.panelMaxWidth
        )
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }

        let insertionEdge: Edge = navigationDirection > 0 ? .trailing : .leading
        let removalEdge: Edge = navigationDirection > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func navigate(to newDestination: PopoverDestination, direction: Int) {
        navigationDirection = direction
        if reduceMotion {
            destination = newDestination
        } else {
            withAnimation(DuoStatusStyle.pageAnimation) {
                destination = newDestination
            }
        }
    }
}

private struct StatusRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var statusStore: SystemStatusStore

    @State private var rootCardsPresented = false

    let onOpenPower: () -> Void

    private var snapshot: SystemStatusSnapshot {
        statusStore.snapshot
    }

    var body: some View {
        rootContent
    }

    private var rootContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverPageHeader(
                title: "Duo Status",
                subtitle: updatedText
            ) {
                settingsAction
            }

            batteryCard
                .modifier(
                    RootCardEntrance(
                        isPresented: rootCardsPresented,
                        order: 0,
                        reduceMotion: reduceMotion
                    )
                )

            networkCard
                .modifier(
                    RootCardEntrance(
                        isPresented: rootCardsPresented,
                        order: 1,
                        reduceMotion: reduceMotion
                    )
                )

            healthCard
                .modifier(
                    RootCardEntrance(
                        isPresented: rootCardsPresented,
                        order: 2,
                        reduceMotion: reduceMotion
                    )
                )

            quitAction
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 2)
        }
        .onAppear {
            guard !rootCardsPresented else {
                return
            }

            if reduceMotion {
                rootCardsPresented = true
            } else {
                withAnimation(.easeOut(duration: 0.28)) {
                    rootCardsPresented = true
                }
            }
        }
    }

    private var batteryCard: some View {
        DuoStatusCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: batterySymbolName)
                        .font(.system(size: 22, weight: .regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DuoStatusStyle.success, .primary)
                        .frame(width: 28)

                    Text(localization.string("section.battery"))
                        .font(.system(size: 14, weight: .semibold))

                    Spacer(minLength: 0)

                    Text(batteryPercentageText)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                batteryProgress

                VStack(alignment: .leading, spacing: 6) {
                    Text(batterySummaryText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer(minLength: 0)

                        Button {
                            onOpenPower()
                        } label: {
                            actionLabel(localization.string("power.open-control"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("open-power-control")
                    }
                }
            }
        }
        .accessibilityIdentifier("status-card-battery")
    }

    @ViewBuilder
    private var batteryProgress: some View {
        if let fraction = snapshot.battery.chargeFraction,
           snapshot.battery.hasBuiltInBattery {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DuoStatusStyle.trackFill)

                    Capsule()
                        .fill(DuoStatusStyle.success)
                        .frame(
                            width: proxy.size.width * CGFloat(min(max(fraction, 0), 1))
                        )
                }
            }
            .frame(height: 7)
            .animation(
                reduceMotion ? nil : DuoStatusStyle.quickAnimation,
                value: fraction
            )
        } else {
            Capsule()
                .fill(DuoStatusStyle.trackFill)
                .frame(height: 7)
        }
    }

    private var networkCard: some View {
        DuoStatusCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: snapshot.network.kind.systemImageName)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(DuoStatusStyle.accent)
                        .frame(width: 28)

                    Text(localization.string("wifi.title"))
                        .font(.system(size: 14, weight: .semibold))

                    Spacer(minLength: 0)

                    if snapshot.network.shouldShowWiFiSignal {
                        Image(systemName: "cellularbars")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.success)
                        .accessibilityLabel(localization.string("network.signal"))
                        .accessibilityValue(
                            snapshot.network.signalLevel.map { "\($0)/4" } ?? "–"
                        )
                    }
                }

                Text(networkName)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                VStack(alignment: .leading, spacing: 6) {
                    Text(networkStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.muted)

                    HStack {
                        Spacer(minLength: 0)

                        Button(action: SettingsWindowAccess.openWiFiSettings) {
                            actionLabel(localization.string("wifi.settings"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("open-wifi-settings")
                    }
                }
            }
        }
        .accessibilityIdentifier("status-card-network")
    }

    private var healthCard: some View {
        DuoStatusCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 28)

                    Text(localization.string("section.system"))
                        .font(.system(size: 14, weight: .semibold))
                }

                HealthMetricSelector(
                    compact: true,
                    selection: Binding(
                        get: { preferences.healthMetric },
                        set: { statusStore.setHealthMetric($0) }
                    )
                )

                if let details = selectedMetricDetails {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(details.value)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .id(details.value)
                                .transition(.opacity)

                            Text(details.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DuoStatusStyle.muted)
                        }

                        Spacer(minLength: 0)
                        healthDots
                    }
                    .animation(
                        reduceMotion ? nil : DuoStatusStyle.quickAnimation,
                        value: details.value
                    )
                } else {
                    UnavailableStatusView(reason: nil)
                        .frame(minHeight: 40)
                }
            }
        }
        .accessibilityIdentifier("status-card-system-health")
    }

    private var healthDots: some View {
        let activeCount = snapshot.health.dotCount ?? 0

        return HStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(
                        index < activeCount
                            ? DuoStatusStyle.success
                            : DuoStatusStyle.trackFill
                    )
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityLabel(localization.string("health.dots"))
        .accessibilityValue("\(activeCount)/4")
    }

    @ViewBuilder
    private var settingsAction: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    settingsActionLabel
                }
                .buttonStyle(ActivateApplicationBeforeActionButtonStyle())
            } else {
                Button(action: SettingsWindowAccess.openLegacySettings) {
                    settingsActionLabel
                }
            }
        }
        .buttonStyle(DuoStatusIconButtonStyle())
        .accessibilityIdentifier("open-settings")
    }

    private var settingsActionLabel: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 18, weight: .medium))
            .accessibilityLabel(localization.string("settings.open"))
    }

    private var quitAction: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label(localization.string("common.quit"), systemImage: "power")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DuoStatusStyle.muted)
                .padding(.horizontal, 4)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quit-app")
    }

    private func actionLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(DuoStatusStyle.accent)
        .contentShape(Rectangle())
    }

    private var updatedText: String {
        let lastUpdated = statusStore.lastUpdatedStore.date
        if abs(lastUpdated.timeIntervalSinceNow) < 10 {
            return "\(localization.string("status.updated")) " +
                localization.string("status.just-now")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localization.locale
        formatter.unitsStyle = .full
        return "\(localization.string("status.updated")) " +
            formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }

    private var batteryPercentageText: String {
        guard snapshot.battery.availability.reason == nil,
              snapshot.battery.hasBuiltInBattery,
              let fraction = snapshot.battery.chargeFraction
        else {
            return "–"
        }

        return "\(Int((fraction * 100).rounded()))%"
    }

    private var batterySymbolName: String {
        guard snapshot.battery.hasBuiltInBattery,
              let fraction = snapshot.battery.chargeFraction
        else {
            return "battery.0"
        }

        if snapshot.battery.isCharging == true {
            return "battery.100.bolt"
        }

        switch fraction {
        case ..<0.13:
            return "battery.0"
        case ..<0.38:
            return "battery.25"
        case ..<0.63:
            return "battery.50"
        case ..<0.88:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private var batterySummaryText: String {
        let source = localization.string(snapshot.battery.powerSource.localizationKey)
        let mode = snapshot.powerPolicy.activeMode.map {
            localization.string($0.localizationKey)
        } ?? localization.string("status.unavailable")
        return "\(source) · \(mode)"
    }

    private var networkName: String {
        snapshot.network.name ?? localization.string(snapshot.network.kind.localizationKey)
    }

    private var networkStatusText: String {
        guard snapshot.network.availability.reason == nil else {
            return localization.string("status.unavailable")
        }

        switch snapshot.network.kind {
        case .wifi, .ethernet, .hotspot:
            return localization.string("network.connected")
        case .disconnected, .unavailable:
            return localization.string(snapshot.network.kind.localizationKey)
        }
    }

    private var selectedMetricDetails: (title: String, value: String)? {
        switch preferences.healthMetric {
        case .cpu:
            guard let usage = snapshot.health.cpuUsagePercent else {
                return nil
            }
            return (
                localization.string("health.metric.cpu"),
                String(format: "%.0f%%", usage)
            )
        case .thermal:
            guard let thermalState = snapshot.health.thermalState else {
                return nil
            }
            return (
                localization.string("health.metric.thermal"),
                localization.string(thermalState.localizationKey)
            )
        case .load:
            guard let load = snapshot.health.oneMinuteLoad else {
                return nil
            }
            return (
                localization.string("health.load.one-minute"),
                String(format: "%.2f", load)
            )
        }
    }

}

private struct RootCardEntrance: ViewModifier {
    let isPresented: Bool
    let order: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(y: reduceMotion || isPresented ? 0 : 8)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.24).delay(Double(order) * 0.035),
                value: isPresented
            )
    }
}

private extension PowerSource {
    var localizationKey: String {
        switch self {
        case .battery:
            return "battery.power-source.battery"
        case .powerAdapter:
            return "battery.power-source.adapter"
        case .unknown:
            return "status.unavailable"
        }
    }
}

private extension ThermalState {
    var localizationKey: String {
        switch self {
        case .nominal:
            return "health.thermal.nominal"
        case .fair:
            return "health.thermal.fair"
        case .serious:
            return "health.thermal.serious"
        case .critical:
            return "health.thermal.critical"
        }
    }
}

extension NetworkKind {
    var localizationKey: String {
        switch self {
        case .wifi:
            return "network.kind.wifi"
        case .ethernet:
            return "network.kind.ethernet"
        case .hotspot:
            return "network.kind.hotspot"
        case .disconnected:
            return "network.kind.disconnected"
        case .unavailable:
            return "status.unavailable"
        }
    }
}
