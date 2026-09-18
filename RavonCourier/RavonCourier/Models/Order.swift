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

extension Int {
    /// Russian count pluralisation for order line items: 1 позиция,
    /// 2 позиции, 5 позиций.
    ///
    /// TODO: belongs in RavonCore next to the shared formatters — the
    /// merchant app needs the identical rule for the same noun.
    var itemsRu: String {
        let mod100 = abs(self) % 100
        let mod10 = abs(self) % 10
        let word: String
        if mod100 >= 11 && mod100 <= 14 {
            word = "позиций"
        } else if mod10 == 1 {
            word = "позиция"
        } else if mod10 >= 2 && mod10 <= 4 {
            word = "позиции"
        } else {
            word = "позиций"
        }
        return "\(self) \(word)"
    }
}
