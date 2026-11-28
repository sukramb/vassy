import AppKit
import Sparkle
import UserNotifications

/// Keeps Vassy up to date with Sparkle: every few hours it reads the appcast on vassy.app,
/// downloads a newer version, checks its signature and installs it while the panel is closed.
/// The appcast and the download are the app's only network requests. They carry no cookies
/// and no identifier, and the whole thing can be switched off in the gear menu.
@MainActor
final class Updates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updates()
    static let notificationId = "vassy-update"
    private static let lastVersionKey = "lastRunVersion"

    /// Version found on vassy.app that is newer than the running one.
    @Published private(set) var available: String?
    /// Tells whether the panel is on screen; an update is never installed under the user's hands.
    var panelIsOpen: () -> Bool = { false }

    private var controller: SPUStandardUpdaterController?
    private var install: (() -> Void)?
    private var timer: Timer?

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// Automatic check, download and install. Off means nothing is requested until asked.
    var enabled: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let updater = controller?.updater else { return }
            updater.automaticallyChecksForUpdates = newValue
            updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    func start() {
        // Sparkle needs an app bundle with a feed; a bare binary (tests) has neither.
        guard controller == nil, Bundle.main.bundleIdentifier != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        announceIfUpdated()
    }

    /// Asked for by the user: shows Sparkle's window with the result and an install button.
    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.available = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.available = nil }
    }

    /// The update is downloaded and verified. A menu bar app rarely quits, so instead of
    /// waiting for that, install as soon as the panel is closed; Sparkle relaunches Vassy.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock: @escaping () -> Void) -> Bool {
        Task { @MainActor in
            self.install = immediateInstallationBlock
            self.installWhenIdle()
        }
        return true
    }

    private func installWhenIdle() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let install = self.install, !self.panelIsOpen() else { return }
                self.timer?.invalidate()
                self.install = nil
                install()
            }
        }
    }

    // MARK: Notification after an update

    /// One notification on the first start of a newer version, so a silent update is not a surprise.
    private func announceIfUpdated() {
        let defaults = UserDefaults.standard, current = Self.current
        let last = defaults.string(forKey: Self.lastVersionKey)
        defaults.set(current, forKey: Self.lastVersionKey)
        guard let last, Self.isNewer(current, than: last) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Vassy was updated to \(current)"
        content.body = "The new version is running. Nothing else to do."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: nil))
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
