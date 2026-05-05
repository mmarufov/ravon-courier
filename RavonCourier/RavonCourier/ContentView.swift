import SwiftUI
import RavonCore

struct ContentView: View {
    @ObservedObject private var auth = AuthService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

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
                RavonAuthFlow(role: .courier) { }
            }
        }
    }
}

#Preview {
    ContentView()
}
