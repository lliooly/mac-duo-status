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
        case wifi
        case power
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var statusStore: SystemStatusStore
    @EnvironmentObject private var controls: ControlCoordinator

    @State private var destination: PopoverDestination = .root
    @State private var navigationDirection = 1
    @State private var rootCardsPresented = false

    private var snapshot: SystemStatusSnapshot {
        statusStore.snapshot
    }

    var body: some View {
        popoverSurface
            .tint(DuoStatusStyle.accent)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                statusStore.refreshNow()
            }
    }

    @ViewBuilder
    private var destinationView: some View {
        ZStack(alignment: .top) {
            switch destination {
            case .root:
                rootContent
                    .transition(pageTransition)
            case .wifi:
                WiFiControlView {
                    navigate(to: .root, direction: -1)
                }
                .transition(pageTransition)
            case .power:
                PowerControlView {
                    navigate(to: .root, direction: -1)
                }
                .transition(pageTransition)
            }
        }
        .animation(reduceMotion ? nil : DuoStatusStyle.pageAnimation, value: destination)
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

    @ViewBuilder
    private var popoverSurface: some View {
        if #available(macOS 26.0, *) {
            destinationView
                .padding(DuoStatusStyle.panelPadding)
                .frame(width: DuoStatusStyle.panelWidth)
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
                .frame(width: DuoStatusStyle.panelWidth)
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

    private var batteryCard: some View {
        DuoStatusCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: batterySymbolName)
                        .font(.system(size: 22, weight: .regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DuoStatusStyle.success, .primary)
                        .frame(width: 28)

                    Text(NSLocalizedString("section.battery", comment: ""))
                        .font(.system(size: 14, weight: .semibold))

                    Spacer(minLength: 0)

                    Text(batteryPercentageText)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                batteryProgress

                HStack(alignment: .center, spacing: 10) {
                    Text(batterySummaryText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.muted)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Button {
                        navigate(to: .power, direction: 1)
                    } label: {
                        actionLabel(NSLocalizedString("power.open-control", comment: ""))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-power-control")
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

                    Text(NSLocalizedString("wifi.title", comment: ""))
                        .font(.system(size: 14, weight: .semibold))

                    Spacer(minLength: 0)

                    if snapshot.network.shouldShowWiFiSignal {
                        Image(systemName: "cellularbars")
                            .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.success)
                        .accessibilityLabel(NSLocalizedString("network.signal", comment: ""))
                        .accessibilityValue(
                            snapshot.network.signalLevel.map { "\($0)/4" } ?? "–"
                        )
                    }
                }

                Text(networkName)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 10) {
                    Text(networkStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.muted)

                    Spacer(minLength: 0)

                    Button {
                        navigate(to: .wifi, direction: 1)
                    } label: {
                        actionLabel(NSLocalizedString("network.switch", comment: ""))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-wifi-control")
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

                    Text(NSLocalizedString("section.system", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                }

                HealthMetricSelector(
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
        .accessibilityLabel(NSLocalizedString("health.dots", comment: ""))
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
            .accessibilityLabel(NSLocalizedString("settings.open", comment: ""))
    }

    private var quitAction: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label(NSLocalizedString("common.quit", comment: ""), systemImage: "power")
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
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(DuoStatusStyle.accent)
        .contentShape(Rectangle())
    }

    private var updatedText: String {
        if abs(snapshot.lastUpdated.timeIntervalSinceNow) < 10 {
            return "\(NSLocalizedString("status.updated", comment: "")) " +
                NSLocalizedString("status.just-now", comment: "")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(NSLocalizedString("status.updated", comment: "")) " +
            formatter.localizedString(for: snapshot.lastUpdated, relativeTo: Date())
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
        let source = snapshot.battery.powerSource.localizedTitle
        let mode = snapshot.powerPolicy.activeMode.map {
            NSLocalizedString($0.localizationKey, comment: "")
        } ?? NSLocalizedString("status.unavailable", comment: "")
        return "\(source) · \(mode)"
    }

    private var networkName: String {
        snapshot.network.name ?? snapshot.network.kind.localizedTitle
    }

    private var networkStatusText: String {
        guard snapshot.network.availability.reason == nil else {
            return NSLocalizedString("status.unavailable", comment: "")
        }

        switch snapshot.network.kind {
        case .wifi, .ethernet, .hotspot:
            return NSLocalizedString("network.connected", comment: "")
        case .disconnected, .unavailable:
            return snapshot.network.kind.localizedTitle
        }
    }

    private var selectedMetricDetails: (title: String, value: String)? {
        switch preferences.healthMetric {
        case .cpu:
            guard let usage = snapshot.health.cpuUsagePercent else {
                return nil
            }
            return (
                NSLocalizedString("health.metric.cpu", comment: ""),
                String(format: "%.0f%%", usage)
            )
        case .thermal:
            guard let thermalState = snapshot.health.thermalState else {
                return nil
            }
            return (
                NSLocalizedString("health.metric.thermal", comment: ""),
                thermalState.localizedTitle
            )
        case .load:
            guard let load = snapshot.health.oneMinuteLoad else {
                return nil
            }
            return (
                NSLocalizedString("health.load.one-minute", comment: ""),
                String(format: "%.2f", load)
            )
        }
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
    var localizedTitle: String {
        switch self {
        case .battery:
            return NSLocalizedString("battery.power-source.battery", comment: "")
        case .powerAdapter:
            return NSLocalizedString("battery.power-source.adapter", comment: "")
        case .unknown:
            return NSLocalizedString("status.unavailable", comment: "")
        }
    }
}

private extension ThermalState {
    var localizedTitle: String {
        switch self {
        case .nominal:
            return NSLocalizedString("health.thermal.nominal", comment: "")
        case .fair:
            return NSLocalizedString("health.thermal.fair", comment: "")
        case .serious:
            return NSLocalizedString("health.thermal.serious", comment: "")
        case .critical:
            return NSLocalizedString("health.thermal.critical", comment: "")
        }
    }
}

extension NetworkKind {
    var localizedTitle: String {
        switch self {
        case .wifi:
            return NSLocalizedString("network.kind.wifi", comment: "")
        case .ethernet:
            return NSLocalizedString("network.kind.ethernet", comment: "")
        case .hotspot:
            return NSLocalizedString("network.kind.hotspot", comment: "")
        case .disconnected:
            return NSLocalizedString("network.kind.disconnected", comment: "")
        case .unavailable:
            return NSLocalizedString("status.unavailable", comment: "")
        }
    }
}
