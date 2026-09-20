//
//  SettingsView.swift
//  mac-duo-status
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var statusStore: SystemStatusStore
    @EnvironmentObject private var controls: ControlCoordinator

    var body: some View {
        Form {
            Section {
                Picker(
                    localization.string("settings.language"),
                    selection: $localization.language
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(localization.displayName(for: language))
                            .tag(language)
                    }
                }
                .accessibilityIdentifier("language-picker")

                HStack(spacing: 8) {
                    Toggle(
                        localization.string("settings.launch-at-login"),
                        isOn: launchAtLoginBinding
                    )

                    if preferences.isUpdatingLaunchAtLogin {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(
                                localization.string("settings.processing")
                            )
                        Text(localization.string("settings.processing"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(preferences.isUpdatingLaunchAtLogin)

                Toggle(
                    localization.string("settings.colored-icon"),
                    isOn: $preferences.usesColor
                )
            } header: {
                Text(localization.string("settings.general"))
            }

            Section {
                HealthMetricSelector(
                    selection: Binding(
                        get: { preferences.healthMetric },
                        set: { statusStore.setHealthMetric($0) }
                    )
                )
            } header: {
                Text(localization.string("settings.indicators"))
            }

            Section {
                ForEach(StatusSection.allCases) { section in
                    Toggle(
                        localization.string(section.localizationKey),
                        isOn: sectionBinding(for: section)
                    )
                }
            } header: {
                Text(localization.string("settings.default-sections"))
            }

            Section {
                PowerAuthorizationView(compact: true)
            } header: {
                Text(localization.string("power.advanced"))
            }

        }
        .formStyle(.grouped)
        .frame(width: adaptiveSettingsWidth)
        .padding()
    }

    private var adaptiveSettingsWidth: CGFloat {
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let metricLabelsWidth = HealthMetric.allCases.reduce(0) { width, metric in
            width + DuoStatusStyle.textWidth(
                localization.string(metric.localizationKey),
                font: bodyFont
            )
        }
        let longestLabelWidth = [
            localization.string("settings.launch-at-login"),
            localization.string("settings.colored-icon"),
            localization.string("settings.default-sections"),
            localization.string("power.advanced")
        ].map {
            DuoStatusStyle.textWidth($0, font: headerFont)
        }.max() ?? 0

        let metricSelectorWidth = metricLabelsWidth + 3 * 28 + 48
        let formRowWidth = longestLabelWidth + 220
        return DuoStatusStyle.clamped(
            max(metricSelectorWidth, formRowWidth),
            min: DuoStatusStyle.settingsMinWidth,
            max: DuoStatusStyle.settingsMaxWidth
        )
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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                preferences.launchAtLogin
            },
            set: { enabled in
                Task { @MainActor in
                    await preferences.setLaunchAtLogin(enabled)
                }
            }
        )
    }

}
