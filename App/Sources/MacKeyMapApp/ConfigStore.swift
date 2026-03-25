import Foundation

final class ConfigStore {
    private let fileManager = FileManager.default

    private var configDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacKeyMap", isDirectory: true)
    }

    private var configURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL) else {
            return AppConfig()
        }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    func save(_ config: AppConfig) {
        do {
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            fputs("Failed to save config: \(error)\n", stderr)
        }
    }
}
