import Foundation

/// The hook the agents call: `Vassy --hook <agent>`, with the event as JSON on stdin.
/// It records the latest lifecycle event of the session in ~/.vassy/events so the app
/// knows who is waiting for an answer. It prints nothing, so the agent carries on
/// unchanged, and it never blocks: hard exit after 1.5 s, every failure is silent.
enum Hook {
    static let events: [Agent: [String]] = [
        .claude: ["Stop", "Notification", "UserPromptSubmit", "SessionEnd"],
        .codex: ["Stop", "PermissionRequest", "UserPromptSubmit", "PostToolUse", "SessionEnd"],
    ]

    static func run(agent name: String?) -> Never {
        // the app's own summary calls must not show up as sessions
        if ProcessInfo.processInfo.environment["VASSY_SUMMARIZER"] != nil { exit(0) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { exit(0) }

        let agent = Agent(rawValue: name ?? "") ?? .claude
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard input.count < 1_000_000,
              let e = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let sid = e["session_id"] as? String,
              sid.range(of: #"^[A-Za-z0-9_-]{8,80}$"#, options: .regularExpression) != nil,
              let event = e["hook_event_name"] as? String, events[agent]?.contains(event) == true
        else { exit(0) }

        let dir = Paths.base.appendingPathComponent("events")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(sid + ".json")
        let prev = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(HookEvent.self, from: $0) }

        // PostToolUse only matters to end a "waiting for permission" state.
        if event == "PostToolUse", prev?.event != "PermissionRequest" { exit(0) }

        var tty = prev?.tty, pid = prev?.pid
        if tty == nil || pid == nil {
            let found = origin(of: getppid(), agent: agent)
            tty = tty ?? found.tty
            pid = pid ?? found.pid
        }
        // Sessions without a terminal (desktop apps, headless runs) cannot be answered from Vassy.
        if agent != .claude, tty == nil { exit(0) }

        let now = (Date().timeIntervalSince1970 * 1000).rounded()
        var out = HookEvent(sessionId: sid, cwd: e["cwd"] as? String ?? prev?.cwd,
                            transcriptPath: e["transcript_path"] as? String ?? prev?.transcriptPath,
                            event: event, at: now)
        // a reminder after Stop keeps the original waiting time
        out.waitingSince = out.isWaiting ? (prev?.waitingSince ?? now) : nil
        switch event {
        case "Notification": out.notification = (e["message"] as? String).map { String($0.prefix(300)) }
        case "PermissionRequest": out.notification = permissionText(e)
        default: break
        }
        out.ended = event == "SessionEnd"
        out.tty = tty
        out.agent = agent.rawValue
        out.pid = pid
        if let data = try? JSONEncoder().encode(out) { try? data.write(to: file, options: .atomic) }
        exit(0)
    }

    private static func permissionText(_ e: [String: Any]) -> String {
        let input = e["tool_input"] as? [String: Any] ?? [:]
        let detail = ["description", "command", "file_path"].compactMap { input[$0] as? String }.first { !$0.isEmpty }
        let tool = e["tool_name"] as? String ?? "tool"
        return String(("Permission needed: " + tool + (detail.map { " · " + $0 } ?? "")).prefix(300))
    }

    /// Walks up from the hook's parent: the first ancestor that owns a terminal gives the
    /// tty, the first one that looks like the agent binary gives the pid to watch.
    private static func origin(of start: Int32, agent: Agent) -> (tty: String?, pid: Int32?) {
        let binary = agent == .claude ? #"(^|/)claude$"# : #"(^|/)codex[^/]*$"#
        var tty: String?, agentPid: Int32?, pid = start
        for _ in 0..<6 where pid > 1 {
            guard let line = ps(pid) else { break }
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 3, let parent = Int32(parts[1]) else { break }
            if tty == nil, parts[0].range(of: #"^ttys\d+$"#, options: .regularExpression) != nil { tty = "/dev/" + parts[0] }
            if agentPid == nil, parts[2].range(of: binary, options: .regularExpression) != nil { agentPid = pid }
            if tty != nil, agentPid != nil { break }
            pid = parent
        }
        return (tty, agentPid)
    }

    private static func ps(_ pid: Int32) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=,ppid=,comm=", "-p", String(pid)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
