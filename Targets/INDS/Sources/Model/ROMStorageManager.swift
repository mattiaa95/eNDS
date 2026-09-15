import Foundation

enum ROMStorageError: LocalizedError {
    case unsupportedFileType(String)
    case duplicateFile(String)
    case invalidROM(String)
    case emptyFile
    case fileTooLarge
    case unavailableDocumentsDirectory
    case noMatchingROM(String)
    case zipContainsNoSupportedFiles
    case invalidName
    case notEnoughSpace

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return String(
                format: NSLocalizedString(
                    "Unsupported file type .%1$@. Import a .nds ROM, a .zip/.7z/.gz archive, or a .sav save file.",
                    comment: "Import Failed alert: the user picked a file whose extension the importer doesn't accept. %1$@ is the file extension."
                ),
                ext
            )
        case .duplicateFile(let name):
            return String(
                format: NSLocalizedString(
                    "\"%1$@\" already exists in your library.",
                    comment: "Import Failed alert: the user imported or renamed a file to a name already present in the library. %1$@ is the filename."
                ),
                name
            )
        case .invalidROM(let reason):
            return String(
                format: NSLocalizedString(
                    "Invalid NDS ROM. %1$@",
                    comment: "Import Failed alert: the user imported a .nds file that failed header validation. %1$@ is the reason."
                ),
                reason
            )
        case .emptyFile:
            return NSLocalizedString(
                "The selected file is empty.",
                comment: "Import Failed alert: the user imported a zero-byte ROM or save file."
            )
        case .fileTooLarge:
            return NSLocalizedString(
                "This file is too large to be a DS ROM.",
                comment: "Import Failed alert: the user imported a ROM bigger than the supported size limit."
            )
        case .unavailableDocumentsDirectory:
            return NSLocalizedString(
                "The app documents directory is unavailable.",
                comment: "Import Failed alert: the app could not reach its own storage folder while importing."
            )
        case .noMatchingROM(let name):
            return String(
                format: NSLocalizedString(
                    "No ROM named \"%1$@.nds\" was found. Import the ROM before its save file.",
                    comment: "Import Failed alert: the user imported a .sav save file with no matching ROM in the library. %1$@ is the save file's base name."
                ),
                name
            )
        case .zipContainsNoSupportedFiles:
            return NSLocalizedString(
                "This archive doesn't contain any .nds or .sav files.",
                comment: "Import Failed alert: the user imported a .zip/.7z/.gz archive with nothing usable inside."
            )
        case .invalidName:
            return NSLocalizedString(
                "Enter a valid name.",
                comment: "Import Failed alert: the user confirmed a ROM rename with an empty or invalid name."
            )
        case .notEnoughSpace:
            return NSLocalizedString(
                "Not enough free space on this device. Free some up and try again.",
                comment: "Import Failed alert: the device does not have room for the file being imported."
            )
        }
    }
}

/// What a single `importAny(from:replaceExisting:)` call produced. A plain
/// `.nds`/`.sav` import always yields exactly one URL (or throws); a `.zip`
/// or `.7z` archive can yield several, and can partially fail (e.g. one
/// duplicate among five ROMs) without the whole import throwing — those
/// per-entry problems are collected in `failureMessages` instead.
struct ROMImportResult {
    var importedROMURLs: [URL] = []
    var importedSaveURLs: [URL] = []
    var failureMessages: [String] = []
}

enum ROMStorageManager {
    private static let romsFolderName = "ROMs"
    private static let biosFolderName = "BIOS"
    private static let savesFolderName = "Saves"
    private static let maxROMSize: Int64 = 512 * 1024 * 1024
    private static let saveExtension = "sav"
    private static let zipROMExtensions: Set<String> = ["nds"]
    private static let zipSaveExtensions: Set<String> = ["sav"]

    static func romsDirectoryURL() throws -> URL {
        try directoryURL(named: romsFolderName)
    }

    static func biosDirectoryURL() throws -> URL {
        try directoryURL(named: biosFolderName)
    }

    /// `Documents/Saves` — matches `MelonDSCoreBridge.mm`'s own battery-save
    /// convention (`Documents/Saves/<romBaseName>.sav`) exactly, so a save
    /// imported here is picked up the next time the ROM loads.
    static func savesDirectoryURL() throws -> URL {
        try directoryURL(named: savesFolderName)
    }

    static func listROMs() throws -> [ROMFile] {
        let directory = try romsDirectoryURL()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { $0.pathExtension.lowercased() == "nds" }
            .map { url in
                let values = try url.resourceValues(forKeys: [.creationDateKey])
                return ROMFile(fileURL: url, creationDate: values.creationDate ?? .distantPast)
            }
    }

