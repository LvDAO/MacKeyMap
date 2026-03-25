import Foundation

struct OverrideConfig: Codable, Equatable {
    var swapLeftAltWin = false
    var swapRightAltWin = false
    var disableContextMenuRemap = false
}

struct AppConfig: Codable, Equatable {
    var enabled = true
    var launchAtLogin = true
    var overrides = OverrideConfig()
    var deviceSelections: [String: Bool] = [:]
}

struct PermissionSnapshot: Decodable {
    let hidListen: String
}

struct DeviceSnapshot: Decodable, Identifiable {
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

struct OverrideSnapshot: Decodable {
    let swapLeftAltWin: Bool
    let swapRightAltWin: Bool
    let disableContextMenuRemap: Bool
}

struct EngineSnapshot: Decodable {
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
