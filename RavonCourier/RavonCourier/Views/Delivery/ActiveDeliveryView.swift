import SwiftUI
import MapKit
import UIKit
import Combine
import RavonCore

struct ActiveDeliveryView: View {
    var onComplete: () -> Void

    private var orderService = OrderService.shared
    private var locationService = LocationService.shared

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    // Pickup-code state (for .courierArrivedRestaurant)
    @State private var pickupCode = ""
    @State private var showPickupCodeError = false

    // Delivery-code state (for .courierArrivedCustomer + handToMe)
    @State private var deliveryCode = ""
    @State private var showDeliveryCodeError = false
    @State private var deliveryAttempts = 0

    // Sheets
    @State private var showDelayReasonSheet = false
    @State private var showCancelSheet = false
    @State private var showReportProblemSheet = false
    @State private var showRestaurantDelaySheet = false
    @State private var showPhotoPicker = false
    @State private var showChat = false

    // Working state
    @State private var isProcessing = false
    @State private var unreadCount = 0
    @State private var completedOrder: Order?
    @State private var toastMessage: String?

    // Ticking clock for time-sensitive UI (no-show, banner refresh).
    // Drives recomputation every second without polling the server.
    @State private var now = Date()
    private let secondTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // No-show countdown duration on the consumer no-show RPC (server side: 5 min).
    private static let noShowGraceSeconds: TimeInterval = 5 * 60
    // How long courier waits at customer before "no-show" button appears.
    private static let noShowAvailableAfter: TimeInterval = 60