    // MARK: - Import (dispatch by extension)

    /// Single entry point for every import surface (the "+" file importer,
    /// external `onOpenURL`): dispatches on `sourceURL`'s extension to the
    /// right handler. `.nds`/`.sav` throw on failure (duplicate, no matching
    /// ROM, ...); `.zip`/`.7z` never throw for individual bad entries inside
    /// them — those are reported in `ROMImportResult.failureMessages` — but
    /// do throw `zipContainsNoSupportedFiles` if the archive contains
    /// nothing usable at all.
    @discardableResult
    static func importAny(from sourceURL: URL, replaceExisting: Bool) throws -> ROMImportResult {
        switch sourceURL.pathExtension.lowercased() {
        case "nds":
            let url = try importROM(from: sourceURL, replaceExisting: replaceExisting)
            return ROMImportResult(importedROMURLs: [url])
        case "zip":
            return try importROMsFromArchive(at: sourceURL, replaceExisting: replaceExisting) {
                NDSZipExtractor.extractEntries(fromZip: $0, matchingExtensions: $1, to: $2)
            }
        case "7z":
            return try importROMsFromArchive(at: sourceURL, replaceExisting: replaceExisting) {
                NDS7zExtractor.extractEntries(from7z: $0, matchingExtensions: $1, to: $2)
            }
        case "gz":
            return try importROMsFromArchive(at: sourceURL, replaceExisting: replaceExisting) {
                NDSGzExtractor.extractEntries(fromGz: $0, matchingExtensions: $1, to: $2)
            }
        case saveExtension:
            let url = try importSave(from: sourceURL, replaceExisting: replaceExisting)
            return ROMImportResult(importedSaveURLs: [url])
        case let ext:
            throw ROMStorageError.unsupportedFileType(ext.isEmpty ? "unknown" : ext)
        }
    }

    /// Headroom left free on top of the file itself. Filling the disk
    /// completely does not just break the import: it breaks the auto-save and
    /// the save states of the game already running, which is far worse.
    private static let freeSpaceMargin: Int64 = 100 * 1024 * 1024

    /// `false` only when we know it does not fit. If the system will not give
    /// the number, nothing is blocked: better to let the copy fail with its
    /// real error than to refuse a legitimate import for lack of a measurement.
    static func hasRoom(forBytes bytes: Int64) -> Bool {
        guard let docs = try? romsDirectoryURL(),
              let free = try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                  .volumeAvailableCapacityForImportantUsage else { return true }
        return free > bytes + freeSpaceMargin
    }

    @discardableResult
    static func importROM(from sourceURL: URL, replaceExisting: Bool) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "nds" else {
            throw ROMStorageError.unsupportedFileType(ext.isEmpty ? "unknown" : ext)
        }

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = attributes[.size] as? Int64 ?? 0
        guard size > 0 else { throw ROMStorageError.emptyFile }
        guard size <= maxROMSize else { throw ROMStorageError.fileTooLarge }
        guard hasRoom(forBytes: size) else { throw ROMStorageError.notEnoughSpace }

        _ = try NDSHeader.read(from: sourceURL)

