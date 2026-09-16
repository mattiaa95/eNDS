import Foundation

/// Safety net for the cartridge battery save (`Saves/<base>.sav`).
///
/// A DS save state embeds the cartridge's save RAM. Loading one therefore
/// replaces what the core believes the cartridge holds, and the core flushes
/// that older copy on top of the `.sav` on disk right there, inside the load
/// (`CartRetail::DoSavestate` → `WriteNDSSave`, synchronous). "Resume Where
/// You Left Off" performs exactly that load on *every* launch, so a player
/// who imported a `.sav` backup — or who simply played on another device —
/// can lose real progress with no undo anywhere.
///
/// So: snapshot the `.sav` immediately before a state load, and let the pause
/// menu put it back. One backup per game is the whole design; what matters is
/// *which* moment it captures. A single snapshot per session is not enough —
/// three hours of play and an in-game save after the auto-resume are exactly
/// the progress a mistaken "Load State" then destroys, and the launch-time
/// copy would not have them. Snapshotting before every load is not right
/// either: right after a load the `.sav` holds the state's SRAM, and copying
/// it would overwrite the good backup with the clobbered file. Hence the
/// stamp below: the `.sav` is re-snapshotted before a load unless it is
/// byte-for-byte the file the previous load left behind.
///
/// Note: a single `.bak` file, not a rotating history. Anything deeper is
/// a backup feature, not a safety net.
enum INDSSaveBackup {

    private static let suffix = "bak"

    /// Modification date + size of a `.sav`. APFS keeps nanosecond
    /// timestamps and the core writes the file atomically (new inode, new
    /// date), so two equal stamps mean the file has not been rewritten.
    private struct Stamp: Equatable {
        let modified: Date?
        let size: Int64?

        init(of url: URL) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            modified = attributes?[.modificationDate] as? Date
            size = attributes?[.size] as? Int64
        }

        // `Date` is a Double underneath, so the round trip through defaults
        // is exact and `==` against a fresh stat stays meaningful.
        init?(stored: [String: Double]) {
            guard let modified = stored["modified"], let size = stored["size"] else { return nil }
            self.modified = Date(timeIntervalSinceReferenceDate: modified)
            self.size = Int64(size)
        }

        var stored: [String: Double]? {
            guard let modified, let size else { return nil }
            return ["modified": modified.timeIntervalSinceReferenceDate, "size": Double(size)]
        }
    }

    private static let stampsKey = "eNDSSaveBackupStamps"

    /// Per game, the `.sav` as the previous state load left it. Recorded
    /// after the load (see `backupBeforeStateLoad`), compared before the
    /// next one. Persisted, and deliberately not reset by `beginSession`:
    /// a `.sav` nobody touched since the last load is still that load's
    /// SRAM in the next session too (auto-resume loads a state first thing),
    /// and the backup taken before it is still the better copy.
    private static var postLoadStamps: [String: Stamp] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: stampsKey) as? [String: [String: Double]] ?? [:]
            return raw.compactMapValues(Stamp.init(stored:))
        }
        set {
            UserDefaults.standard.set(newValue.compactMapValues(\.stored), forKey: stampsKey)
        }
    }

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

    /// Call when a game starts, before any state load. Kept as the session
    /// boundary for callers; the decision of whether to snapshot is made per
    /// load from the on-disk file itself (see `postLoadStamps`).
    static func beginSession(baseName: String) {}

    /// Snapshot the current `.sav` unless it is unchanged since the previous
    /// state load — then it is that state's SRAM, not the player's, and the
    /// existing backup is the one worth keeping. No-op when the game has no
    /// battery save yet (nothing to lose).
    ///
    /// Must be called on the main thread, immediately before the (synchronous)
    /// `loadState`: the post-load stamp is taken on the next main-queue turn,
    /// i.e. once the load — and the flush it triggers — has completed.
    static func backupBeforeStateLoad(baseName: String) {
        guard let save = saveURL(baseName: baseName),
              let backup = backupURL(baseName: baseName),
              FileManager.default.fileExists(atPath: save.path) else { return }
        defer {
            DispatchQueue.main.async {
                postLoadStamps[baseName] = Stamp(of: save)
            }
        }
        if let previous = postLoadStamps[baseName], previous == Stamp(of: save),
           FileManager.default.fileExists(atPath: backup.path) {
            return
        }
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
    ///
    /// Copy beside the target and swap, never remove-then-copy: a copy that
    /// dies half-way (disk full) must not leave the player with neither file.
    @discardableResult
    static func restore(baseName: String) -> Bool {
        guard let save = saveURL(baseName: baseName),
              let backup = backupURL(baseName: baseName),
              FileManager.default.fileExists(atPath: backup.path) else { return false }
        let fileManager = FileManager.default
        let staging = save.appendingPathExtension("restoring")
        try? fileManager.removeItem(at: staging)
        do {
            try fileManager.copyItem(at: backup, to: staging)
            if fileManager.fileExists(atPath: save.path) {
                _ = try fileManager.replaceItemAt(save, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: save)
            }
            postLoadStamps[baseName] = nil // the restored file deserves its own snapshot next time
            return true
        } catch {
            try? fileManager.removeItem(at: staging)
            debugLog("Save restore failed for \(baseName): \(error.localizedDescription)")
            return false
        }
    }
}
