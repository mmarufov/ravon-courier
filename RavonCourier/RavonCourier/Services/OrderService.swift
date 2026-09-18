import CoreLocation
import Foundation
import RavonCore

@MainActor
@Observable
final class OrderService {
    static let shared = OrderService()

    var activeOrder: Order? {
        didSet {
            CourierLocationStreamer.shared.setActiveOrderStatus(activeOrder?.status)
        }
    }
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

    // MARK: - Offer Feed

    /// Orders this courier turned down during this app run.
    ///
    /// TODO: replace with a server-side `courier_decline_order` RPC (being
    /// added in ravon-core) that appends to `orders.excluded_courier_ids`.
    /// Until then nothing records a decline, and `fetch_available_orders`
    /// returns oldest-first — so without this set the order you just declined
    /// is the very next offer, forever. Session-scoped only: a relaunch, or a
    /// second courier device, re-offers it.
    private var declinedOrderIds: Set<UUID> = []

    func markDeclined(_ order: Order) {
        declinedOrderIds.insert(order.id)
    }

    /// The next order to offer this courier, or nil if there is nothing to show.
    ///
    /// Uses the proximity-aware `fetch_available_orders` RPC. The no-arg
    /// overload core labels "for testing / fallback" is a raw table select: it
    /// skips the radius filter *and* `excluded_courier_ids`, so it offers a
    /// Dushanbe courier every unassigned order in the country, including ones
    /// they were explicitly excluded from. Returns nil rather than falling
    /// back to it when we have no GPS fix yet.
    func nextOffer() async -> Order? {
        guard let fix = LocationService.shared.currentLocation else { return nil }
        let orders = try? await SupabaseService.shared.fetchAvailableOrders(
            latitude: fix.latitude,
            longitude: fix.longitude
        )
        return orders?.first { !declinedOrderIds.contains($0.id) }
    }

    // MARK: - Claim Order

    func claimOrder(_ order: Order) async throws {
        errorMessage = nil
        _ = try await SupabaseService.shared.claimOrder(orderId: order.id)
        activeOrder = try await SupabaseService.shared.fetchOrder(id: order.id)

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
