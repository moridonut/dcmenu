// dcmenu — あふ-style keyboard menus for Double Commander on macOS.
//
//   dcmenu [-o DIR] [-k FILE] [-m MENUDIR] <menu> [file...]
//
// Typically called from a hidden Double Commander toolbar button:
//   copy -o %Dt -k %p0 %p
//
// MIT License

import Cocoa

let usage = """
dcmenu — あふ風のキーボードメニュー（Double Commander 用）

  dcmenu [-o DIR] [-k FILE] [-m MENUDIR] <menu> [file...]

  <menu>        メニュー名（MENUDIR/<menu>.menu）またはメニューファイルのパス
  file...       対象ファイル（DC の %p）
  -o DIR        反対側パネルのフォルダ（DC の %Dt）→ %O
  -k FILE       カーソル位置のファイル（DC の %p0）→ %C
  -m MENUDIR    メニューファイルの置き場所（既定: ~/.config/dcmenu、環境変数 DCMENU_DIR）
"""

func defaultMenuDir() -> String {
    if let d = ProcessInfo.processInfo.environment["DCMENU_DIR"], !d.isEmpty {
        return (d as NSString).expandingTildeInPath
    }
    return FileManager.default.homeDirectoryForCurrentUser.path + "/.config/dcmenu"
}

func absolute(_ p: String) -> String {
    let expanded = (p as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") { return expanded }
    return FileManager.default.currentDirectoryPath + "/" + expanded
}

// MARK: - Arguments

var menuDir = defaultMenuDir()
var menuName: String?
var ctx = Context(files: [], cursor: nil, opposite: nil)

do {
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    var optionsDone = false
    while i < args.count {
        let a = args[i]
        if !optionsDone && (a == "-o" || a == "-k" || a == "-m") {
            i += 1
            guard i < args.count else { break }
            let v = args[i]
            if a == "-o" { ctx.opposite = v.isEmpty ? nil : absolute(v) }
            if a == "-k" { ctx.cursor = v.isEmpty ? nil : absolute(v) }
            if a == "-m" { menuDir = absolute(v) }
        } else if !optionsDone && (a == "-h" || a == "--help") {
            print(usage)
            exit(0)
        } else if !optionsDone && a == "--" {
            optionsDone = true
        } else if menuName == nil {
            menuName = a
        } else {
            ctx.files.append(absolute(a))
        }
        i += 1
    }
}

guard let firstMenu = menuName else {
    FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
    exit(1)
}
// DC passes a trailing slash on %Dt; strip it so "%O/" never becomes "//".
if let o = ctx.opposite, o.count > 1, o.hasSuffix("/") { ctx.opposite = String(o.dropLast()) }

appendLog("start: menu=\(firstMenu) files=\(ctx.files.count) cursor=\(ctx.cursor ?? "-") opposite=\(ctx.opposite ?? "-")")

// MARK: - App setup

// Remember who called us (Double Commander) before we take the focus.
let caller: NSRunningApplication? = {
    let me = ProcessInfo.processInfo.processIdentifier
    if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me {
        return front
    }
    return NSRunningApplication.runningApplications(withBundleIdentifier: dcBundleID).first
}()

let app = NSApplication.shared
_ = app.setActivationPolicy(.accessory)

let anchor = menuAnchor(for: caller)

func menuPath(_ name: String) -> String {
    if name.contains("/") || name.hasSuffix(".menu") { return absolute(name) }
    return menuDir + "/" + name + ".menu"
}

func loadMenu(_ name: String) -> MenuFile? {
    let path = menuPath(name)
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        showAlert("dcmenu: メニューファイルが読めません", path)
        return nil
    }
    let m = parseMenu(text, path: path)
    for w in m.warnings { appendLog("warning: " + w) }
    return m
}

func workingDirectory() -> String {
    if let f = ctx.files.first { return URL(fileURLWithPath: f).deletingLastPathComponent().path }
    if let c = ctx.cursor { return URL(fileURLWithPath: c).deletingLastPathComponent().path }
    return FileManager.default.homeDirectoryForCurrentUser.path
}

