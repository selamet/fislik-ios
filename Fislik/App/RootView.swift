import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            FColor.bg.ignoresSafeArea()
            switch app.phase {
            case .launching:
                LaunchView()
            case .onboarding:
                OnboardingView()
            case .auth:
                AuthFlowView()
            case .locked:
                FaceIDLockView()
            case .companySetup:
                CompanySetupView()
            case .main:
                MainView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.phase)
        .task { await app.start() }
    }
}

struct LaunchView: View {
    var body: some View {
        FislikMark(height: 64)
    }
}

/// Role-specific tab shell.
struct MainView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.isAccountant {
                AccountantTabView()
            } else {
                ClientTabView()
            }
        }
        .overlay(alignment: .bottom) {
            if app.sessionExpired {
                SessionExpiredBanner { app.signOutLocally() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: app.sessionExpired)
        .task {
            NotificationsStore.shared.app = app
            NotificationsStore.shared.startPolling()
            PushManager.shared.onOpen = { [weak app] type, payload in
                guard let app else { return }
                app.pendingLink = AppModel.link(forNotification: type, payload: payload)
                Task { await NotificationsStore.shared.refresh() }
            }
            await askForPushOnce()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                NotificationsStore.shared.startPolling()
                UploadQueue.shared.pump()
            case .background:
                NotificationsStore.shared.stopPolling()
            default: break
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pushAsked") private var pushAsked = false

    /// Ask for notification permission once after the first sign-in; afterwards just re-register.
    private func askForPushOnce() async {
        #if DEBUG
        if DemoMode.isOn { return }
        #endif
        if pushAsked {
            if await PushManager.shared.authorizationStatus() == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }
        pushAsked = true
        _ = await PushManager.shared.requestAuthorization()
    }
}

/// 2AC bottom card — "Oturum süresi doldu".
struct SessionExpiredBanner: View {
    let onLogin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FIconTile(icon: .lock, size: 38, iconSize: 18, tint: FColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Oturum süresi doldu").fFont(14, .heavy)
                Text("Güvenlik için tekrar giriş yapman gerekiyor.").fFont(12, .medium).foregroundStyle(FColor.muted)
            }
            Spacer(minLength: 0)
            Button(action: onLogin) {
                HStack(spacing: 5) {
                    Icon(.scanFace, size: 15)
                    Text("Giriş")
                }
                .fFont(13, .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(FColor.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(FColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FColor.line))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
    }
}
