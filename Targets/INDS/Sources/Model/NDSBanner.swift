import Foundation
import UIKit

/// Parses the icon/title "banner" block embedded in every retail NDS ROM,
/// and renders the embedded 32x32 game icon. Pure Swift, no dependency on
/// melonDS — reads directly from the ROM file on disk via `FileHandle`, the
/// same way `NDSHeader` reads the plain header.
///
/// Layout (GBATEK "DS Cartridge Header" / "Icon/Title" — all fields little
/// endian):
///   Header +0x068: u32 offset of the banner block. Some homebrew/hacked
///                  ROMs store 0 here (no banner) or a bogus value past EOF;
///                  both are treated as "no banner" rather than a hard
///                  failure so import/listing still succeeds — callers fall
///                  back to a placeholder icon + the plain header title.
///   Banner +0x000: u16 version (0x0001/0x0002/0x0003/0x0103). The icon,
///                  palette and 6 base titles this parser reads live at the
///                  same fixed offsets in every version — newer versions
///                  only *append* Chinese/Korean titles and animated-icon
///                  frames after +0x840, which this parser doesn't need and
///                  ignores. Version itself isn't validated for that reason.
///   Banner +0x020: 512-byte icon bitmap — 4x4 grid of 8x8-pixel tiles, tile
///                  order row-major (tile 0 = top-left ... tile 15 =
///                  bottom-right), 4bpp pixels within a tile (row-major, 2
///                  pixels/byte, left pixel in the low nibble).
///   Banner +0x220: 16 x u16 BGR555 palette entries; index 0 is always the
///                  reserved transparent color regardless of its stored bits.
///   Banner +0x240: 6 languages x 128 u16 (256 bytes) UTF-16LE titles —
///                  Japanese, English, French, German, Italian, Spanish, in
///                  that fixed order. NUL-terminated; the remainder of the
///                  128-unit slot is padding.
struct NDSBanner: Equatable {
    static let iconDimension = 32

    private enum Layout {
        static let bannerOffsetField = 0x068
        static let iconBitmapOffset = 0x020
        static let paletteOffset = 0x220
        static let paletteEntryCount = 16
        static let titlesOffset = 0x240
        static let titleCodeUnitCount = 128
        static let titleByteCount = titleCodeUnitCount * 2 // 256
        static let languageCount = 6 // ja, en, fr, de, it, es
        static let bannerSize = titlesOffset + languageCount * titleByteCount // 0x840
    }

    enum Language: Int {
        case japanese = 0, english = 1, french = 2, german = 3, italian = 4, spanish = 5
    }

    /// 32x32 palette indices (0...15), row-major, top-left origin.
    private let iconPixels: [UInt8]
    /// 16 raw BGR555 colors exactly as stored in the ROM; index 0 always
    /// renders transparent regardless of its bits (NDS convention).
    private let palette: [UInt16]
    /// Raw per-language titles with embedded newlines preserved (banner text
    /// is authored as up to 3 display lines), trimmed of the NUL padding.
    /// Index order matches `Language`.
    private let titles: [String]

    /// The banner's own English title, newlines preserved as authored.
    /// Intended for a multi-line title block (e.g. a detail screen), mirroring
    /// how the DS system menu itself renders banner titles.
    var englishTitle: String { titles[Language.english.rawValue] }

