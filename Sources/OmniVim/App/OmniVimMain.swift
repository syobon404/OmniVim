import AppKit

@main
@MainActor
enum OmniVimMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = OmniVimAppDelegate()
        application.delegate = delegate
        application.run()
    }
}
