// dcmenu — everything that talks to macOS: popup menus, focus, keystrokes,
// clipboard, running commands, the log.

import Cocoa
import ApplicationServices

let dcBundleID = "com.company.doublecmd"

// MARK: - Log
//
// Commands, their stderr and exit status go to ~/Library/Logs/dcmenu.log
// (override with DCMENU_LOG). `tail -f ~/Library/Logs/dcmenu.log` while testing.

let logURL: URL = {
    if let p = ProcessInfo.processInfo.environment["DCMENU_LOG"], !p.isEmpty {
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/dcmenu.log")
}()

func openLog() -> FileHandle? {
    let fm = FileManager.default
    try? fm.createDirectory(at: logURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true)
    if let size = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? Int,
       size > 1_000_000 {
        let old = logURL.appendingPathExtension("old")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: logURL, to: old)
    }
    let fd = open(logURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard fd >= 0 else { return nil }
    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
}

func logSize() -> UInt64 {
    ((try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? UInt64) ?? 0
}

func appendLog(_ message: String) {
    guard let h = openLog() else { return }
    let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                            formatOptions: [.withInternetDateTime])
    h.write("[\(stamp)] \(message)\n".data(using: .utf8)!)
    h.closeFile()
}

// MARK: - Dialogs

func showAlert(_ title: String, _ info: String = "") {
    appendLog("alert: \(title) \(info)")
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = info
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

/// The %X input box.
func promptForInput(title: String, initial: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "キャンセル")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
    field.stringValue = initial
    alert.accessoryView = field
    alert.layout()
    alert.window.initialFirstResponder = field
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
}

// MARK: - Popup menu

final class Handler: NSObject {
    var chosen: Item?
    @objc func pick(_ sender: NSMenuItem) {
        chosen = sender.representedObject as? Item
    }
}

func buildMenu(_ nodes: [Node], title: String?, handler: Handler) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    if let title = title, !title.isEmpty {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
    }
    for node in nodes {
        switch node {
        case .separator:
            menu.addItem(.separator())
        case .item(let item):
            let mi = NSMenuItem(title: item.label,
                                action: #selector(Handler.pick(_:)),
                                keyEquivalent: item.key)
            mi.keyEquivalentModifierMask = []
            mi.target = handler
            mi.representedObject = item
            mi.isEnabled = true
            menu.addItem(mi)
        case .submenu(let name, let children):
            let mi = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            mi.isEnabled = true
            mi.submenu = buildMenu(children, title: nil, handler: handler)
            menu.addItem(mi)
        }
    }
    return menu
}

/// Shows the menu and returns the chosen item (nil = cancelled).
func popUp(_ file: MenuFile, at point: NSPoint) -> Item? {
    let handler = Handler()
    let menu = buildMenu(file.nodes, title: file.title, handler: handler)
    NSApp.activate(ignoringOtherApps: true)
    _ = menu.popUp(positioning: nil, at: point, in: nil)
    return handler.chosen
}

// MARK: - Where to show the menu

/// Frame (Cocoa screen coordinates) of the frontmost normal window of `pid`.
func frontWindowFrame(pid: pid_t) -> NSRect? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    for w in list {    // front to back
        guard (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
              (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary),
              r.width > 100, r.height > 100 else { continue }
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    return nil
}

/// The mouse position if the mouse is over DC's window; otherwise near the
/// middle of that window. (Karabiner's notification was stuck bottom-right.)
func menuAnchor(for app: NSRunningApplication?) -> NSPoint {
    let mouse = NSEvent.mouseLocation
    guard let app = app, let frame = frontWindowFrame(pid: app.processIdentifier) else {
        return mouse
    }
    if frame.contains(mouse) { return mouse }
    return NSPoint(x: frame.midX - 140, y: frame.midY + 160)
}

// MARK: - Focus and keystrokes

/// Hands the focus back to `app` and waits until it is frontmost.
func giveFocusBack(to app: NSRunningApplication) -> Bool {
    if #available(macOS 14.0, *) {
        NSApp.yieldActivation(to: app)
        _ = app.activate(options: [])
    } else {
        _ = app.activate(options: [.activateIgnoringOtherApps])
    }
    func isFront() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }
    let deadline = Date().addingTimeInterval(1.0)
    while !isFront() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    if !isFront() {
        NSApp.hide(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    // let DC's window become key before the keys arrive
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    return isFront()
}

func ensureAccessibility() -> Bool {
    if AXIsProcessTrusted() { return true }
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    showAlert("Double Commander にキーを送る許可がありません",
              """
              システム設定 → プライバシーとセキュリティ → アクセシビリティ で、\
              許可を求めてきたアプリ（DC から起動した場合はたいてい Double Commander、\
              ターミナルから試した場合はそのターミナル）をオンにしてください。

              オンにしたあと、もう一度メニューから選び直せば動きます。
              """)
    return false
}

func sendKeys(_ strokes: [KeyStroke]) {
    let source = CGEventSource(stateID: .combinedSessionState)
    for s in strokes {
        var flags: CGEventFlags = []
        if s.modifiers.contains(.shift)   { flags.insert(.maskShift) }
        if s.modifiers.contains(.control) { flags.insert(.maskControl) }
        if s.modifiers.contains(.option)  { flags.insert(.maskAlternate) }
        if s.modifiers.contains(.command) { flags.insert(.maskCommand) }
        for down in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: source,
                                   virtualKey: CGKeyCode(s.code), keyDown: down) else { continue }
            ev.flags = flags
            ev.post(tap: .cghidEventTap)
            usleep(8_000)
        }
        usleep(20_000)
    }
}

// MARK: - Clipboard

func copyToClipboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

// MARK: - Running shell commands

/// Directories prepended to PATH: DC starts us with a bare /usr/bin:/bin:...
func extraPathDirs() -> [String] {
    var dirs: [String] = []
    if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
        dirs.append(exe.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/bin").path)
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    dirs += [home + "/bin", home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
    return dirs
}

func runCommand(_ command: String, cwd: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    p.currentDirectoryURL = URL(fileURLWithPath: cwd)
    // DC launches us without LANG; without this pbcopy turns Japanese into mojibake.
    var env = ProcessInfo.processInfo.environment
    if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
    if env["LC_CTYPE"] == nil { env["LC_CTYPE"] = "UTF-8" }
    let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    env["PATH"] = (extraPathDirs() + [path]).joined(separator: ":")
    p.environment = env

    appendLog("run: \(command)\n    cwd: \(cwd)")
    let log = openLog()
    let start = logSize()
    if let h = log { p.standardError = h }

    do {
        try p.run()
    } catch {
        showAlert("dcmenu: 実行できませんでした", command)
        return
    }
    log?.closeFile()

    // Wait a little so quick failures (cp errors, command not found) can be shown.
    let deadline = Date().addingTimeInterval(3.0)
    while p.isRunning && Date() < deadline { usleep(50_000) }
    if p.isRunning {
        appendLog("still running after 3s (pid \(p.processIdentifier))")
        return
    }
    var err = ""
    if let r = try? FileHandle(forReadingFrom: logURL) {
        r.seek(toFileOffset: start)
        err = String(decoding: r.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        r.closeFile()
    }
    appendLog("exit \(p.terminationStatus)")
    if p.terminationStatus == 0 { return }
    showAlert("dcmenu: コマンドが失敗しました（終了コード \(p.terminationStatus)）",
              command + (err.isEmpty ? "" : "\n\n" + err) + "\n\nログ: " + logURL.path)
}
