//
//  CombinedStatusIcon.swift
//  mac-duo-status
//

import AppKit
import SwiftUI

enum BatteryIconColor: Equatable {
    case white
    case green
    case yellow
    case red

    var nsColor: NSColor {
        switch self {
        case .white:
            return .white
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .red:
            return .systemRed
        }
    }
}

enum BatteryIconColorResolver {
    static func resolve(
        for battery: BatteryStatus,
        usesColor: Bool
    ) -> BatteryIconColor {
        guard usesColor else {
            return .white
        }

        if battery.isCharging == true {
            return .green
        }

        if battery.isLowPowerModeEnabled == true {
            return .yellow
        }

        if battery.isCharging == false,
           battery.isLowPowerModeEnabled == false,
           let chargeFraction = battery.chargeFraction,
           chargeFraction < 0.2 {
            return .red
        }

        return .white
    }
}

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
        Image(nsImage: StatusIconRenderer.image(
            snapshot: snapshot,
            size: size,
            usesColor: usesColor
        ))
        .interpolation(.high)
        .frame(width: size, height: size)
        .fixedSize()
        .accessibilityLabel("Duo Status")
    }
}

private enum StatusIconRenderer {
    static func image(
        snapshot: SystemStatusSnapshot,
        size: CGFloat,
        usesColor: Bool
    ) -> NSImage {
        let canvasSize = max(size, 1)
        let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))

        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.saveGState()
        defer { context.restoreGState() }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        drawBattery(
            in: context,
            snapshot: snapshot,
            size: canvasSize,
            usesColor: usesColor
        )
        drawNetwork(
            in: context,
            kind: snapshot.network.kind,
            size: canvasSize
        )
        drawHealth(
            in: context,
            dotCount: snapshot.health.dotCount,
            size: canvasSize
        )

        return image
    }

    private static func drawBattery(
        in context: CGContext,
        snapshot: SystemStatusSnapshot,
        size: CGFloat,
        usesColor: Bool
    ) {
        // Geometry follows the 284 × 284 reference, with AppKit's upward Y axis.
        let center = CGPoint(x: size * 145 / 284, y: size * 144 / 284)
        let radius = size * 107 / 284
        let lineWidth = size * 17 / 284
        let startAngle = radians(210)
        let fullSweep = radians(240)
        let endAngle = startAngle - fullSweep

        strokeArc(
            in: context,
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true,
            color: nsColor(.white, alpha: 0.38),
            lineWidth: lineWidth
        )

        guard let progress = snapshot.battery.chargeFraction else {
            return
        }

        let boundedProgress = min(max(progress, 0), 1)
        guard boundedProgress > 0 else {
            return
        }

        strokeArc(
            in: context,
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: startAngle - fullSweep * boundedProgress,
            clockwise: true,
            color: batteryColor(for: snapshot, usesColor: usesColor),
            lineWidth: lineWidth
        )
    }

    private static func drawNetwork(
        in context: CGContext,
        kind: NetworkKind,
        size: CGFloat
    ) {
        let color = NSColor.white

        if kind == .wifi {
            drawWiFi(in: context, size: size, color: color)
            return
        }

        drawSystemSymbol(
            kind.systemImageName,
            in: context,
            size: size,
            color: color
        )
    }

    private static func drawWiFi(
        in context: CGContext,
        size: CGFloat,
        color: NSColor
    ) {
        let unit = size / 284
        let center = CGPoint(x: 145 * unit, y: 112 * unit)

        // Both arcs share the fan's origin, keeping the gaps even.
        for radius: CGFloat in [63, 37] {
            strokeArc(
                in: context,
                center: center,
                radius: radius * unit,
                startAngle: radians(133),
                endAngle: radians(47),
                clockwise: true,
                color: color,
                lineWidth: 14 * unit
            )
        }

        // Rounded fan tip, rather than the detached circular dot.
        let tip = CGMutablePath()
        tip.move(to: CGPoint(x: 134 * unit, y: 124 * unit))
        tip.addQuadCurve(to: CGPoint(x: 156 * unit, y: 124 * unit),
                         control: CGPoint(x: 145 * unit, y: 134 * unit))
        tip.addQuadCurve(to: CGPoint(x: 157 * unit, y: 118 * unit),
                         control: CGPoint(x: 160 * unit, y: 121 * unit))
        tip.addLine(to: CGPoint(x: 148 * unit, y: 109 * unit))
        tip.addQuadCurve(to: CGPoint(x: 142 * unit, y: 109 * unit),
                         control: CGPoint(x: 145 * unit, y: 106 * unit))
        tip.addLine(to: CGPoint(x: 133 * unit, y: 118 * unit))
        tip.addQuadCurve(to: CGPoint(x: 134 * unit, y: 124 * unit),
                         control: CGPoint(x: 130 * unit, y: 121 * unit))
        tip.closeSubpath()
        context.setFillColor(color.cgColor)
        context.addPath(tip)
        context.fillPath()
    }

    private static func drawSystemSymbol(
        _ name: String,
        in context: CGContext,
        size: CGFloat,
        color: NSColor
    ) {
        guard let baseImage = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        ) else {
            return
        }

        let pointSize = max(size * 0.30, 7)
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .semibold
        )
        let symbol = baseImage.withSymbolConfiguration(configuration) ?? baseImage
        let symbolSize = symbol.size
        let rect = CGRect(
            x: (size - symbolSize.width) * 0.5,
            y: size * 0.37,
            width: symbolSize.width,
            height: symbolSize.height
        )

        var proposedRect = NSRect(origin: .zero, size: symbol.size)
        guard let mask = symbol.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            symbol.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return
        }

        // Draw the SF Symbol as an alpha mask so color mode is preserved too.
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect, mask: mask)
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    private static func drawHealth(
        in context: CGContext,
        dotCount: Int?,
        size: CGFloat
    ) {
        let activeColor = NSColor.white

        let inactiveColor = nsColor(.white, alpha: dotCount == nil ? 0.45 : 0.28)
        let unit = size / 284
        let dotRadius = 11.5 * unit
        let centers: [CGPoint] = [
            CGPoint(x: 91, y: 54),
            CGPoint(x: 126, y: 40),
            CGPoint(x: 166, y: 40),
            CGPoint(x: 202, y: 54)
        ]

        for (index, center) in centers.enumerated() {
            let color = index < (dotCount ?? 0) ? activeColor : inactiveColor
            fillCircle(
                in: context,
                center: CGPoint(x: center.x * unit, y: center.y * unit),
                radius: dotRadius,
                color: color
            )
        }
    }

    private static func batteryColor(
        for snapshot: SystemStatusSnapshot,
        usesColor: Bool
    ) -> NSColor {
        BatteryIconColorResolver.resolve(
            for: snapshot.battery,
            usesColor: usesColor
        ).nsColor
    }

    private static func strokeArc(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        clockwise: Bool,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        let path = CGMutablePath()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise,
            transform: .identity
        )

        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.strokePath()
    }

    private static func fillCircle(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color: NSColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(color.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
    }

    private static func nsColor(_ color: NSColor, alpha: CGFloat) -> NSColor {
        color.withAlphaComponent(alpha)
    }

    private static func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }
}
