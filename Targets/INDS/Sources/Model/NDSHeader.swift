import Foundation

struct NDSHeader: Equatable {
    let title: String
    let gameCode: String
    let makerCode: String
    let unitCode: UInt8

    static func read(from url: URL) throws -> NDSHeader {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            do {
                try handle.close()
            } catch {
                debugLog("Failed to close ROM file handle: \(error.localizedDescription)")
            }
        }

        let data = try handle.read(upToCount: 0x20) ?? Data()
        // Every field below is inside the first 0x20 bytes; a real header is
        // 0x200. Anything shorter is a truncated download, and Data's range
        // subscript traps (not throws) past the end.
        guard data.count >= 0x20 else {
            throw ROMStorageError.invalidROM(NSLocalizedString("The NDS header is incomplete.", comment: "Reason appended to the invalid-ROM import error"))
        }

        return NDSHeader(
            title: Self.string(in: data, range: 0x00..<0x0C),
            gameCode: Self.string(in: data, range: 0x0C..<0x10),
            makerCode: Self.string(in: data, range: 0x10..<0x12),
            unitCode: data.count > 0x12 ? data[0x12] : 0
        )
    }

    private static func string(in data: Data, range: Range<Int>) -> String {
        let bytes = data[range].prefix { $0 != 0 }
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }
}
