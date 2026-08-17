//
//  NDSCheat.swift
//  eNDS
//
//  New (no iGBA equivalent — GBA cheats are a different, simpler format).
//  Swift-side model + on-disk persistence for melonDS Action Replay codes.
//  There is no separate database: the on-disk `.mch` file *is* the model
//  (per-cheat `enabled` included), written in melonDS's own ARCodeFile text
//  format (see Vendor/melonDS/src/ARCodeFile.cpp Load/Save) so it stays
//  loadable by `-[MelonDSCoreBridge reloadCheatsFromFile:enabled:]` — and,
//  if anyone ever pulled it out, by upstream melonDS itself.
//

import Foundation

/// One Action Replay code as edited in the Cheats sheet. `code` is the raw
/// multi-line "AAAAAAAA VVVVVVVV" textarea contents exactly as the user
/// typed them — only split/validated into individual hex-pair lines when
/// persisting to disk (`NDSCheatFileStore`) or checking validity
/// (`NDSCheatValidation`).
struct NDSCheat: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var code: String
    var enabled: Bool
}

enum NDSCheatValidation {
    /// melonDS's own AR data-line grammar (ARCodeFile.cpp: each line is read
    /// with `sscanf(line, "%08X %08X", &c0, &c1)`): two 8-digit hex words —
    /// address then value — separated by one space.
    private static let hexPairPattern = "^[0-9A-Fa-f]{8} [0-9A-Fa-f]{8}$"

    /// `code`'s non-blank lines, trimmed. Blank lines are just spacing and
    /// are dropped, not treated as errors.
    static func codeLines(_ code: String) -> [String] {
        code
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func isValidLine(_ line: String) -> Bool {
        line.range(of: hexPairPattern, options: .regularExpression) != nil
    }

    /// True only if every non-blank line is a valid hex pair *and* at least
    /// one such line exists. An empty/all-invalid code must never be
    /// persisted as `enabled`: melonDS's `AREngine::RunCheat` indexes
    /// `Code[Code.size() - 1]` unconditionally, which is undefined behavior
    /// for a zero-length code — the exact shape of iGBA's own historical P0
    /// cheats crash. This guard is checked independently at every layer
    /// (the toggle in `NDSCheatsView`, serialization here, and the bridge's
    /// own filter in `-reloadCheatsFromFile:enabled:`) — belt and suspenders.
    static func isValid(_ code: String) -> Bool {
        let lines = codeLines(code)
        return !lines.isEmpty && lines.allSatisfy(isValidLine)
    }
}

/// Reads/writes a game's cheat list as melonDS's own `.mch` ARCodeFile text
/// format, always as a flat "ROOT" list (no categories — this app's Cheats
/// sheet is a single flat list per game).
enum NDSCheatFileStore {
    /// `Documents/Saves/<baseName>.mch` — same directory as the battery save
    /// (`ROMFile.saveFileURL`'s `Documents/Saves/<baseName>.sav` convention,
    /// mirroring `MelonDSCoreBridge`'s own `loadROMAtPath:`), melonDS's own
    /// cheat-file extension (melonDS's Qt frontend, EmuInstance.cpp
    /// `loadCheats`: `getAssetPath(..., ".mch")`).
    static func fileURL(forBaseName baseName: String) -> URL? {
        guard !baseName.isEmpty, let dir = try? ROMStorageManager.savesDirectoryURL() else { return nil }
        return dir.appendingPathComponent(baseName).appendingPathExtension("mch")
    }

    /// Empty if `baseName` has no cheat file yet, or it doesn't parse —
    /// never throws, matching `ARCodeFile::Load` treating a missing file as
    /// a normal, error-free empty list rather than a failure.
    static func load(forBaseName baseName: String) -> [NDSCheat] {
        guard let url = fileURL(forBaseName: baseName),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Overwrites the whole file with `cheats`. Best-effort (a write
    /// failure — e.g. disk full — just leaves the previous on-disk version
    /// in place; there's nothing actionable for the user to do about it).
    static func save(_ cheats: [NDSCheat], forBaseName baseName: String) {
        guard let url = fileURL(forBaseName: baseName) else { return }
        try? serialize(cheats).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - melonDS ARCodeFile text format

    private static func serialize(_ cheats: [NDSCheat]) -> String {
        var text = "ROOT\n\n"
        for cheat in cheats {
            let lines = NDSCheatValidation.codeLines(cheat.code)
            // Same empty-code guard as -reloadCheatsFromFile:enabled: below
            // — never write a code as enabled if it has no valid lines.
            let enabled = cheat.enabled && !lines.isEmpty
            let name = cheat.name
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            text += "CODE \(enabled ? 1 : 0) \(name)\n"
            for line in lines {
                text += "\(line.uppercased())\n"
            }
            text += "\n"
        }
        return text
    }

    /// Deliberately lenient: unrecognized lines (a foreign file's CAT/DESC,
    /// stray text, ...) are just skipped rather than failing the whole parse
    /// — this only ever needs to round-trip what `serialize(_:)` itself
    /// wrote, and must never crash/throw on a hand-edited file.
    private static func parse(_ text: String) -> [NDSCheat] {
        var cheats: [NDSCheat] = []
        var pendingName: String?
        var pendingEnabled = false
        var pendingLines: [String] = []

        func flush() {
            guard let name = pendingName else { return }
            cheats.append(NDSCheat(name: name, code: pendingLines.joined(separator: "\n"), enabled: pendingEnabled))
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("CODE ") {
                flush()
                pendingLines = []
                let rest = line.dropFirst("CODE ".count)
                if let spaceIndex = rest.firstIndex(of: " ") {
                    pendingEnabled = rest[rest.startIndex..<spaceIndex] == "1"
                    pendingName = String(rest[rest.index(after: spaceIndex)...])
                } else {
                    pendingEnabled = false
                    pendingName = rest.isEmpty ? nil : String(rest)
                }
            } else if NDSCheatValidation.isValidLine(line) {
                pendingLines.append(line.uppercased())
            }
            // ROOT / CAT / DESC / blank / garbage: ignored.
        }
        flush()

        return cheats
    }
}
