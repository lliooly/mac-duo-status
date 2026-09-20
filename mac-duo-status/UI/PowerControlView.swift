//
//  PowerControlView.swift
//  mac-duo-status
//

import SwiftUI

struct PowerControlView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var controls: ControlCoordinator
    @ObservedObject private var batteryStatusStore: BatteryStatusStore
    @ObservedObject private var powerPolicyStatusStore: PowerPolicyStatusStore

    let onBack: () -> Void

    init(
        batteryStatusStore: BatteryStatusStore,
        powerPolicyStatusStore: PowerPolicyStatusStore,
        onBack: @escaping () -> Void
    ) {
        _batteryStatusStore = ObservedObject(wrappedValue: batteryStatusStore)
        _powerPolicyStatusStore = ObservedObject(wrappedValue: powerPolicyStatusStore)
        self.onBack = onBack
    }

    private var status: PowerPolicyStatus {
        powerPolicyStatusStore.status
    }

    private var availableModes: [PowerMode] {
        [.automatic, .lowPower, .highPower].filter {
            status.capabilities.supportedPowerModes.contains($0)
        }
    }

    private var currentScope: PowerSourceScope? {
        switch batteryStatusStore.status.powerSource {
        case .battery:
            return .battery
        case .powerAdapter:
            return .powerAdapter
        case .unknown:
            return nil
        }
    }

    private var currentMode: PowerMode? {
        currentScope.flatMap(mode(for:))
    }

    private var modeReadbackUnavailable: Bool {
        guard let currentScope,
              status.capabilities.energyModeScopes.contains(currentScope)
        else {
            return true
        }

        return currentMode == nil
    }

    private var canEditModes: Bool {
        guard let currentScope else {
            return false
        }

        return status.helperStatus.isAuthorized &&
            status.capabilities.energyModeScopes.contains(currentScope) &&
            !availableModes.isEmpty &&
            currentMode != nil &&
            !controls.powerOperationState.isPending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverPageHeader(
                title: localization.string("power.title"),
                subtitle: localizedMode(status.activeMode),
                onBack: onBack
            )

            powerSummaryCard
            energyModeControls

            DuoStatusCard {
                PowerAuthorizationView()
            }
        }
    }

    private var powerSummaryCard: some View {
        DuoStatusCard {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: batteryStatusStore.status.isCharging == true
                        ? "battery.100.bolt"
                        : "battery.100")
                        .font(.system(size: 22, weight: .regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DuoStatusStyle.success, .primary)
                        .frame(width: 28)

                    Text(localization.string("power.active-mode"))
                        .font(.system(size: 13, weight: .semibold))

                    Spacer(minLength: 0)

                    Text(localizedMode(status.activeMode))
                        .font(.system(size: 13, weight: .semibold))
                }

                Divider()
                    .overlay(DuoStatusStyle.divider)
                    .padding(.vertical, 11)

                StatusValueRow(
                    title: localization.string("power.scope.title"),
                    value: localizedScope(currentScope)
                )
            }
        }
    }

    @ViewBuilder
    private var energyModeControls: some View {
        DuoStatusCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DuoStatusStyle.accent)

                    Text(localization.string("power.modes"))
                        .font(.system(size: 13, weight: .semibold))
                }

                if availableModes.isEmpty || modeReadbackUnavailable {
                    readOnlyModeRows
                } else {
                    VStack(spacing: 5) {
                        ForEach(availableModes) { mode in
                            modeRow(mode, isSelected: currentMode == mode)
                        }
                    }
                }

                if !status.helperStatus.isAuthorized ||
                    availableModes.isEmpty ||
                    modeReadbackUnavailable {
                    Divider()
                        .overlay(DuoStatusStyle.divider)
                        .padding(.top, 2)

                    batterySettingsFallback
                }
            }
        }
    }

    @ViewBuilder
    private var readOnlyModeRows: some View {
        StatusValueRow(
            title: localization.string("power.current-mode"),
            value: localizedMode(modeReadbackUnavailable ? nil : currentMode)
        )
    }

    private func modeRow(_ mode: PowerMode, isSelected: Bool) -> some View {
        Button {
            guard let currentScope else {
                return
            }

            Task {
                await controls.setPowerMode(mode, scope: currentScope)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.systemImageName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? DuoStatusStyle.accent : DuoStatusStyle.muted)
                    .frame(width: 30, height: 30)
                    .background(
                        isSelected
                            ? DuoStatusStyle.accent.opacity(0.13)
                            : DuoStatusStyle.controlFill,
                        in: Circle()
                    )

                Text(localization.string(mode.localizationKey))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DuoStatusStyle.accent)
                }
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 40)
            .background(
                isSelected ? DuoStatusStyle.accent.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEditModes)
        .animation(reduceMotion ? nil : DuoStatusStyle.quickAnimation, value: isSelected)
        .accessibilityIdentifier("power-mode-\(mode.rawValue)")
    }

    private var batterySettingsFallback: some View {
        Button {
            SettingsWindowAccess.openBatterySettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DuoStatusStyle.muted)

                Text(localization.string("power.open-system-settings"))
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DuoStatusStyle.muted)
            }
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("open-battery-settings")
    }

    private func mode(for scope: PowerSourceScope) -> PowerMode? {
        switch scope {
        case .battery:
            return status.batteryMode
        case .powerAdapter:
            return status.adapterMode
        }
    }

    private func localizedMode(_ mode: PowerMode?) -> String {
        guard let mode else {
            return localization.string("status.unavailable")
        }

        return localization.string(mode.localizationKey)
    }

    private func localizedScope(_ scope: PowerSourceScope?) -> String {
        guard let scope else {
            return localization.string("status.unavailable")
        }

        return localization.string(scope.localizationKey)
    }
}

private extension PowerMode {
    var systemImageName: String {
        switch self {
        case .automatic:
            return "battery.100"
        case .lowPower:
            return "battery.25"
        case .highPower:
            return "bolt.fill"
        }
    }
}
