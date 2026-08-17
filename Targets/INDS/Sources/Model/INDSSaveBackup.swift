import Foundation

/// Safety net for the cartridge battery save (`Saves/<base>.sav`).
///
/// A DS save state embeds the cartridge's save RAM. Loading one therefore
/// replaces what the core believes the cartridge holds, and the next time the
/// core flushes (`WriteNDSSave`) that older copy lands on top of the `.sav` on
/// disk. "Resume Where You Left Off" performs exactly that load on *every*
/// launch, so a player who imported a `.sav` backup — or who simply played on
/// another device — can lose real progress with no undo anywhere.
///
/// So: snapshot the `.sav` once per game session, immediately before the first
/// state load, and let the pause menu put it back. One backup per game, taken
/// at the moment it still reflects the cartridge, is the whole design.
///
/// ponytail: a single `.bak` file, not a rotating history. The one moment worth
/// recovering is "before this session's first state load"; anything deeper is a
/// backup feature, not a safety net.
enum INDSSaveBackup {

    private static let suffix = "bak"

    /// Games whose save has already been snapshotted in this app run. Reset by
    /// `beginSession(baseName:)` so each game gets exactly one snapshot per
    /// session, not one per state load — re-backing up after a load would
    /// overwrite the good copy with the clobbered one.
    private static var snapshotted: Set<String> = []

    private static func savesDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Saves", isDirectory: true)
    }

    static func saveURL(baseName: String) -> URL? {
        savesDirectory()?.appendingPathComponent(baseName).appendingPathExtension("sav")
    }

    static func backupURL(baseName: String) -> URL? {
        saveURL(baseName: baseName)?.appendingPathExtension(suffix)
    }

    /// Call when a game starts, before any state load, so this session is
    /// allowed to take its own snapshot.
    static func beginSession(baseName: String) {
        snapshotted.remove(baseName)
    }

    /// Snapshot the current `.sav` unless this session already did. No-op when
    /// the game has no battery save yet (nothing to lose).
    static func backupBeforeStateLoad(baseName: String) {
        guard !snapshotted.contains(baseName),
              let save = saveURL(baseName: baseName),
              let backup = backupURL(baseName: baseName),
              FileManager.default.fileExists(atPath: save.path) else { return }
        snapshotted.insert(baseName)
        do {
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            try FileManager.default.copyItem(at: save, to: backup)
        } catch {
            debugLog("Save backup failed for \(baseName): \(error.localizedDescription)")
        }
    }

    static func hasBackup(baseName: String) -> Bool {
        guard let backup = backupURL(baseName: baseName) else { return false }
        return FileManager.default.fileExists(atPath: backup.path)
    }

    /// When the backup was taken — shown in the confirmation so the player can
    /// tell which save they are about to go back to.
    static func backupDate(baseName: String) -> Date? {
        guard let backup = backupURL(baseName: baseName) else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: backup.path)[.modificationDate] as? Date
    }

    /// Put the snapshot back over the live `.sav`. The caller MUST reload the
    /// ROM afterwards: the core only reads `savePath` in `loadROMAtPath:`, so a
    /// plain reset would keep running with the in-memory save it already has
    /// and flush it straight back over the file we just restored.
    @discardableResult
    static func restore(baseName: String) -> Bool {
        guard let save = saveURL(baseName: baseName),
              let backup = backupURL(baseName: baseName),
              FileManager.default.fileExists(atPath: backup.path) else { return false }
        do {
            if FileManager.default.fileExists(atPath: save.path) {
                try FileManager.default.removeItem(at: save)
            }
            try FileManager.default.copyItem(at: backup, to: save)
            snapshotted.remove(baseName) // the restored file deserves its own snapshot next time
            return true
        } catch {
            debugLog("Save restore failed for \(baseName): \(error.localizedDescription)")
            return false
        }
    }
}
