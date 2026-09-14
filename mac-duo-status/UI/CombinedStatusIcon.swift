//
//  CombinedStatusIcon.swift
//  mac-duo-status
//

import SwiftUI

struct CombinedStatusIcon: View {
    let snapshot: SystemStatusSnapshot
    let size: CGFloat
    let usesColor: Bool

    init(
        snapshot: SystemStatusSnapshot,
        size: CGFloat = 32,
        usesColor: Bool = false
    ) {
        self.snapshot = snapshot
        self.size = size
        self.usesColor = usesColor
    }

    var body: some View {
        ZStack {
            BatteryArc(
                progress: snapshot.battery.chargeFraction,
                color: batteryColor
            )

            Image(systemName: snapshot.network.kind.systemImageName)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(networkColor)
                .offset(y: size * 0.03)

            HStack(spacing: size * 0.07) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(
                            index < (snapshot.health.dotCount ?? 0)
                                ? healthColor
                                : Color.secondary.opacity(0.25)
                        )
                        .frame(width: size * 0.09, height: size * 0.09)
                }
            }
            .offset(y: size * 0.34)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Duo Status")
    }

    private var batteryColor: Color {
        guard usesColor else {
            return .primary
        }

        if snapshot.battery.isCharging == true {
            return .green
        }

        if snapshot.battery.isLowPowerModeEnabled == true {
            return .yellow
        }

        if let chargeFraction = snapshot.battery.chargeFraction, chargeFraction < 0.2 {
            return .red
        }

        return .primary
    }

    private var networkColor: Color {
        usesColor ? .blue : .primary
    }

    private var healthColor: Color {
        guard usesColor else {
            return .primary
        }

        switch snapshot.health.thermalState {
        case .serious:
            return .orange
        case .critical:
            return .red
        default:
            return .primary
        }
    }
}

private struct BatteryArc: View {
    let progress: Double?
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(
                    Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            if let progress {
                Circle()
                    .trim(
                        from: 0.15,
                        to: 0.15 + 0.7 * min(max(progress, 0), 1)
                    )
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
            }
        }
    }
}
