import SwiftUI
import AppKit

/// Shared keys and defaults for `@AppStorage` / `UserDefaults`.
enum Prefs {
    static let captureKey = "captureHotKey"
    static let clipboardKey = "clipboardHotKey"
    static let defaultOpacity = "defaultOpacity"
    static let rememberPins = "rememberPins"
    static let dropShadow = "dropShadow"
    static let donateURL = URL(string: "https://ko-fi.com/leodavidai")!

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            captureKey: HotKey.defaultCapture.encoded,
            clipboardKey: HotKey.defaultClipboard.encoded,
            defaultOpacity: 1.0,
            rememberPins: true,
            dropShadow: true
        ])
    }
}

/// Entry point: a Dock-less menu bar app with a Settings window.
@main
struct PinShotFloatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var pins = PinManager.shared

    var body: some Scene {
        MenuBarExtra("PinShotFloat", systemImage: "pin.fill") {
            MenuContent().environmentObject(pins)
        }
        Settings {
            SettingsView()
        }
    }
}

/// Bootstraps defaults, hotkeys and restored pins; cleans up at quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        HotKeyManager.shared.registerFromDefaults()
        PinManager.shared.restore()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PinManager.shared.persist()
        PinStore.cleanTemporaryFiles()
    }
}

/// The menu shown from the menu bar icon.
struct MenuContent: View {
    @EnvironmentObject var pins: PinManager

    var body: some View {
        Button("Capture Region") { CaptureCoordinator.shared.beginCapture() }
        Button("Pin Clipboard Image") { pins.pinClipboard() }
        Divider()
        if pins.panels.isEmpty {
            Text("No pinned shots")
        } else {
            Text("\(pins.panels.count) pinned shot\(pins.panels.count == 1 ? "" : "s")")
        }
        Button(pins.allHidden ? "Show All Pins" : "Hide All Pins") { pins.toggleAllVisibility() }
            .disabled(pins.panels.isEmpty)
        Button("Make All Pins Interactive") { pins.restoreInteraction() }
            .disabled(!pins.anyClickThrough)
        Button("Close All Pins") { pins.closeAll() }
            .disabled(pins.panels.isEmpty)
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Support / Donate ❤️") { NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!) }
        Divider()
        Button("Quit PinShotFloat") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
