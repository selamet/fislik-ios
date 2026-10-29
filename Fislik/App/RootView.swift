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
        if app.isAccountant {
            AccountantTabView()
        } else {
            ClientTabView()
        }
    }
}
