import AppKit

@main
struct MacKeyMapMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = MenuBarController()

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
