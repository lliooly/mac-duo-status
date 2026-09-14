//
//  SettingsView.swift
//  mac-duo-status
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var statusStore: SystemStatusStore

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
                Picker(
                    NSLocalizedString("health.metric", comment: ""),
                    selection: $preferences.healthMetric
                ) {
                    ForEach(HealthMetric.allCases) { metric in
                        Text(metric.localizedTitle)
                            .tag(metric)
                    }
                }
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
                Text("Duo Status")
                    .font(.headline)
                Text(NSLocalizedString("settings.skeleton-note", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(NSLocalizedString("settings.about", comment: ""))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
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
