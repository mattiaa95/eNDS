import Foundation

struct ROMFile: Identifiable, Equatable {
    let id: String
    let filename: String
    let fileURL: URL
    let creationDate: Date
    let header: NDSHeader?
    /// Parsed icon/title banner (killer-feature game icon + official title).
    /// `nil` for ROMs with no valid banner (some homebrew/hacks) — callers
    /// fall back to `header.title` / the filename and an initials placeholder.
    let banner: NDSBanner?

    /// Filename without its extension — the shared key used to keep every
    /// per-ROM companion file (`.sav`, save states, cached icon, thumbnail)
    /// and UserDefaults entry in sync with the ROM itself.
    var baseName: String { (filename as NSString).deletingPathExtension }

    /// Prefers the banner's official English title (flattened to one line)
    /// over the coarse 12-character ASCII title in the plain header, and
    /// finally the filename — matching `NDSHeader.title`'s own fallback chain.
    var displayName: String {
        if let bannerTitle = banner?.displayTitle, !bannerTitle.isEmpty {
            return bannerTitle
        }
        if let title = header?.title, !title.isEmpty {
            return title
        }
        return fileURL.deletingPathExtension().lastPathComponent
    }

    var gameCode: String {
        header?.gameCode.isEmpty == false ? header?.gameCode ?? "----" : "----"
    }

    /// Battery save file for this ROM, if `MelonDSCoreBridge` has ever
    /// written one (`Documents/Saves/<baseName>.sav` — see `loadROMAtPath:`
    /// in MelonDSCoreBridge.mm) or the user imported one.
    var saveFileURL: URL? {
        try? ROMStorageManager.savesDirectoryURL().appendingPathComponent(baseName).appendingPathExtension("sav")
    }

    var hasSaveFile: Bool {
        guard let url = saveFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var hasAnySaveState: Bool {
        NDSSaveStatePaths.hasAnySaveState(baseName: baseName)
    }

    var isFavorite: Bool {
        get { UserDefaults.standard.bool(forKey: "\(filename)_isFavorite") }
        set { UserDefaults.standard.set(newValue, forKey: "\(filename)_isFavorite") }
    }

    var playTime: TimeInterval {
        get { UserDefaults.standard.double(forKey: "\(filename)_playTime") }
        set { UserDefaults.standard.set(newValue, forKey: "\(filename)_playTime") }
    }

    var lastPlayedDate: Date? {
        get { UserDefaults.standard.object(forKey: "\(filename)_lastPlayed") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "\(filename)_lastPlayed") }
    }

    var fileSize: Int64? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? Int64
    }

    var formattedFileSize: String {
        guard let fileSize else { return "-" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedPlayTime: String {
        let minutes = Int(playTime) / 60
        let hours = minutes / 60
        return String(format: "%02d:%02d", hours, minutes % 60)
    }

    init(fileURL: URL, creationDate: Date) {
        self.id = fileURL.lastPathComponent
        self.filename = fileURL.lastPathComponent
        self.fileURL = fileURL
        self.creationDate = creationDate
        self.header = try? NDSHeader.read(from: fileURL)
        self.banner = try? NDSBanner.read(from: fileURL)
    }

    func recordingPlayStart() {
        UserDefaults.standard.set(Date(), forKey: "\(filename)_lastPlayed")
    }

    func incrementPlayTime(by seconds: TimeInterval) {
        UserDefaults.standard.set(playTime + seconds, forKey: "\(filename)_playTime")
    }
}
