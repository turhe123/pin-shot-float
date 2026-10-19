# PinShotFloat — specification

**Tagline:** Capture a region and pin it as a floating, always-on-top reference window you can resize and fade.

**Category:** Menu Bar Utility

**Inspired by (paid):** ScreenFloat ($15.99 one-time)

**Frameworks:** SwiftUI, AppKit, ScreenCaptureKit, CoreGraphics, UniformTypeIdentifiers, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. ScreenFloat is a long-running Mac app sold for about sixteen dollars that turns screenshots into floating windows that stay above other windows, so designers, developers and students can keep a reference visible while working. It is regularly listed among favorite Mac screenshot tools and is carried in Setapp-style bundles. Our clean-room version is only the pinning part: capture, float, adjust and dismiss.

Feature set for our version. A global hotkey captures a region, and a second hotkey pins whatever image is currently on the clipboard. Each pinned shot appears as a borderless floating panel at the location where it was taken, so it looks like the pixels simply froze in place. Each panel can be dragged by its body, resized by its edges with the aspect ratio locked, made click-through so the mouse passes to windows underneath, have its opacity changed with scroll and a slider, be flipped to a thumbnail size, be copied back to the clipboard, saved to disk, or closed. A menu command shows or hides all pins at once, and another closes all. Pins can optionally persist across launches by being stored as PNG files in Application Support.

UI spec. MenuBarExtra app with no Dock icon. Menu items: Capture Region, Pin Clipboard Image, Show or Hide All Pins, Close All Pins, Settings, and Quit. A right-click context menu on each pin offers Opacity submenu with twenty-five, fifty, seventy-five and one hundred percent, Click-through toggle, Copy, Save As, Shrink to Thumbnail, and Close. Settings window fields: capture hotkey, pin clipboard hotkey, default opacity slider, a toggle to remember pins between launches, a toggle for dropping a soft shadow, and launch at login. Empty state in the menu says No pinned shots. Escape closes the focused pin. Option-scroll adjusts opacity.

Technical approach. Region selection uses a transparent overlay NSWindow per display. The capture uses ScreenCaptureKit single-frame screenshot of the selected rectangle in display coordinates, returning a CGImage. Each pin is a subclass of NSPanel with the nonactivating style mask, a floating window level, collection behavior that allows it on all Spaces and over full-screen apps, and a SwiftUI image view hosted inside. Click-through is the ignoresMouseEvents property, with a menu bar toggle to bring pins back into interactive mode since a click-through pin cannot receive clicks. Global hotkeys use the Carbon hot key API. Persistence writes PNG data with a small JSON manifest holding frames and opacity into Application Support. Screen Recording permission is requested on first capture with an explanatory sheet and a button that opens System Settings. Launch at login uses SMAppService.

Edge cases and error handling. When displays change, keep pins on screens that still exist and move others to the main display. Limit the number of pins to thirty to avoid memory growth and warn when the limit is reached. Handle images from the clipboard that are PDF or TIFF. Guard against the case where the user makes every pin click-through and forgets, by always providing the menu bar command to restore interaction. Clean up temporary files at quit and on failed saves show an alert with the reason.
