import SwiftUI
import RavonCore

struct HomeTabView: View {
    var body: some View {
        TabView {
            Tab("Главная", systemImage: "house.fill") {
                HomeView()
            }

            Tab("Доходы", systemImage: "chart.bar.fill") {
                EarningsView()
            }

            Tab("Профиль", systemImage: "person.fill") {
                ProfileView()
            }
        }
        .tint(.ravonRed)
    }
}

#Preview {
    HomeTabView()
}
