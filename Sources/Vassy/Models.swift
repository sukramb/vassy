import Foundation
import SwiftUI

/// A coding agent Vassy can watch. Each one has its own hook events, transcript
/// format and way of telling whether a session is still alive.
enum Agent: String, CaseIterable {
    case claude, codex
    var name: String { self == .claude ? "Claude" : "Codex" }
}

/// Where Vassy keeps its state: events, summaries, marks, config and the hook script.
enum Paths {
    static let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vassy")
}

/// The optional ~/.vassy/config.json written by install.sh.
struct Config: Codable {
    var agents: [String]?
    var summarizer: String?    // "claude" | "codex"; default: whichever CLI is installed
    var language: String?      // language of the summaries, e.g. "German"; default: the system language
    var codexModel: String?    // model for Codex summaries; default: the user's Codex default

    static let current: Config = {
        guard let d = try? Data(contentsOf: Paths.base.appendingPathComponent("config.json")),
              let c = try? JSONDecoder().decode(Config.self, from: d) else { return Config() }
        return c
    }()
}

/// Written by hook/hook.js, one file per agent session.
struct HookEvent: Codable {
    var sessionId: String
    var cwd: String?
    var transcriptPath: String?
    var event: String
    var at: Double            // ms since 1970
    var waitingSince: Double? // ms, set while Claude waits for the user
    var notification: String?
    var ended: Bool?
    var tty: String?
    var agent: String?        // missing in files written before multi-agent support
    var pid: Int32?           // the agent process, used as liveness check where there is no registry

    var agentKind: Agent { Agent(rawValue: agent ?? "") ?? .claude }
    var isWaiting: Bool { event == "Stop" || event == "Notification" || event == "PermissionRequest" }
}

/// Claude Code's own registry of live sessions (~/.claude/sessions/<pid>.json).
/// Not a documented format, so every field is optional and failures are ignored.
struct RegistryEntry: Codable {
    var pid: Int32
    var sessionId: String?
    var cwd: String?
    var name: String?
    var status: String?
    var kind: String?
    var statusUpdatedAt: Double?
}

struct SessionAction: Codable, Hashable {
    var label: String
    var text: String
    var prod: Bool?
}

/// Haiku's compact summary of a waiting session.
struct Summary: Codable {
    var project: String
    var title: String
    var context: String
    var state: String
    var kind: String            // decision | task | info
    var question: String
    var recommendation: String
    var actions: [SessionAction]
    var live: Bool?
    var basedOn: Double?        // HookEvent.at the summary was made for
}

/// What the user did in the app, kept per session.
struct UserMark: Codable {
    var snoozedAt: Double?
    var dismissedAt: Double?
    var sentAt: Double?
    var pinnedAt: Double?
}

enum Phase { case waiting, running, done }

/// A group that sessions are sorted into, shown as a coloured chip and filter.
struct Project: Hashable {
    var name: String
    var isOther: Bool { name == Projects.other }
    var color: Color { Projects.color(for: name) }
}

/// One entry of the optional ~/.vassy/projects.json:
/// [{"name": "My App", "hint": "what it is, for the summarizer", "match": ["folder-keyword"]}]
struct ProjectRule: Codable {
    var name: String
    var hint: String?
    var match: [String]?
}

/// Project grouping. With a projects.json the user's own list is used; without one,
/// sessions are grouped by the name the summarizer picks or by their folder name.
enum Projects {
    static let other = "Other"

    static let rules: [ProjectRule] = {
        let url = Paths.base.appendingPathComponent("projects.json")
        guard let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([ProjectRule].self, from: d) else { return [] }
        return r.filter { !$0.name.isEmpty }
    }()

    private static let palette: [(UInt32, UInt32)] = [
        (0xBE185D, 0xF9A8C9), (0x0F766E, 0x5EEAD4), (0x6D28D9, 0xC4B5FD),
        (0xB45309, 0xFCD34D), (0x1D4ED8, 0x93C5FD), (0x15803D, 0x86EFAC),
    ]

    static func color(for name: String) -> Color {
        if name == other { return .secondary }
        let i = rules.firstIndex { $0.name == name } ?? Int(name.unicodeScalars.reduce(UInt32(0)) { ($0 &* 31) &+ $1.value } % UInt32(palette.count))
        let c = palette[i % palette.count]
        return Color(light: c.0, dark: c.1)
    }

    static func resolve(summary: String?, cwd: String?) -> Project {
        let s = (summary ?? "").trimmingCharacters(in: .whitespaces)
        if rules.isEmpty {
            if !s.isEmpty { return Project(name: s) }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            guard let cwd, !cwd.isEmpty, cwd != home else { return Project(name: other) }
            return Project(name: (cwd as NSString).lastPathComponent)
        }
        let c = (cwd ?? "").lowercased()
        if let r = rules.first(where: { ($0.match ?? []).contains { !$0.isEmpty && c.contains($0.lowercased()) } }) {
            return Project(name: r.name)
        }
        if let r = rules.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return Project(name: r.name) }
        return Project(name: other)
    }

    /// Lines for the summarizer prompt: what the projects are and what to put in "project".
    static var promptIntro: String {
        if rules.isEmpty { return "Derive the project name from the folder and the content of the transcript." }
        let list = rules.map { r in "\"\(r.name)\"" + (r.hint.map { " (\($0))" } ?? "") }.joined(separator: ", ")
        return "Projects: \(list), otherwise \"\(other)\"."
    }
    static var promptField: String {
        rules.isEmpty ? "Short project name, max 20 characters" : (rules.map(\.name) + [other]).joined(separator: "|")
    }
}

struct SessionItem: Identifiable {
    let id: String
    var event: HookEvent
    var registry: RegistryEntry?
    var summary: Summary?
    var tty: String?
    var phase: Phase
    var summarizing: Bool
    var summaryFailed: Bool
    var sortKey: Double
    var showAgent = false     // set when sessions of more than one agent are listed

    var project: Project { Projects.resolve(summary: summary?.project, cwd: event.cwd) }
    var title: String {
        if let t = summary?.title, !t.isEmpty { return t }
        if let n = registry?.name, !n.isEmpty { return n }
        return ((event.cwd ?? "Session") as NSString).lastPathComponent
    }
    var isTask: Bool { summary?.kind == "task" }
    var waitingDate: Date { Date(timeIntervalSince1970: (event.waitingSince ?? event.at) / 1000) }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
    static let waiting = Color(light: 0xB4460B, dark: 0xFDBA74)
    static let task = Color(light: 0x1D4ED8, dark: 0x93C5FD)
    static let good = Color(light: 0x15803D, dark: 0x86EFAC)
}

func waitedText(since date: Date, now: Date = Date()) -> String {
    let m = Int(now.timeIntervalSince(date) / 60)
    if m < 1 { return "just now" }
    if m < 60 { return "waiting \(m) min" }
    let h = m / 60
    if h < 24 { return "waiting \(h) h" }
    return "waiting \(h / 24) d"
}
