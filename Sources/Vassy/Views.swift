import SwiftUI
import ServiceManagement

enum Tab { case queue, all }

struct RootView: View {
    @ObservedObject var store: Store
    @State private var tab: Tab

    init(store: Store, initialTab: Tab = .queue) {
        self.store = store
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                switch tab {
                case .queue: QueueView(store: store)
                case .all: OverviewView(store: store)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 468, height: 780)
        .overlay(alignment: .bottom) { toast }
        .modifier(GlassBackground())
        .animation(.snappy(duration: 0.25), value: store.queue.first?.id)
        .animation(.easeOut(duration: 0.2), value: store.toast)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tab == .queue ? "Queue" : "All sessions").font(.system(size: 17, weight: .bold))
                Spacer()
                Picker("", selection: $tab) {
                    Text("Queue").tag(Tab.queue)
                    Text("All").tag(Tab.all)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            if tab == .queue { ProgressBar(done: store.handledToday, open: store.queue.count) }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            let busy = store.running.count
            Text(busy == 0 ? "No session is working" : "Working right now: \(busy)")
            Spacer()
            Text("⌥⌘C").fontWeight(.semibold)
            Menu {
                Toggle("Launch at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }))
                Divider()
                Button("Quit") { NSApp.terminate(nil) }
            } label: { Image(systemName: "gearshape") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    @ViewBuilder private var toast: some View {
        if let t = store.toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text(t).lineLimit(2)
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.thickMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            .padding(.bottom, 52)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

struct ProgressBar: View {
    let done: Int
    let open: Int
    var body: some View {
        let total = done + open
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(open == 0 ? (done == 0 ? "Nothing waiting" : "All \(done) done")
                               : "\(done) of \(total) done · \(open) left")
                Spacer()
                Text("Oldest first")
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<max(total, 1), id: \.self) { i in
                    Capsule().fill(i < done ? Color.good : Color.primary.opacity(0.12)).frame(height: 5)
                }
            }
        }
    }
}

// MARK: - Queue

struct QueueView: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let current = store.queue.first {
                    CurrentCard(store: store, item: current).id(current.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                    let rest = Array(store.queue.dropFirst())
                    if !rest.isEmpty {
                        SectionTitle(text: "Up next · \(rest.count)")
                        VStack(spacing: 4) {
                            ForEach(Array(rest.enumerated()), id: \.element.id) { idx, item in
                                NextRow(item: item, position: idx + 2) { store.pullForward(item) }
                            }
                        }
                    }
                } else {
                    EmptyQueue(running: store.running.count)
                }
            }
            .padding(16).padding(.bottom, 30)
        }
    }
}

struct SectionTitle: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.8)
            .foregroundStyle(color).padding(.horizontal, 6)
    }
}

struct ProjectChip: View {
    let item: SessionItem
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(item.project.color).frame(width: 8, height: 8)
            Text(item.project.name.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(item.project.color)
            if item.showAgent { AgentTag(agent: item.event.agentKind) }
        }
    }
}

/// Names the agent a session belongs to; only shown when several agents are in use.
struct AgentTag: View {
    let agent: Agent
    var body: some View {
        Text(agent.name).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

struct KindBadge: View {
    let item: SessionItem
    var body: some View {
        let task = item.isTask
        Text(task ? "Your task" : "Decision")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(task ? Color.task : Color.waiting)
            .background((task ? Color.task : Color.waiting).opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct CurrentCard: View {
    @ObservedObject var store: Store
    let item: SessionItem
    @State private var draft = ""
    @State private var confirm: Int?
    @State private var hoverText: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProjectChip(item: item)
                if item.summary != nil { KindBadge(item: item) }
                if item.summary?.live == true { LiveBadge() }
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(waitedText(since: item.waitingDate, now: ctx.date))
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            Text(item.title).font(.system(size: 18, weight: .bold)).fixedSize(horizontal: false, vertical: true)

            if let s = item.summary {
                Text([s.context, s.state].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.system(size: 13.5)).foregroundStyle(.secondary).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .help([s.context, s.state].joined(separator: "\n"))
                if !s.question.isEmpty || !s.recommendation.isEmpty {
                    QuestionBox(item: item, summary: s)
                }
                if item.summarizing { Label("Summarizing the new reply …", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12)).foregroundStyle(.secondary) }
                actionButtons(s)
            } else {
                pendingSummary
            }

            replyField
            bottomRow
        }
        .padding(18)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardStroke))
        .onAppear { focusSoon() }
        .onChange(of: store.focusTick) { focusSoon() }
    }

