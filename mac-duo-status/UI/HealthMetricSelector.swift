//
//  HealthMetricSelector.swift
//  mac-duo-status
//

import SwiftUI

struct HealthMetricSelector: View {
    @EnvironmentObject private var localization: LocalizationStore

    private let compact: Bool
    @Binding var selection: HealthMetric

    init(
        compact: Bool = false,
        selection: Binding<HealthMetric>
    ) {
        self.compact = compact
        _selection = selection
    }

    var body: some View {
        Group {
            if #available(macOS 27.0, *) {
                capsuleSurface(
                    picker
                        .pickerStyle(.tabs)
                        .controlSize(.large)
                        .buttonSizing(.flexible)
                )
            } else {
                capsuleSurface(
                    picker
                        .pickerStyle(.segmented)
                )
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

    @ViewBuilder
    private func capsuleSurface<Content: View>(_ content: Content) -> some View {
        let horizontalPadding: CGFloat = compact ? 4 : 6

        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background {
                if #available(macOS 26.0, *) {
                    Capsule(style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(
                            .clear,
                            in: Capsule(style: .continuous)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(0.12),
                                    lineWidth: 0.75
                                )
                        }
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(0.12),
                                    lineWidth: 0.75
                                )
                        }
                        .shadow(
                            color: Color.black.opacity(0.12),
                            radius: 6,
                            y: 2
                        )
                }
            }
            .clipShape(Capsule(style: .continuous))
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
