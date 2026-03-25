import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private struct StatusVisualState {
        let alpha: CGFloat
        let showsWarning: Bool
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = RustEngineBridge()
    private let updater = ReleaseUpdater()
    private let configStore = ConfigStore()
    private lazy var baseStatusImage = loadBaseStatusImage()
    private var config = AppConfig()
    private var snapshot = EngineSnapshot.empty
    private var refreshTimer: Timer?
    private var launchAtLoginError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? AppSupportPaths.ensureApplicationSupportDirectories()
        DiagnosticsStore.log("application launched")

        config = configStore.load()
        statusItem.button?.toolTip = "MacKeyMap"

        engine.start()
        applyConfigToEngine()
        syncLaunchAtLogin()
        refreshState()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(handleRefreshTimer(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticsStore.log("application terminating")
        refreshTimer?.invalidate()
        engine.stop()
    }

    private func refreshState() {
        if let snapshot = engine.fetchSnapshot() {
            self.snapshot = snapshot
        }
        rebuildMenu()
        updateStatusItem()
    }

    @objc
    private func handleRefreshTimer(_ timer: Timer) {
        refreshState()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let image = makeStatusImage(for: currentStatusState()) {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "MK"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let enabledItem = NSMenuItem(
            title: "Enable Remapping",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = config.enabled ? .on : .off
        menu.addItem(enabledItem)

        let presetItem = NSMenuItem(title: "Preset: Standard PC to Mac", action: nil, keyEquivalent: "")
        presetItem.isEnabled = false
        menu.addItem(presetItem)

        if let startupError = snapshot.startupError {
            let errorItem = NSMenuItem(title: "Engine Error: \(startupError)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())
        menu.addItem(makeOverridesItem())
        menu.addItem(makeDevicesItem())

        menu.addItem(.separator())
        menu.addItem(makePermissionStatusItem())

        menu.addItem(makeDiagnosticsItem())

        let requestPermissions = NSMenuItem(
            title: "Open Required Settings",
            action: #selector(requestPermissions(_:)),
            keyEquivalent: ""
        )
        requestPermissions.target = self
        menu.addItem(requestPermissions)

        let inputMonitoringItem = NSMenuItem(
            title: "Open Input Monitoring Settings",
            action: #selector(openInputMonitoringSettings(_:)),
            keyEquivalent: ""
        )
        inputMonitoringItem.target = self
        menu.addItem(inputMonitoringItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = config.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        if let launchAtLoginError {
            let errorItem = NSMenuItem(title: "Login Item Error: \(launchAtLoginError)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MacKeyMap", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeOverridesItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Modifier Overrides", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let leftSwap = NSMenuItem(
            title: "Swap Left Alt and Win",
            action: #selector(toggleSwapLeft(_:)),
            keyEquivalent: ""
        )
        leftSwap.target = self
        leftSwap.state = config.overrides.swapLeftAltWin ? .on : .off
        submenu.addItem(leftSwap)

        let rightSwap = NSMenuItem(
            title: "Swap Right Alt and Win",
            action: #selector(toggleSwapRight(_:)),
            keyEquivalent: ""
        )
        rightSwap.target = self
        rightSwap.state = config.overrides.swapRightAltWin ? .on : .off
        submenu.addItem(rightSwap)

        let disableContext = NSMenuItem(
            title: "Disable Context Menu Remap",
            action: #selector(toggleContextMenuRemap(_:)),
            keyEquivalent: ""
        )
        disableContext.target = self
        disableContext.state = config.overrides.disableContextMenuRemap ? .on : .off
        submenu.addItem(disableContext)

        item.submenu = submenu
        return item
    }

    private func makeDevicesItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Connected Keyboards", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let devices = snapshot.devices.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.id < rhs.id
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if devices.isEmpty {
            let title: String
            if snapshot.permissions.hidListen != "granted" {
                title = "Input Monitoring not granted"
            } else {
                title = "No keyboards detected"
            }
            let emptyItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for device in devices {
                var title = device.name
                if device.builtIn {
                    title += " (Built-in)"
                } else if !device.transport.isEmpty {
                    title += " [\(device.transport)]"
                }

                let deviceItem = NSMenuItem(title: title, action: #selector(toggleDevice(_:)), keyEquivalent: "")
                deviceItem.target = self
                deviceItem.state = device.selected ? .on : .off
                deviceItem.representedObject = device.id
                if let error = device.lastError, device.selected {
                    deviceItem.toolTip = error
                } else if device.active {
                    if device.remapMode == "system" {
                        deviceItem.toolTip = "System remap active"
                    }
                } else if device.selected {
                    deviceItem.toolTip = "Selected but system remap is not active"
                }
                submenu.addItem(deviceItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func makeDiagnosticsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let openLogsItem = NSMenuItem(
            title: "Open Diagnostics Folder",
            action: #selector(openDiagnosticsFolder(_:)),
            keyEquivalent: ""
        )
        openLogsItem.target = self
        submenu.addItem(openLogsItem)

        let exportItem = NSMenuItem(
            title: "Export Diagnostics…",
            action: #selector(exportDiagnostics(_:)),
            keyEquivalent: ""
        )
        exportItem.target = self
        submenu.addItem(exportItem)

        item.submenu = submenu
        return item
    }

    private func makePermissionStatusItem() -> NSMenuItem {
        let title = "Permissions: Input Monitoring \(snapshot.permissions.hidListen)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func applyConfigToEngine() {
        engine.setGlobalEnabled(config.enabled)
        engine.setOverrides(config.overrides)
        for (identifier, enabled) in config.deviceSelections {
            engine.setDeviceEnabled(id: identifier, enabled: enabled)
        }
    }

    private func saveConfig() {
        configStore.save(config)
    }

    private func syncLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if config.launchAtLogin {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
                DiagnosticsStore.log("launch-at-login sync failed: \(error.localizedDescription)")
            }
        } else {
            launchAtLoginError = "Launch at login requires macOS 13+"
        }
    }

    @objc
    private func toggleEnabled(_ sender: NSMenuItem) {
        config.enabled.toggle()
        engine.setGlobalEnabled(config.enabled)
        saveConfig()
        DiagnosticsStore.log("global remapping toggled to \(config.enabled)")
        refreshState()
    }

    @objc
    private func toggleSwapLeft(_ sender: NSMenuItem) {
        config.overrides.swapLeftAltWin.toggle()
        engine.setOverrides(config.overrides)
        saveConfig()
        DiagnosticsStore.log("swap left Alt/Win toggled to \(config.overrides.swapLeftAltWin)")
        refreshState()
    }

    @objc
    private func toggleSwapRight(_ sender: NSMenuItem) {
        config.overrides.swapRightAltWin.toggle()
        engine.setOverrides(config.overrides)
        saveConfig()
        DiagnosticsStore.log("swap right Alt/Win toggled to \(config.overrides.swapRightAltWin)")
        refreshState()
    }

    @objc
    private func toggleContextMenuRemap(_ sender: NSMenuItem) {
        config.overrides.disableContextMenuRemap.toggle()
        engine.setOverrides(config.overrides)
        saveConfig()
        DiagnosticsStore.log("context menu remap toggled to \(!config.overrides.disableContextMenuRemap)")
        refreshState()
    }

    @objc
    private func toggleDevice(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else {
            return
        }
        let currentValue = snapshot.devices.first(where: { $0.id == identifier })?.selected ?? false
        let newValue = !currentValue
        config.deviceSelections[identifier] = newValue
        engine.setDeviceEnabled(id: identifier, enabled: newValue)
        saveConfig()
        DiagnosticsStore.log("device \(identifier) toggled to \(newValue)")
        refreshState()
    }

    @objc
    private func requestPermissions(_ sender: NSMenuItem) {
        DiagnosticsStore.log("requesting Input Monitoring permission")
        engine.requestPermissions()
        refreshState()
        if snapshot.permissions.hidListen != "granted" {
            openInputMonitoringSettings(sender)
        }
    }

    @objc
    private func openInputMonitoringSettings(_ sender: NSMenuItem) {
        DiagnosticsStore.log("opening Input Monitoring settings")
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @objc
    private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        config.launchAtLogin.toggle()
        syncLaunchAtLogin()
        saveConfig()
        DiagnosticsStore.log("launch at login toggled to \(config.launchAtLogin)")
        refreshState()
    }

    @objc
    private func checkForUpdates(_ sender: NSMenuItem) {
        Task { @MainActor in
            await updater.checkForUpdates()
        }
    }

    @objc
    private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    @objc
    private func openDiagnosticsFolder(_ sender: NSMenuItem) {
        do {
            try AppSupportPaths.ensureApplicationSupportDirectories()
            DiagnosticsStore.log("opening diagnostics folder")
            NSWorkspace.shared.activateFileViewerSelecting([AppSupportPaths.logsDirectory])
        } catch {
            presentErrorAlert(title: "Unable to open diagnostics folder", error: error)
        }
    }

    @objc
    private func exportDiagnostics(_ sender: NSMenuItem) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = DiagnosticsStore.suggestedExportFilename()
        panel.allowedContentTypes = [.zip]

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            try DiagnosticsStore.exportArchive(
                to: destinationURL,
                snapshot: snapshot,
                config: config,
                launchAtLoginError: launchAtLoginError
            )
            DiagnosticsStore.log("exported diagnostics to \(destinationURL.path)")
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        } catch {
            DiagnosticsStore.log("diagnostics export failed: \(error.localizedDescription)")
            presentErrorAlert(title: "Unable to export diagnostics", error: error)
        }
    }

    private func openSettingsURL(_ value: String) {
        guard let url = URL(string: value) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func currentStatusState() -> StatusVisualState {
        let activeRemap = config.enabled
            && snapshot.permissions.hidListen == "granted"
            && snapshot.startupError == nil
            && snapshot.devices.contains(where: { $0.active })

        let warningVisible = snapshot.permissions.hidListen != "granted"
            || snapshot.startupError != nil
            || snapshot.devices.contains(where: { $0.selected && $0.lastError != nil })

        return StatusVisualState(
            alpha: activeRemap ? 1.0 : 0.42,
            showsWarning: warningVisible
        )
    }

    private func loadBaseStatusImage() -> NSImage? {
        guard let image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: "MacKeyMap"
        )
        else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private func makeStatusImage(for state: StatusVisualState) -> NSImage? {
        guard let baseStatusImage else {
            return nil
        }

        let imageSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: imageSize, flipped: false) { [self, baseStatusImage] rect in
            let iconRect = rect.insetBy(dx: 1.0, dy: 1.0)
            baseStatusImage.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: state.alpha,
                respectFlipped: true,
                hints: nil
            )
            if state.showsWarning {
                self.drawWarningBadge(in: rect)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawWarningBadge(in rect: NSRect) {
        NSColor.labelColor.setFill()

        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: rect.maxX - 4.0, y: rect.minY + 6.0))
        triangle.line(to: NSPoint(x: rect.maxX - 6.9, y: rect.minY + 1.15))
        triangle.line(to: NSPoint(x: rect.maxX - 1.1, y: rect.minY + 1.15))
        triangle.close()
        triangle.fill()
    }

    private func presentErrorAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
