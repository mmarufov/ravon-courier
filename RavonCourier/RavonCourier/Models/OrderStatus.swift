import SwiftUI
import RavonCore

extension OrderStatus {
    var isRestaurantPhase: Bool {
        self == .assigned || self == .courierArrivedRestaurant
    }

    var isCustomerPhase: Bool {
        self == .pickedUp || self == .delivering || self == .courierArrivedCustomer
    }

    var courierStepIndex: Int {
        switch self {
        case .assigned: 0
        case .courierArrivedRestaurant: 1
        case .pickedUp: 2
        case .delivering: 3
        case .courierArrivedCustomer: 4
        case .delivered: 5
        default: -1
        }
    }

    var statusColor: Color {
        switch self {
        case .assigned: .blue
        case .courierArrivedRestaurant: .indigo
        case .pickedUp: .purple
        case .delivering: .ravonRed
        case .courierArrivedCustomer: .teal
        case .delivered: .green
        case .cancelled, .rejected,
             .cancelledByCustomer, .cancelledByRestaurant, .cancelledBySystem:
            .red
        default: .secondary
        }
    }
}
