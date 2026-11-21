import AppKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
  fputs(message + "\n", stderr)
  exit(1)
}
let bundleID = "com.playstation.tornemobile"
func targets() -> [NSRunningApplication] {
  NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == bundleID && !$0.isTerminated
  }
}
func tick() { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
let compact = ProcessInfo.processInfo.environment["TORNE_RETURN_COMPACT"] == "1"
func detail(_ message: String) { if !compact { print(message) } }
var args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args == ["--help"] {
  print(
    """
    復帰検証: ./TorneReturn --torne
    別方式:   ./TorneReturn --torne --method sigterm
    検出のみ: ./TorneReturn --torne --detect
    PID指定:  ./TorneReturn --pid 12345 [--method normal|sigterm] [--reopen] [--detect]
    一覧:     ./TorneReturn --list
    確認後に終了要求を1回。--reopen を付けた場合だけ、終了確認後に必要なら1回起動します。
    """)
  exit(0)
}
if args == ["--list"] {
  for app in NSWorkspace.shared.runningApplications {
    print("\(app.processIdentifier)\t\(app.localizedName ?? "?")\t\(app.bundleIdentifier ?? "?")")
  }
  exit(0)
}
var method = "normal"
var detectOnly = false
var reopen = false
var explicitPID: Int32?
var auto = false
while !args.isEmpty {
  let flag = args.removeFirst()
  switch flag {
  case "--torne":
    guard !auto && explicitPID == nil else { fail("対象指定が重複しています。") }
    auto = true
  case "--pid":
    guard !auto, explicitPID == nil, !args.isEmpty, let value = Int32(args.removeFirst()), value > 0
    else { fail("PID を確認してください。") }
    explicitPID = value
  case "--method":
    guard !args.isEmpty else { fail("方式を指定してください。") }
    method = args.removeFirst()
    guard ["normal", "sigterm"].contains(method) else { fail("方式は normal または sigterm です。") }
  case "--detect": detectOnly = true
  case "--reopen": reopen = true
  default: fail("不明な引数: \(flag)。--help を参照してください。")
  }
}
let app: NSRunningApplication
if auto {
  let matches = targets()
  guard matches.count == 1, let target = matches.first else {
    fail("torne 本体候補は \(matches.count) 件です。1件以外は停止します。")
  }
  app = target
} else if let pid = explicitPID, let target = NSRunningApplication(processIdentifier: pid) {
  app = target
} else {
  fail("--torne または --pid PID を指定してください。")
}
guard app.bundleIdentifier == bundleID, !app.isTerminated else {
  fail("torne 本体以外・終了済みの PID は操作しません。")
}
let pid = app.processIdentifier
detail("対象: \(app.localizedName ?? "?") PID=\(pid) Bundle ID=\(bundleID)")
guard !detectOnly else {
  print("検出のみ。操作していません。")
  exit(0)
}
guard let appURL = app.bundleURL, appURL.pathExtension == "app",
  Bundle(url: appURL)?.bundleIdentifier == bundleID
else { fail("再起動先のアプリを検証できないため停止します。") }
detail("起動先: \(appURL.path)")
detail("方式: \(method == "normal" ? "通常の終了要求" : "SIGTERM (15) を1回送信")")
detail("再生が止まり、ホーム画面からの再操作が必要になる可能性があります。")
detail(reopen ? "--reopen 有効: 旧プロセスの終了を確認し、必要なら1回起動します。" : "再起動は無効: 終了しても本ツールでは開き直しません。")
detail("強制終了(SIGKILL)、自動再送、設定変更はしません。終了しない場合は停止します。")
detail("続行する場合は PID \(pid) を入力して Return（それ以外は中止）:")
guard readLine() == String(pid) else {
  print("中止しました。")
  exit(0)
}
guard !app.isTerminated, let current = NSRunningApplication(processIdentifier: pid),
  current.isEqual(app), current.bundleIdentifier == bundleID, current.bundleURL == appURL
else {
  fail("対象が変化したため停止します。")
}
if method == "normal" {
  print("terminate() 戻り値: \(current.terminate())")
} else {
  guard Darwin.kill(pid, SIGTERM) == 0 else {
    fail("SIGTERM 送信失敗: \(String(cString: strerror(errno)))")
  }
  detail("SIGTERM 送信済み。終了確認待ちです。")
}
let deadline = Date().addingTimeInterval(8)
while !app.isTerminated && Date() < deadline { tick() }
guard app.isTerminated else { fail("8秒以内にtorneの終了を確認できませんでした。") }
detail("旧 PID \(pid) の終了を確認。自動再起動を2秒待ちます。")
let settle = Date().addingTimeInterval(2)
while Date() < settle { tick() }
let replacements = targets()
if !replacements.isEmpty {
  print(
    "既に起動中の torne PID: \(replacements.map { String($0.processIdentifier) }.joined(separator: ", "))。追加起動しません。"
  )
  exit(0)
}
guard reopen else {
  print("torne は終了しました。再起動は依頼されていないため行いません。必要なら手動で開いてください。")
  exit(0)
}
// 新規インスタンス作成を指定せず LaunchServices に開くよう依頼する。
// 直前にシステム側で起動が始まった場合も既存インスタンスを優先する。
guard NSWorkspace.shared.open(appURL) else { fail("起動要求に失敗しました。torne を手動で開いてください。") }
detail("起動要求を1回送りました。")
let launchDeadline = Date().addingTimeInterval(8)
while targets().isEmpty && Date() < launchDeadline { tick() }
let launched = targets()
if launched.isEmpty { fail("torneの起動を確認できませんでした。") }
print("torneを再起動しました。PID: \(launched.map { String($0.processIdentifier) }.joined(separator: ", "))")
detail("ホーム画面が表示されたかは画面で確認してください。再生継続は保証しません。")
