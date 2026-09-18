import Foundation

/// What a cold launch should do with a courier who was already on shift.
///
/// This used to be three inline branches in `HomeView.restoreState()`, and one
/// of them — the mid-delivery branch — forgot to restart location streaming.
/// The courier's UI looked fine while dispatch saw them as gone for the rest of
/// the delivery. Modelling the decision as a value puts the "did we remember to
/// stream?" answer in one place, where it can be asserted instead of reviewed.
enum ShiftRestoration: Equatable, CaseIterable {
    /// `courier_locations.is_online` is false — nothing to restore.
    case stayOffline
    /// An active, non-terminal order is assigned to this courier.
    case resumeDelivery
    /// `current_order_id` points at an order that's already finished; clear it
    /// before taking new offers.
    case clearStaleOrderThenLookForOrders
    /// On shift, no order.
    case lookForOrders

    static func decide(
        isOnline: Bool,
        hasActiveOrder: Bool,
        hasCurrentOrderId: Bool
    ) -> ShiftRestoration {
        guard isOnline else { return .stayOffline }
        if hasActiveOrder { return .resumeDelivery }
        if hasCurrentOrderId { return .clearStaleOrderThenLookForOrders }
        return .lookForOrders
    }

    /// Every branch that leaves the courier on shift must be streaming
    /// location. Dispatch reads `courier_locations`; a courier who isn't
    /// emitting is invisible, whatever their screen says.
    var requiresLocationStreaming: Bool {
        switch self {
        case .stayOffline: false
        case .resumeDelivery, .clearStaleOrderThenLookForOrders, .lookForOrders: true
        }
    }

    /// The single place restoration touches the heartbeat.
    @MainActor
    func apply(to streamer: some LocationStreaming) {
        if requiresLocationStreaming {
            streamer.beginStreaming()
        }
    }
}
