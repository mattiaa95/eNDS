import UIKit

/// Stores the "last played" gameplay thumbnail for each ROM as a PNG in
/// `Documents/Thumbnails/<baseName>.png`. Written by `NDSRomViewController`
/// (top screen frame, captured on pause/quit) and read by the ROM library
/// (`ROMDetailView`'s large preview). Mirrors `ROMIconStore`'s cache shape —
/// separate store because it holds a different image (gameplay frame vs.
/// cartridge banner icon) with a different lifecycle (rewritten every play
/// session vs. rendered once).
enum ThumbnailManager {
    private static let directoryName = "Thumbnails"
    private static let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
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

    private static func url(baseName: String) -> URL? {
        directory?.appendingPathComponent(baseName).appendingPathExtension("png")
    }

    /// Saves `image` as the thumbnail for `baseName`, overwriting any
    /// existing one. Cheap enough (256x192 source) to call synchronously from
    /// the main thread at pause/quit time.
    static func save(_ image: UIImage, baseName: String) {
        memoryCache.setObject(image, forKey: baseName as NSString)
        guard let url = url(baseName: baseName), let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func thumbnail(baseName: String) -> UIImage? {
        let key = baseName as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        guard let url = url(baseName: baseName),
              FileManager.default.fileExists(atPath: url.path),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        memoryCache.setObject(image, forKey: key)
        return image
    }

    static func hasThumbnail(baseName: String) -> Bool {
        guard let url = url(baseName: baseName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func invalidate(baseName: String) {
        memoryCache.removeObject(forKey: baseName as NSString)
        if let url = url(baseName: baseName) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func rename(fromBaseName oldName: String, toBaseName newName: String) {
        memoryCache.removeObject(forKey: oldName as NSString)
        guard let oldURL = url(baseName: oldName), let newURL = url(baseName: newName),
              FileManager.default.fileExists(atPath: oldURL.path) else { return }
        try? FileManager.default.removeItem(at: newURL)
        try? FileManager.default.moveItem(at: oldURL, to: newURL)
    }
}
