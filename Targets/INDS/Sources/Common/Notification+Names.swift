import Foundation

extension Notification.Name {
    static let romImported = Notification.Name("eNDSRomImported")
    static let romImportFailed = Notification.Name("eNDSRomImportFailed")
    static let biosFilesChanged = Notification.Name("eNDSBiosFilesChanged")
    /// An externally opened file would overwrite existing data and needs the
    /// user's confirmation. userInfo["url"] is a staged copy in tmp.
    static let romImportNeedsReplaceConfirm = Notification.Name("eNDSRomImportNeedsReplaceConfirm")
}