    private var cardFill: Color { item.isTask || item.summary == nil ? Color.primary.opacity(0.04) : Color.waiting.opacity(0.08) }
    private var cardStroke: Color { item.isTask || item.summary == nil ? Color.primary.opacity(0.08) : Color.waiting.opacity(0.35) }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fieldFocused = true }
    }

    @ViewBuilder private var pendingSummary: some View {
        if item.summaryFailed {
            HStack {
                Label("Summary failed", systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Retry") { store.resummarize(item) }
            }
            .font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Wird zusammengefasst …")
            }
            .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        if let n = item.event.notification {
            Text(n).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func actionButtons(_ s: Summary) -> some View {
        if !s.actions.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(s.actions.enumerated()), id: \.offset) { i, a in
                    let confirming = confirm == i
                    Button {
                        if a.prod == true && !confirming { confirm = i; return }
                        confirm = nil
                        store.send(a.text, to: item)
                    } label: {
                        HStack(spacing: 7) {
                            if a.prod == true { Image(systemName: "arrow.up.circle.fill") }
                            Text(confirming ? "Really ship this? Click again" : (i == 0 ? "\(a.label)  ·  Recommended" : a.label))
                            Spacer()
                            Text("⌘\(i + 1)").font(.system(size: 11, weight: .medium)).opacity(0.7)
                        }
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ActionStyle(kind: confirming ? .danger : (i == 0 ? .primary : .secondary)))
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .onHover { hoverText = $0 ? a.text : nil }
                    .help(a.text)
                }
            }
            Group {
                if let h = hoverText {
                    (Text("Sends: ").fontWeight(.semibold) + Text("“\(h)”").font(.system(size: 11.5, design: .monospaced)))
                } else { Text(" ") }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var replyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your own answer").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Dictate or type …").foregroundStyle(.secondary)
                            .padding(.leading, 5).padding(.top, 1).allowsHitTesting(false)
                    }
                    TextEditor(text: $draft)
                        .scrollContentBackground(.hidden)
                        .focused($fieldFocused)
                        .frame(minHeight: 56, maxHeight: 110)
                }
                .font(.system(size: 13.5))
                HStack {
                    Label("Field is active, just start talking", systemImage: "mic")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        store.send(text, to: item)
                        draft = ""
                    } label: {
                        HStack(spacing: 8) { Text("Send"); Text("⌘↵").font(.system(size: 11)).opacity(0.75) }
                            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 32)
                    }
                    .buttonStyle(ActionStyle(kind: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .muted : .send))
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(fieldFocused ? Color.accentColor : Color.primary.opacity(0.14),
                                                                     lineWidth: fieldFocused ? 2 : 1))
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 8) {
            Button { store.snooze(item) } label: { KeyLabel(title: "Later", key: "⌘→") }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button { store.open(item) } label: { KeyLabel(title: "Open tab", key: "⌘O") }
                .keyboardShortcut("o", modifiers: .command)
            Button { store.dismiss(item) } label: { KeyLabel(title: "Hide", key: "⌘D") }
                .keyboardShortcut("d", modifiers: .command)
        }
        .buttonStyle(ActionStyle(kind: .secondary))
        .padding(.top, 4)
    }
}

struct QuestionBox: View {
    let item: SessionItem
    let summary: Summary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !summary.question.isEmpty {
                Label { Text(summary.question).font(.system(size: 15, weight: .semibold)) } icon: {
                    Image(systemName: "questionmark.circle").foregroundStyle(item.isTask ? Color.task : Color.waiting)
                }
            }
            if !summary.recommendation.isEmpty {
                Label {
                    (Text("Recommendation: ").fontWeight(.semibold).foregroundStyle(Color.good) + Text(summary.recommendation))
                        .font(.system(size: 13.5))
                } icon: { Image(systemName: "lightbulb").foregroundStyle(Color.good) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct KeyLabel: View {
    let title: String
    let key: String
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Text(key).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .frame(maxWidth: .infinity).frame(height: 32)
    }
}

struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.good).frame(width: 6, height: 6)
            Text("LIVE")
        }
        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(Color.good)
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(Color.good.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct ActionStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger, send, muted }
    let kind: Kind
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(fg)
            .background(bg.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(kind == .secondary ? Color.primary.opacity(0.16) : .clear))
            .offset(y: hovering && !configuration.isPressed ? -1 : 0)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
    private var bg: Color {
        switch kind {
        case .primary: Color.primary
        case .secondary: Color.clear
        case .danger: Color(red: 0.76, green: 0.25, blue: 0.05)
        case .send: Color.accentColor
        case .muted: Color.primary.opacity(0.07)
        }
    }
    private var fg: Color {
        switch kind {
        case .primary: Color(nsColor: .windowBackgroundColor)
        case .secondary: Color.primary
        case .danger, .send: .white
        case .muted: .secondary
        }
    }
}

