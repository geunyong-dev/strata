import AppKit
import SwiftUI

@MainActor
final class StrataAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM launches a bare executable, without an app bundle's activation
        // policy. Make it a foreground app so its windows receive keyboard input.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct StrataApp: App {
    @NSApplicationDelegateAdaptor(StrataAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1040, height: 720)
    }
}
