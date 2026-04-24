import SwiftUI
import RavonCore

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.ravonDark.ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomeScreen.tag(0)
                howItWorksScreen.tag(1)
                acceptingOrdersScreen.tag(2)
                deliveryProcessScreen.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
    }

    // MARK: - Screen 1: Welcome

    private var welcomeScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 80))
                .foregroundStyle(Color.ravonRed)

            Text("Добро пожаловать в Ravon")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Зарабатывайте доставляя еду в удобное для вас время")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Screen 2: How it works

    private var howItWorksScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Как это работает")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 28) {
                stepRow(number: 1, icon: "power", title: "Начните смену", subtitle: "Нажмите кнопку чтобы выйти на линию")
                stepRow(number: 2, icon: "bell.badge", title: "Получите заказ", subtitle: "Заказы приходят к вам автоматически")
                stepRow(number: 3, icon: "banknote", title: "Доставьте и заработайте", subtitle: "Завершите доставку и получите оплату")
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private func stepRow(number: Int, icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.ravonRed)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Screen 3: Accepting orders

    private var acceptingOrdersScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            mockOrderCard

            Text("Принятие заказов")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Когда появится новый заказ, у вас будет 30 секунд чтобы принять или отклонить его. Не волнуйтесь — вы не обязаны принимать каждый заказ!")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private var mockOrderCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(Color.ravonRed)
                Text("Ресторан")
                    .fontWeight(.medium)
                Spacer()
                Text("50 сомони")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.ravonRed)
            }

            HStack {
                Image(systemName: "mappin")
                    .foregroundStyle(.secondary)
                Text("ул. Рудаки, 10")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ZStack {
                Circle()
                    .stroke(Color.ravonRed, lineWidth: 3)
                    .frame(width: 48, height: 48)
                Text("30")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            .padding(.vertical, 4)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 48)
    }

    // MARK: - Screen 4: Delivery process

    private var deliveryProcessScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Процесс доставки")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 24) {
                processStep(icon: "bag", text: "Заберите заказ из ресторана")
                processStep(icon: "checkmark.shield", text: "Подтвердите код верификации")
                processStep(icon: "location", text: "Доставьте клиенту")
                processStep(icon: "checkmark.circle", text: "Завершите доставку")
            }
            .padding(.horizontal, 32)

            Spacer()

            RavonPrimaryButton("Начать") {
                hasCompletedOnboarding = true
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private func processStep(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.ravonRed)
                .frame(width: 32)

            Text(text)
                .font(.body)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    OnboardingView()
}
