import Foundation

/// Single-file `.gz` decompression (e.g. `Game.nds.gz` → `Game.nds`) on top
/// of the zlib the app already links for minizip. Mirrors the
/// `NDSZipExtractor`/`NDS7zExtractor.extractEntries` contract — a `[URL]`
/// of extracted files filtered by inner extension — so
/// `ROMStorageManager.importROMsFromArchive` can drive all three formats
/// through the same closure. A `.gz` holds exactly one file, so the result
/// is always 0 or 1 URLs.
enum NDSGzExtractor {
    /// 512MB cap: same decompression-bomb guard as the `.7z` extractor. A
    /// real NGame ROM tops out at 512MB (rare) — anything past that is hostile.
    private static let maxDecompressedBytes = 512 * 1024 * 1024

    static func extractEntries(fromGz gzURL: URL, matchingExtensions extensions: Set<String>, to directory: URL) -> [URL] {
        // "Game.nds.gz" → inner name "Game.nds"; reject before decompressing
        // if we don't support what's inside.
        let innerName = gzURL.deletingPathExtension().lastPathComponent
        let innerExt = (innerName as NSString).pathExtension.lowercased()
        guard !innerName.isEmpty, extensions.contains(innerExt) else {
            debugLog("[GzExtractor] Unsupported inner type in \(gzURL.lastPathComponent)")
            return []
        }

        let didStartAccess = gzURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { gzURL.stopAccessingSecurityScopedResource() }
        }

        guard let gz = gzopen(gzURL.path, "rb") else { return [] }

        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        var readBytes: Int32 = 0
        repeat {
            readBytes = gzread(gz, &chunk, UInt32(chunk.count))
            if readBytes > 0 {
                data.append(contentsOf: chunk[0..<Int(readBytes)])
                if data.count > Self.maxDecompressedBytes { readBytes = -1 }
            }
        } while readBytes > 0
        let cleanEOF = readBytes == 0 // <0 = corrupt stream or bomb cap hit
        gzclose(gz)
        guard cleanEOF, !data.isEmpty else {
            debugLog("[GzExtractor] Corrupt or oversized .gz: \(gzURL.lastPathComponent)")
            return []
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(innerName)
            try data.write(to: destination)
            return [destination]
        } catch {
            debugLog("[GzExtractor] Write failed: \(error.localizedDescription)")
            return []
        }
    }
}
