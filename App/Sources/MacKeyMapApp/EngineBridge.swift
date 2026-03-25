import Foundation

/// Thin Swift wrapper over the Rust C ABI used by the menu bar process.
@_silgen_name("mackeymap_engine_create")
private func mackeymap_engine_create() -> UnsafeMutableRawPointer?

@_silgen_name("mackeymap_engine_destroy")
private func mackeymap_engine_destroy(_ engine: UnsafeMutableRawPointer?)

@_silgen_name("mackeymap_engine_start")
private func mackeymap_engine_start(_ engine: UnsafeMutableRawPointer?) -> UInt8

@_silgen_name("mackeymap_engine_stop")
private func mackeymap_engine_stop(_ engine: UnsafeMutableRawPointer?)

@_silgen_name("mackeymap_engine_request_permissions")
private func mackeymap_engine_request_permissions(_ engine: UnsafeMutableRawPointer?) -> UInt8

@_silgen_name("mackeymap_engine_set_global_enabled")
private func mackeymap_engine_set_global_enabled(_ engine: UnsafeMutableRawPointer?, _ enabled: UInt8)

@_silgen_name("mackeymap_engine_set_overrides")
private func mackeymap_engine_set_overrides(
    _ engine: UnsafeMutableRawPointer?,
    _ swapLeftAltWin: UInt8,
    _ swapRightAltWin: UInt8,
    _ disableContextMenuRemap: UInt8
)

@_silgen_name("mackeymap_engine_set_device_enabled")
private func mackeymap_engine_set_device_enabled(
    _ engine: UnsafeMutableRawPointer?,
    _ identifier: UnsafePointer<CChar>?,
    _ enabled: UInt8
)

@_silgen_name("mackeymap_engine_copy_snapshot_json")
private func mackeymap_engine_copy_snapshot_json(_ engine: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("mackeymap_string_free")
private func mackeymap_string_free(_ string: UnsafeMutablePointer<CChar>?)

final class RustEngineBridge {
    private let handle: UnsafeMutableRawPointer?

    init() {
        self.handle = mackeymap_engine_create()
    }

    deinit {
        stop()
        mackeymap_engine_destroy(handle)
    }

    func start() {
        _ = mackeymap_engine_start(handle)
    }

    func stop() {
        mackeymap_engine_stop(handle)
    }

    func requestPermissions() {
        _ = mackeymap_engine_request_permissions(handle)
    }

    func setGlobalEnabled(_ enabled: Bool) {
        mackeymap_engine_set_global_enabled(handle, enabled ? 1 : 0)
    }

    func setOverrides(_ overrides: OverrideConfig) {
        mackeymap_engine_set_overrides(
            handle,
            overrides.swapLeftAltWin ? 1 : 0,
            overrides.swapRightAltWin ? 1 : 0,
            overrides.disableContextMenuRemap ? 1 : 0
        )
    }

    func setDeviceEnabled(id: String, enabled: Bool) {
        id.withCString { cString in
            mackeymap_engine_set_device_enabled(handle, cString, enabled ? 1 : 0)
        }
    }

    /// Returns the current engine snapshot if the Rust side produced valid JSON.
    func fetchSnapshot() -> EngineSnapshot? {
        guard let raw = mackeymap_engine_copy_snapshot_json(handle) else {
            return nil
        }
        defer { mackeymap_string_free(raw) }

        let json = String(cString: raw)
        guard let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(EngineSnapshot.self, from: data)
    }
}
