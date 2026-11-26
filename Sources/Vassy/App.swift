import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UserNotifications

@main
enum Main {
    static func main() {
        // Debug: Vassy --summarize <transcript.jsonl> [cwd] [claude|codex]
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "--summarize" {
            let ev = HookEvent(sessionId: "debug", cwd: args.count > 3 ? args[3] : nil, transcriptPath: args[2],
                               event: "Stop", at: Date().timeIntervalSince1970 * 1000,
                               agent: args.count > 4 ? args[4] : nil)
            let start = Date()
            if let s = Summarizer.run(event: ev), let d = try? JSONEncoder().encode(s) {
                print(String(decoding: d, as: UTF8.self))
            } else { print("FAILED") }
            print(String(format: "%.1fs", Date().timeIntervalSince(start)))
            exit(0)
        }
        // Debug: Vassy --send <tty> <text>
        if args.count >= 4, args[1] == "--send" {
            MainActor.assumeIsolated {
                print(Terminal.send(args[3], tty: args[2]))
                RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            }
            exit(0)
        }
        // Debug: Vassy --snapshot <out.png> [all] [dark]
        if args.count >= 3, args[1] == "--snapshot" {
            MainActor.assumeIsolated {
                _ = NSApplication.shared
                let store = Store()
                RunLoop.main.run(until: Date().addingTimeInterval(1))
                let view = RootView(store: store, initialTab: args.contains("all") ? .all : .queue)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: args.contains("dark") ? .darkAqua : .aqua)
                let win = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 468, height: 780),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
                win.backgroundColor = args.contains("dark") ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)
                win.appearance = host.appearance
                win.contentView = host
                win.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(1.5))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2]))
                    print("ok")
                }
            }
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = makeMainMenu()
        app.run()
    }

    /// Menu bar apps have no menu, so ⌘V/⌘C/⌘A/⌘Z would not reach the text field.
    /// Wispr Flow inserts dictated text with ⌘V, so this menu is required.
    static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Vassy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}

/// A borderless panel that can take keyboard focus, so Wispr Flow and the
/// shortcuts reach the reply field.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyPanel!
    private var store: Store!
    private var bag = Set<AnyCancellable>()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ note: Notification) {
        store = Store()
        setUpStatusItem()
        setUpPanel()
        store.$items.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusItem() }
        }.store(in: &bag)
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.vassy.toggle"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
        }
        hotKey = HotKey { [weak self] in MainActor.assumeIsolated { self?.toggle() } }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityLabel("Vassy")
        updateStatusItem()
    }

    @MainActor private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let count = store.queue.count
        let img = NSImage(systemSymbolName: count > 0 ? "rectangle.stack.fill" : "rectangle.stack", accessibilityDescription: "Vassy")
        img?.isTemplate = true
        button.image = img
        if count > 0 {
            button.attributedTitle = NSAttributedString(string: " \(count)", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.systemOrange,
            ])
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    @objc private func statusClicked() { toggle() }

    // MARK: Panel

    @MainActor private func setUpPanel() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 468, height: 780),
                         styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: RootView(store: store))
        host.wantsLayer = true
        host.layer?.cornerRadius = 22
        host.layer?.masksToBounds = true
        panel.contentView = host
        // Close on a click outside or Escape, not on losing key status: dictation
        // tools briefly show their own overlay, which must not close the panel.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { if self?.panel.isVisible == true { self?.hide() } }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape), self?.panel.isVisible == true {
                MainActor.assumeIsolated { self?.hide() }
                return nil
            }
            return event
        }
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    @MainActor private func show() {
        guard let button = statusItem.button, let win = button.window else { return }
        let b = win.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = win.screen ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        var x = b.midX - size.width / 2
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        let y = b.minY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, vf.minY + 8)))
        store.refresh()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        store.focusTick += 1
    }

    @MainActor private func hide() {
        panel.orderOut(nil)
    }

    // MARK: Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        self.show()
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// Global ⌥⌘C via Carbon (works without Accessibility permission).
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?

    init(handler: @escaping () -> Void) {
        HotKey.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4353_4553), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
