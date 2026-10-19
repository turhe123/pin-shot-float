import AppKit
import ScreenCaptureKit

/// Orchestrates permission checks, region selection overlays and the ScreenCaptureKit screenshot.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()
    private var overlays: [SelectionOverlayWindow] = []

    func beginCapture() {
        guard overlays.isEmpty else { return }
        guard CGPreflightScreenCaptureAccess() else { explainPermission(); return }
        guard PinManager.shared.canAddPin() else { return }
        NSApp.activate(ignoringOtherApps: true)
        overlays = NSScreen.screens.map { screen in
            let w = SelectionOverlayWindow(screen: screen) { [weak self] rect in self?.finish(rect) }
            w.orderFrontRegardless()
            return w
        }
        let mouse = NSEvent.mouseLocation
        (overlays.first { $0.frame.contains(mouse) } ?? overlays.first)?.makeKey()
    }

    private func finish(_ rect: CGRect?) {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        guard let rect, rect.width >= 4, rect.height >= 4 else { return }
        // Give the window server a moment to remove the overlays before grabbing pixels.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { await self.capture(rect) }
        }
    }

    @MainActor
    private func capture(_ rect: CGRect) async {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return }
        let clipped = rect.intersection(screen.frame)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotFound
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // sourceRect is in display points with a top-left origin.
            config.sourceRect = CGRect(x: clipped.minX - screen.frame.minX,
                                       y: screen.frame.maxY - clipped.maxY,
                                       width: clipped.width, height: clipped.height)
            let scale = screen.backingScaleFactor
            config.width = Int(clipped.width * scale)
            config.height = Int(clipped.height * scale)
            config.showsCursor = false
            config.scalesToFit = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            PinManager.shared.addPin(image: image, frame: clipped)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Capture failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func explainPermission() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        PinShotFloat needs Screen Recording access to capture a region of your screen. \
        Nothing ever leaves your Mac. Enable PinShotFloat in System Settings › Privacy & Security › \
        Screen & System Audio Recording, then try again (you may need to relaunch the app).
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            CGRequestScreenCaptureAccess()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    enum CaptureError: LocalizedError {
        case displayNotFound
        var errorDescription: String? { "The selected display is no longer available." }
    }
}

/// Transparent full-screen window that lets the user drag out a capture rectangle on one display.
final class SelectionOverlayWindow: NSWindow {
    init(screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
        contentView = SelectionView(completion: completion)
    }
    override var canBecomeKey: Bool { true }
}

/// Draws the dimmed backdrop and selection, and reports the selected rect in global screen coordinates.
private final class SelectionView: NSView {
    private let completion: (CGRect?) -> Void
    private var start: CGPoint?
    private var current: CGPoint?

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let window, let sel = selection else { return }
        let local = window.convertFromScreen(sel)
        NSColor.clear.setFill()
        local.fill(using: .copy)
        NSColor.systemPink.setStroke()
        let path = NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) { start = NSEvent.mouseLocation; current = start; redrawAll() }
    override func mouseDragged(with event: NSEvent) { current = NSEvent.mouseLocation; redrawAll() }
    override func mouseUp(with event: NSEvent) {
        current = NSEvent.mouseLocation
        completion(selection.map { CGRect(x: $0.minX.rounded(), y: $0.minY.rounded(),
                                          width: $0.width.rounded(), height: $0.height.rounded()) })
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { completion(nil) } else { super.keyDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) { completion(nil) }

    /// The selection may span displays, so every overlay redraws.
    private func redrawAll() {
        for w in NSApp.windows where w is SelectionOverlayWindow {
            if let v = w.contentView as? SelectionView, v !== self { v.start = start; v.current = current }
            w.contentView?.needsDisplay = true
        }
    }
}
