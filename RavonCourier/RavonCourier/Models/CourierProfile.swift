import Foundation

enum VehicleType: String, Codable, CaseIterable {
    case bicycle = "bicycle"
    case motorcycle = "motorcycle"
    case car = "car"
    case onFoot = "on_foot"

    var displayName: String {
        switch self {
        case .bicycle: "Велосипед"
        case .motorcycle: "Мотоцикл"
        case .car: "Автомобиль"
        case .onFoot: "Пешком"
        }
    }

    var icon: String {
        switch self {
        case .bicycle: "bicycle"
        case .motorcycle: "motorcycle"
        case .car: "car.fill"
        case .onFoot: "figure.walk"
        }
    }
}
