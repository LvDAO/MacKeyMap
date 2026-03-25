// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacKeyMap",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "MacKeyMapApp", targets: ["MacKeyMapApp"]),
    ],
    targets: [
        .executableTarget(
            name: "MacKeyMapApp",
            path: "App/Sources/MacKeyMapApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags([
                    "-L", "target/debug",
                    "-L", "target/release",
                    "-l", "mackeymap_core",
                ]),
            ]
        ),
    ]
)
