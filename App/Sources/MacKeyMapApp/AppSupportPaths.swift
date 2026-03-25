import Foundation

/// Canonical filesystem locations used by the app for persisted state and diagnostics.
enum AppSupportPaths {
    static let appDirectoryName = "MacKeyMap"

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    static var logsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    static var configURL: URL {
        applicationSupportDirectory.appendingPathComponent("config.json")
    }

    static var updatesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Updates", isDirectory: true)
    }

    static var appLogURL: URL {
        logsDirectory.appendingPathComponent("app.log")
    }

    static var engineLogURL: URL {
        logsDirectory.appendingPathComponent("engine.log")
    }

    static func ensureApplicationSupportDirectories() throws {
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: updatesDirectory,
            withIntermediateDirectories: true
        )
    }
}
