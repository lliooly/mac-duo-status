//
//  HealthMetricSelector.swift
//  mac-duo-status
//

import SwiftUI

struct HealthMetricSelector: View {
    @Binding var selection: HealthMetric

    @State private var hoveredMetric: HealthMetric?

    init(selection: Binding<HealthMetric>) {
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HealthMetric.allCases) { metric in
                metricButton(for: metric)
            }
        }
        .padding(2)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .frame(maxWidth: .infinity, minHeight: 30)
    }

    private func metricButton(for metric: HealthMetric) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selection = metric
            }
        } label: {
            Text(metric.localizedTitle)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(selection == metric ? .white : .primary)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(backgroundColor(for: metric))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredMetric = isHovered ? metric : nil
        }
        .accessibilityIdentifier("health-metric-\(metric.rawValue)")
        .accessibilityAddTraits(selection == metric ? .isSelected : [])
    }

    private func backgroundColor(for metric: HealthMetric) -> Color {
        if selection == metric {
            return DuoStatusStyle.accent
        }

        if hoveredMetric == metric {
            return Color.primary.opacity(0.08)
        }

        return .clear
    }
}
