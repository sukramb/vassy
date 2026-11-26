import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published private(set) var items: [SessionItem] = []
    @Published var toast: String?
    @Published private(set) var handledToday = 0
    @Published var focusTick = 0   // bumped whenever the panel opens

    var queue: [SessionItem] {
        items.filter { $0.phase == .waiting }.sorted { $0.sortKey < $1.sortKey }
    }
    var running: [SessionItem] { items.filter { $0.phase == .running }.sorted { $0.event.at > $1.event.at } }
    var done: [SessionItem] {
        Array(items.filter { $0.phase == .done }.sorted { $0.event.at > $1.event.at }.prefix(15))
    }

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var base: URL { Paths.base }
    private var eventsDir: URL { base.appendingPathComponent("events") }
    private var summariesDir: URL { base.appendingPathComponent("summaries") }
    private var marksFile: URL { base.appendingPathComponent("marks.json") }
    private var registryDir: URL { home.appendingPathComponent(".claude/sessions") }

    private var summaries: [String: Summary] = [:]
    private var marks: [String: UserMark] = [:]
    private var inFlight: Set<String> = []
    private var failedFor: [String: Double] = [:]
    private var notified: [String: Double] = [:]
    private var ttyCache: [Int32: String] = [:]
    private var firstRun = true
    private var handledDay = Calendar.current.startOfDay(for: Date())
    private var timer: Timer?
    private var toastTask: Task<Void, Never>?

    init() {
        Paths.secure()
        try? fm.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: summariesDir, withIntermediateDirectories: true)
        for url in (try? fm.contentsOfDirectory(at: summariesDir, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "json" {
            if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Summary.self, from: d) {
                summaries[url.deletingPathExtension().lastPathComponent] = s
            }
        }
        if let d = try? Data(contentsOf: marksFile), let m = try? JSONDecoder().decode([String: UserMark].self, from: d) {
            marks = m
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Polling

    func refresh() {
        let now = Date().timeIntervalSince1970 * 1000
        let registry = readRegistry()
        let registryAvailable = fm.fileExists(atPath: registryDir.path)
        seedFromRegistry(registry)
        var next: [SessionItem] = []

        for url in (try? fm.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "json" {
            guard let d = try? Data(contentsOf: url), let ev = try? JSONDecoder().decode(HookEvent.self, from: d) else { continue }
            let sid = ev.sessionId
            // The id becomes part of file paths, so it must be well-formed and match its file.
            guard HookEvent.validId(sid), sid == url.deletingPathExtension().lastPathComponent else { continue }
            let reg = registry[sid]
            let recent = now - ev.at < 12 * 3_600_000
            let alive: Bool
            switch ev.agentKind {
            case .claude: alive = reg != nil || (!registryAvailable && recent)
            case .codex: alive = ev.pid.map { kill($0, 0) == 0 } ?? recent
            }
            if ev.ended == true || !alive {
                if now - ev.at > 3 * 86_400_000 { cleanup(sid) }
                continue
            }

            let ttyOf = { (pid: Int32) in self.ttyCache[pid] ?? Terminal.ttyOf(pid: pid).map { self.ttyCache[pid] = $0; return $0 } }
            let tty = reg.flatMap { ttyOf($0.pid) } ?? ev.tty ?? ev.pid.flatMap(ttyOf)
            let mark = marks[sid] ?? UserMark()
            let summary = summaries[sid]
            let waitingEvent = ev.isWaiting
            let since = ev.waitingSince ?? ev.at

            var phase: Phase
            if let sent = mark.sentAt, sent > ev.at { phase = .running }
            else if !waitingEvent || reg?.status == "busy" { phase = .running }
            else if summary?.basedOn == ev.at && summary?.kind == "info" { phase = .done }
            else if let dis = mark.dismissedAt, dis > since { phase = .done }
            else { phase = .waiting }

            if phase != .running, waitingEvent, (summary?.basedOn ?? 0) < ev.at,
               !inFlight.contains(sid), failedFor[sid] != ev.at, now - ev.at > 1500, inFlight.count < 2 {
                startSummary(ev)
            }

            var sortKey = since
            if let s = mark.snoozedAt, s > since { sortKey = s }
            if let p = mark.pinnedAt, p > since, p > (mark.snoozedAt ?? 0) { sortKey = -p }
            let stale = (summary?.basedOn ?? 0) < ev.at
            next.append(SessionItem(id: sid, event: ev, registry: reg, summary: summary, tty: tty, phase: phase,
                                    summarizing: inFlight.contains(sid) || (phase == .waiting && stale && failedFor[sid] != ev.at),
                                    summaryFailed: stale && failedFor[sid] == ev.at && !inFlight.contains(sid),
                                    sortKey: sortKey))
        }

        if Set(next.map { $0.event.agentKind }).count > 1 {
            for i in next.indices { next[i].showAgent = true }
        }
        notifyNewcomers(next)
        if Calendar.current.startOfDay(for: Date()) != handledDay {
            handledDay = Calendar.current.startOfDay(for: Date()); handledToday = 0
        }
        items = next
        firstRun = false
    }

    private func readRegistry() -> [String: RegistryEntry] {
        var map: [String: RegistryEntry] = [:]
        for url in (try? fm.contentsOfDirectory(at: registryDir, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "json" {
            guard let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(RegistryEntry.self, from: d),
                  let sid = r.sessionId, r.kind == nil || r.kind == "interactive", kill(r.pid, 0) == 0 else { continue }
            map[sid] = r
        }
        return map
    }

    /// Sessions that were already idle before the hook existed get an event file
    /// built from Claude Code's registry, so they show up without waiting for a new turn.
    private func seedFromRegistry(_ registry: [String: RegistryEntry]) {
        for (sid, r) in registry where HookEvent.validId(sid) && (r.status == "idle" || r.status == "busy") {
            let file = eventsDir.appendingPathComponent(sid + ".json")
            guard !fm.fileExists(atPath: file.path), let transcript = findTranscript(sid) else { continue }
            let at = r.statusUpdatedAt ?? Date().timeIntervalSince1970 * 1000
            let idle = r.status == "idle"
            let ev = HookEvent(sessionId: sid, cwd: r.cwd, transcriptPath: transcript, event: idle ? "Stop" : "UserPromptSubmit",
                               at: at, waitingSince: idle ? at : nil, notification: nil, ended: false,
                               tty: Terminal.ttyOf(pid: r.pid))
            if let d = try? JSONEncoder().encode(ev) { try? d.write(to: file, options: .atomic) }
        }
    }

    private func findTranscript(_ sid: String) -> String? {
        let projects = home.appendingPathComponent(".claude/projects")
        for dir in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            let f = dir.appendingPathComponent(sid + ".jsonl")
            if fm.fileExists(atPath: f.path) { return f.path }
        }
        return nil
    }

    private func cleanup(_ sid: String) {
        try? fm.removeItem(at: eventsDir.appendingPathComponent(sid + ".json"))
        try? fm.removeItem(at: summariesDir.appendingPathComponent(sid + ".json"))
        summaries[sid] = nil
        if marks.removeValue(forKey: sid) != nil { saveMarks() }
    }

    private func startSummary(_ ev: HookEvent) {
        let sid = ev.sessionId
        inFlight.insert(sid)
        Task.detached(priority: .utility) { [weak self] in
            let s = Summarizer.run(event: ev)
            await self?.finishSummary(sid: sid, at: ev.at, summary: s)
        }
    }

    private func finishSummary(sid: String, at: Double, summary s: Summary?) {
        inFlight.remove(sid)
        if let s {
            summaries[sid] = s
            if let d = try? JSONEncoder().encode(s) {
                try? d.write(to: summariesDir.appendingPathComponent(sid + ".json"), options: .atomic)
            }
        } else {
            failedFor[sid] = at
        }
        refresh()
    }

    // MARK: - Notifications

    private func notifyNewcomers(_ list: [SessionItem]) {
        for item in list where item.phase == .waiting {
            guard let s = item.summary, let based = s.basedOn, based == item.event.at, notified[item.id] != based else { continue }
            notified[item.id] = based
            if firstRun { continue }
            let c = UNMutableNotificationContent()
            c.title = "\(item.project.name) · \(s.title)"
            c.body = s.question + (s.recommendation.isEmpty ? "" : "\nRecommendation: \(s.recommendation)")
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id + "-\(Int(based))", content: c, trigger: nil))
        }
    }

    // MARK: - Actions

    func send(_ text: String, to item: SessionItem) {
        guard !item.event.needsPermission else { show("Answer the permission request in the terminal."); return }
        switch Terminal.send(text, tty: item.tty, agent: item.event.agentKind, pid: item.registry?.pid ?? item.event.pid) {
        case .success:
            update(item.id) { $0.sentAt = Date().timeIntervalSince1970 * 1000 }
            handledToday += 1
            show("Sent to \(item.title)")
        case .failure(let err):
            show(err.message)
            log("send failed for \(item.id.prefix(8)) on \(item.tty ?? "no tty"): \(err.message)")
        }
        refresh()
    }

    /// A short local log of failures (never message contents), to make rare problems traceable.
    private func log(_ line: String) {
        let file = base.appendingPathComponent("vassy.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let old = (try? Data(contentsOf: file)).map { $0.suffix(100_000) } ?? Data()
        try? (old + Data("\(stamp) \(line)\n".utf8)).write(to: file, options: .atomic)
    }

    func open(_ item: SessionItem) {
        if case .failure(let err) = Terminal.focus(tty: item.tty) { show(err.message) }
    }

    func snooze(_ item: SessionItem) {
        update(item.id) { $0.snoozedAt = Date().timeIntervalSince1970 * 1000 }
        show("Moved to the back of the queue")
        refresh()
    }

    func dismiss(_ item: SessionItem) {
        update(item.id) { $0.dismissedAt = Date().timeIntervalSince1970 * 1000 }
        handledToday += 1
        show("Hidden until the session asks again")
        refresh()
    }

    func pullForward(_ item: SessionItem) {
        update(item.id) { $0.pinnedAt = Date().timeIntervalSince1970 * 1000 }
        refresh()
    }

    func resummarize(_ item: SessionItem) {
        failedFor[item.id] = nil
        summaries[item.id]?.basedOn = 0
        refresh()
    }

    private func update(_ sid: String, _ f: (inout UserMark) -> Void) {
        var m = marks[sid] ?? UserMark()
        f(&m)
        marks[sid] = m
        saveMarks()
    }

    private func saveMarks() {
        if let d = try? JSONEncoder().encode(marks) { try? d.write(to: marksFile, options: .atomic) }
    }

    func show(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}
