import AppKit

/// Talks to Terminal.app: find the tab of a session by its tty, bring it forward,
/// or type a line into it (Terminal's `do script … in tab` types text plus Return).
enum Terminal {
    /// Text that goes into a terminal: no control characters (no Escape sequences,
    /// no early Return), one line, trimmed.
    static func clean(_ s: String) -> String {
        let scalars = s.unicodeScalars.map { ($0.value < 0x20 || $0.value == 0x7F) ? " " : Character($0) }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    private static func validTTY(_ tty: String?) -> String? {
        guard let tty, tty.range(of: #"^/dev/ttys[0-9]{1,4}$"#, options: .regularExpression) != nil else { return nil }
        return tty
    }

    private static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func run(tty: String, body: String) -> Result<Void, TerminalError> {
        let src = """
        tell application "Terminal"
          repeat with w in windows
            repeat with i from 1 to (count of tabs of w)
              if tty of tab i of w is "\(tty)" then
                \(body)
                return "ok"
              end if
            end repeat
          end repeat
        end tell
        return "notfound"
        """
        var err: NSDictionary?
        let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err {
            let n = err[NSAppleScript.errorNumber] as? Int ?? 0
            return .failure(TerminalError(message: n == -1743
                ? "Vassy may not control Terminal. Allow it in System Settings › Privacy & Security › Automation."
                : "Terminal did not respond (\(n))."))
        }
        return out?.stringValue == "ok" ? .success(()) : .failure(TerminalError(message: "Terminal tab not found. Was it closed?"))
    }

    static func send(_ text: String, tty: String?) -> Result<Void, TerminalError> {
        guard let tty = validTTY(tty) else { return .failure(TerminalError(message: "This session has no known Terminal tab.")) }
        let line = clean(text)
        guard !line.isEmpty else { return .failure(TerminalError(message: "The message is empty.")) }
        let typed = run(tty: tty, body: "do script \(appleScriptString(line)) in tab i of w")
        guard case .success = typed else { return typed }
        // Claude Code treats a fast burst of characters as a paste and swallows the
        // trailing Return, so submit with a separate, empty `do script` (= Return).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            _ = run(tty: tty, body: "do script \"\" in tab i of w")
        }
        return .success(())
    }

    static func focus(tty: String?) -> Result<Void, TerminalError> {
        guard let tty = validTTY(tty) else { return .failure(TerminalError(message: "This session has no known Terminal tab.")) }
        return run(tty: tty, body: """
        set selected of tab i of w to true
                set index of w to 1
                activate
        """)
    }

    static func ttyOf(pid: Int32) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=", "-p", String(pid)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("ttys") ? "/dev/" + s : nil
    }
}

struct TerminalError: Error { let message: String }
