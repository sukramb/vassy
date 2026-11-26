import AppKit
import UserNotifications

/// Looks every few hours whether a newer Vassy is on vassy.app. If so, it sends one
/// notification per new version and shows an update link in the panel.
/// It is the app's only network request: a GET for a small static file, without cookies or
/// any identifier, and it can be switched off in the gear menu.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()
    static let downloadPage = URL(string: "https://vassy.app/#install")!
    private static let feed = URL(string: "https://vassy.app/version.json")!
    private static let enabledKey = "checkForUpdates"
    private static let notifiedKey = "updateNotifiedFor"
    static let notificationId = "vassy-update"

    /// Version offered for download when it is newer than the running one.
    @Published private(set) var available: String?
    private var timer: Timer?

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
            if newValue { check() } else { available = nil }
        }
    }

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func check() {
        guard enabled else { return }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "Vassy"]
        Task {
            guard let (data, response) = try? await URLSession(configuration: config).data(from: Self.feed),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4096,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latest = json["version"] as? String,
                  latest.range(of: #"^[0-9]{1,4}(\.[0-9]{1,4}){0,3}\z"#, options: .regularExpression) != nil
            else { return }
            available = Self.isNewer(latest, than: Self.current) ? latest : nil
            if available != nil { notifyOnce(latest) }
        }
    }

    /// One notification per new version; clicking it opens the download page.
    private func notifyOnce(_ version: String) {
        guard UserDefaults.standard.string(forKey: Self.notifiedKey) != version else { return }
        UserDefaults.standard.set(version, forKey: Self.notifiedKey)
        let content = UNMutableNotificationContent()
        content.title = "Vassy \(version) is available"
        content.body = "Click to open vassy.app and download the update."
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
