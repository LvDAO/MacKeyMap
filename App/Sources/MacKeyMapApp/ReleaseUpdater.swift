import AppKit
import Foundation

/// Minimal GitHub Releases updater used by the menu bar app.
@MainActor
final class ReleaseUpdater {
    private let session: URLSession
    private let owner = "LvDAO"
    private let repository = "MacKeyMap"
    private var isBusy = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkForUpdates() async {
        guard !isBusy else {
            return
        }

        isBusy = true
        defer { isBusy = false }

        DiagnosticsStore.log("checking for updates")

        do {
            let release = try await fetchLatestRelease()
            guard let currentVersion = AppVersion.current else {
                throw UpdaterError.invalidCurrentVersion
            }

            if release.version <= currentVersion {
                DiagnosticsStore.log("no update available; current=\(currentVersion.rawValue) latest=\(release.version.rawValue)")
                presentInfoAlert(
                    title: "MacKeyMap is up to date",
                    message: "You are already running \(currentVersion.rawValue)."
                )
                return
            }

            let response = presentInstallPrompt(for: release)
            guard response == .alertFirstButtonReturn else {
                DiagnosticsStore.log("update cancelled by user")
                return
            }

            try await downloadAndInstall(release: release)
        } catch {
            DiagnosticsStore.log("update failed: \(error.localizedDescription)")
            presentErrorAlert(
                title: "Unable to update MacKeyMap",
                message: error.localizedDescription
            )
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repository)/releases/latest"
        guard let url = URL(string: endpoint) else {
            throw UpdaterError.invalidReleaseURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacKeyMap/\(AppVersion.current?.rawValue ?? "unknown")", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdaterError.invalidReleaseResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw UpdaterError.httpFailure(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()

        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard AppVersion(tag: release.tagName) != nil else {
            throw UpdaterError.invalidRemoteVersion(release.tagName)
        }
        return release
    }

    private func presentInstallPrompt(for release: GitHubRelease) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "MacKeyMap \(release.version.rawValue) is available"
        alert.informativeText = release.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? release.body!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Download and install the latest release from GitHub."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal()
    }

    private func downloadAndInstall(release: GitHubRelease) async throws {
        let asset = try release.primaryAsset()
        try AppSupportPaths.ensureApplicationSupportDirectories()

        let stagingDirectory = AppSupportPaths.updatesDirectory
            .appendingPathComponent(release.version.rawValue, isDirectory: true)
        let extractedDirectory = stagingDirectory.appendingPathComponent("extracted", isDirectory: true)
        let archiveURL = stagingDirectory.appendingPathComponent(asset.name)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
        try fileManager.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)

        DiagnosticsStore.log("downloading update asset \(asset.name)")
        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("MacKeyMap/\(release.version.rawValue)", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdaterError.invalidReleaseResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw UpdaterError.httpFailure(httpResponse.statusCode)
        }

        try fileManager.moveItem(at: temporaryURL, to: archiveURL)
        try await ProcessRunner.run(
            executablePath: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractedDirectory.path]
        )

        let stagedAppURL = extractedDirectory.appendingPathComponent("MacKeyMap.app", isDirectory: true)
        guard fileManager.fileExists(atPath: stagedAppURL.path) else {
            throw UpdaterError.missingDownloadedApp
        }

        guard let targetAppURL = installTargetURL() else {
            DiagnosticsStore.log("update downloaded for manual install at \(stagedAppURL.path)")
            NSWorkspace.shared.activateFileViewerSelecting([stagedAppURL])
            presentInfoAlert(
                title: "Update Downloaded",
                message: "MacKeyMap downloaded \(release.version.rawValue). Replace the current app manually from Finder."
            )
            return
        }

        try launchInstaller(stagedAppURL: stagedAppURL, targetAppURL: targetAppURL)
        DiagnosticsStore.log("update prepared; replacing \(targetAppURL.path)")
        NSApp.terminate(nil)
    }

    private func installTargetURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let bundlePath = bundleURL.path

        if bundlePath.contains("/AppTranslocation/") {
            return nil
        }

        let parentURL = bundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentURL.path) else {
            return nil
        }

        return bundleURL
    }

    private func launchInstaller(stagedAppURL: URL, targetAppURL: URL) throws {
        let scriptURL = AppSupportPaths.updatesDirectory.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/zsh
        set -euo pipefail
        pid="$1"
        source_app="$2"
        target_app="$3"
        while kill -0 "$pid" 2>/dev/null; do
          sleep 1
        done
        rm -rf "$target_app"
        ditto "$source_app" "$target_app"
        open "$target_app"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagedAppURL.path,
            targetAppURL.path,
        ]
        try process.run()
    }

    private func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }

    var version: AppVersion {
        AppVersion(tag: tagName) ?? .zero
    }

    func primaryAsset() throws -> GitHubReleaseAsset {
        let expectedName = "MacKeyMap-\(version.rawValue)-macos.zip"
        if let exactMatch = assets.first(where: { $0.name == expectedName }) {
            return exactMatch
        }
        if let fallback = assets.first(where: { $0.name.hasSuffix("-macos.zip") }) {
            return fallback
        }
        throw UpdaterError.missingReleaseAsset(expectedName)
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct AppVersion: Comparable {
    let rawValue: String
    private let components: [Int]

    static let zero = AppVersion(rawValue: "0.0.0", components: [0, 0, 0])

    static var current: AppVersion? {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return value.flatMap(AppVersion.init(rawValue:))
    }

    init?(rawValue: String) {
        let numbers = rawValue
            .split(separator: ".")
            .map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else {
            return nil
        }
        self.rawValue = rawValue
        self.components = numbers.compactMap { $0 }
    }

    init?(tag: String) {
        let normalized = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        self.init(rawValue: normalized)
    }

    private init(rawValue: String, components: [Int]) {
        self.rawValue = rawValue
        self.components = components
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< maxCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

private enum UpdaterError: LocalizedError {
    case invalidCurrentVersion
    case invalidReleaseURL
    case invalidReleaseResponse
    case invalidRemoteVersion(String)
    case missingReleaseAsset(String)
    case missingDownloadedApp
    case httpFailure(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            return "The current app version could not be read."
        case .invalidReleaseURL:
            return "The GitHub release URL is invalid."
        case .invalidReleaseResponse:
            return "GitHub returned an unexpected response."
        case let .invalidRemoteVersion(version):
            return "GitHub returned an invalid release version: \(version)."
        case let .missingReleaseAsset(name):
            return "The GitHub release does not contain \(name)."
        case .missingDownloadedApp:
            return "The downloaded update did not contain MacKeyMap.app."
        case let .httpFailure(statusCode):
            return "GitHub returned HTTP \(statusCode)."
        }
    }
}

private enum ProcessRunner {
    static func run(executablePath: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.terminationHandler = { finishedProcess in
                if finishedProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "MacKeyMap.ProcessRunner",
                            code: Int(finishedProcess.terminationStatus),
                            userInfo: [
                                NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: executablePath).lastPathComponent) exited with status \(finishedProcess.terminationStatus).",
                            ]
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
