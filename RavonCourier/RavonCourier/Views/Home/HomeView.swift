import Combine
import SwiftUI
import CoreLocation
import MapKit
import RavonCore

enum DashState {
    case offline
    case lookingForOrders
    case offerShown(Order)
    case paused
    case activeDelivery(Order)

    var isLookingForOrders: Bool {
        if case .lookingForOrders = self { return true }
        return false
    }

    var stateKey: String {
        switch self {
        case .offline: "offline"
        case .lookingForOrders: "looking"
        case .offerShown: "offer"
        case .paused: "paused"
        case .activeDelivery: "delivery"
        }
    }
}

struct HomeView: View {
    @State private var dashState: DashState = .offline
    @State private var shiftStartTime: Date?
    @State private var isGoingOnline = false
    @State private var showOnlineError = false
    @State private var onlineErrorMessage = ""
    @Environment(\.scenePhase) private var scenePhase

    private var orderService = OrderService.shared
    private var locationService = LocationService.shared
    private var earningsService = EarningsService.shared

    var body: some View {
        ZStack {
            if case .activeDelivery = dashState {
                ActiveDeliveryView(onComplete: handleDeliveryComplete)
            } else {
                mapView
                    .overlay {
                        if case .paused = dashState {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                        }
                    }
                    .ignoresSafeArea()

                switch dashState {
                case .offline:
                    offlineOverlay
                case .lookingForOrders:
                    lookingForOrdersOverlay
                case .offerShown(let order):
                    VStack {
                        lookingHeader
                        Spacer()
                        OrderOfferView(order: order, dashState: $dashState)
                    }
                case .paused:
                    pausedOverlay
                default:
                    EmptyView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: dashState.stateKey)
        .task {
            await earningsService.fetchEarnings()
            await restoreState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            guard dashState.isLookingForOrders else { return }
            Task {
                await handleForegroundReconnect()
            }
        }
        .onReceive(RealtimeService.shared.$lastAvailableOrderChange.compactMap { $0 }) { _ in
            guard dashState.isLookingForOrders else { return }
            Task {
                let orders = try? await SupabaseService.shared.fetchAvailableOrders()
                if let order = orders?.first {
                    dashState = .offerShown(order)
                }
            }
        }
        .alert("Ошибка", isPresented: $showOnlineError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(onlineErrorMessage)
        }
    }

    // MARK: - Map Background

    private var mapView: some View {
        Map {
            if let location = locationService.currentLocation {
                Annotation("", coordinate: location) {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Circle()
                            .fill(.blue)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Offline State

    private var offlineOverlay: some View {
        VStack {
            // Today's earnings card
            todayEarningsCard
                .padding(.horizontal)
                .padding(.top, 60)

            Spacer()

            VStack(spacing: 12) {
                RavonPrimaryButton("Начать смену", isLoading: isGoingOnline) {
                    Task { await goOnline() }
                }
                .padding(.horizontal, 32)

                Text("Вы будете получать заказы поблизости")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 48)
        }
    }

    private var todayEarningsCard: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(String(format: "%.0f", earningsService.summary.totalEarned))
                    .font(.title)
                    .fontWeight(.bold)
                Text("сомони")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 40)

            VStack(spacing: 4) {
                Text("\(earningsService.summary.totalDeliveries)")
                    .font(.title)
                    .fontWeight(.bold)
                Text("доставок")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Looking for Orders State

    private var lookingForOrdersOverlay: some View {
        VStack {
            lookingHeader
            Spacer()
            lookingPulse
            Spacer()
            lookingBottomBar
        }
    }

    private var lookingHeader: some View {
        HStack {
            if let start = shiftStartTime {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let elapsed = Int(Date().timeIntervalSince(start))
                    let minutes = elapsed / 60
                    let seconds = elapsed % 60
                    Text("На линии: \(String(format: "%02d:%02d", minutes, seconds))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 60)
    }

    private var lookingPulse: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.ravonRed.opacity(0.1))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(Color.ravonRed.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.ravonRed)
            }

            Text("Ищем заказы...")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    private var lookingBottomBar: some View {
        HStack(spacing: 16) {
            Button {
                dashState = .paused
            } label: {
                Text("Пауза")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                Task { await goOffline() }
            } label: {
                Text("Завершить")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray3), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Paused State

    private var pausedOverlay: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Пауза")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            Spacer()

            VStack(spacing: 12) {
                RavonPrimaryButton("Продолжить") {
                    dashState = .lookingForOrders
                    Task {
                        try? await RealtimeService.shared.subscribeToAvailableOrders()
                        locationService.startUpdating()
                        let orders = try? await SupabaseService.shared.fetchAvailableOrders()
                        if let order = orders?.first {
                            dashState = .offerShown(order)
                        }
                    }
                }
                .padding(.horizontal, 32)

                Button("Завершить смену") {
                    Task { await goOffline() }
                }
                .foregroundStyle(.white.opacity(0.8))
                .font(.subheadline)
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Online/Offline Actions

    private func goOnline() async {
        isGoingOnline = true
        do {
            locationService.requestPermission()
            locationService.startUpdating()
            locationService.setOnline(true)

            try? await Task.sleep(for: .seconds(0.5))

            let latitude = locationService.currentLocation?.latitude ?? 38.56
            let longitude = locationService.currentLocation?.longitude ?? 68.77

            try await SupabaseService.shared.goOnline(
                latitude: latitude, longitude: longitude
            )

            try await RealtimeService.shared.subscribeToAvailableOrders()
            shiftStartTime = Date()

            let available = try await SupabaseService.shared.fetchAvailableOrders()
            if let firstOrder = available.first {
                dashState = .offerShown(firstOrder)
            } else {
                dashState = .lookingForOrders
            }
        } catch {
            locationService.setOnline(false)
            locationService.stopUpdating()
            onlineErrorMessage = "Не удалось выйти на линию: \(error.localizedDescription)"
            showOnlineError = true
        }
        isGoingOnline = false
    }

    private func goOffline() async {
        try? await SupabaseService.shared.goOffline()
        locationService.setOnline(false)
        locationService.stopUpdating()
        await RealtimeService.shared.unsubscribeFromAvailableOrders()
        shiftStartTime = nil
        dashState = .offline
    }

    // MARK: - State Restoration

    private func restoreState() async {
        guard let uid = AuthService.shared.userId else { return }
        do {
            let courierLocation = try await SupabaseService.shared.fetchCourierStatus()
            if courierLocation.isOnline {
                if let activeOrder = try await SupabaseService.shared.fetchActiveOrder(courierId: uid) {
                    orderService.activeOrder = activeOrder
                    try? await RealtimeService.shared.subscribeToCourierOrders(courierId: uid)
                    dashState = .activeDelivery(activeOrder)
                } else if courierLocation.currentOrderId != nil {
                    // current_order_id set but no active order found (cancelled/delivered)
                    try? await SupabaseService.shared.clearCurrentOrder()
                    locationService.requestPermission()
                    locationService.startUpdating()
                    locationService.setOnline(true)
                    shiftStartTime = Date()
                    try await RealtimeService.shared.subscribeToAvailableOrders()
                    dashState = .lookingForOrders
                } else {
                    locationService.requestPermission()
                    locationService.startUpdating()
                    locationService.setOnline(true)
                    shiftStartTime = Date()
                    try await RealtimeService.shared.subscribeToAvailableOrders()
                    let available = try await SupabaseService.shared.fetchAvailableOrders()
                    if let order = available.first {
                        dashState = .offerShown(order)
                    } else {
                        dashState = .lookingForOrders
                    }
                }
            }
        } catch {
            // No courier status row — stay offline
        }
    }

    private func handleForegroundReconnect() async {
        guard let uid = AuthService.shared.userId else { return }
        // Check if an order was assigned while backgrounded
        await orderService.fetchActiveOrder()
        if let activeOrder = orderService.activeOrder {
            dashState = .activeDelivery(activeOrder)
            return
        }
        // Re-subscribe to available orders
        try? await RealtimeService.shared.subscribeToAvailableOrders()
        locationService.startUpdating()
        if let orders = try? await SupabaseService.shared.fetchAvailableOrders(),
           let order = orders.first {
            dashState = .offerShown(order)
        }
    }

    private func handleDeliveryComplete() {
        dashState = .lookingForOrders
        Task {
            try? await RealtimeService.shared.subscribeToAvailableOrders()
            locationService.startUpdating()
            locationService.setOnline(true)
            let orders = try? await SupabaseService.shared.fetchAvailableOrders()
            if let order = orders?.first {
                dashState = .offerShown(order)
            }
        }
    }
}

#Preview {
    HomeView()
}
