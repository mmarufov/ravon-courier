import CoreLocation
import Foundation
import RavonCore

@MainActor
@Observable
final class OrderService {
    static let shared = OrderService()

    var availableOrders: [Order] = []
    var activeOrder: Order?
    var isLoading = false
    var errorMessage: String?

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

    func pickUpOrder(verificationCode: String) async throws {
        guard let order = activeOrder else { return }
        try await SupabaseService.shared.pickUpOrder(orderId: order.id, verificationCode: verificationCode)
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

    func deliverOrder() async {
        guard let order = activeOrder else { return }
        do {
            try await SupabaseService.shared.deliverOrder(orderId: order.id)
            activeOrder = nil
            await RealtimeService.shared.unsubscribeFromOrders()
            await EarningsService.shared.fetchEarnings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Cancel Active Order

    func cancelActiveOrder() async {
        guard let order = activeOrder else { return }
        do {
            try await SupabaseService.shared.cancelOrder(orderId: order.id, reason: nil)
            activeOrder = nil
            await RealtimeService.shared.unsubscribeFromOrders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
