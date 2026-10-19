import AppKit
import UniformTypeIdentifiers

/// Stores pins as PNG files plus a JSON manifest (frames, opacity) in Application Support.
enum PinStore {
    struct Entry {
        let id: UUID
        let frame: CGRect
        let opacity: Double
        let image: CGImage
    }

    private struct ManifestItem: Codable {
        let id: UUID
        let x, y, width, height: Double
        let opacity: Double
    }

    private static let fm = FileManager.default

    static var directory: URL? {
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("PinShotFloat/Pins", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var temporaryDirectory: URL {
        fm.temporaryDirectory.appendingPathComponent("PinShotFloat", isDirectory: true)
    }

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func save(_ entries: [Entry]) {
        guard let dir = directory else { return }
        var manifest: [ManifestItem] = []
        for entry in entries {
            let url = dir.appendingPathComponent("\(entry.id.uuidString).png")
            if !fm.fileExists(atPath: url.path) {
                guard let data = pngData(entry.image), (try? data.write(to: url, options: .atomic)) != nil else { continue }
            }
            manifest.append(ManifestItem(id: entry.id, x: entry.frame.minX, y: entry.frame.minY,
                                         width: entry.frame.width, height: entry.frame.height, opacity: entry.opacity))
        }
        if let json = try? JSONEncoder().encode(manifest) {
            try? json.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        }
        // Remove PNGs that no longer belong to a pin.
        let keep = Set(manifest.map { "\($0.id.uuidString).png" })
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in files where file.hasSuffix(".png") && !keep.contains(file) {
            try? fm.removeItem(at: dir.appendingPathComponent(file))
        }
    }

    static func load() -> [Entry] {
        guard let dir = directory,
              let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode([ManifestItem].self, from: data) else { return [] }
        return manifest.prefix(PinManager.maxPins).compactMap { item in
            let url = dir.appendingPathComponent("\(item.id.uuidString).png")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return Entry(id: item.id, frame: CGRect(x: item.x, y: item.y, width: item.width, height: item.height),
                         opacity: item.opacity, image: image)
        }
    }

    static func clear() {
        guard let dir = directory else { return }
        try? fm.removeItem(at: dir)
    }

    static func cleanTemporaryFiles() {
        try? fm.removeItem(at: temporaryDirectory)
    }

    /// Writes PNG data via a temp file then moves it into place; throws a readable error on failure.
    static func export(_ image: CGImage, to url: URL) throws {
        guard let data = pngData(image) else {
            throw NSError(domain: "PinShotFloat", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The image could not be encoded as PNG."])
        }
        try fm.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let temp = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? fm.removeItem(at: temp) }
        try data.write(to: temp)
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: url)
        }
    }
}
