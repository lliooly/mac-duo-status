//
//  PowerControlView.swift
//  mac-duo-status
//

import SwiftUI

struct PowerControlView: View {
    @EnvironmentObject private var controls: ControlCoordinator
    @EnvironmentObject private var statusStore: SystemStatusStore

    let onBack: () -> Void

    @State private var selectedChargeLimit = 80.0
    @State private var selectedScope: PowerSourceScope = .battery

    private var status: PowerPolicyStatus {
        statusStore.snapshot.powerPolicy
    }

    private var availableScopes: [PowerSourceScope] {
        [.battery, .powerAdapter].filter {
            status.capabilities.energyModeScopes.contains($0)
        }
    }

    private var availableModes: [PowerMode] {
        [.automatic, .lowPower, .highPower].filter {
            status.capabilities.supportedPowerModes.contains($0)
        }
    }

    private var selectedMode: PowerMode? {
        mode(for: selectedScope)
    }

    private var preferredScope: PowerSourceScope {
        currentPowerSourceScope ?? .battery
    }

    private var currentPowerSourceScope: PowerSourceScope? {
        switch statusStore.snapshot.battery.powerSource {
        case .battery:
            return .battery
        case .powerAdapter:
            return .powerAdapter
        case .unknown:
            return nil
        }
    }

    private var modeReadbackUnavailable: Bool {
        guard !availableScopes.isEmpty else {
            return true
        }

        return availableScopes.contains { mode(for: $0) == nil }
    }

    private var canEditModes: Bool {
        status.helperStatus.isAuthorized &&
            !availableScopes.isEmpty &&
            !availableModes.isEmpty &&
            selectedMode != nil &&
            !controls.powerOperationState.isPending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            StatusValueRow(
                title: NSLocalizedString("power.active-mode", comment: ""),
                value: localizedMode(status.activeMode),
                showsDivider: true
            )

            energyModeControls

            chargeLimitControls

            if !status.helperStatus.isAuthorized ||
                availableModes.isEmpty ||
                modeReadbackUnavailable {
                batterySettingsFallback
            }

            PowerAuthorizationView()
                .padding(.top, 2)
        }
        .onAppear {
            selectedChargeLimit = Double(status.chargeLimit ?? 80)
            selectedScope = availableScopes.contains(preferredScope)
                ? preferredScope
                : (availableScopes.first ?? preferredScope)
        }
        .onChange(of: status.chargeLimit) { newValue in
            if let newValue {
                selectedChargeLimit = Double(newValue)
            }
        }
        .onChange(of: statusStore.snapshot.battery.powerSource) { _ in
            synchronizeSelectedScope()
        }
    }

    private func synchronizeSelectedScope() {
        guard let currentPowerSourceScope,
              availableScopes.contains(currentPowerSourceScope)
        else {
            return
        }

        selectedScope = currentPowerSourceScope
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("common.back", comment: ""))

            Text(NSLocalizedString("power.title", comment: ""))
                .font(.system(size: 16, weight: .semibold))

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var energyModeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("power.modes", comment: ""))
                .font(.system(size: 12, weight: .semibold))

            if availableModes.isEmpty || availableScopes.isEmpty {
                readOnlyModeRows
            } else {
                scopeSelector

                if selectedMode == nil {
                    StatusValueRow(
                        title: NSLocalizedString(
                            selectedScope.localizationKey,
                            comment: ""
                        ),
                        value: NSLocalizedString("status.unavailable", comment: "")
                    )
                } else {
                    VStack(spacing: 2) {
                        ForEach(availableModes) { mode in
                            modeRow(mode, isSelected: selectedMode == mode)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scopeSelector: some View {
        if availableScopes.count > 1 {
            Picker(
                NSLocalizedString("power.scope.title", comment: ""),
                selection: $selectedScope
            ) {
                ForEach(availableScopes) { scope in
                    Text(NSLocalizedString(scope.localizationKey, comment: ""))
                        .tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("power-scope-picker")
        } else if let scope = availableScopes.first {
            HStack(spacing: 6) {
                Image(systemName: scope.systemImageName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DuoStatusStyle.muted)

                Text(NSLocalizedString(scope.localizationKey, comment: ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DuoStatusStyle.muted)
            }
        }
    }

    @ViewBuilder
    private var readOnlyModeRows: some View {
        let scopes = availableScopes.isEmpty
            ? PowerSourceScope.allCases
            : availableScopes

        ForEach(scopes) { scope in
            StatusValueRow(
                title: NSLocalizedString(scope.localizationKey, comment: ""),
                value: localizedMode(mode(for: scope))
            )
        }
    }

    private func modeRow(_ mode: PowerMode, isSelected: Bool) -> some View {
        Button {
            Task {
                await controls.setPowerMode(mode, scope: selectedScope)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.systemImageName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .white : DuoStatusStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected
                            ? DuoStatusStyle.accent
                            : Color.primary.opacity(0.08),
                        in: Circle()
                    )

                Text(NSLocalizedString(mode.localizationKey, comment: ""))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DuoStatusStyle.accent)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEditModes)
        .accessibilityIdentifier("power-mode-\(mode.rawValue)")
    }

    @ViewBuilder
    private var chargeLimitControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("power.charge-limit", comment: ""))
                .font(.system(size: 12, weight: .semibold))

            if status.chargeLimitCapability == .available,
               !status.capabilities.chargeLimitValues.isEmpty {
                HStack(spacing: 10) {
                    Slider(value: $selectedChargeLimit, in: 80...100, step: 1)

                    Text("\(Int(selectedChargeLimit.rounded()))%")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button(NSLocalizedString("common.apply", comment: "")) {
                        Task {
                            await controls.setChargeLimit(
                                Int(selectedChargeLimit.rounded())
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(controls.powerOperationState.isPending)
                }
            } else {
                StatusValueRow(
                    title: NSLocalizedString("power.current-limit", comment: ""),
                    value: status.chargeLimit.map { "\($0)%" }
                        ?? NSLocalizedString("status.unavailable", comment: "")
                )
            }
        }
    }

    private var batterySettingsFallback: some View {
        Button {
            SettingsWindowAccess.openBatterySettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DuoStatusStyle.muted)

                Text(NSLocalizedString("power.open-system-settings", comment: ""))
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DuoStatusStyle.muted)
            }
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
            return NSLocalizedString("status.unavailable", comment: "")
        }

        return NSLocalizedString(mode.localizationKey, comment: "")
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

private extension PowerSourceScope {
    var systemImageName: String {
        switch self {
        case .battery:
            return "battery.75"
        case .powerAdapter:
            return "powerplug"
        }
    }
}
