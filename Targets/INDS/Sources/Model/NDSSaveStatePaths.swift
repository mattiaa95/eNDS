import UIKit

/// Mirrors `MelonDSCoreBridge`'s save-state path convention
/// (`Documents/SaveStates/<romBaseName>/slot<N>.mln`, `.../auto.mln`) in pure
/// Swift so the ROM library can list existing save states for display
/// (`ROMDetailView`, the grid's "Resume" badge) without instantiating a core
/// — the real bridge only knows a ROM's base name (and therefore this path)
/// *after* `loadROMAtPath:biosDirectory:error:` has fully loaded it, which is
/// far too heavy to do just to list files. Core/MelonDSCoreBridge.* is
/// off-limits to edit, so this intentionally duplicates that (tiny, stable)
/// convention instead of exposing a new bridge method. Keep in sync with
/// `-[MelonDSCoreBridge saveStateDirectoryPath]` if it ever changes.
enum NDSSaveStatePaths {
    static let numberedSlotCount = 4

    static func directory(forBaseName baseName: String) -> URL? {
        guard !baseName.isEmpty,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("SaveStates", isDirectory: true)
            .appendingPathComponent(baseName, isDirectory: true)
    }

    static func slotPath(forBaseName baseName: String, slot: Int) -> URL? {
        directory(forBaseName: baseName)?.appendingPathComponent("slot\(slot).mln")
    }

    static func autoPath(forBaseName baseName: String) -> URL? {
        directory(forBaseName: baseName)?.appendingPathComponent("auto.mln")
    }

    /// True if any save state (auto or numbered) exists for this ROM. Used
    /// for the grid/classic cell's "Resume" badge.
    static func hasAnySaveState(baseName: String) -> Bool {
        let fm = FileManager.default
        if let auto = autoPath(forBaseName: baseName), fm.fileExists(atPath: auto.path) {
            return true
        }
        for slot in 0..<numberedSlotCount {
            if let path = slotPath(forBaseName: baseName, slot: slot), fm.fileExists(atPath: path.path) {
                return true
            }
        }
        return false
    }

    /// Builds slot info (with on-disk modification dates) for display in
    /// `ROMDetailView`. Reuses `NDSSaveStateSlotInfo` from the pause menu's
    /// save-state UI so both surfaces agree on slot numbering/labels.
    static func slotInfos(forBaseName baseName: String) -> [NDSSaveStateSlotInfo] {
        let fm = FileManager.default
        var infos: [NDSSaveStateSlotInfo] = []
        if let auto = autoPath(forBaseName: baseName), fm.fileExists(atPath: auto.path) {
            infos.append(NDSSaveStateSlotInfo(slot: -1, modifiedDate: modificationDate(at: auto)))
        }
        for slot in 0..<numberedSlotCount {
            guard let path = slotPath(forBaseName: baseName, slot: slot), fm.fileExists(atPath: path.path) else { continue }
            infos.append(NDSSaveStateSlotInfo(slot: slot, modifiedDate: modificationDate(at: path)))
        }
        return infos
    }

    /// Renames the whole save-state directory (used when a ROM is renamed).
    static func rename(fromBaseName oldName: String, toBaseName newName: String) {
        guard let oldDir = directory(forBaseName: oldName), let newDir = directory(forBaseName: newName),
              FileManager.default.fileExists(atPath: oldDir.path) else { return }
        try? FileManager.default.removeItem(at: newDir)
        try? FileManager.default.moveItem(at: oldDir, to: newDir)
    }

    /// Deletes the whole save-state directory (used by "Delete ROM + Save Data").
    static func delete(baseName: String) {
        guard let dir = directory(forBaseName: baseName) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Frees a single slot. Without this, someone who filled all four could
    /// only ever overwrite one — there was no way to clear a state they no
    /// longer wanted. `slot < 0` is the auto-save.
    @discardableResult
    static func deleteSlot(baseName: String, slot: Int) -> Bool {
        let url = slot < 0 ? autoPath(forBaseName: baseName)
                           : slotPath(forBaseName: baseName, slot: slot)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            if let thumb = thumbnailPath(forBaseName: baseName, slot: slot) {
                try? FileManager.default.removeItem(at: thumb)
            }
            return true
        } catch {
            debugLog("Deleting save state slot \(slot) failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func modificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    /// Fecha en disco de un slot (`slot < 0` = autoguardado), `nil` si está
    /// vacío. Es lo que usa la hoja de Save/Load para refrescarse al abrir:
    /// los arrays que le llegan se calcularon al presentar el menú de pausa y
    /// se quedan viejos si se guarda y se reabre sin salir de la pausa.
    static func modifiedDate(baseName: String, slot: Int) -> Date? {
        let url = slot < 0 ? autoPath(forBaseName: baseName)
                           : slotPath(forBaseName: baseName, slot: slot)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return modificationDate(at: url)
    }

    // MARK: - Miniaturas por slot
    //
    // Un PNG del frame superior junto a cada `.mln`, con el mismo nombre. Sin
    // esto los cuatro slots son cuatro filas idénticas y elegir cuál cargar (o
    // cuál sacrificar al guardar) es adivinar por la fecha. Vive aquí y no en
    // `ThumbnailManager` porque ese guarda una imagen por ROM y estas son una
    // por slot, con el ciclo de vida del propio save state: se borran con él.

    static func thumbnailPath(forBaseName baseName: String, slot: Int) -> URL? {
        let name = slot < 0 ? "auto" : "slot\(slot)"
        return directory(forBaseName: baseName)?.appendingPathComponent("\(name).png")
    }

    static func saveThumbnail(_ image: UIImage, baseName: String, slot: Int) {
        guard let url = thumbnailPath(forBaseName: baseName, slot: slot),
              let data = image.pngData() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func thumbnail(baseName: String, slot: Int) -> UIImage? {
        guard let url = thumbnailPath(forBaseName: baseName, slot: slot) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
