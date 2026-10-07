import Foundation
import Darwin

func validateServiceDirectory(_ path: String, owner: uid_t) throws {
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
          info.st_uid == owner, info.st_mode & 0o022 == 0 else {
        throw PowerModeError("目录所有者或权限不正确：\(path)。")
    }
}

func prepareRuntimeDirectory(_ path: String, owner: uid_t) throws {
    if mkdir(path, 0o755) == 0 {
        guard chmod(path, 0o755) == 0 else { throw PowerModeError("无法设置运行目录权限。") }
    } else if errno != EEXIST {
        throw PowerModeError("无法创建运行目录：\(errno)。")
    }
    try validateServiceDirectory(path, owner: owner)
}
