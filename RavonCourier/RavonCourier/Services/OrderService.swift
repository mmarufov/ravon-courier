import CoreLocation
import Foundation
import RavonCore

@MainActor
@Observable
final class OrderService {
    static let shared = OrderService()

    var availableOrders: [Order] = []
    var activeOrder: Order? {
        didSet {
            CourierLocationStreamer.shared.setActiveOrderStatus(activeOrder?.status)
        }
    }
    var isLoading = false
    var errorMessage: String?

    /// Cooldown state — populated by `refreshCancellationCooldown()` on screen appear.
    var recentCancelCount: Int = 0
    var cancelCooldownUntil: Date?

    private init() {}

    // MARK: - Active Order Check

    func fetchActiveOrder() async {
        guard let uid = AuthService.shared.userId else { return }
        do {
            if let active = try await SupabaseService.shared.fetchActiveOrder(courierId: uid) {
                activeOrder = active
                try? await RealtimeService.shared.subscribeToCourierOrders(courierId: uid)
            }
        } catch {
            // Non-critical — don't block the UI
        }
    }

    /// Re-fetch the active order (used after realtime status change).
    func refreshActiveOrder() async {
        guard let order = activeOrder else { return }
        do {
            let refreshed = try await SupabaseService.shared.fetchOrder(id: order.id)
            if refreshed.status.isTerminal {
                activeOrder = nil
                await RealtimeService.shared.unsubscribeFromOrders()
                await EarningsService.shared.fetchEarnings()
            } else {
                activeOrder = refreshed
            }
        } catch {
            // Silent — next event will retry
        }
    }

    // MARK: - Available Orders

    func fetchAvailableOrders() async {
        isLoading = true
        errorMessage = nil

        do {
            availableOrders = try await SupabaseService.shared.fetchAvailableOrders()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func subscribeToAvailableOrders() async {
        try? await RealtimeService.shared.subscribeToAvailableOrders()
    }

    func unsubscribeFromAvailableOrders() async {
        await RealtimeService.shared.unsubscribeFromAvailableOrders()
    }

    // MARK: - Claim Order

    func claimOrder(_ order: Order) async throws {
        errorMessage = nil
        _ = try await SupabaseService.shared.claimOrder(orderId: order.id)
        activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)
        availableOrders.removeAll { $0.id == order.id }

        if let courierId = AuthService.shared.userId {
            try? await RealtimeService.shared.subscribeToCourierOrders(courierId: courierId)
        }
    }

    // MARK: - Courier Lifecycle

    func courierArrivedAtRestaurant() async {
        guard let order = activeOrder else { return }
        do {
            try await SupabaseService.shared.courierArrivedAtRestaurant(orderId: order.id)
            activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pickUpOrder(pickupCode: String) async throws {
        guard let order = activeOrder else { return }
        try await SupabaseService.shared.pickUpOrder(orderId: order.id, pickupCode: pickupCode)
        activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)
    }

    func startDelivering() async {
        guard let order = activeOrder else { return }
        do {
            try await SupabaseService.shared.startDelivering(orderId: order.id)
            activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func courierArrivedAtCustomer() async {
        guard let order = activeOrder else { return }
        do {
            try await SupabaseService.shared.courierArrivedAtCustomer(orderId: order.id)
            activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Hand-to-me delivery — verifies consumer's delivery code.
    func deliverOrderHandToMe(deliveryCode: String) async throws {
        guard let order = activeOrder else { return }
        try await SupabaseService.shared.deliverOrder(orderId: order.id, deliveryCode: deliveryCode)
        activeOrder = nil
        await RealtimeService.shared.unsubscribeFromOrders()
        await EarningsService.shared.fetchEarnings()
    }

    /// Leave-at-door delivery — uploads photo proof first, then completes.
    func deliverOrderLeaveAtDoor(jpegData: Data) async throws {
        guard let order = activeOrder else { return }
        let path = try await SupabaseService.shared.uploadDeliveryProof(orderId: order.id, jpegData: jpegData)
        try await SupabaseService.shared.deliverOrder(orderId: order.id, proofUrl: path)
        activeOrder = nil
        await RealtimeService.shared.unsubscribeFromOrders()
        await EarningsService.shared.fetchEarnings()
    }

    // MARK: - Cancel / Problem Reporting

    /// Pre-pickup courier-initiated cancel via whitelisted reason.
    func cancelByCourier(reason: CancellationReason) async throws {
        guard let order = activeOrder else { return }
        try await SupabaseService.shared.cancelOrderByCourier(orderId: order.id, reason: reason)
        activeOrder = nil
        await RealtimeService.shared.unsubscribeFromOrders()
        await EarningsService.shared.fetchEarnings()
    }

    /// Post-pickup: status doesn't change; system messages the consumer.
    func reportProblemPostPickup(reason: CancellationReason, freeForm: String?) async throws {
        guard let order = activeOrder else { return }
        try await SupabaseService.shared.reportProblemPostPickup(
            orderId: order.id, reason: reason, freeForm: freeForm
        )
    }

    // MARK: - Delay Ladder

    func explainDelay(reason: CourierDelayReason, freeForm: String?) async throws {
        guard let order = activeOrder else { return }
        try await SupabaseService.shared.explainDelay(
            orderId: order.id, reason: reason, freeForm: freeForm
        )
        activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)
    }

    // MARK: - No-show + Restaurant delay

    func reportCustomerNoShow() async throws {
        guard let order = activeOrder else { return }
        try await SupabaseService.shared.reportCustomerNoShow(orderId: order.id)
        activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)
    }

    func reportRestaurantDelay(extraMinutes: Int) async throws {
        guard let order = activeOrder else { return }
        try await SupabaseService.shared.reportRestaurantDelay(
            orderId: order.id, extraMinutes: extraMinutes
        )
        activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)
    }

    // MARK: - Cancel Cooldown

    func refreshCancellationCooldown() async {
        do {
            let status = try await SupabaseService.shared.fetchCancellationCooldownStatus()
            recentCancelCount = status.recentCancels
            cancelCooldownUntil = status.cooldownUntil
        } catch {
            recentCancelCount = 0
            cancelCooldownUntil = nil
        }
    }

    var isCancelOnCooldown: Bool {
        recentCancelCount >= 3 && (cancelCooldownUntil ?? .distantPast) > Date()
    }
}
