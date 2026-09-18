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
    private var profileService = ProfileService.shared

    var body: some View {
        ZStack {
            if profileService.isSuspended {
                SuspensionBlocker(until: profileService.suspendedUntil)
            } else if case .activeDelivery = dashState {
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
            await profileService.fetchProfile()
            await earningsService.fetchEarnings()
            if !profileService.isSuspended {
                await restoreState()
            }
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
                if let order = await orderService.nextOffer() {
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
                Task { await pauseShift() }
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
                RavonPrimaryButton("Продолжить", isLoading: isGoingOnline) {
                    Task { await resumeShift() }
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
        // Re-fetch profile to catch a fresh suspension before going online.
        await profileService.fetchProfile()
        if profileService.isSuspended {
            onlineErrorMessage = "Аккаунт приостановлен — выход на линию недоступен"
            showOnlineError = true
            return
        }
        await startShift(restartClock: true)
    }

    /// Register as online server-side, start the heartbeat, take the first offer.
    private func startShift(restartClock: Bool) async {
        isGoingOnline = true
        do {
            locationService.beginStreaming()

            try? await Task.sleep(for: .seconds(0.5))

            let latitude = locationService.currentLocation?.latitude ?? 38.56
            let longitude = locationService.currentLocation?.longitude ?? 68.77

            try await SupabaseService.shared.goOnline(
                latitude: latitude, longitude: longitude
            )

            try await RealtimeService.shared.subscribeToAvailableOrders()
            if restartClock {
                shiftStartTime = Date()
            }

            if let order = await orderService.nextOffer() {
                dashState = .offerShown(order)
            } else {
                dashState = .lookingForOrders
            }
        } catch {
            locationService.endStreaming()
            onlineErrorMessage = "Не удалось выйти на линию: \(error.localizedDescription)"
            showOnlineError = true
        }
        isGoingOnline = false
    }

    /// Пауза — genuinely offline to dispatch, with the shift clock preserved.
    ///
    /// This used to only dim the map: `is_online` stayed true, the heartbeat
    /// kept flowing and `claim_order` still considered the courier available,
    /// so offers arrived behind the overlay. A control that looks like it works
    /// and doesn't is worse than no control.
    private func pauseShift() async {
        dashState = .paused
        try? await SupabaseService.shared.goOffline()
        locationService.endStreaming()
        await RealtimeService.shared.unsubscribeFromAvailableOrders()
    }

    private func resumeShift() async {
        await startShift(restartClock: false)
    }

    private func goOffline() async {
        try? await SupabaseService.shared.goOffline()
        locationService.endStreaming()
        await RealtimeService.shared.unsubscribeFromAvailableOrders()
        shiftStartTime = nil
        dashState = .offline
    }

    // MARK: - State Restoration

    private func restoreState() async {
        guard let uid = AuthService.shared.userId else { return }
        do {
            let courierLocation = try await SupabaseService.shared.fetchCourierStatus()
            let activeOrder = courierLocation.isOnline
                ? try await SupabaseService.shared.fetchActiveOrder(courierId: uid)
                : nil
            let plan = ShiftRestoration.decide(
                isOnline: courierLocation.isOnline,
                hasActiveOrder: activeOrder != nil,
                hasCurrentOrderId: courierLocation.currentOrderId != nil
            )
            plan.apply(to: locationService)

            switch plan {
            case .stayOffline:
                return

            case .resumeDelivery:
                guard let activeOrder else { return }
                orderService.activeOrder = activeOrder
                try? await RealtimeService.shared.subscribeToCourierOrders(courierId: uid)
                shiftStartTime = Date()
                dashState = .activeDelivery(activeOrder)

            case .clearStaleOrderThenLookForOrders, .lookForOrders:
                if plan == .clearStaleOrderThenLookForOrders {
                    // current_order_id set but no active order (cancelled/delivered)
                    try? await SupabaseService.shared.clearCurrentOrder()
                }
                shiftStartTime = Date()
                try await RealtimeService.shared.subscribeToAvailableOrders()
                // Give the first GPS fix a moment to land — the offer feed is
                // proximity-filtered and needs a location.
                try? await Task.sleep(for: .seconds(0.5))
                if let order = await orderService.nextOffer() {
                    dashState = .offerShown(order)
                } else {
                    dashState = .lookingForOrders
                }
            }
        } catch {
            // No courier status row — stay offline
        }
    }

    private func handleForegroundReconnect() async {
        guard AuthService.shared.userId != nil else { return }
        // Check if an order was assigned while backgrounded
        await orderService.fetchActiveOrder()
        if let activeOrder = orderService.activeOrder {
            dashState = .activeDelivery(activeOrder)
            return
        }
        // Re-subscribe to available orders and make sure the heartbeat is live
        try? await RealtimeService.shared.subscribeToAvailableOrders()
        locationService.beginStreaming()
        if let order = await orderService.nextOffer() {
            dashState = .offerShown(order)
        }
    }

    private func handleDeliveryComplete() {
        dashState = .lookingForOrders
        Task {
            try? await RealtimeService.shared.subscribeToAvailableOrders()
            locationService.beginStreaming()
            if let order = await orderService.nextOffer() {
                dashState = .offerShown(order)
            }
        }
    }
}

#Preview {
    HomeView()
}
