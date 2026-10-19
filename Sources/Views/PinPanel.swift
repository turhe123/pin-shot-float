import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A borderless, non-activating, always-on-top panel showing one pinned image.
final class PinPanel: NSPanel, NSMenuDelegate {
    let pinID: UUID
    let image: CGImage
    var onClose: (() -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var isThumbnail = false
    private var savedFrame: CGRect?
    private static let thumbnailSide: CGFloat = 120

    /// The full-size frame, even while shrunk to a thumbnail.
    var expandedFrame: CGRect { savedFrame.map { CGRect(origin: frame.origin, size: $0.size) } ?? frame }

    init(id: UUID, image: CGImage, frame: CGRect, opacity: Double, shadow: Bool) {
        self.pinID = id
        self.image = image
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = shadow
        alphaValue = CGFloat(min(max(opacity, 0.1), 1))
        contentAspectRatio = frame.size
        minSize = CGSize(width: 24, height: 24)
        let host = PinHostingView(rootView: PinImageView(image: NSImage(cgImage: image, size: frame.size)))
        host.panel = self
        contentView = host
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        super.close()
        let callback = onClose
        onClose = nil
        callback?()
    }

    // MARK: Actions

    func setOpacity(_ value: CGFloat) { alphaValue = min(max(value, 0.1), 1) }

    func setClickThrough(_ on: Bool) {
        ignoresMouseEvents = on
        onStateChange?()
    }

    func toggleThumbnail() {
        if let saved = savedFrame {
            var f = frame
            f.origin.y -= saved.height - f.height
            f.size = saved.size
            savedFrame = nil
            isThumbnail = false
            setFrame(f, display: true, animate: true)
        } else {
            savedFrame = frame
            let scale = Self.thumbnailSide / max(frame.width, frame.height)
            guard scale < 1 else { savedFrame = nil; return }
            var f = frame
            f.size = CGSize(width: frame.width * scale, height: frame.height * scale)
            f.origin.y += frame.height - f.height // keep the top-left corner anchored
            isThumbnail = true
            setFrame(f, display: true, animate: true)
        }
    }

    @objc func copyImage() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: image, size: expandedFrame.size)])
    }

    @objc func saveAs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Pinned Shot.png"
        NSApp.activate(ignoringOtherApps: true)
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try PinStore.export(image, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save the image"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func opacityItem(_ sender: NSMenuItem) { setOpacity(CGFloat(sender.tag) / 100) }
    @objc private func toggleClickThrough() { setClickThrough(!ignoresMouseEvents) }
    @objc private func thumbnailItem() { toggleThumbnail() }
    @objc private func closeItem() { close() }
    @objc private func sliderChanged(_ sender: NSSlider) { setOpacity(CGFloat(sender.doubleValue)) }

    // MARK: Context menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let opacityMenu = NSMenu()
        for pct in [25, 50, 75, 100] {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(opacityItem(_:)), keyEquivalent: "")
            item.tag = pct
            item.target = self
            item.state = Int((alphaValue * 100).rounded()) == pct ? .on : .off
            opacityMenu.addItem(item)
        }
        opacityMenu.addItem(.separator())
        let slider = NSSlider(value: Double(alphaValue), minValue: 0.1, maxValue: 1, target: self,
                              action: #selector(sliderChanged(_:)))
        slider.frame = CGRect(x: 16, y: 4, width: 160, height: 22)
        let sliderHolder = NSView(frame: CGRect(x: 0, y: 0, width: 192, height: 30))
        sliderHolder.addSubview(slider)
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderHolder
        opacityMenu.addItem(sliderItem)
        let opacityRoot = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityRoot.submenu = opacityMenu
        menu.addItem(opacityRoot)

        let ct = NSMenuItem(title: "Click-through", action: #selector(toggleClickThrough), keyEquivalent: "")
        ct.state = ignoresMouseEvents ? .on : .off
        ct.toolTip = "Use “Make All Pins Interactive” in the menu bar to undo."
        menu.addItem(ct)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copyImage), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Save As…", action: #selector(saveAs), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: isThumbnail ? "Restore Full Size" : "Shrink to Thumbnail",
                                action: #selector(thumbnailItem), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Close", action: #selector(closeItem), keyEquivalent: "w"))
        for item in menu.items where item.action != nil { item.target = self }
        return menu
    }
}

/// Hosts the SwiftUI image and forwards drag, scroll and right-click to the owning panel.
final class PinHostingView: NSHostingView<PinImageView> {
    weak var panel: PinPanel?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { panel?.toggleThumbnail(); return }
        panel?.makeKey()
        window?.performDrag(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? { panel?.makeMenu() }

    /// Option-scroll adjusts opacity.
    override func scrollWheel(with event: NSEvent) {
        guard let panel, event.modifierFlags.contains(.option) else { return super.scrollWheel(with: event) }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 200 : event.scrollingDeltaY / 20
        panel.setOpacity(panel.alphaValue + delta)
    }
}

/// SwiftUI view that renders the pinned pixels, scaled to fill the panel.
struct PinImageView: View {
    let image: NSImage
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }
}
