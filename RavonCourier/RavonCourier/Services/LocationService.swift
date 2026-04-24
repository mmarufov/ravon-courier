import Foundation
import CoreLocation
import MapKit
import RavonCore

@MainActor
@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    var currentLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var isOnline = false
    private var lastBroadcastTime: Date = .distantPast
    private static let broadcastInterval: TimeInterval = 5

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    func setOnline(_ online: Bool) {
        isOnline = online
    }

    func openInMaps(destination: CLLocationCoordinate2D, name: String) {
        let placemark = MKPlacemark(coordinate: destination)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func broadcastLocationIfNeeded(_ location: CLLocation) {
        guard isOnline else { return }

        let now = Date()
        guard now.timeIntervalSince(lastBroadcastTime) >= Self.broadcastInterval else { return }
        lastBroadcastTime = now

        Task {
            try? await SupabaseService.shared.updateCourierLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                heading: location.course >= 0 ? location.course : nil,
                speed: location.speed >= 0 ? location.speed : nil
            )
        }
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
        broadcastLocationIfNeeded(location)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }
}
