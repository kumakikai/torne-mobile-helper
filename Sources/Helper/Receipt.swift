import Darwin
import Foundation

let receiptModeGuide = "目安: 0600（所有者のみ読み書き可）"

func receiptModeStatus(_ mode: UInt16, ownedByCurrentUser: Bool) -> String {
  if !ownedByCurrentUser { return "所有者が現在のユーザーと一致しません。" }
  if mode == 0o600 { return "目安どおりです。" }
  if mode & 0o400 == 0 { return "所有者に読み取り権限がありません。" }
  return "所有者は読み取り可能ですが、目安の0600とは異なります。"
}

func receiptSummary(_ path: String) throws -> String {
  let a = try FileManager.default.attributesOfItem(atPath: path)
  guard a[.type] as? FileAttributeType == .typeRegular else { return "通常のファイルではありません。" }
  let mode = (a[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
  let owner = (a[.ownerAccountID] as? NSNumber)?.uint32Value
  let isOwner = owner == getuid()
  return
    "現在: \(String(format: "%04o", Int(mode)))\n\(receiptModeGuide)\n判定: \(receiptModeStatus(mode, ownedByCurrentUser: isOwner))"
}
struct RepairFailure: LocalizedError {
  let text: String
  var code: Int32? = nil
  var errorDescription: String? { text }
  var accessDenied: Bool { code == EACCES || code == EPERM }
}
func systemFailure(_ operation: String) -> RepairFailure {
  let code = errno
  return RepairFailure(text: operation + ": " + String(cString: strerror(code)), code: code)
}
final class ReceiptRepair {
  let file: URL
  let parentFD: Int32
  let fd: Int32
  let before: stat
  var originalMode: mode_t { before.st_mode & 0o7777 }
  init(expected: URL, selected: URL) throws {
    guard expected.standardizedFileURL == selected.standardizedFileURL,
      selected.lastPathComponent == "receipt",
      selected.deletingLastPathComponent().lastPathComponent == "StoreKit"
    else { throw RepairFailure(text: "確認済みのレシートと一致しません。") }
    file = selected
    let components = selected.deletingLastPathComponent().pathComponents
    var directory = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard directory >= 0 else { throw systemFailure("ディレクトリを開けません") }
    for part in components.dropFirst() {
      let next = Darwin.openat(directory, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      if next < 0 {
        let error = systemFailure("親ディレクトリを安全に開けません (\(part))")
        Darwin.close(directory)
        throw error
      }
      Darwin.close(directory)
      directory = next
    }
    var info = stat()
    guard fstatat(directory, "receipt", &info, AT_SYMLINK_NOFOLLOW) == 0 else {
      let error = systemFailure("レシート属性取得失敗")
      Darwin.close(directory)
      throw error
    }
    guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1 else {
      Darwin.close(directory)
      throw RepairFailure(text: "通常ファイル・現在ユーザー所有・ハードリンク1個の条件を満たしません。")
    }
    let access: Int32
    if (info.st_mode & 0o400) != 0 {
      access = O_RDONLY
    } else if (info.st_mode & 0o200) != 0 {
      access = O_WRONLY
    } else if (info.st_mode & 0o100) != 0 {
      access = O_EXEC
    } else {
      Darwin.close(directory)
      throw RepairFailure(text: "現在の権限ではレシートを安全に開けません。")
    }
    let opened = Darwin.openat(directory, "receipt", access | O_NOFOLLOW | O_CLOEXEC)
    guard opened >= 0 else {
      let error = systemFailure("レシートを開けません")
      Darwin.close(directory)
      throw error
    }
    var actual = stat()
    guard fstat(opened, &actual) == 0, actual.st_dev == info.st_dev, actual.st_ino == info.st_ino,
      (actual.st_mode & S_IFMT) == S_IFREG, actual.st_uid == getuid(), actual.st_nlink == 1
    else {
      Darwin.close(opened)
      Darwin.close(directory)
      throw RepairFailure(text: "対象が取得中に変わったため停止します。")
    }
    parentFD = directory
    fd = opened
    before = actual
  }
  deinit {
    Darwin.close(fd)
    Darwin.close(parentFD)
  }
  func applyOnce() throws -> String {
    var current = stat()
    var entry = stat()
    guard fstat(fd, &current) == 0, fstatat(parentFD, "receipt", &entry, AT_SYMLINK_NOFOLLOW) == 0,
      current.st_dev == before.st_dev, current.st_ino == before.st_ino,
      entry.st_dev == before.st_dev, entry.st_ino == before.st_ino,
      (entry.st_mode & S_IFMT) == S_IFREG, current.st_uid == getuid(), current.st_nlink == 1,
      (current.st_mode & 0o7777) == originalMode
    else { throw RepairFailure(text: "ファイルまたは権限が変わりました。再診断してください。") }
    guard fchmod(fd, 0o600) == 0 else { throw systemFailure("権限の変更に失敗しました") }
    var after = stat()
    var afterEntry = stat()
    guard fstat(fd, &after) == 0, (after.st_mode & 0o7777) == 0o600 else {
      throw RepairFailure(text: "変更後の権限を確認できませんでした。再診断してください。")
    }
    guard fstatat(parentFD, "receipt", &afterEntry, AT_SYMLINK_NOFOLLOW) == 0,
      afterEntry.st_dev == before.st_dev, afterEntry.st_ino == before.st_ino
    else {
      return "変更後にレシートが置き換わりました。再診断してください。"
    }
    return "レシートの権限を0600に変更しました。"
  }
}

struct ReceiptDiscovery {
  var paths: [URL] = []
  var unreadableMetadata = 0
  var firstError: String?
}
// Only exact Container Manager metadata IDs identify a container. No receipt contents are read.
func discoverReceipts(root: URL) throws -> ReceiptDiscovery {
  let fm = FileManager.default
  let entries = try fm.contentsOfDirectory(
    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
  var found = ReceiptDiscovery()
  for entry in entries {
    do {
      let a = try fm.attributesOfItem(atPath: entry.path)
      guard a[.type] as? FileAttributeType == .typeDirectory else { continue }
      let meta = entry.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
      let attrs = try fm.attributesOfItem(atPath: meta.path)
      guard attrs[.type] as? FileAttributeType == .typeRegular,
        let count = attrs[.size] as? NSNumber, count.intValue <= 262144
      else { continue }
      let data = try Data(contentsOf: meta)
      guard
        let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
          as? [String: Any],
        dict["MCMMetadataIdentifier"] as? String == "com.playstation.tornemobile"
      else { continue }
      // Do not probe the receipt until the exact container identity is known.
      found.paths.append(entry.appendingPathComponent("Data/StoreKit/receipt"))
    } catch {
      found.unreadableMetadata += 1
      if found.firstError == nil {
        let e = error as NSError
        found.firstError = "\(e.domain) code=\(e.code): \(e.localizedDescription)"
      }
    }
  }
  return found
}
