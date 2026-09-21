//
//  HealthMetricSelector.swift
//  mac-duo-status
//

import SwiftUI

struct HealthMetricSelector: View {
    @EnvironmentObject private var localization: LocalizationStore

    @Binding var selection: HealthMetric

    init(selection: Binding<HealthMetric>) {
        _selection = selection
    }

    var body: some View {
        Group {
            if #available(macOS 27.0, *) {
                picker
                    .pickerStyle(.tabs)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
            } else {
                picker
                    .pickerStyle(.segmented)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("health-metric-selector")
    }

    private var picker: some View {
        Picker(selection: $selection) {
            metricOptions
        } label: {
            Text(localization.string("settings.indicators"))
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("health-metric-selector")
    }

    private var metricOptions: some View {
        ForEach(HealthMetric.allCases) { metric in
            Text(localization.string(metric.localizationKey))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .tag(metric)
                .accessibilityIdentifier("health-metric-\(metric.rawValue)")
        }
    }
}
