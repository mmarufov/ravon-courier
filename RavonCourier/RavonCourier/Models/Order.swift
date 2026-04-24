import Foundation
import RavonCore

extension Order {
    var itemCount: Int {
        (orderItems ?? []).reduce(0) { $0 + $1.quantity }
    }

    var shortId: String {
        String(id.uuidString.prefix(6)).uppercased()
    }
}
