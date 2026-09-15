//
//  SettingsWindowAccess.swift
//  mac-duo-status
//

import AppKit
import SwiftUI

struct ActivateApplicationBeforeActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            configuration.trigger()
        } label: {
            configuration.label
        }
    }
}

@MainActor
enum SettingsWindowAccess {
    static func openLegacySettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
    }
}
