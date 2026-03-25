import Foundation

/// Persists user-facing app configuration into Application Support.
final class ConfigStore {
    private let fileManager = FileManager.default

    /// Loads the saved configuration or returns defaults if no file exists yet.
    func load() -> AppConfig {
        guard let data = try? Data(contentsOf: AppSupportPaths.configURL) else {
            return AppConfig()
        }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    /// Saves the current configuration atomically so menu changes survive restarts.
    func save(_ config: AppConfig) {
        do {
            try AppSupportPaths.ensureApplicationSupportDirectories()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: AppSupportPaths.configURL, options: .atomic)
        } catch {
            fputs("Failed to save config: \(error)\n", stderr)
        }
    }
}
