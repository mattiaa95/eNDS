import UniformTypeIdentifiers

extension UTType {
    static let ndsROM = UTType(exportedAs: "com.mls.nds-rom", conformingTo: .data)
    static let ndsBIOS = UTType.data
    /// `org.7-zip.7-zip-archive` — declared as `UTImportedTypeDeclarations`
    /// in Info.plist (we don't own the `org.7-zip` reverse-DNS domain, so
    /// this is imported rather than exported, unlike `ndsROM` above).
    static let sevenZipArchive = UTType(importedAs: "org.7-zip.7-zip-archive", conformingTo: .archive)
}
