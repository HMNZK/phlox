import Foundation

struct FileTreeEdit: Equatable {
    let id = UUID()
    let parent: String
    let folder: Bool
    var originalPath: String? = nil
    var name = ""
    var submitted = false
    var error: String? = nil
    var isNew: Bool { originalPath == nil }
    var rowID: String { originalPath ?? (parent.isEmpty ? "" : parent + "/") + ".phlox-input-" + id.uuidString }
}

struct FileTreeFailure {
    let operationKey: String
    let reason: String
    init(operationKey: String, error: Error) {
        self.operationKey = operationKey
        if let nameError = error as? FileTreeNameError { reason = nameError.key; return }
        if let access = error as? WorkingTreeServiceError {
            switch access {
            case .outsideRoot: reason = "プロジェクトのフォルダの外では操作できません"; return
            case .invalidRelativePath: reason = "ファイルのパスが不正です。"; return
            default: break
            }
        }
        let native = error as NSError
        if (native.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(native.code))
            || (native.domain == NSCocoaErrorDomain && [CocoaError.Code.fileWriteNoPermission.rawValue, CocoaError.Code.fileReadNoPermission.rawValue].contains(native.code)) {
            reason = "権限がありません"
        } else if (native.domain == NSPOSIXErrorDomain && native.code == Int(EROFS))
            || (native.domain == NSCocoaErrorDomain && native.code == CocoaError.Code.fileWriteVolumeReadOnly.rawValue) {
            reason = "ディスクは読み取り専用です"
        } else if (native.domain == NSPOSIXErrorDomain && native.code == Int(ENOSPC))
            || (native.domain == NSCocoaErrorDomain && native.code == CocoaError.Code.fileWriteOutOfSpace.rawValue) {
            reason = "ディスクに空き領域がありません"
        } else { reason = error.localizedDescription }
    }
}
