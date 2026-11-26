import AppKit
import SwiftUI

/// Registers Vassy's hook with the agents the user picked, and removes it again.
/// Used by the first-run window, by `Vassy --setup <agents>` and by install.sh.
enum Setup {
    /// Every hook entry Vassy writes contains this, which is how they are found again.
    static let marker = ".vassy/hook"
    /// Stable path the agents call; a symlink to the running app's binary, refreshed at launch.
    static var hookLink: URL { Paths.base.appendingPathComponent("hook") }

    static func title(_ agent: Agent) -> String { agent == .claude ? "Claude Code" : "Codex" }

    static func configFile(_ agent: Agent) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch agent {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex:
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            return (codexHome ?? home.appendingPathComponent(".codex")).appendingPathComponent("hooks.json")
        }
    }

    static func isInstalled(_ agent: Agent) -> Bool {
        Summarizer.find(agent.rawValue) != nil
            || FileManager.default.fileExists(atPath: configFile(agent).deletingLastPathComponent().path)
    }

    static func isRegistered(_ agent: Agent) -> Bool {
        guard let text = try? String(contentsOf: configFile(agent), encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    /// A downloaded app opened straight from the Downloads folder runs from a random,
    /// read-only location; a hook pointing there would break after the next restart.
    static var isTranslocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }

    /// Points ~/.vassy/hook at the binary that is running now.
    static func refreshHookLink() {
        guard !isTranslocated, let binary = Bundle.main.executablePath else { return }
        let fm = FileManager.default
        Paths.secure()
        if (try? fm.destinationOfSymbolicLink(atPath: hookLink.path)) == binary { return }
        try? fm.removeItem(at: hookLink)
        try? fm.createSymbolicLink(atPath: hookLink.path, withDestinationPath: binary)
    }

    /// Makes the hook entries match `agents`: added where picked, removed everywhere else.
    /// Each changed file is backed up to ~/.vassy/backups first. Returns one line per agent.
    @discardableResult
    static func apply(agents: Set<Agent>) -> [String] {
        let fm = FileManager.default
        Paths.secure()
        let backups = Paths.base.appendingPathComponent("backups")
        try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
        refreshHookLink()
        let stamp = { () -> String in
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
        }()
        var report: [String] = []

        for agent in Agent.allCases {
            let file = configFile(agent), wanted = agents.contains(agent)
            var root: [String: Any] = [:]
            if let data = try? Data(contentsOf: file) {
                guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    report.append("\(title(agent)): \(file.path) is not valid JSON, left untouched")
                    continue
                }
                root = parsed
            } else if !wanted || !fm.fileExists(atPath: file.deletingLastPathComponent().path) {
                if wanted { report.append("\(title(agent)): not found on this Mac, skipped") }
                continue
            }

            let before = root["hooks"] as? [String: Any] ?? [:]
            var hooks: [String: Any] = [:]
            for (event, value) in before {
                guard let groups = value as? [[String: Any]] else { hooks[event] = value; continue }
                let kept = groups.filter { group in
                    !((group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains(marker) })
                }
                if !kept.isEmpty { hooks[event] = kept }
            }
            if wanted {
                let command = "\"\(hookLink.path)\" --hook \(agent.rawValue)"
                for event in Hook.events[agent] ?? [] {
                    let entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 3]]]
                    hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [entry]
                }
            }
            if NSDictionary(dictionary: hooks).isEqual(to: before) { continue }

            if fm.fileExists(atPath: file.path) {
                try? fm.copyItem(at: file, to: backups.appendingPathComponent("\(agent.rawValue)-\(file.lastPathComponent).\(stamp)"))
            }
            root["hooks"] = hooks.isEmpty ? nil : hooks
            // Written to the real file behind a symlink, keeping its permissions.
            let target = file.resolvingSymlinksInPath()
            let mode = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
            guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
                  (try? (data + Data("\n".utf8)).write(to: target, options: .atomic)) != nil else {
                report.append("\(title(agent)): could not write \(file.path)")
                continue
            }
            if let mode { try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path) }
            report.append("\(title(agent)): hook \(wanted ? "registered" : "removed") in \(file.path)")
        }

        if !agents.isEmpty { saveAgents(agents) }
        return report
    }

    private static func saveAgents(_ agents: Set<Agent>) {
        let file = Paths.base.appendingPathComponent("config.json")
        var config = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        config["agents"] = Agent.allCases.filter(agents.contains).map(\.rawValue)
        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            try? (data + Data("\n".utf8)).write(to: file, options: .atomic)
        }
    }
}

// MARK: - Window

@MainActor
enum SetupWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Vassy"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SetupView { window?.close() })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SetupView: View {
    let close: () -> Void
    @State private var picked: Set<Agent> = Set(Agent.allCases.filter { Setup.isRegistered($0) })
    @State private var report: [String]?

    init(close: @escaping () -> Void) {
        self.close = close
        // First run: preselect what is installed.
        if Agent.allCases.allSatisfy({ !Setup.isRegistered($0) }) {
            _picked = State(initialValue: Set(Agent.allCases.filter(Setup.isInstalled)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Which agents should Vassy watch?").font(.system(size: 20, weight: .bold))
                Text("Vassy adds a small hook to each agent you pick, so it knows when a session is waiting for you.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if Setup.isTranslocated {
                Label("Move Vassy into your Applications folder first, then open it again.", systemImage: "arrow.down.app")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.waiting)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let report {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report, id: \.self) { Text($0).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                    if report.isEmpty { Text("Nothing to change.").font(.system(size: 13)) }
                    if picked.contains(.codex) {
                        Label("One more step for Codex: start codex, type /hooks and trust the Vassy entries.", systemImage: "hand.raised")
                            .font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Agent.allCases, id: \.self) { agent in
                        Toggle(isOn: Binding(get: { picked.contains(agent) },
                                             set: { on in if on { picked.insert(agent) } else { picked.remove(agent) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Setup.title(agent)).font(.system(size: 14, weight: .semibold))
                                Text(Setup.isInstalled(agent) ? Setup.configFile(agent).path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                                                              : "Not found on this Mac")
                                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.switch)
                        .padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text("Each file is backed up to ~/.vassy/backups before it is changed. You can change this later from the gear menu.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                if Setup.isTranslocated {
                    Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut(.defaultAction)
                } else if report != nil {
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                    Button("Set up") { report = Setup.apply(agents: picked) }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 22)
        .frame(width: 460, height: 420)
    }
}
