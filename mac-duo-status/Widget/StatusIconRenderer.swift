//
//  StatusIconRenderer.swift
//  mac-duo-status
//

import AppKit
import Foundation

enum StatusIconRenderer {
    static func image(
        presentation: StatusIconPresentation,
        size: CGFloat,
        usesColor: Bool,
        batteryColorOverride: NSColor? = nil,
        foregroundColor: NSColor = .white
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
            presentation: presentation,
            size: canvasSize,
            usesColor: usesColor,
            batteryColorOverride: batteryColorOverride,
            foregroundColor: foregroundColor
        )
        drawNetwork(
            in: context,
            kind: presentation.networkKind,
            size: canvasSize,
            foregroundColor: foregroundColor
        )
        drawHealth(
            in: context,
            dotCount: presentation.healthDotCount,
            size: canvasSize,
            foregroundColor: foregroundColor
        )

        return image
    }

    private static func drawBattery(
        in context: CGContext,
        presentation: StatusIconPresentation,
        size: CGFloat,
        usesColor: Bool,
        batteryColorOverride: NSColor?,
        foregroundColor: NSColor
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
            color: foregroundColor.withAlphaComponent(0.38),
            lineWidth: lineWidth
        )

        guard presentation.batteryIsAvailable,
              presentation.batteryHasBuiltInBattery,
              let progress = presentation.batteryChargeFraction
        else {
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
            color: batteryColor(
                for: presentation,
                usesColor: usesColor,
                override: batteryColorOverride,
                foregroundColor: foregroundColor
            ),
            lineWidth: lineWidth
        )
    }

    private static func drawNetwork(
        in context: CGContext,
        kind: WidgetNetworkKind,
        size: CGFloat,
        foregroundColor: NSColor
    ) {
        if kind == .wifi {
            drawWiFi(
                in: context,
                size: size,
                color: foregroundColor
            )
            return
        }

        drawSystemSymbol(
            kind.systemImageName,
            in: context,
            size: size,
            color: foregroundColor
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
        tip.addQuadCurve(
            to: CGPoint(x: 156 * unit, y: 124 * unit),
            control: CGPoint(x: 145 * unit, y: 134 * unit)
        )
        tip.addQuadCurve(
            to: CGPoint(x: 157 * unit, y: 118 * unit),
            control: CGPoint(x: 160 * unit, y: 121 * unit)
        )
        tip.addLine(to: CGPoint(x: 148 * unit, y: 109 * unit))
        tip.addQuadCurve(
            to: CGPoint(x: 142 * unit, y: 109 * unit),
            control: CGPoint(x: 145 * unit, y: 106 * unit)
        )
        tip.addLine(to: CGPoint(x: 133 * unit, y: 118 * unit))
        tip.addQuadCurve(
            to: CGPoint(x: 134 * unit, y: 124 * unit),
            control: CGPoint(x: 130 * unit, y: 121 * unit)
        )
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

        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect, mask: mask)
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    private static func drawHealth(
        in context: CGContext,
        dotCount: Int?,
        size: CGFloat,
        foregroundColor: NSColor
    ) {
        let inactiveColor = foregroundColor.withAlphaComponent(
            dotCount == nil ? 0.45 : 0.28
        )
        let unit = size / 284
        let dotRadius = 11.5 * unit
        let centers: [CGPoint] = [
            CGPoint(x: 91, y: 54),
            CGPoint(x: 126, y: 40),
            CGPoint(x: 166, y: 40),
            CGPoint(x: 202, y: 54)
        ]

        for (index, center) in centers.enumerated() {
            let color = index < (dotCount ?? 0)
                ? foregroundColor
                : inactiveColor
            fillCircle(
                in: context,
                center: CGPoint(x: center.x * unit, y: center.y * unit),
                radius: dotRadius,
                color: color
            )
        }
    }

    private static func batteryColor(
        for presentation: StatusIconPresentation,
        usesColor: Bool,
        override: NSColor?,
        foregroundColor: NSColor
    ) -> NSColor {
        if let override {
            return override
        }

        let color = BatteryIconColorResolver.resolve(
            chargeFraction: presentation.batteryChargeFraction,
            isCharging: presentation.batteryIsCharging,
            isLowPowerModeEnabled: presentation.batteryIsLowPowerModeEnabled,
            usesColor: usesColor
        )

        return color == .white ? foregroundColor : color.nsColor
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

    private static func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }
}
