import SwiftUI
import ServiceManagement

/// Settings window: hotkeys, default opacity, persistence, shadow, launch at login and support link.
struct SettingsView: View {
    @AppStorage(Prefs.captureKey) private var captureKey = HotKey.defaultCapture.encoded
    @AppStorage(Prefs.clipboardKey) private var clipboardKey = HotKey.defaultClipboard.encoded
    @AppStorage(Prefs.defaultOpacity) private var defaultOpacity = 1.0
    @AppStorage(Prefs.rememberPins) private var rememberPins = true
    @AppStorage(Prefs.dropShadow) private var dropShadow = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Capture region") { HotKeyRecorder(encoded: $captureKey) }
                LabeledContent("Pin clipboard image") { HotKeyRecorder(encoded: $clipboardKey) }
            }
            Section("Pins") {
                LabeledContent("Default opacity") {
                    HStack {
                        Slider(value: $defaultOpacity, in: 0.1...1)
                        Text("\(Int(defaultOpacity * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Remember pins between launches", isOn: $rememberPins)
                    .onChange(of: rememberPins) { PinManager.shared.persist() }
                Toggle("Drop a soft shadow", isOn: $dropShadow)
                    .onChange(of: dropShadow) { PinManager.shared.applyShadowSetting() }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                HStack {
                    Text("PinShotFloat is free and open source.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Support / Donate ❤️") {
                        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onChange(of: captureKey) { HotKeyManager.shared.registerFromDefaults() }
        .onChange(of: clipboardKey) { HotKeyManager.shared.registerFromDefaults() }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Button that records the next key combination (with ⌘, ⌃ or ⌥) as a global hotkey.
struct HotKeyRecorder: View {
    @Binding var encoded: Int
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : HotKey(encoded: encoded).displayString) {
            recording ? stop() : start()
        }
        .frame(minWidth: 110)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            if let key = HotKey(event: event) { encoded = key.encoded; stop(); return nil }
            NSSound.beep()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
