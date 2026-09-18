import Foundation
import CoreLocation
import MapKit
import RavonCore

/// Anything that can start and stop the courier's location heartbeat.
///
/// Exists so `ShiftRestoration` can be exercised in tests without a real
/// `CLLocationManager`. `LocationService` is the only production conformer.
@MainActor
protocol LocationStreaming: AnyObject {
    func beginStreaming()
    func endStreaming()
}

@MainActor
@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    /// How often we emit a heartbeat while on shift, movement or not.
    ///
    /// `CLLocationManager` only calls us back when the courier *moves*, and
    /// `CourierLocationStreamer` additionally drops fixes below its
    /// per-status movement threshold. Left at that, a courier standing at the
    /// restaurant counter or at the customer's door — exactly when the
    /// buttons get pressed — emits nothing at all and looks offline to
    /// dispatch. So we also emit on a fixed timer from the last known fix.
    /// 15 s keeps `last_heartbeat_at` comfortably inside a 60 s freshness
    /// window with room for one dropped request.
    static let heartbeatInterval: TimeInterval = 15

    var currentLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// True once `beginStreaming()` has run and until `endStreaming()` does.
    private(set) var isOnline = false
    private(set) var isUpdating = false

    private let locationManager = CLLocationManager()
    private var lastFix: CLLocation?
    private var heartbeatTimer: Timer?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
    }

    // MARK: - Shift lifecycle

    /// Go on shift: ask for permission, start GPS, start the heartbeat timer.
    ///
    /// Every code path that puts the courier on shift must call this — see
    /// `ShiftRestoration.requiresLocationStreaming`.
    func beginStreaming() {
        requestPermission()
        startUpdating()
        setOnline(true)
    }

    /// Go off shift: stop GPS, stop the timer, reset the streamer's cadence.
    func endStreaming() {
        setOnline(false)
        stopUpdating()
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        isUpdating = true
        locationManager.startUpdatingLocation()
    }

    func stopUpdating() {
        isUpdating = false
        locationManager.stopUpdatingLocation()
    }

    func setOnline(_ online: Bool) {
        isOnline = online
        if online {
            startHeartbeatTimer()
        } else {
            stopHeartbeatTimer()
            CourierLocationStreamer.shared.reset()
        }
    }

    func openInMaps(destination: CLLocationCoordinate2D, name: String) {
        let location = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: - Timer-driven heartbeat

    private func startHeartbeatTimer() {
        guard heartbeatTimer == nil else { return }
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: Self.heartbeatInterval, repeats: true
        ) { _ in
            Task { @MainActor in
                await self.emitKeepaliveHeartbeat()
            }
        }
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// Re-send the last known fix so `last_heartbeat_at` stays fresh while the
    /// courier is stationary.
    ///
    /// This goes straight to `update_courier_heartbeat` rather than through
    /// `CourierLocationStreamer.submit`, because the streamer's whole job is
    /// to *drop* fixes that haven't moved far enough — routing the keepalive
    /// through it would filter out the one case it exists to cover. The server
    /// derives `last_moved_at` from geog drift, so a repeated position is
    /// read correctly as "here, still".
    private func emitKeepaliveHeartbeat() async {
        guard isOnline, let fix = lastFix else { return }
        do {
            try await SupabaseService.shared.updateCourierHeartbeat(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                accuracyMeters: fix.horizontalAccuracy >= 0 ? fix.horizontalAccuracy : nil,
                heading: fix.course >= 0 ? fix.course : nil,
                speed: fix.speed >= 0 ? fix.speed : nil
            )
        } catch {
            // Drop — the next tick retries in `heartbeatInterval`.
        }
    }
}

extension LocationService: LocationStreaming {}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
        lastFix = location
        guard isOnline else { return }
        // Movement-driven path: the streamer applies its status-aware cadence
        // and movement filter. The timer above covers standing still.
        Task {
            await CourierLocationStreamer.shared.submit(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                heading: location.course >= 0 ? location.course : nil,
                speed: location.speed >= 0 ? location.speed : nil
            )
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }
}
