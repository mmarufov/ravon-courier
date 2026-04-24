import Foundation
import CoreLocation
import RavonCore

extension AddressSnapshot {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude ?? 0,
            longitude: longitude ?? 0
        )
    }

    var shortAddress: String {
        street ?? city ?? "Неизвестный адрес"
    }

    var hasCoordinate: Bool {
        latitude != nil && longitude != nil
    }
}
