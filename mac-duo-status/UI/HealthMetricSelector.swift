//
//  HealthMetricSelector.swift
//  mac-duo-status
//

import SwiftUI

struct HealthMetricSelector: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: HealthMetric

    @State private var hoveredMetric: HealthMetric?
    @Namespace private var selectionAnimation

    init(selection: Binding<HealthMetric>) {
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HealthMetric.allCases) { metric in
                metricButton(for: metric)
            }
        }
        .padding(3)
        .background(
            DuoStatusStyle.controlFill,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DuoStatusStyle.cardStroke, lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }

    private func metricButton(for metric: HealthMetric) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : DuoStatusStyle.quickAnimation) {
                selection = metric
            }
        } label: {
            Text(metric.localizedTitle)
                .font(.system(size: 11, weight: selection == metric ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .foregroundStyle(selection == metric ? .primary : DuoStatusStyle.muted)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background {
                    if selection == metric {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                            .shadow(color: Color.black.opacity(0.10), radius: 2, y: 1)
                            .matchedGeometryEffect(
                                id: "health-metric-selection",
                                in: selectionAnimation
                            )
                    } else if hoveredMetric == metric {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
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
}
