import AppKit
import Darwin
import Foundation

func forceQuitResult(originalTerminated: Bool, hasNewProcess: Bool, accepted: Bool) -> String {
  if originalTerminated && hasNewProcess {
    return "torneが強制終了後にもう一度起動しました。必要なら「強制終了…」をもう一度押してください。"
  }
  if originalTerminated {
    return "torneを終了しました。\nまた開いたら「強制終了…」をもう一度押してください。"
  }
  return accepted ? "torneの終了を確認できませんでした。必要なら「強制終了…」をもう一度押してください。" : "強制終了の要求に失敗しました。"
}

final class Helper: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  let output = NSTextView()
  let statusLabel = NSTextField(labelWithString: "起動状態を確認中…")
  var busy = false
  private var outputRevision = 0
  func show(_ text: String) {
    outputRevision += 1
    output.string = text
  }
  func button(_ title: String, _ action: Selector) -> NSButton {
    let b = NSButton(title: title, target: self, action: action)
    b.bezelStyle = .rounded
    return b
  }
  func link(_ title: String, _ url: String) -> NSButton {
    let b = button(title + " ↗", #selector(openLink(_:)))
    b.identifier = NSUserInterfaceItemIdentifier(url)
    b.toolTip = url
    return b
  }
  @objc func openLink(_ sender: NSButton) {
    guard let value = sender.identifier?.rawValue, let url = URL(string: value),
      url.scheme == "https"
    else { return }
    if !NSWorkspace.shared.open(url) { show("リンクを開けませんでした: " + value) }
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 510),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Torne Mobile Helper"
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
    ])
    let title = NSTextField(labelWithString: "Torne Mobile Helper")
    title.font = .boldSystemFont(ofSize: 20)
    stack.addArrangedSubview(title)
    stack.addArrangedSubview(NSTextField(labelWithString: "起動状態の確認以外に、情報を自動で収集・送信することはありません。"))
    let recoverRow = NSStackView(views: [
      button("起動状態を更新", #selector(detect)), button("再起動して復帰…", #selector(recover)),
      button("強制終了…", #selector(forceQuit)),
    ])
    stack.addArrangedSubview(recoverRow)
    stack.addArrangedSubview(statusLabel)
    updateStatus()
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateStatus()
    }
    stack.addArrangedSubview(button("Apple Music同時起動問題の対処（システム設定を開く）", #selector(openSettings)))
    let diagRow = NSStackView(views: [
      button("レシートを診断…", #selector(autoReceipt)), button("レシートの権限を修正…", #selector(repairReceipt)),
    ])
    stack.addArrangedSubview(diagRow)
    stack.addArrangedSubview(
      NSStackView(views: [
        NSTextField(labelWithString: "アプリ"),
        link(
          "torne mobile（iPad／App Store）", "https://apps.apple.com/jp/app/torne-mobile/id949323340"),
      ]))
    stack.addArrangedSubview(NSTextField(labelWithString: "参考情報"))
    stack.addArrangedSubview(
      NSStackView(views: [
        link("購入復旧の権限問題（Qiita）", "https://qiita.com/yun_98/items/9eeeb1f9f7829c446fec"),
        link("Apple Music同時起動（note）", "https://note.com/sorairo555/n/nb8a4ac3ed60c"),
      ]))

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.documentView = output
    output.isEditable = false
    output.isSelectable = true
    output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    output.autoresizingMask = [.width]
    output.textContainer?.widthTracksTextView = true
    stack.addArrangedSubview(scroll)
    scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
    show("操作結果がここに表示されます。")
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func targets() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
      $0.bundleIdentifier == "com.playstation.tornemobile" && !$0.isTerminated
    }
  }
  func updateStatus() {
    let apps = targets()
    statusLabel.stringValue =
      apps.isEmpty
      ? "torne: 未起動（またはこの実行元から取得不可）"
      : "torne: 起動中 / PID " + apps.map { String($0.processIdentifier) }.joined(separator: ", ")
  }
  @objc func forceQuit() {
    guard !busy else { return }
    let apps = targets()
    guard apps.count == 1, let app = apps.first else {
      show("torneが1つだけ起動しているときに使えます。")
      return
    }
    let pid = app.processIdentifier
    let alert = NSAlert()
    alert.messageText = "torne を強制終了しますか？"
    alert.informativeText = "PID: \(pid)\n再生が止まり、未保存の状態が失われる場合があります。"
    alert.addButton(withTitle: "強制終了")
    alert.addButton(withTitle: "キャンセル")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    guard !app.isTerminated, let current = NSRunningApplication(processIdentifier: pid),
      current.isEqual(app), current.bundleIdentifier == "com.playstation.tornemobile"
    else {
      show("対象が変わったため中止しました。")
      return
    }
    let accepted = current.forceTerminate()
    show(accepted ? "終了を確認中…" : "強制終了の要求に失敗しました。")
    let revision = outputRevision
    let deadline = ProcessInfo.processInfo.systemUptime + 8
    checkForceQuit(current, accepted: accepted, revision: revision, deadline: deadline)
  }
  private func checkForceQuit(
    _ app: NSRunningApplication, accepted: Bool, revision: Int, deadline: TimeInterval
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self, self.outputRevision == revision else { return }
      self.updateStatus()
      let terminated = app.isTerminated
      let relaunched =
        terminated && self.targets().contains { $0.processIdentifier != app.processIdentifier }
      if relaunched || !accepted || ProcessInfo.processInfo.systemUptime >= deadline {
        self.show(
          forceQuitResult(
            originalTerminated: terminated, hasNewProcess: relaunched, accepted: accepted))
        return
      }
      if terminated {
        self.output.string = forceQuitResult(
          originalTerminated: true, hasNewProcess: false, accepted: true)
      }
      self.checkForceQuit(app, accepted: accepted, revision: revision, deadline: deadline)
    }
  }
  @objc func openSettings() {
    show(
      "Apple Musicが同時に開く場合は、次の設定をオフにしてみてください。\n\nシステム設定 → プライバシーとセキュリティ → メディアとApple Music → torne mobile"
    )
    guard
      let url = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.systempreferences"), NSWorkspace.shared.open(url)
    else {
      output.string += "\nシステム設定を自動で開けませんでした。Appleメニューから開いてください。"
      return
    }
  }
  @objc func detect() {
    updateStatus()
    let apps = targets()
    show(
      "本体候補 \(apps.count) 件\n"
        + apps.map { "\($0.localizedName ?? "?") PID=\($0.processIdentifier)" }.joined(
          separator: "\n"))
  }
  @objc func recover() {
    guard !busy else { return }
    let apps = targets()
    guard apps.count == 1, let app = apps.first else {
      show("torneが1つだけ起動しているときに使えます（検出: \(apps.count)件）。")
      return
    }
    let pid = app.processIdentifier
    let alert = NSAlert()
    alert.messageText = "torneを再起動しますか？"
    alert.informativeText = "PID: \(pid)\n再生が停止します。"
    alert.addButton(withTitle: "再起動")
    alert.addButton(withTitle: "キャンセル")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let child = Process()
    child.executableURL = Bundle.main.executableURL?.deletingLastPathComponent()
      .appendingPathComponent("TorneReturn")
    child.arguments = ["--pid", String(pid), "--method", "sigterm"] + ["--reopen"]
    child.environment = ProcessInfo.processInfo.environment.merging(["TORNE_RETURN_COMPACT": "1"]) {
      _, new in new
    }
    let input = Pipe()
    let out = Pipe()
    child.standardInput = input
    child.standardOutput = out
    child.standardError = out
    busy = true
    show("再起動中…")
    do {
      try child.run()
      input.fileHandleForWriting.write(Data("\(pid)\n".utf8))
      try? input.fileHandleForWriting.close()
      DispatchQueue.global().async {
        let data = out.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        DispatchQueue.main.async {
          self.busy = false
          self.show(String(decoding: data, as: UTF8.self))
        }
      }
    } catch {
      busy = false
      show("起動失敗: \(error.localizedDescription)")
    }
  }
  func reportReceipt(_ file: URL) throws {
    guard file.lastPathComponent == "receipt",
      file.deletingLastPathComponent().lastPathComponent == "StoreKit"
    else {
      throw NSError(
        domain: "TorneHelper", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "StoreKit/receipt を選択してください。"])
    }
    show(try receiptSummary(file.path))
  }
  @objc func autoReceipt() {
    guard !busy else { return }
    if let bookmark = UserDefaults.standard.data(forKey: "torneReceiptReadOnlyBookmark") {
      do {
        var stale = false
        let file = try URL(
          resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil,
          bookmarkDataIsStale: &stale)
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        if !stale {
          try reportReceipt(file)
          return
        }
      } catch {
        // Ask the user to select the receipt again.
      }
    }
    authorizeReceipt()
  }
  @objc func repairReceipt() {
    guard !busy else { return }
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Containers")
    guard let result = try? discoverReceipts(root: root), result.paths.count == 1,
      let expected = result.paths.first
    else {
      show("torneのレシートを特定できませんでした。診断は「レシートを診断…」からファイルを選べます。")
      return
    }
    do {
      let repair = try ReceiptRepair(expected: expected, selected: expected)
      if repair.originalMode == 0o600 {
        show("権限はすでに0600です。")
        return
      }
      let alert = NSAlert()
      alert.messageText = "レシートの権限を0600に変更しますか？"
      alert.informativeText =
        "対象: \(expected.path)\n現在: \(String(format: "%04o", Int(repair.originalMode))) → 0600（所有者だけ読み書き可）"
      alert.addButton(withTitle: "権限を変更")
      alert.addButton(withTitle: "キャンセル")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      show(try repair.applyOnce())
    } catch {
      let folder = expected.deletingLastPathComponent()
      let accessNote =
        (error as? RepairFailure)?.accessDenied == true
        ? "\nmacOSのアクセス確認が出た場合は「許可」を選んでください。"
        : ""
      let message = "レシートの権限を修正できませんでした。\n\(error.localizedDescription)\(accessNote)"
      show(message + "\n\n対象フォルダ: \(folder.path)")
      let alert = NSAlert()
      alert.messageText = "レシートの権限を修正できませんでした"
      alert.informativeText = "Finderで対象のStoreKitフォルダを開けます。"
      alert.addButton(withTitle: "Finderで開く")
      alert.addButton(withTitle: "閉じる")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      if !NSWorkspace.shared.open(folder) {
        show(message + "\n\nFinderで開けませんでした。Finderで⌘⇧Gを押し、次のパスを入力してください。\n\(folder.path)")
      }
    }
  }
  @objc func authorizeReceipt() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.prompt = "このファイルを許可"
    panel.message = "torneの StoreKit/receipt を選択してください。"
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Containers")
    guard panel.runModal() == .OK, let file = panel.url else { return }
    let scoped = file.startAccessingSecurityScopedResource()
    defer { if scoped { file.stopAccessingSecurityScopedResource() } }
    do {
      try reportReceipt(file)
      do {
        let bookmark = try file.bookmarkData(
          options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
          includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: "torneReceiptReadOnlyBookmark")
      } catch { output.string += "\n\n次回もアクセス許可が必要な場合があります。" }
    } catch { show("現在の権限: 確認できませんでした。\n\(receiptModeGuide)\n\n" + error.localizedDescription) }
  }
}

let application = NSApplication.shared
let delegate = Helper()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
