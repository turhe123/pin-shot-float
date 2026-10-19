import AppKit
import Combine

/// Owns every pinned panel: creation, limits, bulk commands, display changes and persistence.
final class PinManager: ObservableObject {
    static let shared = PinManager()
    static let maxPins = 30

    @Published private(set) var panels: [PinPanel] = []
    @Published private(set) var allHidden = false
    @Published private(set) var anyClickThrough = false
    private var screenObserver: NSObjectProtocol?

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.relocateOrphanedPins() }
    }

    func canAddPin() -> Bool {
        guard panels.count >= Self.maxPins else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Pin limit reached"
        alert.informativeText = "You can have up to \(Self.maxPins) pinned shots. Close some pins to add new ones."
        alert.runModal()
        return false
    }

    @discardableResult
    func addPin(image: CGImage, frame: CGRect, opacity: Double? = nil, id: UUID = UUID()) -> PinPanel? {
        guard canAddPin() else { return nil }
        let d = UserDefaults.standard
        let panel = PinPanel(id: id, image: image, frame: frame,
                             opacity: opacity ?? d.double(forKey: Prefs.defaultOpacity),
                             shadow: d.bool(forKey: Prefs.dropShadow))
        panel.onClose = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.panels.removeAll { $0 === panel }
            self.refreshState()
            self.persist()
        }
        panel.onStateChange = { [weak self] in self?.refreshState() }
        panels.append(panel)
        if allHidden { allHidden = false; panels.forEach { $0.orderFrontRegardless() } }
        panel.orderFrontRegardless()
        refreshState()
        persist()
        return panel
    }

    /// Pins the clipboard image (PNG, TIFF, PDF, …) centred on the mouse pointer.
    func pinClipboard() {
        guard let nsImage = NSImage(pasteboard: .general),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "No image on the clipboard"
            alert.informativeText = "Copy an image (PNG, TIFF, JPEG or PDF) and try again."
            alert.runModal()
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        var size = nsImage.size
        let fit = min(1, visible.width * 0.8 / max(size.width, 1), visible.height * 0.8 / max(size.height, 1))
        size = CGSize(width: size.width * fit, height: size.height * fit)
        var origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        addPin(image: cg, frame: CGRect(origin: origin, size: size))
    }

    func toggleAllVisibility() {
        allHidden.toggle()
        panels.forEach { allHidden ? $0.orderOut(nil) : $0.orderFrontRegardless() }
    }

    func restoreInteraction() {
        panels.forEach { $0.setClickThrough(false) }
        if allHidden { toggleAllVisibility() }
        refreshState()
    }

    func closeAll() {
        panels.forEach { $0.onClose = nil; $0.close() }
        panels.removeAll()
        allHidden = false
        refreshState()
        persist()
    }

    func applyShadowSetting() {
        let shadow = UserDefaults.standard.bool(forKey: Prefs.dropShadow)
        panels.forEach { $0.hasShadow = shadow; $0.invalidateShadow() }
    }

    private func refreshState() {
        anyClickThrough = panels.contains { $0.ignoresMouseEvents }
    }

    /// Keeps pins on displays that still exist; moves the rest onto the main display.
    private func relocateOrphanedPins() {
        guard let main = NSScreen.main ?? NSScreen.screens.first else { return }
        for panel in panels where !NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) }) {
            var frame = panel.frame
            frame.origin = CGPoint(x: main.visibleFrame.midX - frame.width / 2,
                                   y: main.visibleFrame.midY - frame.height / 2)
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: Persistence

    func persist() {
        guard UserDefaults.standard.bool(forKey: Prefs.rememberPins) else { PinStore.clear(); return }
        PinStore.save(panels.map { PinStore.Entry(id: $0.pinID, frame: $0.expandedFrame, opacity: $0.alphaValue, image: $0.image) })
    }

    func restore() {
        guard UserDefaults.standard.bool(forKey: Prefs.rememberPins) else { return }
        for entry in PinStore.load() {
            addPin(image: entry.image, frame: entry.frame, opacity: entry.opacity, id: entry.id)
        }
        relocateOrphanedPins()
    }
}
