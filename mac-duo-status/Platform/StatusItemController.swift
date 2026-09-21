//
//  StatusItemController.swift
//  mac-duo-status
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, ObservableObject {
    private let statusStore: SystemStatusStore
    private let preferencesStore: PreferencesStore
    private let controlCoordinator: ControlCoordinator
    private let localizationStore: LocalizationStore

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    init(
        statusStore: SystemStatusStore,
        preferencesStore: PreferencesStore,
        controlCoordinator: ControlCoordinator,
        localizationStore: LocalizationStore
    ) {
        self.statusStore = statusStore
        self.preferencesStore = preferencesStore
        self.controlCoordinator = controlCoordinator
        self.localizationStore = localizationStore
        super.init()

        install()
    }

    private func install() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "com.shishishi3.mac-duo-status.menu-bar"

        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleStatusItemAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Duo Status"
        button.setAccessibilityLabel("Duo Status")

        statusItem = item
        popover = makePopover()
        updateIcon()
        observeChanges()
    }

    private func makePopover() -> NSPopover {
        let content = StatusPopoverView(
            batteryStatusStore: statusStore.batteryStatusStore,
            powerPolicyStatusStore: statusStore.powerPolicyStatusStore
        )
            .environmentObject(statusStore)
            .environmentObject(preferencesStore)
            .environmentObject(controlCoordinator)
            .environmentObject(localizationStore)

        let hostingController = NSHostingController(rootView: content)
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = [.preferredContentSize]
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        return popover
    }

    private func observeChanges() {
        statusStore.$snapshot
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        preferencesStore.$usesColor
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem?.button else {
            return
        }

        button.image = StatusIconRenderer.image(
            presentation: StatusIconPresentation(snapshot: statusStore.snapshot),
            size: 20,
            usesColor: preferencesStore.usesColor,
            foregroundColor: .white
        )
    }

    @objc
    private func handleStatusItemAction(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else {
            return
        }

        popover?.performClose(nil)

        let menu = NSMenu()
        menu.autoenablesItems = false

        let settingsItem = NSMenuItem(
            title: localizationStore.string("settings.open"),
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: localizationStore.string("common.quit"),
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
            in: button
        )
    }

    @objc
    private func openSettings() {
        SettingsWindowAccess.openLegacySettings()
    }

    @objc
    private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
