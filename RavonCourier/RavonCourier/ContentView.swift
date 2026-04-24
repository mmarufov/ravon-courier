import SwiftUI
import RavonCore

struct ContentView: View {
    @ObservedObject private var auth = AuthService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private var courierAuth = CourierAuth.shared

    var body: some View {
        Group {
            if !auth.isLoaded {
                ProgressView("Загрузка...")
            } else if auth.isSignedIn {
                if !hasCompletedOnboarding {
                    OnboardingView()
                } else {
                    HomeTabView()
                }
            } else {
                LoginView(authService: courierAuth)
            }
        }
    }
}

#Preview {
    ContentView()
}
