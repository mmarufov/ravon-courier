import Foundation
import RavonCore

// Local enum for picker UI (CaseIterable + displayName).
// Maps to SupabaseService.EarningsPeriod for API calls.

enum EarningsPeriod: String, CaseIterable {
    case today, week, month, all

    var displayName: String {
        switch self {
        case .today: "Сегодня"
        case .week: "Неделя"
        case .month: "Месяц"
        case .all: "Всё время"
        }
    }
}
