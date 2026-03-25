import AppKit
import Foundation
import ServiceManagement

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = RustEngineBridge()
    private let configStore = ConfigStore()
    private var config = AppConfig()
    private var snapshot = EngineSnapshot.empty
    private var refreshTimer: Timer?
    private var launchAtLoginError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = configStore.load()
        statusItem.button?.title = "MK"
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

        let hidGranted = snapshot.permissions.hidListen == "granted"
        let hasActiveRemap = snapshot.devices.contains { $0.active }
        let symbolName: String

        if !config.enabled {
            symbolName = "keyboard"
        } else if !hidGranted {
            symbolName = "keyboard.badge.ellipsis"
        } else if hasActiveRemap {
            symbolName = "keyboard.fill"
        } else {
            symbolName = "keyboard"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MacKeyMap") {
            image.isTemplate = true
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
        refreshState()
    }

    @objc
    private func toggleSwapLeft(_ sender: NSMenuItem) {
        config.overrides.swapLeftAltWin.toggle()
        engine.setOverrides(config.overrides)
        saveConfig()
        refreshState()
    }

    @objc
    private func toggleSwapRight(_ sender: NSMenuItem) {
        config.overrides.swapRightAltWin.toggle()
        engine.setOverrides(config.overrides)
        saveConfig()
        refreshState()
    }

    @objc
    private func toggleContextMenuRemap(_ sender: NSMenuItem) {
        config.overrides.disableContextMenuRemap.toggle()
        engine.setOverrides(config.overrides)
        saveConfig()
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
        refreshState()
    }

    @objc
    private func requestPermissions(_ sender: NSMenuItem) {
        engine.requestPermissions()
        refreshState()
        if snapshot.permissions.hidListen != "granted" {
            openInputMonitoringSettings(sender)
        }
    }

    @objc
    private func openInputMonitoringSettings(_ sender: NSMenuItem) {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @objc
    private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        config.launchAtLogin.toggle()
        syncLaunchAtLogin()
        saveConfig()
        refreshState()
    }

    @objc
    private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func openSettingsURL(_ value: String) {
        guard let url = URL(string: value) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
