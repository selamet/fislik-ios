import SwiftUI

@main
struct FislikApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(appearance.colorScheme)
                .tint(FColor.brand)
                .onOpenURL { app.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { app.handle(url: url) }
                }
        }
    }
}

enum Appearance: String, CaseIterable {
    case light, dark, system

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var label: String {
        switch self {
        case .light: "Açık"
        case .dark: "Koyu"
        case .system: "Sistem"
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset") {
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
            Keychain.clear()
        }
        DemoMode.install()
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-appearance"), i + 1 < ProcessInfo.processInfo.arguments.count {
            UserDefaults.standard.set(ProcessInfo.processInfo.arguments[i + 1], forKey: "appearance")
        }
        #endif
        PushManager.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        BackgroundSessionEvents.shared.completionHandler = completionHandler
    }
}

/// Holds the system completion handler for the background upload session.
final class BackgroundSessionEvents: @unchecked Sendable {
    static let shared = BackgroundSessionEvents()
    var completionHandler: (() -> Void)?
}
