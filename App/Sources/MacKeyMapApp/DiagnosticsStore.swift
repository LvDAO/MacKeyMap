import Foundation

/// App-side diagnostics helpers for lightweight logging and user-exportable bundles.
enum DiagnosticsStore {
    private static let maxLogBytes = 512 * 1024

    static func log(_ message: String) {
        do {
            try AppSupportPaths.ensureApplicationSupportDirectories()
            try rotateLogIfNeeded(at: AppSupportPaths.appLogURL)

            let line = "[\(iso8601Timestamp())] \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: AppSupportPaths.appLogURL.path) {
                let handle = try FileHandle(forWritingTo: AppSupportPaths.appLogURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: AppSupportPaths.appLogURL, options: .atomic)
            }
        } catch {
            fputs("Failed to write diagnostics log: \(error)\n", stderr)
        }
    }

    static func exportArchive(
        to destinationURL: URL,
        snapshot: EngineSnapshot,
        config: AppConfig,
        launchAtLoginError: String?
    ) throws {
        try AppSupportPaths.ensureApplicationSupportDirectories()

        let fileManager = FileManager.default
        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacKeyMap-diagnostics-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let summaryData = diagnosticSummary(
            snapshot: snapshot,
            config: config,
            launchAtLoginError: launchAtLoginError
        )
        .data(using: .utf8) else {
            throw NSError(
                domain: "MacKeyMap.Diagnostics",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode diagnostics summary."]
            )
        }

        try summaryData.write(
            to: stagingDirectory.appendingPathComponent("summary.txt"),
            options: .atomic
        )

        try encoder.encode(config)
            .write(to: stagingDirectory.appendingPathComponent("config.json"), options: .atomic)

        try encoder.encode(snapshot)
            .write(to: stagingDirectory.appendingPathComponent("engine_snapshot.json"), options: .atomic)

        try copyIfPresent(from: AppSupportPaths.appLogURL, to: stagingDirectory.appendingPathComponent("app.log"))
        try copyIfPresent(from: AppSupportPaths.engineLogURL, to: stagingDirectory.appendingPathComponent("engine.log"))

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", stagingDirectory.path, destinationURL.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "MacKeyMap.Diagnostics",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create diagnostics archive."]
            )
        }
    }

    static func suggestedExportFilename() -> String {
        "MacKeyMap-diagnostics-\(exportTimestamp()).zip"
    }

    private static func diagnosticSummary(
        snapshot: EngineSnapshot,
        config: AppConfig,
        launchAtLoginError: String?
    ) -> String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
        let bundlePath = bundle.bundleURL.path
        let codeSignature = currentCodeSignatureSummary()

        let deviceLines = snapshot.devices.map { device in
            let mode = device.remapMode ?? "none"
            return "- \(device.name) | selected=\(device.selected) active=\(device.active) mode=\(mode) transport=\(device.transport) error=\(device.lastError ?? "none")"
        }

        let headerLines = [
            "MacKeyMap Diagnostics",
            "Generated: \(iso8601Timestamp())",
            "Version: \(shortVersion) (\(buildVersion))",
            "Bundle identifier: \(bundleIdentifier)",
            "Bundle path: \(bundlePath)",
            "Code signature: \(codeSignature)",
            "Engine status: \(snapshot.engineStatus)",
            "Remapping enabled: \(config.enabled)",
            "Launch at login: \(config.launchAtLogin)",
            "Input Monitoring: \(snapshot.permissions.hidListen)",
            "Launch-at-login error: \(launchAtLoginError ?? "none")",
            "Config path: \(AppSupportPaths.configURL.path)",
            "App log path: \(AppSupportPaths.appLogURL.path)",
            "Engine log path: \(AppSupportPaths.engineLogURL.path)",
            "",
            "Devices:",
        ]

        let allLines = headerLines + (deviceLines.isEmpty ? ["- none"] : deviceLines)
        return allLines.joined(separator: "\n")
    }

    private static func rotateLogIfNeeded(at url: URL) throws {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.intValue >= maxLogBytes
        else {
            return
        }

        let previousURL = url.deletingPathExtension().appendingPathExtension("previous.log")
        if FileManager.default.fileExists(atPath: previousURL.path) {
            try FileManager.default.removeItem(at: previousURL)
        }
        try FileManager.default.moveItem(at: url, to: previousURL)
    }

    private static func copyIfPresent(from sourceURL: URL, to destinationURL: URL) throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func currentCodeSignatureSummary() -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", Bundle.main.bundleURL.path]
        process.standardError = outputPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "unavailable (\(error.localizedDescription))"
        }

        guard process.terminationStatus == 0 else {
            return "codesign exited with status \(process.terminationStatus)"
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return "unavailable"
        }

        let authority = output
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("Authority=") })
            .map { String($0.dropFirst("Authority=".count)) }
        let teamIdentifier = output
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("TeamIdentifier=") })
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
        let signature = output
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("Signature=") })
            .map { String($0.dropFirst("Signature=".count)) }

        return [signature, authority, teamIdentifier]
            .compactMap { $0 }
            .joined(separator: " | ")
            .ifEmpty("unavailable")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