struct NextRow: View {
    let item: SessionItem
    let position: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(position)").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).background(Color.primary.opacity(0.07), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(item.project.name.uppercased()).font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(item.project.color)
                        if item.showAgent { AgentTag(agent: item.event.agentKind) }
                        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                    Text(item.summary?.question ?? "Wird zusammengefasst …").font(.system(size: 12))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(waitedText(since: item.waitingDate).replacingOccurrences(of: "waiting ", with: ""))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Move to the front")
    }
}

struct EmptyQueue: View {
    let running: Int
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 24, weight: .bold)).foregroundStyle(Color.good)
                .frame(width: 56, height: 56).background(Color.good.opacity(0.14), in: Circle())
            Text("All clear").font(.system(size: 18, weight: .bold))
            Text(running > 0 ? "\(running) session\(running == 1 ? " is" : "s are") still working. As soon as one finishes or has a question, it shows up here."
                             : "As soon as a session finishes or has a question, it shows up here.")
                .font(.system(size: 13.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity).padding(.top, 90)
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var store: Store
    @State private var filter: Project?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    FilterPill(label: "All", color: .secondary, on: filter == nil) { filter = nil }
                    ForEach(projects, id: \.self) { p in
                        FilterPill(label: p.name, color: p.color, on: filter == p) { filter = p }
                    }
                }
                let q = store.queue.filter(match), r = store.running.filter(match), d = store.done.filter(match)
                if !q.isEmpty {
                    SectionTitle(text: "Needs you · \(q.count)", color: .waiting)
                    ForEach(q) { OverviewRow(store: store, item: $0, style: .waiting) }
                }
                if !r.isEmpty {
                    SectionTitle(text: "Running · \(r.count)")
                    ForEach(r) { OverviewRow(store: store, item: $0, style: .running) }
                }
                if !d.isEmpty {
                    SectionTitle(text: "Done · \(d.count)")
                    ForEach(d) { OverviewRow(store: store, item: $0, style: .done) }
                }
                if q.isEmpty && r.isEmpty && d.isEmpty {
                    Text("No sessions found.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(16).padding(.bottom, 30)
        }
    }

    private func match(_ i: SessionItem) -> Bool { filter == nil || i.project == filter }
    /// Projects that currently have sessions, in a stable order with "other" last.
    private var projects: [Project] {
        let present = Set((store.queue + store.running + store.done).map(\.project))
        return present.sorted { ($0.isOther ? 1 : 0, $0.name.lowercased()) < ($1.isOther ? 1 : 0, $1.name.lowercased()) }
    }
}

struct FilterPill: View {
    let label: String
    let color: Color
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10).frame(height: 28)
            .foregroundStyle(on ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .background(on ? Color.primary : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct OverviewRow: View {
    enum Style { case waiting, running, done }
    @ObservedObject var store: Store
    let item: SessionItem
    let style: Style

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.project.name.uppercased()).font(.system(size: 10.5, weight: .bold)).foregroundStyle(item.project.color)
                    if item.showAgent { AgentTag(agent: item.event.agentKind) }
                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if item.summary?.live == true { LiveBadge() }
                }
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button { store.open(item) } label: { Image(systemName: "arrow.up.forward.square") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Open the Terminal tab")
                .accessibilityLabel("Open the Terminal tab")
        }
        .padding(10)
        .background(style == .waiting ? Color.waiting.opacity(0.08) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var subtitle: String {
        switch style {
        case .waiting: return item.summary?.question ?? "Wird zusammengefasst …"
        case .running: return item.summary.map { "Working · last: \($0.title)" } ?? "Working …"
        case .done: return item.summary?.state ?? ""
        }
    }

    @ViewBuilder private var icon: some View {
        switch style {
        case .waiting: Image(systemName: "questionmark.circle.fill").foregroundStyle(Color.waiting)
        case .running: ProgressView().controlSize(.mini)
        case .done: Image(systemName: "checkmark").foregroundStyle(Color.good)
        }
    }
}
