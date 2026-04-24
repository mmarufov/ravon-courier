import SwiftUI
import MapKit
import RavonCore

struct ActiveDeliveryView: View {
    var onComplete: () -> Void

    private var orderService = OrderService.shared
    private var locationService = LocationService.shared

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    @State private var verificationCode = ""
    @State private var showCodeError = false
    @State private var isProcessing = false
    @State private var showChat = false
    @State private var showCancelConfirm = false
    @State private var unreadCount = 0
    @State private var completedOrder: Order?

    var body: some View {
        if let completed = completedOrder, orderService.activeOrder == nil {
            completionCardView(for: completed)
        } else if let order = orderService.activeOrder {
            VStack(spacing: 0) {
                mapSection(for: order)
                deliveryCard(for: order)
            }
            .sheet(isPresented: $showChat) {
                NavigationStack {
                    ChatView(orderId: order.id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Закрыть") {
                                    showChat = false
                                    // Reset unread count when chat is viewed
                                    unreadCount = 0
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .task {
                unreadCount = (try? await SupabaseService.shared.fetchUnreadCount(orderId: order.id)) ?? 0
            }
            .onReceive(RealtimeService.shared.$lastChatMessage) { event in
                guard let event, event.message.orderId == order.id,
                      event.message.senderId != AuthService.shared.userId else { return }
                unreadCount += 1
            }
        }
    }

    // MARK: - Completion Card

    private func completionCardView(for order: Order) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Доставка завершена!")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                Text("Заработано: \(String(format: "%.0f", order.deliveryFee)) сомони")
                    .font(.title3)

                if let tip = order.tipAmount, tip > 0 {
                    Text("Чаевые: \(String(format: "%.0f", tip)) сомони")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            RavonPrimaryButton("Следующий заказ") {
                completedOrder = nil
                onComplete()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Map

    @ViewBuilder
    private func mapSection(for order: Order) -> some View {
        let destination: CLLocationCoordinate2D = {
            if order.status.isRestaurantPhase {
                return order.restaurant?.coordinate
                    ?? order.deliveryAddressSnapshot?.coordinate
                    ?? CLLocationCoordinate2D(latitude: 38.56, longitude: 68.77)
            } else {
                return order.deliveryAddressSnapshot?.coordinate
                    ?? CLLocationCoordinate2D(latitude: 38.56, longitude: 68.77)
            }
        }()

        Map {
            if let current = locationService.currentLocation {
                Annotation("Вы", coordinate: current) {
                    Image(systemName: "location.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                }
            }

            Annotation(
                order.status.isRestaurantPhase ? (order.restaurant?.name ?? "Ресторан") : "Клиент",
                coordinate: destination
            ) {
                Image(systemName: order.status.isRestaurantPhase ? "building.2.fill" : "house.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(order.status.statusColor)
                    .clipShape(Circle())
            }
        }
        .frame(height: 220)
    }

    // MARK: - Card

    private func deliveryCard(for order: Order) -> some View {
        VStack(spacing: 12) {
            courierProgressBar(for: order.status)
                .padding(.horizontal)
                .padding(.top, 16)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Заказ #\(order.shortId)")
                        .font(.headline)
                    Text(statusText(for: order.status))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if order.status.isChatActive {
                    Button { showChat = true } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.title3)
                            .foregroundStyle(Color.ravonRed)
                    }
                    .overlay(alignment: .topTrailing) {
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.caption2).bold()
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.ravonRed)
                                .clipShape(Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }

                statusBadge(for: order.status)
            }
            .padding(.horizontal)

            Divider()

            destinationInfo(for: order)

            Divider()

            HStack {
                Text("\(order.itemCount) позиц.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(order.deliveryFee, specifier: "%.0f") сом.")
                    .font(.headline)
                    .foregroundStyle(Color.ravonRed)
            }
            .padding(.horizontal)

            if order.status == .courierArrivedRestaurant {
                verificationCodeInput
            }

            actionButtons(for: order)
                .padding(.horizontal)

            Button(role: .destructive) {
                showCancelConfirm = true
            } label: {
                Text("Отменить доставку")
                    .font(.subheadline)
            }
            .padding(.bottom)
            .confirmationDialog(
                "Отменить доставку?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Отменить доставку", role: .destructive) {
                    isProcessing = true
                    Task {
                        await orderService.cancelActiveOrder()
                        isProcessing = false
                        onComplete()
                    }
                }
                Button("Нет", role: .cancel) {}
            } message: {
                Text("Заказ будет снят с вас и вернётся в общий пул")
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 5, y: -2)
    }

    // MARK: - Progress Bar

    private func courierProgressBar(for status: OrderStatus) -> some View {
        let currentStep = status.courierStepIndex
        let steps = [
            ("figure.walk", "Еду"),
            ("building.2", "Ресторан"),
            ("checkmark.seal", "Забрал"),
            ("car", "В пути"),
            ("house", "У клиента"),
            ("flag.checkered", "Готово")
        ]

        return HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(index <= currentStep ? status.statusColor : Color(.systemGray4))
                            .frame(width: 28, height: 28)
                        Image(systemName: step.0)
                            .font(.system(size: 12))
                            .foregroundStyle(index <= currentStep ? .white : .secondary)
                    }
                    Text(step.1)
                        .font(.system(size: 9))
                        .foregroundStyle(index <= currentStep ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < currentStep ? status.statusColor : Color(.systemGray4))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Destination

    private func destinationInfo(for order: Order) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if order.status.isRestaurantPhase {
                addressRow(
                    icon: "building.2.fill",
                    iconColor: .ravonRed,
                    title: order.restaurant?.name ?? "Ресторан",
                    subtitle: order.restaurant?.address ?? "",
                    coordinate: order.restaurant?.coordinate
                        ?? CLLocationCoordinate2D(latitude: 38.56, longitude: 68.77),
                    locationName: order.restaurant?.name ?? "Ресторан"
                )
            } else {
                addressRow(
                    icon: "house.fill",
                    iconColor: .blue,
                    title: "Адрес клиента",
                    subtitle: order.deliveryAddressSnapshot?.shortAddress ?? "",
                    coordinate: order.deliveryAddressSnapshot?.coordinate
                        ?? CLLocationCoordinate2D(latitude: 38.56, longitude: 68.77),
                    locationName: "Клиент"
                )
            }
        }
        .padding(.horizontal)
    }

    private func addressRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        coordinate: CLLocationCoordinate2D,
        locationName: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                locationService.openInMaps(destination: coordinate, name: locationName)
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Verification Code

    private var verificationCodeInput: some View {
        VStack(spacing: 8) {
            Text("Введите код подтверждения")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 12) {
                TextField("0000", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospaced())
                    .frame(width: 120)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onChange(of: verificationCode) { _, newValue in
                        if newValue.count > 4 {
                            verificationCode = String(newValue.prefix(4))
                        }
                        verificationCode = newValue.filter(\.isNumber)
                        showCodeError = false
                    }
            }

            if showCodeError {
                Text("Неверный код подтверждения")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButtons(for order: Order) -> some View {
        switch order.status {
        case .assigned:
            Button {
                isProcessing = true
                Task {
                    await orderService.courierArrivedAtRestaurant()
                    isProcessing = false
                }
            } label: {
                Label("Прибыл в ресторан", systemImage: "building.2.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.large)
            .disabled(isProcessing)

        case .courierArrivedRestaurant:
            Button {
                isProcessing = true
                Task {
                    do {
                        try await orderService.pickUpOrder(verificationCode: verificationCode)
                        verificationCode = ""
                        showCodeError = false
                    } catch let error as ServiceError where error == .invalidVerificationCode {
                        showCodeError = true
                    } catch {}
                    isProcessing = false
                }
            } label: {
                Label("Забрал заказ", systemImage: "bag.fill.badge.checkmark")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.ravonRed)
            .controlSize(.large)
            .disabled(verificationCode.count != 4 || isProcessing)

        case .pickedUp:
            Button {
                isProcessing = true
                Task {
                    await orderService.startDelivering()
                    isProcessing = false
                }
            } label: {
                Label("Начать доставку", systemImage: "car.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
            .disabled(isProcessing)

        case .delivering:
            Button {
                isProcessing = true
                Task {
                    await orderService.courierArrivedAtCustomer()
                    isProcessing = false
                }
            } label: {
                Label("Прибыл к клиенту", systemImage: "house.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)
            .disabled(isProcessing)

        case .courierArrivedCustomer:
            Button {
                isProcessing = true
                Task {
                    completedOrder = orderService.activeOrder
                    await orderService.deliverOrder()
                    if orderService.errorMessage != nil {
                        completedOrder = nil
                    }
                    isProcessing = false
                }
            } label: {
                Label("Доставлено", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(isProcessing)

        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func statusText(for status: OrderStatus) -> String {
        switch status {
        case .assigned: "Направляйтесь в ресторан"
        case .courierArrivedRestaurant: "Введите код и заберите заказ"
        case .pickedUp: "Начните доставку клиенту"
        case .delivering: "Доставьте клиенту"
        case .courierArrivedCustomer: "Передайте заказ клиенту"
        default: status.displayName
        }
    }

    private func statusBadge(for status: OrderStatus) -> some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.statusColor.opacity(0.15))
            .foregroundStyle(status.statusColor)
            .clipShape(Capsule())
    }
}

#Preview {
    ActiveDeliveryView(onComplete: {})
}
