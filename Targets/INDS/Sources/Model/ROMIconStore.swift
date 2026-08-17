import UIKit

/// Caches rendered NDS banner icons as PNGs in `Documents/Icons/<baseName>.png`
/// so `NDSBanner.renderIcon()` (bitmap decode + CGImage build) only runs once
/// per ROM. Mirrors iGBA's `ScreenshotManager` caching shape, scoped to just
/// what the icon needs (banner icons are tiny — 32x32 — so no dedicated
/// PNG-encoding thread is needed the way iGBA's full-screen screenshots do).
enum ROMIconStore {
    private static let directoryName = "Icons"
    private static let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    private static var directory: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = docs.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func cacheURL(baseName: String) -> URL? {
        directory?.appendingPathComponent(baseName).appendingPathExtension("png")
    }

    /// Returns the ROM's banner icon, preferring the on-disk PNG cache, then
    /// an in-memory cache, and only falling back to parsing+rendering the
    /// banner (and writing the cache) when neither exists yet. Returns `nil`
    /// when the ROM has no parseable banner — callers should show a
    /// placeholder (initials card) in that case.
    static func icon(for rom: ROMFile) -> UIImage? {
        let key = rom.baseName as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        if let url = cacheURL(baseName: rom.baseName),
           FileManager.default.fileExists(atPath: url.path),
           let image = UIImage(contentsOfFile: url.path) {
            memoryCache.setObject(image, forKey: key)
            return image
        }

        guard let banner = rom.banner, let rendered = banner.renderIcon() else {
            return nil
        }
        memoryCache.setObject(rendered, forKey: key)
        if let url = cacheURL(baseName: rom.baseName), let data = rendered.pngData() {
            try? data.write(to: url, options: .atomic)
        }
        return rendered
    }

    /// Removes the cached icon for a ROM (called when a ROM is renamed or
    /// deleted so a stale icon can't survive under the old/reused base name).
    static func invalidate(baseName: String) {
        memoryCache.removeObject(forKey: baseName as NSString)
        if let url = cacheURL(baseName: baseName) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Moves a cached icon to a new base name (used by rename) instead of
    /// discarding it, so a rename doesn't force a re-render.
    static func rename(fromBaseName oldName: String, toBaseName newName: String) {
        memoryCache.removeObject(forKey: oldName as NSString)
        guard let oldURL = cacheURL(baseName: oldName), let newURL = cacheURL(baseName: newName),
              FileManager.default.fileExists(atPath: oldURL.path) else { return }
        try? FileManager.default.removeItem(at: newURL)
        try? FileManager.default.moveItem(at: oldURL, to: newURL)
    }
}
