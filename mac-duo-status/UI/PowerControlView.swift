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

    private var status: PowerPolicyStatus {
        statusStore.snapshot.powerPolicy
    }

    private var availableModes: [PowerMode] {
        status.capabilities.supportedPowerModes.sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let activeMode = status.activeMode {
                StatusValueRow(
                    title: NSLocalizedString("power.active-mode", comment: ""),
                    value: NSLocalizedString(activeMode.localizationKey, comment: "")
                )
            }

            Divider()
                .overlay(DuoStatusStyle.divider)

            energyModeControls

            chargeLimitControls

            PowerAuthorizationView()
                .padding(.top, 2)
        }
        .onAppear {
            selectedChargeLimit = Double(status.chargeLimit ?? 80)
        }
        .onChange(of: status.chargeLimit) { newValue in
            if let newValue {
                selectedChargeLimit = Double(newValue)
            }
        }
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

            if availableModes.isEmpty {
                StatusValueRow(
                    title: NSLocalizedString("power.scope.battery", comment: ""),
                    value: localizedMode(status.batteryMode)
                )
                StatusValueRow(
                    title: NSLocalizedString("power.scope.adapter", comment: ""),
                    value: localizedMode(status.adapterMode)
                )
            } else {
                modePicker(
                    scope: .battery,
                    currentMode: status.batteryMode
                )
                modePicker(
                    scope: .powerAdapter,
                    currentMode: status.adapterMode
                )
            }
        }
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

                    Text("(Int(selectedChargeLimit.rounded()))%")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button(NSLocalizedString("common.apply", comment: "")) {
                        Task {
                            await controls.setChargeLimit(Int(selectedChargeLimit.rounded()))
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

    @ViewBuilder
    private func modePicker(
        scope: PowerSourceScope,
        currentMode: PowerMode?
    ) -> some View {
        if let currentMode {
            Picker(
                NSLocalizedString(scope.localizationKey, comment: ""),
                selection: Binding(
                    get: { currentMode },
                    set: { newMode in
                        Task {
                            await controls.setPowerMode(newMode, scope: scope)
                        }
                    }
                )
            ) {
                ForEach(availableModes) { mode in
                    Text(NSLocalizedString(mode.localizationKey, comment: ""))
                        .tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(controls.powerOperationState.isPending)
        } else {
            StatusValueRow(
                title: NSLocalizedString(scope.localizationKey, comment: ""),
                value: NSLocalizedString("status.unavailable", comment: "")
            )
        }
    }

    private func localizedMode(_ mode: PowerMode?) -> String {
        guard let mode else {
            return NSLocalizedString("status.unavailable", comment: "")
        }

        return NSLocalizedString(mode.localizationKey, comment: "")
    }
}