    var body: some View {
        Group {
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
                                        unreadCount = 0
                                    }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showDelayReasonSheet) {
                    DelayReasonSheet { reason in
                        Task { await submitDelayExplanation(reason) }
                    }
                }
                .sheet(isPresented: $showCancelSheet) {
                    CourierCancelReasonSheet(mode: .cancel) { reason in
                        Task { await submitCancel(reason) }
                    }
                }
                .sheet(isPresented: $showReportProblemSheet) {
                    CourierCancelReasonSheet(mode: .reportProblem) { reason in
                        Task { await submitReportProblem(reason) }
                    }
                }
                .sheet(isPresented: $showRestaurantDelaySheet) {
                    RestaurantDelaySheet(cumulativeMinutes: order.restaurantDelayMin) { extra in
                        Task { await submitRestaurantDelay(extra) }
                    }
                }
                .sheet(isPresented: $showPhotoPicker) {
                    PhotoProofPicker { image in
                        Task { await submitDeliveryProof(image: image) }
                    }
                }
                .task(id: order.id) {
                    unreadCount = (try? await SupabaseService.shared.fetchUnreadCount(orderId: order.id)) ?? 0
                    await orderService.refreshCancellationCooldown()
                }
                .onReceive(RealtimeService.shared.$lastChatMessage) { event in
                    guard let event, event.message.orderId == order.id,
                          event.message.senderId != AuthService.shared.userId,
                          !event.message.isSystem else { return }
                    unreadCount += 1
                }
                .onReceive(RealtimeService.shared.$lastOrderChange) { event in
                    guard let event, event.orderId == order.id else { return }
                    Task { await orderService.refreshActiveOrder() }
                }
                .onReceive(secondTick) { date in now = date }
            }
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
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

    // MARK: - Delivery Card

    private func deliveryCard(for order: Order) -> some View {
        VStack(spacing: 12) {
            // Banners always at the top of the card.
            delayBannerStack(for: order)
                .padding(.horizontal)
                .padding(.top, 12)

            courierProgressBar(for: order.status)
                .padding(.horizontal)

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
                Text(order.itemCount.itemsRu)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(order.deliveryFee, specifier: "%.0f") сом.")
                    .font(.headline)
                    .foregroundStyle(Color.ravonRed)
            }
            .padding(.horizontal)

            // Pickup code (.courierArrivedRestaurant)
            if order.status == .courierArrivedRestaurant {
                pickupCodeInput
                restaurantDelayChip(for: order)
            }

            // Delivery completion UI (.courierArrivedCustomer)
            if order.status == .courierArrivedCustomer {
                deliveryCompletionUI(for: order)
                noShowSection(for: order)
                    .padding(.horizontal)
            }

            actionButtons(for: order)
                .padding(.horizontal)

            cancelOrReportButton(for: order)
                .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 5, y: -2)
    }

    // MARK: - Delay Banner

    @ViewBuilder
    private func delayBannerStack(for order: Order) -> some View {
        if order.delayWarningActive {
            Button { showDelayReasonSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.black)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Что происходит? Расскажите клиенту.")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.black)
                        Text("Нажмите, чтобы выбрать причину")
                            .font(.caption)
                            .foregroundStyle(.black.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.black.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        if order.courierNoShowWarnedAt != nil {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.red)
                Text("Внимание: вы можете быть отключены")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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

    // MARK: - Pickup Code Input

    private var pickupCodeInput: some View {
        VStack(spacing: 8) {
            Text("Введите код подтверждения")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("0000", text: $pickupCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())
                .frame(width: 120)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: pickupCode) { _, newValue in
                    pickupCode = String(newValue.filter(\.isNumber).prefix(4))
                    showPickupCodeError = false
                }

            if showPickupCodeError {
                Text("Неверный код. Попросите ресторан назвать ещё раз.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Restaurant-delay chip

    @ViewBuilder
    private func restaurantDelayChip(for order: Order) -> some View {
        let cumulative = order.restaurantDelayMin
        let capped = cumulative >= 30
        Button {
            if !capped { showRestaurantDelaySheet = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(capped ? .secondary : Color.orange)
                Text(cumulative > 0 ? "Ресторан задерживает (+\(cumulative) мин)" : "Ресторан задерживает")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(capped ? .secondary : .primary)
                Spacer()
                if !capped {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(capped)
        .padding(.horizontal)
    }

    // MARK: - Delivery completion (handToMe / leaveAtDoor)

    @ViewBuilder
    private func deliveryCompletionUI(for order: Order) -> some View {
        switch order.deliveryMode {
        case .handToMe:
            DeliveryCodePadView(
                code: $deliveryCode,
                attempts: $deliveryAttempts,
                showError: $showDeliveryCodeError
            )
        case .leaveAtDoor:
            HStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.blue)
                Text("Оставить у двери — нажмите «Доставлено» и сделайте фото")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
    }

    // MARK: - No-show button + countdown

    @ViewBuilder
    private func noShowSection(for order: Order) -> some View {
        if let started = order.noShowStartedAt {
            // Countdown active.
            let elapsed = now.timeIntervalSince(started)
            let remaining = max(0, Self.noShowGraceSeconds - elapsed)
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
                Text("Клиент не отвечает — \(formatMMSS(remaining))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let arrived = order.arrivedAtCustomerAt,
                  now.timeIntervalSince(arrived) >= Self.noShowAvailableAfter {
            Button {
                Task { await reportNoShow() }
            } label: {
                Label("Клиент не отвечает", systemImage: "person.fill.questionmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
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
                        try await orderService.pickUpOrder(pickupCode: pickupCode)
                        pickupCode = ""
                        showPickupCodeError = false
                    } catch let error as ServiceError {
                        if case .invalidVerificationCode = error {
                            showPickupCodeError = true
                        } else {
                            showToast(error.errorDescription ?? "Ошибка")
                        }
                    } catch {
                        showToast(error.localizedDescription)
                    }
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
            .disabled(pickupCode.count != 4 || isProcessing)

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
            // Single "Доставлено" button — branches by deliveryMode at call site.
            Button {
                Task { await completeDelivery(order) }
            } label: {
                Label("Доставлено", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(isProcessing || !canCompleteDelivery(order))

        default:
            EmptyView()
        }
    }

    // MARK: - Cancel / Report-Problem button

    @ViewBuilder
    private func cancelOrReportButton(for order: Order) -> some View {
        if order.status.courierCanCancel {
            let onCooldown = orderService.isCancelOnCooldown
            VStack(spacing: 4) {
                Button(role: .destructive) {
                    showCancelSheet = true
                } label: {
                    Text("Отменить заказ")
                        .font(.subheadline)
                }
                .disabled(onCooldown || isProcessing)
                if onCooldown, let until = orderService.cancelCooldownUntil {
                    Text("Восстановится в \(formatHHMM(until))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if !order.status.isTerminal &&
                  (order.status == .pickedUp ||
                   order.status == .delivering ||
                   order.status == .courierArrivedCustomer) {
            Button {
                showReportProblemSheet = true
            } label: {
                Label("Сообщить о проблеме", systemImage: "exclamationmark.bubble")
                    .font(.subheadline)
            }
            .disabled(isProcessing)
        }
    }

    // MARK: - Helpers

    private func canCompleteDelivery(_ order: Order) -> Bool {
        switch order.deliveryMode {
        case .handToMe:   return deliveryCode.count == 4
        case .leaveAtDoor: return true
        }
    }

    private func completeDelivery(_ order: Order) async {
        isProcessing = true
        defer { isProcessing = false }
        switch order.deliveryMode {
        case .handToMe:
            do {
                completedOrder = order
                try await orderService.deliverOrderHandToMe(deliveryCode: deliveryCode)
                deliveryCode = ""
                showDeliveryCodeError = false
                deliveryAttempts = 0
            } catch let error as ServiceError {
                completedOrder = nil
                if case .wrongDeliveryCode = error {
                    deliveryAttempts += 1
                    showDeliveryCodeError = true
                } else if let mapped = ServiceError.from(serverError: error), case .wrongDeliveryCode = mapped {
                    deliveryAttempts += 1
                    showDeliveryCodeError = true
                } else {
                    showToast(error.errorDescription ?? "Ошибка")
                }
            } catch {
                completedOrder = nil
                if let mapped = ServiceError.from(serverError: error), case .wrongDeliveryCode = mapped {
                    deliveryAttempts += 1
                    showDeliveryCodeError = true
                } else {
                    showToast(error.localizedDescription)
                }
            }
        case .leaveAtDoor:
            showPhotoPicker = true
        }
    }

    private func submitDeliveryProof(image: UIImage) async {
        guard let order = orderService.activeOrder else { return }
        guard let data = DeliveryProofImage.compress(image) else {
            showToast("Не удалось сжать фото — попробуйте ещё раз")
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            completedOrder = order
            try await orderService.deliverOrderLeaveAtDoor(jpegData: data)
        } catch let error as ServiceError {
            completedOrder = nil
            if case .missingProofImage = error {
                showPhotoPicker = true
            } else if case .imageTooLarge = error {
                showToast("Фото слишком большое — снимите ещё раз")
            } else {
                showToast(error.errorDescription ?? "Ошибка")
            }
        } catch {
            completedOrder = nil
            if let mapped = ServiceError.from(serverError: error), case .missingProofImage = mapped {
                showPhotoPicker = true
            } else {
                showToast(error.localizedDescription)
            }
        }
    }

    private func submitDelayExplanation(_ reason: CourierDelayReason) async {
        do {
            try await orderService.explainDelay(reason: reason, freeForm: nil)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func submitCancel(_ reason: CancellationReason) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await orderService.cancelByCourier(reason: reason)
            await orderService.refreshCancellationCooldown()
            onComplete()
        } catch let error as ServiceError {
            if case .courierCancelCooldown = error {
                showToast("Слишком много отмен. Подождите.")
                await orderService.refreshCancellationCooldown()
            } else {
                showToast(error.errorDescription ?? "Ошибка")
            }
        } catch {
            if let mapped = ServiceError.from(serverError: error), case .courierCancelCooldown = mapped {
                showToast("Слишком много отмен. Подождите.")
                await orderService.refreshCancellationCooldown()
            } else {
                showToast(error.localizedDescription)
            }
        }
    }

    private func submitReportProblem(_ reason: CancellationReason) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await orderService.reportProblemPostPickup(reason: reason, freeForm: nil)
            showToast("Поддержка получит сообщение")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func submitRestaurantDelay(_ extra: Int) async {
        do {
            try await orderService.reportRestaurantDelay(extraMinutes: extra)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func reportNoShow() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await orderService.reportCustomerNoShow()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toastMessage = nil }
        }
    }

    // MARK: - Display helpers

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

    private func formatMMSS(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func formatHHMM(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

#Preview {
    ActiveDeliveryView(onComplete: {})
}
