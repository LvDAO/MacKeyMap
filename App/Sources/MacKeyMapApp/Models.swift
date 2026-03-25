import Foundation

/// User-configurable modifier remap switches surfaced in the menu bar UI.
struct OverrideConfig: Codable, Equatable {
    var swapLeftAltWin = false
    var swapRightAltWin = false
    var disableContextMenuRemap = false
}

/// Persisted menu bar app configuration.
struct AppConfig: Codable, Equatable {
    var enabled = true
    var launchAtLogin = true
    var overrides = OverrideConfig()
    var deviceSelections: [String: Bool] = [:]
}

/// Permission state mirrored from the Rust engine snapshot.
struct PermissionSnapshot: Codable {
    let hidListen: String
}

/// Per-device state reported by the Rust engine.
struct DeviceSnapshot: Codable, Identifiable {
    let id: String
    let name: String
    let manufacturer: String
    let transport: String
    let vendorId: Int
    let productId: Int
    let locationId: Int
    let builtIn: Bool
    let selected: Bool
    let active: Bool
    let remapMode: String?
    let lastError: String?
}

/// Effective override state echoed back from the engine.
struct OverrideSnapshot: Codable {
    let swapLeftAltWin: Bool
    let swapRightAltWin: Bool
    let disableContextMenuRemap: Bool
}

/// Full engine state used for UI rendering and diagnostics export.
struct EngineSnapshot: Codable {
    let engineStatus: String
    let enabled: Bool
    let preset: String
    let permissions: PermissionSnapshot
    let overrides: OverrideSnapshot
    let startupError: String?
    let devices: [DeviceSnapshot]

    static let empty = EngineSnapshot(
        engineStatus: "stopped",
        enabled: false,
        preset: "standard_pc_to_mac",
        permissions: PermissionSnapshot(hidListen: "unknown"),
        overrides: OverrideSnapshot(
            swapLeftAltWin: false,
            swapRightAltWin: false,
            disableContextMenuRemap: false
        ),
        startupError: nil,
        devices: []
    )
}
