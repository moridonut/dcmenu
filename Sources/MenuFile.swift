// dcmenu — menu file model and parser.
// Pure Foundation (no AppKit), so the logic can be checked in isolation.

import Foundation

struct Item {
    var key: String      // 1-character accelerator, lowercased ("" = none)
    var label: String
    var command: String
}

indirect enum Node {
    case item(Item)
    case separator
    case submenu(String, [Node])
}

struct MenuFile {
    var title: String?
    var nodes: [Node]
    var path: String
    var warnings: [String]
}

/// Menu file format (one file = one menu, like あふ's Menu/*.txt):
///
///   # comment                 (also ;)
///   title: コピーメニュー       shown as a greyed header line
///   2 | 同一フォルダにコピー | @key ctrl+opt+shift+2
///   -                         separator
///   { サブメニュー              inline submenu start (opens to the side)
///   }                         inline submenu end
///
/// Commands are shell commands, or one of the built-ins:
///   @menu <name>    open another menu file in place (あふ's &MENU)
///   @key <keys>     send keystrokes to Double Commander
///   @clip <text>    put text on the clipboard, one line per selected file
///   @edit [cmd]     open this menu file for editing (あふ's &EDIT)
func parseMenu(_ text: String, path: String) -> MenuFile {
    var title: String?
    var warnings: [String] = []
    var stack: [[Node]] = [[]]
    var names: [String] = []
    var seenKeys: [Set<String>] = [[]]

    for (n, rawLine) in text.components(separatedBy: .newlines).enumerated() {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

        if line.lowercased().hasPrefix("title:") {
            title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            continue
        }
        if line.hasPrefix("{") {
            let name = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            names.append(name.isEmpty ? "..." : name)
            stack.append([])
            seenKeys.append([])
            continue
        }
        if line.hasPrefix("}") {
            if !names.isEmpty {
                let nodes = stack.removeLast()
                seenKeys.removeLast()
                stack[stack.count - 1].append(.submenu(names.removeLast(), nodes))
            }
            continue
        }
        if line == "-" || line == "--" || line.hasPrefix("---") {
            stack[stack.count - 1].append(.separator)
            continue
        }

        let parts = line.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var item: Item?
        if parts.count >= 3 {
            item = Item(key: String(parts[0].prefix(1)).lowercased(),
                        label: parts[1],
                        command: parts[2...].joined(separator: "|"))
        } else if parts.count == 2 {
            item = Item(key: "", label: parts[0], command: parts[1])
        } else {
            warnings.append("\(path):\(n + 1): 読めない行です: \(line)")
        }
        if let it = item {
            if !it.key.isEmpty {
                if seenKeys[seenKeys.count - 1].contains(it.key) {
                    warnings.append("\(path):\(n + 1): キー '\(it.key)' が重複しています（先の項目が優先されます）")
                }
                seenKeys[seenKeys.count - 1].insert(it.key)
            }
            stack[stack.count - 1].append(.item(it))
        }
    }
    while !names.isEmpty {
        let nodes = stack.removeLast()
        stack[stack.count - 1].append(.submenu(names.removeLast(), nodes))
    }
    return MenuFile(title: title, nodes: stack[0], path: path, warnings: warnings)
}

// MARK: - Actions

enum Action {
    case shell(String)
    case menu(String)
    case key(String)
    case clip(String)
    case edit(String?)
    case unknown(String)
}

func parseAction(_ command: String) -> Action {
    let c = command.trimmingCharacters(in: .whitespaces)
    guard c.hasPrefix("@") else { return .shell(c) }
    let word: String
    let rest: String
    if let sp = c.firstIndex(of: " ") {
        word = String(c[c.startIndex..<sp])
        rest = String(c[sp...]).trimmingCharacters(in: .whitespaces)
    } else {
        word = c
        rest = ""
    }
    switch word.lowercased() {
    case "@menu": return .menu(rest)
    case "@key":  return .key(rest)
    case "@clip": return .clip(rest)
    case "@edit": return .edit(rest.isEmpty ? nil : rest)
    default:      return .unknown(word)
    }
}

// MARK: - Macro expansion

