//
//  SettingsView.swift
//  mac-duo-status
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var statusStore: SystemStatusStore
    @EnvironmentObject private var controls: ControlCoordinator

    var body: some View {
        Form {
            Section {
                Toggle(
                    NSLocalizedString("settings.launch-at-login", comment: ""),
                    isOn: $preferences.launchAtLogin
                )

                Toggle(
                    NSLocalizedString("settings.colored-icon", comment: ""),
                    isOn: $preferences.usesColor
                )
            } header: {
                Text(NSLocalizedString("settings.general", comment: ""))
            }

            Section {
                HealthMetricSelector(
                    selection: $preferences.healthMetric
                )
                .onChange(of: preferences.healthMetric) { newMetric in
                    statusStore.setHealthMetric(newMetric)
                }
            } header: {
                Text(NSLocalizedString("settings.indicators", comment: ""))
            }

            Section {
                ForEach(StatusSection.allCases) { section in
                    Toggle(
                        section.localizedTitle,
                        isOn: sectionBinding(for: section)
                    )
                }
            } header: {
                Text(NSLocalizedString("settings.default-sections", comment: ""))
            }

            Section {
                PowerAuthorizationView(compact: true)
            } header: {
                Text(NSLocalizedString("power.advanced", comment: ""))
            }

        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }

    private func sectionBinding(for section: StatusSection) -> Binding<Bool> {
        Binding(
            get: {
                preferences.isExpanded(section)
            },
            set: { newValue in
                preferences.setExpanded(newValue, for: section)
            }
        )
    }

}