func report(_ error: Error, item: Item) {
    switch error {
    case ExpandError.cancelled:
        return
    case ExpandError.noOpposite:
        showAlert("「\(item.label)」には反対側パネルのフォルダが必要です",
                  "DC のボタンのパラメータに -o %Dt を入れてください。")
    case ExpandError.noFile:
        showAlert("「\(item.label)」には対象ファイルが必要です",
                  "DC のボタンのパラメータに %p（または -k %p0）を入れてください。")
    default:
        showAlert("dcmenu: \(error)")
    }
}

// MARK: - Main loop: show a menu, run the chosen item; @menu shows the next one in place.

var current = firstMenu
var hops = 0

while true {
    guard let file = loadMenu(current) else { exit(1) }

    // Macros in the title (e.g. "→ %O") show what is about to happen — a confirmation
    // step for copy/move. %X is not allowed there; a macro that can't be filled stays as-is.
    var shown = file
    if let t = file.title, t.contains("%"), !t.contains("%X") {
        let titleExpander = Expander(ctx: ctx, label: "", prompt: { _, _ in nil })
        shown.title = (try? titleExpander.expand(t, path: ctx.files.first ?? ctx.cursor,
                                                 quote: false)) ?? t
    }

    guard let item = popUp(shown, at: anchor) else { exit(0) }   // Esc / clicked away
    appendLog("chosen: [\(item.key)] \(item.label) -> \(item.command)")

    let firstPath = ctx.files.first ?? ctx.cursor
    let expander = Expander(ctx: ctx, label: item.label, prompt: promptForInput)

    switch parseAction(item.command) {
    case .menu(let next):
        hops += 1
        if hops > 20 { showAlert("dcmenu: @menu が循環しています", next); exit(1) }
        // a relative name is looked up next to the current menu file
        current = next.contains("/") ? next
            : URL(fileURLWithPath: file.path).deletingLastPathComponent()
                .appendingPathComponent(next + ".menu").path
        continue

    case .key(let spec):
        guard let strokes = parseKeySpec(spec) else {
            showAlert("dcmenu: キーの書き方が読めません", "@key \(spec)\n\n\(file.path)")
            exit(1)
        }
        guard ensureAccessibility() else { exit(1) }
        // Prefer the running Double Commander (also when testing from a terminal).
        guard let target = NSRunningApplication
                .runningApplications(withBundleIdentifier: dcBundleID).first ?? caller else {
            showAlert("dcmenu: キーを送る先（Double Commander）が見つかりません")
            exit(1)
        }
        if !giveFocusBack(to: target) {
            appendLog("warning: \(target.localizedName ?? "?") did not become frontmost; sending anyway")
        }
        sendKeys(strokes)
        appendLog("sent: \(spec) -> \(target.localizedName ?? "?")")

    case .clip(let template):
        do {
            var lines: [String] = []
            let paths: [String?] = ctx.files.isEmpty ? [ctx.cursor] : ctx.files.map { Optional($0) }
            for p in paths {
                let s = try expander.expand(template, path: p, quote: false)
                if !lines.contains(s) { lines.append(s) }
            }
            copyToClipboard(lines.joined(separator: "\n"))
            appendLog("clip: \(lines.count) line(s)")
        } catch {
            report(error, item: item)
        }

    case .edit(let editor):
        let cmd = (editor ?? "open -t") + " " + shellQuote(file.path)
        runCommand(cmd, cwd: URL(fileURLWithPath: file.path).deletingLastPathComponent().path)

    case .shell(let command):
        do {
            let expanded = try expander.expand(command, path: firstPath, quote: true)
            runCommand(expanded, cwd: workingDirectory())
        } catch {
            report(error, item: item)
        }

    case .unknown(let word):
        showAlert("dcmenu: 知らないコマンドです: \(word)",
                  "使えるのは @menu @key @clip @edit です。\n\n\(file.path)")
    }
    exit(0)
}