func shellQuote(_ s: String) -> String {
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// What Double Commander told us about the panels.
struct Context {
    var files: [String]        // DC %p  — marked files, or the cursor file if none are marked
    var cursor: String?        // DC %p0 — the file under the cursor
    var opposite: String?      // DC %Dt — the other panel's folder (あふ $O)
}

enum ExpandError: Error {
    case noFile
    case noOpposite
    case cancelled
}

/// Expands macros. The letters %P %D %N %F %E %A %B %M %X follow pochi / ぽちエス;
/// %C %O %U are added for the file manager context.
///
///   %P  full path              %D  parent folder           %N  name with extension
///   %F  parent folder name     %E  extension               %A  name without extension
///   %B  full path w/o ext      %M  all files               %X  ask (%X"initial")
///   %C  file under the cursor  %O  other panel's folder    %U  file:// URL
///   %%  literal %
///
/// quote == true  (shell commands): every value is shell-quoted; %M is a quoted list.
/// quote == false (@clip):          values are inserted raw; %M is newline-separated.
final class Expander {
    let ctx: Context
    let label: String
    /// Asks the user for a value (%X). Injected so this file stays AppKit-free.
    let prompt: (_ title: String, _ initial: String) -> String?
    private var asked: String?

    init(ctx: Context, label: String,
         prompt: @escaping (_ title: String, _ initial: String) -> String?) {
        self.ctx = ctx
        self.label = label
        self.prompt = prompt
    }

    private func values(for path: String?) -> [Character: String] {
        var map: [Character: String] = [:]
        if let path = path {
            let url = URL(fileURLWithPath: path)
            let dir = url.deletingLastPathComponent()
            map["P"] = path
            map["D"] = dir.path
            map["N"] = url.lastPathComponent
            map["F"] = dir.lastPathComponent
            map["E"] = url.pathExtension
            map["A"] = url.deletingPathExtension().lastPathComponent
            map["B"] = url.deletingPathExtension().path
            map["U"] = url.absoluteString
        }
        if let c = ctx.cursor ?? path { map["C"] = c }
        if let o = ctx.opposite { map["O"] = o }
        return map
    }

    func expand(_ command: String, path: String?, quote: Bool) throws -> String {
        let map = values(for: path)
        var out = ""
        var i = command.startIndex
        while i < command.endIndex {
            let ch = command[i]
            let next = command.index(after: i)
            guard ch == "%", next < command.endIndex else {
                out.append(ch)
                i = next
                continue
            }
            let code = command[next]
            var after = command.index(after: next)

            switch code {
            case "%":
                out.append("%")
            case "M":
                if ctx.files.isEmpty { throw ExpandError.noFile }
                out.append(quote ? ctx.files.map(shellQuote).joined(separator: " ")
                                 : ctx.files.joined(separator: "\n"))
            case "X":
                var initial = ""
                if after < command.endIndex, command[after] == "\"" {
                    let start = command.index(after: after)
                    if let close = command[start...].firstIndex(of: "\"") {
                        initial = try expand(String(command[start..<close]), path: path, quote: false)
                        after = command.index(after: close)
                    }
                }
                if asked == nil {
                    guard let typed = prompt(label, initial) else { throw ExpandError.cancelled }
                    asked = typed
                }
                out.append(quote ? shellQuote(asked!) : asked!)
            case "P", "D", "N", "F", "E", "A", "B", "U", "C", "O":
                guard let v = map[code] else {
                    throw code == "O" ? ExpandError.noOpposite : ExpandError.noFile
                }
                out.append(quote ? shellQuote(v) : v)
            default:
                out.append(ch)          // unknown macro: keep "%" and re-read the next char
                after = next
            }
            i = after
        }
        return out
    }
}

// MARK: - Key specs for @key

/// macOS virtual key codes (kVK_*). Letter/number codes are positional and
/// identical on ANSI and JIS keyboards.
let keyCodes: [String: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
    "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
    "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47, "`": 50,
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
    "esc": 53, "escape": 53, "fwddelete": 117,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
]

struct Modifiers: OptionSet {
    let rawValue: Int
    static let shift   = Modifiers(rawValue: 1)
    static let control = Modifiers(rawValue: 2)
    static let option  = Modifiers(rawValue: 4)
    static let command = Modifiers(rawValue: 8)
}

struct KeyStroke {
    var code: UInt16
    var modifiers: Modifiers
}

/// "ctrl+opt+shift+2"  /  "cmd+f5 down return" (several strokes, space-separated)
func parseKeySpec(_ spec: String) -> [KeyStroke]? {
    var strokes: [KeyStroke] = []
    for token in spec.lowercased().split(separator: " ") where !token.isEmpty {
        // split on "+", but allow "+" itself as the final key isn't supported (use "=" with shift)
        let parts = token.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyName = parts.last, !keyName.isEmpty, let code = keyCodes[keyName] else {
            return nil
        }
        var mods: Modifiers = []
        for m in parts.dropLast() {
            switch m {
            case "ctrl", "control", "ctl": mods.insert(.control)
            case "opt", "option", "alt":   mods.insert(.option)
            case "shift":                  mods.insert(.shift)
            case "cmd", "command":         mods.insert(.command)
            default: return nil
            }
        }
        strokes.append(KeyStroke(code: code, modifiers: mods))
    }
    return strokes.isEmpty ? nil : strokes
}
