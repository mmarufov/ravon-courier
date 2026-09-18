import Testing
@testable import RavonCourier

/// Records what a `ShiftRestoration` asks of the heartbeat, without a
/// `CLLocationManager` or a backend.
@MainActor
private final class StreamerSpy: LocationStreaming {
    var beginCount = 0
    var endCount = 0
    func beginStreaming() { beginCount += 1 }
    func endStreaming() { endCount += 1 }
}

@Suite("Shift restoration")
struct ShiftRestorationTests {
    /// The bug this guards: `restoreState()`'s mid-delivery branch used to omit
    /// the `startUpdating()` / `setOnline(true)` calls its two siblings made, so
    /// a courier who force-quit mid-delivery came back with a working UI and a
    /// dead heartbeat — invisible to dispatch for the rest of the delivery.
    @MainActor
    @Test("every branch that stays on shift starts the heartbeat")
    func onShiftBranchesStartTheHeartbeat() {
        let onShift: [ShiftRestoration] = [
            .resumeDelivery,
            .clearStaleOrderThenLookForOrders,
            .lookForOrders,
        ]
        for plan in onShift {
            let spy = StreamerSpy()
            plan.apply(to: spy)
            #expect(plan.requiresLocationStreaming, "\(plan) leaves the courier on shift")
            #expect(spy.beginCount == 1, "\(plan) must start the heartbeat")
            #expect(spy.endCount == 0, "\(plan) must not stop the heartbeat")
        }
    }

    @MainActor
    @Test("offline restoration leaves the heartbeat alone")
    func offlineBranchDoesNotStream() {
        let spy = StreamerSpy()
        ShiftRestoration.stayOffline.apply(to: spy)
        #expect(!ShiftRestoration.stayOffline.requiresLocationStreaming)
        #expect(spy.beginCount == 0)
    }

    /// Fails if a fifth branch is added without deciding whether it streams.
    @Test("stayOffline is the only branch that skips the heartbeat")
    func onlyOfflineSkipsTheHeartbeat() {
        let nonStreaming = ShiftRestoration.allCases.filter { !$0.requiresLocationStreaming }
        #expect(nonStreaming == [.stayOffline])
    }

    @Test("decide maps a courier_locations row onto a branch")
    func decideMapsRowsOntoBranches() {
        #expect(
            ShiftRestoration.decide(isOnline: false, hasActiveOrder: true, hasCurrentOrderId: true)
                == .stayOffline
        )
        #expect(
            ShiftRestoration.decide(isOnline: true, hasActiveOrder: true, hasCurrentOrderId: true)
                == .resumeDelivery
        )
        #expect(
            ShiftRestoration.decide(isOnline: true, hasActiveOrder: false, hasCurrentOrderId: true)
                == .clearStaleOrderThenLookForOrders
        )
        #expect(
            ShiftRestoration.decide(isOnline: true, hasActiveOrder: false, hasCurrentOrderId: false)
                == .lookForOrders
        )
    }
}