    /// `englishTitle` flattened to a single line (newlines → spaces, blank
    /// lines dropped, whitespace collapsed at the joins) — better suited for
    /// grid-cell titles, search and sorting than the raw multi-line text.
    var displayTitle: String {
        englishTitle
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private enum ParseError: Error {
        case headerTooSmall
        case noBanner
        case truncatedBanner
    }

    static func read(from url: URL) throws -> NDSBanner {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let headerChunk = try handle.read(upToCount: Layout.bannerOffsetField + 4),
              headerChunk.count >= Layout.bannerOffsetField + 4 else {
            throw ParseError.headerTooSmall
        }
        let bannerOffset = Int(u32LE(headerChunk, Layout.bannerOffsetField))
        guard bannerOffset > 0 else {
            throw ParseError.noBanner
        }

        try handle.seek(toOffset: UInt64(bannerOffset))
        guard let banner = try handle.read(upToCount: Layout.bannerSize),
              banner.count == Layout.bannerSize else {
            throw ParseError.truncatedBanner
        }

        var pixels = [UInt8](repeating: 0, count: iconDimension * iconDimension)
        for tileIndex in 0..<16 {
            let tileX = tileIndex % 4
            let tileY = tileIndex / 4
            let tileByteOffset = Layout.iconBitmapOffset + tileIndex * 32
            for byteInTile in 0..<32 {
                let byte = banner[banner.startIndex + tileByteOffset + byteInTile]
                let row = byteInTile / 4
                let colPair = byteInTile % 4
                let px = tileX * 8 + colPair * 2
                let py = tileY * 8 + row
                pixels[py * iconDimension + px] = byte & 0x0F           // left pixel: low nibble
                pixels[py * iconDimension + px + 1] = (byte >> 4) & 0x0F // right pixel: high nibble
            }
        }

        var paletteEntries = [UInt16](repeating: 0, count: Layout.paletteEntryCount)
        for i in 0..<Layout.paletteEntryCount {
            paletteEntries[i] = u16LE(banner, Layout.paletteOffset + i * 2)
        }

        var titleStrings = [String](repeating: "", count: Layout.languageCount)
        for lang in 0..<Layout.languageCount {
            let base = Layout.titlesOffset + lang * Layout.titleByteCount
            var units: [UInt16] = []
            units.reserveCapacity(Layout.titleCodeUnitCount)
            for u in 0..<Layout.titleCodeUnitCount {
                let unit = u16LE(banner, base + u * 2)
                if unit == 0 { break } // NUL-terminated; rest of the slot is padding
                units.append(unit)
            }
            titleStrings[lang] = String(decoding: units, as: UTF16.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return NDSBanner(iconPixels: pixels, palette: paletteEntries, titles: titleStrings)
    }

    /// Renders the 32x32 icon to a `UIImage` from the raw palette indices.
    /// No scaling/interpolation happens here — draw the result with
    /// `.interpolation(.none)` so the pixel art stays crisp when scaled up.
    func renderIcon() -> UIImage? {
        // Straight (unpremultiplied-safe) RGBA8888: transparent pixels (index
        // 0) are left at the array's zero default for both color and alpha,
        // so the buffer also satisfies the premultiplied-alpha invariant
        // (color <= alpha) exactly — no special-casing needed at draw time.
        var rgba = [UInt8](repeating: 0, count: iconPixels.count * 4)
        for (i, index) in iconPixels.enumerated() where index != 0 {
            let color = palette[Int(index)]
            let r5 = color & 0x1F
            let g5 = (color >> 5) & 0x1F
            let b5 = (color >> 10) & 0x1F
            rgba[i * 4 + 0] = expand5to8(r5)
            rgba[i * 4 + 1] = expand5to8(g5)
            rgba[i * 4 + 2] = expand5to8(b5)
            rgba[i * 4 + 3] = 255
        }

        let dimension = Self.iconDimension
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: dimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Replicates a 5-bit color channel (0...31) into 8 bits (0...255) by bit
    /// replication (`v<<3 | v>>2`), the standard exact GBA/NDS 15-bit → 8-bit
    /// color expansion (0 → 0, 31 → 255).
    private func expand5to8(_ v5: UInt16) -> UInt8 {
        UInt8((v5 << 3) | (v5 >> 2))
    }

    private static func u16LE(_ data: Data, _ offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        guard base + 1 < data.endIndex else { return 0 }
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    private static func u32LE(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        guard base + 3 < data.endIndex else { return 0 }
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }
}
