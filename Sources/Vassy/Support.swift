import AppKit
import SwiftUI

/// Buy Me a Coffee link, and a one-time nudge once Vassy has sent enough answers.
/// The count stays in ~/.vassy/support.json. The page opens in the browser; nothing is sent back.
@MainActor
final class Support: ObservableObject {
    static let shared = Support()
    static let link = URL(string: "https://buymeacoffee.com/sukrambm")!
    static let threshold = 50

    /// True while the panel should show the nudge. Reloaded when the panel opens.
    @Published private(set) var nudgeVisible = false

    private init() { refresh() }

    /// Hidden below the threshold. At or above it, shown until the nudge is dismissed.
    static func shouldNudge(answered: Int, nudgeClosed: Bool) -> Bool {
        answered >= threshold && !nudgeClosed
    }

    /// Reloads ~/.vassy/support.json. The panel calls this from show(), because the
    /// view stays alive while the panel is closed and would otherwise keep a stale flag.
    func refresh() {
        let s = SupportState.load()
        nudgeVisible = Self.shouldNudge(answered: s.answered, nudgeClosed: s.nudgeClosed)
    }

    /// One answer that Terminal accepted.
    func recordSend() {
        var s = SupportState.load()
        s.answered += 1
        s.save()
        nudgeVisible = Self.shouldNudge(answered: s.answered, nudgeClosed: s.nudgeClosed)
    }

    /// The nudge's coffee button: open the page, then never show the nudge again.
    func openFromNudge() {
        NSWorkspace.shared.open(Self.link)
        dismiss()
    }

    func dismiss() {
        var s = SupportState.load()
        s.nudgeClosed = true
        s.save()
        nudgeVisible = false
    }
}

/// ~/.vassy/support.json, shaped as {"answered": Int, "nudgeClosed": Bool}.
struct SupportState: Codable {
    var answered: Int
    var nudgeClosed: Bool

    private static var file: URL { Paths.base.appendingPathComponent("support.json") }

    static func load() -> SupportState {
        guard let d = try? Data(contentsOf: file),
              let s = try? JSONDecoder().decode(SupportState.self, from: d) else {
            return SupportState(answered: 0, nudgeClosed: false)
        }
        return s
    }

    func save() {
        Paths.secure()
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: Self.file, options: .atomic) }
    }
}

struct SupportNudge: View {
    @ObservedObject var support: Support

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color.waiting)
            Text("Vassy is free. A coffee helps keep it maintained.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Buy me a coffee") { support.openFromNudge() }
                .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(Color.waiting)
                .fixedSize()
                .help("Opens buymeacoffee.com")
            Button { support.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Close")
            .help("Don't show this again")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.waiting.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
