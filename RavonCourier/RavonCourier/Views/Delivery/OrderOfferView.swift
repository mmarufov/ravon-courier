import SwiftUI
import AudioToolbox
import RavonCore

struct OrderOfferView: View {
    let order: Order
    @Binding var dashState: DashState

    @State private var timeRemaining = 30
    @State private var timer: Timer?
    @State private var isAccepting = false
    @State private var toastMessage: String?

    private var orderService = OrderService.shared

    init(order: Order, dashState: Binding<DashState>) {
        self.order = order
        self._dashState = dashState
    }

    var body: some View {
        VStack(spacing: 16) {
            // Restaurant info
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(Color.ravonRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.restaurant?.name ?? "Ресторан")
                        .font(.headline)
                    Text(order.restaurant?.address ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Order details
            HStack {
                Image(systemName: "bag.fill")
                    .foregroundStyle(.secondary)
                Text("\(order.orderItems?.count ?? 0) поз.")
                    .font(.subheadline)
                Spacer()
            }

            HStack {
                Image(systemName: "house.fill")
                    .foregroundStyle(.secondary)
                Text(order.deliveryAddressSnapshot?.shortAddress ?? "")
                    .font(.subheadline)
                Spacer()
            }

            // Countdown timer
            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 4)
                    .frame(width: 64, height: 64)

                Circle()
                    .trim(from: 0, to: CGFloat(timeRemaining) / 30.0)
                    .stroke(Color.ravonRed, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)

                VStack(spacing: 0) {
                    Text("\(timeRemaining)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("сек")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            // Earnings
            Text("\(String(format: "%.0f", order.deliveryFee)) сомони")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.ravonRed)

            // Accept button
            RavonPrimaryButton("Принять", isLoading: isAccepting) {
                acceptOffer()
            }

            // Decline button
            Button("Отклонить") {
                declineOffer()
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10, y: -5)
        .padding(.horizontal, 16)
        .overlay(alignment: .top) {
            if let message = toastMessage {
                Text(message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red, in: Capsule())
                    .offset(y: -50)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            AudioServicesPlaySystemSound(1315)
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                } else {
                    declineOffer()
                }
            }
        }
    }

    private func acceptOffer() {
        timer?.invalidate()
        isAccepting = true
        Task {
            do {
                try await orderService.claimOrder(order)
                dashState = .activeDelivery(order)
            } catch let error as ServiceError where error == .orderAlreadyClaimed {
                showToast("Заказ уже занят другим курьером")
                fetchNextOffer()
            } catch {
                showToast("Ошибка: \(error.localizedDescription)")
                fetchNextOffer()
            }
            isAccepting = false
        }
    }

    private func declineOffer() {
        timer?.invalidate()
        Task {
            dashState = .lookingForOrders
            try? await Task.sleep(for: .seconds(3))
            let orders = try? await SupabaseService.shared.fetchAvailableOrders()
            if let next = orders?.first {
                dashState = .offerShown(next)
            }
        }
    }

    private func fetchNextOffer() {
        Task {
            dashState = .lookingForOrders
            let orders = try? await SupabaseService.shared.fetchAvailableOrders()
            if let next = orders?.first {
                dashState = .offerShown(next)
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                toastMessage = nil
            }
        }
    }
}