        let destinationURL = try romsDirectoryURL().appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path), !replaceExisting {
            throw ROMStorageError.duplicateFile(sourceURL.lastPathComponent)
        }

        try copyItem(from: sourceURL, to: destinationURL, replaceExisting: replaceExisting)
        return destinationURL
    }

    /// Imports a `.sav` battery save, matching it to an already-imported ROM
    /// by base filename (case-insensitive). Throws `.noMatchingROM` rather
    /// than silently copying an orphaned save that nothing would ever read.
    @discardableResult
    static func importSave(from sourceURL: URL, replaceExisting: Bool) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == saveExtension else {
            throw ROMStorageError.unsupportedFileType(ext.isEmpty ? "unknown" : ext)
        }

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = attributes[.size] as? Int64 ?? 0
        guard size > 0 else { throw ROMStorageError.emptyFile }

        let savBaseName = sourceURL.deletingPathExtension().lastPathComponent
        guard let matchedROMBaseName = try matchingROMBaseName(forSaveBaseName: savBaseName) else {
            throw ROMStorageError.noMatchingROM(savBaseName)
        }

        let destinationURL = try savesDirectoryURL()
            .appendingPathComponent(matchedROMBaseName)
            .appendingPathExtension(saveExtension)
        if FileManager.default.fileExists(atPath: destinationURL.path), !replaceExisting {
            throw ROMStorageError.duplicateFile(destinationURL.lastPathComponent)
        }

        try copyItem(from: sourceURL, to: destinationURL, replaceExisting: replaceExisting)
        return destinationURL
    }

    /// Finds a `.nds` file in the ROMs directory whose base name matches
    /// `saveBaseName` case-insensitively, returning that file's *exact*
    /// on-disk base name (so the copied `.sav` lines up byte-for-byte with
    /// what `MelonDSCoreBridge` derives from the real ROM filename).
    private static func matchingROMBaseName(forSaveBaseName saveBaseName: String) throws -> String? {
        let directory = try romsDirectoryURL()
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for url in urls where url.pathExtension.lowercased() == "nds" {
            let romBaseName = url.deletingPathExtension().lastPathComponent
            if romBaseName.caseInsensitiveCompare(saveBaseName) == .orderedSame {
                return romBaseName
            }
        }
        return nil
    }

    /// Extracts every `.nds`/`.sav` entry from `sourceURL` (a `.zip` or
    /// `.7z` archive — `extract` is `NDSZipExtractor.extractEntries` or
    /// `NDS7zExtractor.extractEntries`, whichever matches `sourceURL`'s
    /// extension) into a scratch directory, imports the ROMs first, then
    /// the saves (so a save bundled alongside its ROM in the same archive
    /// can match it), and reports any per-entry failures instead of
    /// aborting the whole batch. Both archive formats share this exact
    /// success/duplicate/error flow — only the extraction step differs.
    private static func importROMsFromArchive(
        at sourceURL: URL,
        replaceExisting: Bool,
        extract: (_ archiveURL: URL, _ extensions: Set<String>, _ directory: URL) -> [URL]
    ) throws -> ROMImportResult {
        let fileManager = FileManager.default
        let tmpDir = fileManager.temporaryDirectory.appendingPathComponent("ROMImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tmpDir) }

        // The whole extraction lands in tmp BEFORE importROM applies its own
        // per-entry guard, and it is the phase that eats the most disk. The
        // compressed size is a lower bound on what comes out: if even that
        // does not fit, a localized error now beats filling the disk halfway.
        // ponytail: knowingly a lower bound — an archive that expands to much
        // more can still fill tmp and will fail with the extractor's raw
        // error, exactly as before.
        let archiveSize = ((try? fileManager.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64) ?? 0
        guard hasRoom(forBytes: archiveSize) else { throw ROMStorageError.notEnoughSpace }

        let extracted = extract(sourceURL, zipROMExtensions.union(zipSaveExtensions), tmpDir)
        guard !extracted.isEmpty else {
            throw ROMStorageError.zipContainsNoSupportedFiles
        }

        var result = ROMImportResult()
        let romEntries = extracted.filter { zipROMExtensions.contains($0.pathExtension.lowercased()) }
        let saveEntries = extracted.filter { zipSaveExtensions.contains($0.pathExtension.lowercased()) }

        for romURL in romEntries {
            do {
                result.importedROMURLs.append(try importROM(from: romURL, replaceExisting: replaceExisting))
            } catch {
                result.failureMessages.append(error.localizedDescription)
            }
        }
        for saveURL in saveEntries {
            do {
                result.importedSaveURLs.append(try importSave(from: saveURL, replaceExisting: replaceExisting))
            } catch {
                result.failureMessages.append(error.localizedDescription)
            }
        }
        return result
    }

    // MARK: - Delete

    /// Deletes the ROM file itself, and — when `alsoDeleteSaveData` is true —
    /// its battery save, save states, cached icon and thumbnail too, plus the
    /// per-ROM UserDefaults entries (favorite/play time/last played), so
    /// nothing orphaned survives under this base name.
    static func deleteROM(_ rom: ROMFile, alsoDeleteSaveData: Bool) throws {
        try FileManager.default.removeItem(at: rom.fileURL)
        guard alsoDeleteSaveData else { return }

        if let saveURL = rom.saveFileURL {
            try? FileManager.default.removeItem(at: saveURL)
        }
        // The `.sav.bak` safety net too: left behind, a later ROM imported
        // under this name would be offered "Recover Cartridge Save" with
        // *this* game's SRAM.
        if let backupURL = INDSSaveBackup.backupURL(baseName: rom.baseName) {
            try? FileManager.default.removeItem(at: backupURL)
        }
        NDSSaveStatePaths.delete(baseName: rom.baseName)
        ROMIconStore.invalidate(baseName: rom.baseName)
        ThumbnailManager.invalidate(baseName: rom.baseName)

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "\(rom.filename)_isFavorite")
        defaults.removeObject(forKey: "\(rom.filename)_playTime")
        defaults.removeObject(forKey: "\(rom.filename)_lastPlayed")
    }

    // MARK: - Rename

    /// Renames the ROM file and every companion file/UserDefaults entry keyed
    /// by its base name, so a rename never orphans save data or resets
    /// favorite/play-time/last-played history. Returns the ROM's new URL.
    @discardableResult
    static func renameROM(_ rom: ROMFile, toBaseName rawNewBaseName: String) throws -> URL {
        let newBaseName = rawNewBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        // 240 bytes leaves room for the longest companion suffix (`.sav.bak`)
        // under APFS's 255-byte name limit, so no derived file can ever fail
        // to be written for a name the ROM itself accepted.
        guard !newBaseName.isEmpty, !newBaseName.contains("/"), !newBaseName.contains(":"),
              newBaseName.utf8.count <= 240 else {
            throw ROMStorageError.invalidName
        }
        guard newBaseName != rom.baseName else {
            return rom.fileURL
        }

        let newFilename = (newBaseName as NSString).appendingPathExtension("nds") ?? "\(newBaseName).nds"
        let newROMURL = try romsDirectoryURL().appendingPathComponent(newFilename)
        if FileManager.default.fileExists(atPath: newROMURL.path) {
            throw ROMStorageError.duplicateFile(newFilename)
        }
        // Save data already under the target name is a "Delete ROM Only"
        // leftover, kept on purpose for a re-import — refuse rather than
        // silently wipe it.
        let newSaveURL = try savesDirectoryURL().appendingPathComponent(newBaseName).appendingPathExtension("sav")
        if FileManager.default.fileExists(atPath: newSaveURL.path) {
            throw ROMStorageError.duplicateFile(newSaveURL.lastPathComponent)
        }
        if NDSSaveStatePaths.hasAnySaveState(baseName: newBaseName) {
            throw ROMStorageError.duplicateFile(newBaseName)
        }

        // The battery save moves first and for real: a rename that silently
        // left the `.sav` behind under the old name would look like lost
        // progress. If the ROM move then fails, put the save back.
        let oldSaveURL = rom.saveFileURL
        let hasSave = oldSaveURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if hasSave, let oldSaveURL {
            try FileManager.default.moveItem(at: oldSaveURL, to: newSaveURL)
        }
        do {
            try FileManager.default.moveItem(at: rom.fileURL, to: newROMURL)
        } catch {
            if hasSave, let oldSaveURL {
                try? FileManager.default.moveItem(at: newSaveURL, to: oldSaveURL)
            }
            throw error
        }

        if let oldBackup = INDSSaveBackup.backupURL(baseName: rom.baseName),
           let newBackup = INDSSaveBackup.backupURL(baseName: newBaseName),
           FileManager.default.fileExists(atPath: oldBackup.path) {
            try? FileManager.default.removeItem(at: newBackup)
            try? FileManager.default.moveItem(at: oldBackup, to: newBackup)
        }
        NDSSaveStatePaths.rename(fromBaseName: rom.baseName, toBaseName: newBaseName)
        ROMIconStore.rename(fromBaseName: rom.baseName, toBaseName: newBaseName)
        ThumbnailManager.rename(fromBaseName: rom.baseName, toBaseName: newBaseName)

        let defaults = UserDefaults.standard
        let oldFilename = rom.filename
        for suffix in ["_isFavorite", "_playTime", "_lastPlayed"] {
            let oldKey = "\(oldFilename)\(suffix)"
            let newKey = "\(newFilename)\(suffix)"
            if let value = defaults.object(forKey: oldKey) {
                defaults.set(value, forKey: newKey)
                defaults.removeObject(forKey: oldKey)
            }
        }

        return newROMURL
    }

    static func copyItem(from sourceURL: URL, to destinationURL: URL, replaceExisting: Bool) throws {
        let fileManager = FileManager.default
        // Opening a file from our own Files folder ("On My iPhone/eNDS/ROMs")
        // hands us source == destination (with a /private prefix). Removing
        // the destination first would delete the only copy — nothing to do.
        if sourceURL.standardizedFileURL.resolvingSymlinksInPath() == destinationURL.standardizedFileURL.resolvingSymlinksInPath() {
            return
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            guard replaceExisting else {
                throw ROMStorageError.duplicateFile(destinationURL.lastPathComponent)
            }
            // Copy beside the target and swap, never remove-then-copy: a copy
            // that dies half-way (disk full, provider hiccup) must not leave
            // the user with neither file — this is the "Replace?" path for
            // battery saves. Dotfile so `listROMs` never lists the staging copy.
            let staging = destinationURL.deletingLastPathComponent()
                .appendingPathComponent(".\(destinationURL.lastPathComponent).importing")
            try? fileManager.removeItem(at: staging)
            do {
                try fileManager.copyItem(at: sourceURL, to: staging)
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: staging)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
            return
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func directoryURL(named name: String) throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ROMStorageError.unavailableDocumentsDirectory
        }
        let directory = documents.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
