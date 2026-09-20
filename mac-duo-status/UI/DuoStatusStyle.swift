//
//  DuoStatusStyle.swift
//  mac-duo-status
//

import AppKit
import SwiftUI

enum DuoStatusStyle {
    static let accent = Color(red: 0.04, green: 0.43, blue: 0.96)
    static let success = Color(red: 0.22, green: 0.72, blue: 0.31)
    static let muted = Color.primary.opacity(0.58)
    static let subtle = Color.primary.opacity(0.40)
    static let divider = Color.primary.opacity(0.11)
    static let cardFill = Color(
        nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.white.withAlphaComponent(0.58)
        }
    )
    static let cardStroke = Color.primary.opacity(0.10)
    static let controlFill = Color.primary.opacity(0.075)
    static let trackFill = Color.primary.opacity(0.10)

    static let panelCornerRadius: CGFloat = 22
    static let cardCornerRadius: CGFloat = 17
    static let panelMinWidth: CGFloat = 340
    static let panelMaxWidth: CGFloat = 560
    static let panelPadding: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let settingsMinWidth: CGFloat = 440
    static let settingsMaxWidth: CGFloat = 680

    static let quickAnimation = Animation.easeInOut(duration: 0.18)
    static let pageAnimation = Animation.easeInOut(duration: 0.24)

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    static func clamped(
        _ width: CGFloat,
        min minimum: CGFloat,
        max maximum: CGFloat
    ) -> CGFloat {
        min(max(width, minimum), maximum)
    }
}
